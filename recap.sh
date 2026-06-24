#!/usr/bin/env bash
#
# daily-recap — collect the previous day's work across a workspace of git repos
# and post an AI-written recap to a Discord channel via webhook. Optionally folds
# in your Claude Code session prompts, if you use Claude Code.
#
# Triggered by launchd at 8:55am (see install.sh), or run manually:  ./recap.sh
#
# Self-contained: all machine-specific settings live in config.sh.

set -uo pipefail
shopt -s nullglob

# --- locate self & load config ----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
LOG_FILE="$SCRIPT_DIR/recap.log"
TODO_FILE="$SCRIPT_DIR/todos.txt"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"; }

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run: cp config.example.sh config.sh  then edit it." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$CONFIG_FILE"

# --dry-run: print the recap to stdout instead of posting to Discord
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# --- defaults for anything missing from config ------------------------------
: "${WORKSPACE_DIR:=$HOME/code}"
: "${REPO_INCLUDE:=}"
: "${GIT_AUTHOR_FILTER:=auto}"
: "${LOOKBACK:=smart}"
: "${INCLUDE_UNCOMMITTED:=true}"
: "${INCLUDE_CLAUDE_SESSIONS:=false}"
: "${USE_AI_SUMMARY:=true}"
: "${SEND_WHEN_EMPTY:=true}"
: "${CLAUDE_BIN:=}"
: "${JQ_BIN:=}"
: "${DISCORD_WEBHOOK_URL:=}"
: "${SKIP_WEEKENDS:=true}"
: "${NETLIFY_AUTH_TOKEN:=}"
: "${NETLIFY_SITES:=}"
: "${DEPLOY_REPOS:=}"
: "${DEPLOY_GIT_FETCH:=true}"

log "=== run start (workspace=$WORKSPACE_DIR) ==="

# --- weekend guard ----------------------------------------------------------
# Don't deliver on Sat (6) or Sun (7). Friday's work is reported Monday because
# LOOKBACK=smart makes Monday reach back to Friday. This guard also suppresses a
# weekday job that was deferred (Mac asleep) and fires on a weekend wake.
if [ "$SKIP_WEEKENDS" = "true" ] && [ "$DRY_RUN" -eq 0 ]; then
  dow_now="$(date +%u)"
  if [ "$dow_now" -ge 6 ]; then
    log "weekend (dow=$dow_now); SKIP_WEEKENDS=true; skipping"
    log "=== run end (skipped: weekend) ==="
    exit 0
  fi
fi

# --- resolve binaries (launchd runs with a minimal PATH) --------------------
find_bin() {
  # usage: find_bin <name> <override> <candidate>...
  local name="$1"; shift
  local override="$1"; shift
  if [ -n "$override" ] && [ -x "$override" ]; then echo "$override"; return 0; fi
  local c
  for c in "$@"; do [ -x "$c" ] && { echo "$c"; return 0; }; done
  command -v "$name" 2>/dev/null && return 0
  return 1
}

JQ_BIN="$(find_bin jq "$JQ_BIN" /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq)" || {
  echo "ERROR: jq not found (install with: brew install jq)" >&2; log "ERROR jq not found"; exit 1; }
CLAUDE_BIN="$(find_bin claude "$CLAUDE_BIN" "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude)" || CLAUDE_BIN=""

if [ -z "$DISCORD_WEBHOOK_URL" ] || [ "$DISCORD_WEBHOOK_URL" = "PASTE_YOUR_DISCORD_WEBHOOK_URL_HERE" ]; then
  echo "ERROR: DISCORD_WEBHOOK_URL is not set in config.sh" >&2; log "ERROR webhook not set"; exit 1
fi

# --- author filter ----------------------------------------------------------
AUTHOR=""
case "$GIT_AUTHOR_FILTER" in
  auto) AUTHOR="$(git config --global user.email 2>/dev/null || true)" ;;
  "")   AUTHOR="" ;;
  *)    AUTHOR="$GIT_AUTHOR_FILTER" ;;
esac
log "author filter: ${AUTHOR:-<all authors>}"

# --- time window ------------------------------------------------------------
TODAY="$(date +%Y-%m-%d)"
DOW="$(date +%u)"          # 1=Mon .. 7=Sun
case "$LOOKBACK" in
  smart)        if [ "$DOW" -eq 1 ]; then DAYS=3; else DAYS=1; fi ;;  # Monday -> cover the weekend
  ''|*[!0-9]*)  DAYS=1 ;;                                             # non-numeric fallback
  *)            DAYS="$LOOKBACK" ;;
esac
SINCE_DATE="$(date -v-"${DAYS}"d +%Y-%m-%d)"
YESTERDAY="$(date -v-1d +%Y-%m-%d)"
SINCE="$SINCE_DATE 00:00:00"
UNTIL="$TODAY 00:00:00"
SINCE_EPOCH="$(date -j -f '%Y-%m-%d %H:%M:%S' "$SINCE" +%s)"
UNTIL_EPOCH="$(date -j -f '%Y-%m-%d %H:%M:%S' "$UNTIL" +%s)"
if [ "$SINCE_DATE" = "$YESTERDAY" ]; then
  DATE_LABEL="$SINCE_DATE"
else
  DATE_LABEL="$SINCE_DATE \xe2\x86\x92 $YESTERDAY"   # e.g. Fri -> Sun on Mondays
  DATE_LABEL="$(printf '%b' "$DATE_LABEL")"
fi
log "window: $SINCE .. $UNTIL"

# --- discover repos ---------------------------------------------------------
# Always skip the recap tool's own folder. If REPO_INCLUDE is set, keep only
# repos whose folder name matches one of its glob patterns (e.g. "parkito-*").
REPOS=()
[ -d "$WORKSPACE_DIR/.git" ] && [ "$WORKSPACE_DIR" != "$SCRIPT_DIR" ] && REPOS+=("$WORKSPACE_DIR")
for d in "$WORKSPACE_DIR"/*/; do
  [ -d "${d}.git" ] || continue
  repo_path="${d%/}"
  [ "$repo_path" = "$SCRIPT_DIR" ] && continue           # never recap ourselves
  name="$(basename "$repo_path")"
  if [ -n "$REPO_INCLUDE" ]; then
    match=0
    set -f                                   # split patterns without glob-expanding them
    for pat in $REPO_INCLUDE; do
      case "$name" in $pat) match=1; break ;; esac
    done
    set +f
    [ "$match" -eq 1 ] || continue
  fi
  REPOS+=("$repo_path")
done
log "repos found: ${#REPOS[@]}${REPO_INCLUDE:+ (filter: $REPO_INCLUDE)}"

# --- collect activity -------------------------------------------------------
REPORT="# Work report for $DATE_LABEL (workspace: $(basename "$WORKSPACE_DIR"))"
HAS_ACTIVITY=0
append() { REPORT="$REPORT"$'\n'"$1"; }

repo=""
gitlog() {
  if [ -n "$AUTHOR" ]; then
    git -C "$repo" log --no-merges --author="$AUTHOR" "$@"
  else
    git -C "$repo" log --no-merges "$@"
  fi
}

for repo in "${REPOS[@]}"; do
  name="$(basename "$repo")"

  commit_lines="$(gitlog --since="$SINCE" --until="$UNTIL" --pretty=format:'- %s (%h)' 2>/dev/null)"
  commit_count="$(printf '%s\n' "$commit_lines" | grep -c '^- ' || true)"

  wip=""
  if [ "$INCLUDE_UNCOMMITTED" = "true" ]; then
    wip="$(git -C "$repo" status --short 2>/dev/null | head -40)"
  fi

  if [ "${commit_count:-0}" -gt 0 ] || [ -n "$wip" ]; then
    HAS_ACTIVITY=1
    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    append ""
    append "## $name (branch: $branch)"
    if [ "${commit_count:-0}" -gt 0 ]; then
      append "Commits ($commit_count):"
      append "$commit_lines"
    fi
    if [ -n "$wip" ]; then
      append "Uncommitted / in progress:"
      append "$wip"
    fi
  fi
done

# --- Claude Code session prompts -------------------------------------------
if [ "$INCLUDE_CLAUDE_SESSIONS" = "true" ]; then
  enc="$(printf '%s' "$WORKSPACE_DIR" | sed 's#/#-#g')"
  cdir="$HOME/.claude/projects/$enc"
  sessions_text=""
  if [ -d "$cdir" ]; then
    for f in "$cdir"/*.jsonl; do
      [ -f "$f" ] || continue
      m="$(stat -f %m "$f" 2>/dev/null || echo 0)"
      if [ "$m" -ge "$SINCE_EPOCH" ] && [ "$m" -lt "$UNTIL_EPOCH" ]; then
        prompts="$("$JQ_BIN" -rc '
          select(.type=="user" and (has("toolUseResult")|not) and (.isMeta != true))
          | (.message.content) as $c
          | (if ($c|type)=="string" then $c
             elif ($c|type)=="array" then ([$c[]? | select(.type=="text") | .text] | join(" "))
             else "" end)
          | gsub("\\s+";" ")
          | select(length>0 and length<2000)
          | select((contains("<system-reminder>")|not)
                   and (contains("<command-name>")|not)
                   and (contains("Caveat:")|not)
                   and (startswith("<")|not))
        ' "$f" 2>/dev/null)"
        [ -n "$prompts" ] && sessions_text="$sessions_text$prompts"$'\n'
      fi
    done
  fi
  if [ -n "$sessions_text" ]; then
    HAS_ACTIVITY=1
    sessions_text="$(printf '%s\n' "$sessions_text" | tail -n 60)"
    append ""
    append "## Claude Code sessions (prompts / what was worked on)"
    append "$(printf '%s\n' "$sessions_text" | sed 's/^/- /')"
  fi
fi

# --- delivery: one clean embed (narrative body + deploy/to-do fields) -------
# Uses globals: DATE_LABEL, NARRATIVE, DEPLOY_NAME, DEPLOY_VALUE, TODOS_NAME, TODOS_VALUE
post_embed() {
  local title desc ts payload http
  title="$(printf '\xf0\x9f\x97\x93\xef\xb8\x8f  Daily Recap \xc2\xb7 %s' "$DATE_LABEL")"
  desc="${NARRATIVE:0:4000}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n===== DRY RUN: Discord embed preview =====\n# %s\n\n%s\n' "$title" "$desc"
    [ -n "$DEPLOY_VALUE" ] && printf '\n[ %s ]\n%s\n' "$DEPLOY_NAME" "$DEPLOY_VALUE"
    [ -n "$TODOS_VALUE" ]  && printf '\n[ %s ]\n%s\n' "$TODOS_NAME" "$TODOS_VALUE"
    printf '==========================================\n'
    return 0
  fi

  payload="$("$JQ_BIN" -n \
    --arg title "$title" \
    --arg desc  "$desc" \
    --arg dname "$DEPLOY_NAME" \
    --arg dval  "${DEPLOY_VALUE:0:1024}" \
    --arg tname "$TODOS_NAME" \
    --arg tval  "${TODOS_VALUE:0:1024}" \
    --arg ts    "$ts" \
    '{
       username: "Daily Recap",
       embeds: [ {
         title: $title,
         description: (if $desc == "" then null else $desc end),
         color: 5814783,
         timestamp: $ts,
         footer: { text: "daily-recap" },
         fields: (
             (if $dval != "" then [ {name: $dname, value: $dval, inline: false} ] else [] end)
           + (if $tval != "" then [ {name: $tname, value: $tval, inline: false} ] else [] end)
         )
       } ]
     }')"
  http="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/json' -X POST -d "$payload" "$DISCORD_WEBHOOK_URL")"
  case "$http" in
    200|204) log "Discord post OK ($http)"; return 0 ;;
    *)       log "Discord post FAILED (HTTP $http)"; return 1 ;;
  esac
}

# --- deploy detection (only reported when a deploy actually happened) -------
# Netlify if a token is configured (true production deploys); otherwise detect
# merges into the production branch (main/master) of the deploy repos.
detect_deploys_via_netlify() {
  local sites_json out="" sid sname deploys count
  sites_json="$(curl -sS --max-time 20 -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
    "https://api.netlify.com/api/v1/sites?per_page=100" 2>/dev/null)"
  printf '%s' "$sites_json" | "$JQ_BIN" -e 'type=="array"' >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r sid sname; do
    [ -n "$sid" ] || continue
    if [ -n "$NETLIFY_SITES" ]; then
      case " $NETLIFY_SITES " in *" $sname "*) : ;; *) continue ;; esac
    fi
    deploys="$(curl -sS --max-time 20 -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
      "https://api.netlify.com/api/v1/sites/$sid/deploys?per_page=30" 2>/dev/null)"
    count="$(printf '%s' "$deploys" | "$JQ_BIN" -r --argjson s "$SINCE_EPOCH" --argjson u "$UNTIL_EPOCH" '
      [ .[]? | select(.context=="production" and .state=="ready")
             | (.created_at | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) as $t
             | select($t >= $s and $t < $u) ] | length' 2>/dev/null)"
    if [ "${count:-0}" -gt 0 ]; then
      if [ "$count" -gt 1 ]; then out="$out- **$sname** ($count deploys)"$'\n'; else out="$out- **$sname**"$'\n'; fi
    fi
  done <<EOF
$(printf '%s' "$sites_json" | "$JQ_BIN" -r '.[] | "\(.id)\t\(.name)"')
EOF
  printf '%s' "$out" | sed '/^$/d'
  return 0
}

detect_deploys_via_git() {
  local out="" r repo b prod n
  for r in $DEPLOY_REPOS; do
    repo="$WORKSPACE_DIR/$r"
    [ -d "$repo/.git" ] || continue
    if [ "$DEPLOY_GIT_FETCH" = "true" ]; then
      GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
        git -C "$repo" fetch --quiet --no-tags origin 2>/dev/null || log "deploy: fetch failed for $r"
    fi
    prod=""
    for b in origin/main origin/master; do
      git -C "$repo" rev-parse --verify --quiet "$b" >/dev/null 2>&1 && { prod="$b"; break; }
    done
    [ -n "$prod" ] || continue
    n="$(git -C "$repo" log "$prod" --since="$SINCE" --until="$UNTIL" --oneline 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" -gt 0 ]; then
      if [ "$n" -gt 1 ]; then out="$out- **$r** -> ${prod#origin/} ($n new commits)"$'\n'
      else out="$out- **$r** -> ${prod#origin/} ($n new commit)"$'\n'; fi
    fi
  done
  printf '%s' "$out" | sed '/^$/d'
}

# --- deploy detection -> DEPLOY_NAME / DEPLOY_VALUE -------------------------
DEPLOY_NAME=""
DEPLOY_VALUE=""
if [ -n "$NETLIFY_AUTH_TOKEN" ]; then
  if DEPLOY_VALUE="$(detect_deploys_via_netlify)"; then
    DEPLOY_NAME="$(printf '\xf0\x9f\x9a\x80 Deployed to production')"
  else
    log "deploy: netlify check failed; falling back to git merge detection"
    DEPLOY_VALUE="$(detect_deploys_via_git)"
    DEPLOY_NAME="$(printf '\xf0\x9f\x9a\x80 Merged to production branch (likely deployed)')"
  fi
else
  DEPLOY_VALUE="$(detect_deploys_via_git)"
  DEPLOY_NAME="$(printf '\xf0\x9f\x9a\x80 Merged to production branch (likely deployed)')"
fi
[ -n "$DEPLOY_VALUE" ] && log "deploy: detected"

# --- today's to-dos (verbatim, never AI-rewritten) -------------------------
TODOS_NAME="$(printf '\xf0\x9f\x93\x8b To-dos for today')"
TODOS_VALUE=""
[ -s "$TODO_FILE" ] && TODOS_VALUE="$(grep -v '^[[:space:]]*$' "$TODO_FILE" | sed 's/^/- /')"
[ -n "$TODOS_VALUE" ] && log "todos: $(printf '%s\n' "$TODOS_VALUE" | grep -c '^- ')"

# --- narrative (AI summary of commits / WIP / sessions) --------------------
NARRATIVE=""
if [ "$HAS_ACTIVITY" -eq 1 ]; then
  if [ "$USE_AI_SUMMARY" = "true" ] && [ -n "$CLAUDE_BIN" ]; then
    PROMPT="You are writing a brief daily work recap (a personal standup) for a developer. Based ONLY on the git activity and Claude Code session prompts below for ${DATE_LABEL}, write a concise, friendly narrative of what they worked on. Group by project/repo. Clearly separate what was SHIPPED/FIXED (commits) from WORK IN PROGRESS (uncommitted changes) and EXPLORED (Claude sessions). Use light Discord markdown (bold repo names, short bullets). Keep it under 1200 characters. No preamble, no sign-off, no 'Here is' headers, and do NOT add any closing/decorative emoji. If something is unclear, summarize at a high level rather than guessing details. Do NOT claim anything was deployed, shipped to production, or released — deployment status is reported separately, so ignore it entirely."
    NARRATIVE="$(printf '%s' "$REPORT" | "$CLAUDE_BIN" -p "$PROMPT" --output-format text 2>>"$LOG_FILE" || true)"
    [ -z "$NARRATIVE" ] && log "AI summary empty (claude failed?) — falling back to raw report"
  else
    log "AI summary disabled or claude not found — using raw report"
  fi
  [ -z "$NARRATIVE" ] && NARRATIVE="$REPORT"
fi

# --- nothing at all to report? ---------------------------------------------
if [ -z "$NARRATIVE" ] && [ -z "$DEPLOY_VALUE" ] && [ -z "$TODOS_VALUE" ]; then
  if [ "$SEND_WHEN_EMPTY" = "true" ]; then
    NARRATIVE="Nothing recorded for this period. Enjoy the quiet."
  else
    log "nothing to report; SEND_WHEN_EMPTY=false; skipping"
    log "=== run end ==="
    exit 0
  fi
fi

# --- send -------------------------------------------------------------------
if post_embed; then
  log "=== run end (delivered) ==="
else
  log "=== run end (delivery FAILED) ==="
  exit 1
fi
