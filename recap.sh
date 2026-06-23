#!/usr/bin/env bash
#
# parkito-daily-recap — collect the previous day's work across a workspace of git
# repos (+ Claude Code session prompts) and post an AI-written recap to a Discord
# channel via webhook.
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
: "${WORKSPACE_DIR:=$HOME/Parkito}"
: "${GIT_AUTHOR_FILTER:=auto}"
: "${LOOKBACK:=smart}"
: "${INCLUDE_UNCOMMITTED:=true}"
: "${INCLUDE_CLAUDE_SESSIONS:=true}"
: "${USE_AI_SUMMARY:=true}"
: "${SEND_WHEN_EMPTY:=true}"
: "${CLAUDE_BIN:=}"
: "${JQ_BIN:=}"
: "${DISCORD_WEBHOOK_URL:=}"
: "${SKIP_WEEKENDS:=true}"
: "${NETLIFY_AUTH_TOKEN:=}"
: "${NETLIFY_SITES:=}"
: "${DEPLOY_REPOS:=parkito-web parkito-host}"
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
REPOS=()
[ -d "$WORKSPACE_DIR/.git" ] && REPOS+=("$WORKSPACE_DIR")
for d in "$WORKSPACE_DIR"/*/; do
  [ -d "${d}.git" ] && REPOS+=("${d%/}")
done
log "repos found: ${#REPOS[@]}"

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

# --- deliver helpers --------------------------------------------------------
post_discord() {
  # $1 = title (empty for continuation chunks), $2 = description
  local title="$1" desc="$2" payload http
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n----- DRY RUN: would post to Discord -----\n%s\n\n%s\n------------------------------------------\n' "$title" "$desc"
    return 0
  fi
  payload="$("$JQ_BIN" -n --arg t "$title" --arg d "$desc" \
    '{username:"Parkito Recap",
      embeds:[ ({description:$d, color:5814783} + (if $t=="" then {} else {title:$t} end)) ]}')"
  http="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/json' -X POST -d "$payload" "$DISCORD_WEBHOOK_URL")"
  case "$http" in
    200|204) log "Discord post OK ($http)"; return 0 ;;
    *)       log "Discord post FAILED (HTTP $http)"; return 1 ;;
  esac
}

deliver() {
  # chunk body to Discord's 4096-char embed-description limit
  local title="$1" body="$2" max=4000 first=1 chunk t
  while [ "${#body}" -gt 0 ]; do
    chunk="${body:0:$max}"
    body="${body:${#chunk}}"
    if [ "$first" -eq 1 ]; then t="$title"; first=0; else t=""; fi
    post_discord "$t" "$chunk" || return 1
  done
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

DEPLOY_BLOCK=""
deploy_lines=""
deploy_header=""
if [ -n "$NETLIFY_AUTH_TOKEN" ]; then
  if deploy_lines="$(detect_deploys_via_netlify)"; then
    deploy_header="$(printf '\xf0\x9f\x9a\x80 **Deployed to production**')"
  else
    log "deploy: netlify check failed; falling back to git merge detection"
    deploy_lines="$(detect_deploys_via_git)"
    deploy_header="$(printf '\xf0\x9f\x9a\x80 **Merged to production branch** (likely deployed)')"
  fi
else
  deploy_lines="$(detect_deploys_via_git)"
  deploy_header="$(printf '\xf0\x9f\x9a\x80 **Merged to production branch** (likely deployed)')"
fi
if [ -n "$deploy_lines" ]; then
  DEPLOY_BLOCK="$(printf '\n\n%s\n%s' "$deploy_header" "$deploy_lines")"
  log "deploy: detected"
fi

# --- today's to-dos (verbatim, never AI-rewritten) --------------------------
TODOS_BLOCK=""
if [ -s "$TODO_FILE" ]; then
  todos_list="$(grep -v '^[[:space:]]*$' "$TODO_FILE" | sed 's/^/- /')"
  if [ -n "$todos_list" ]; then
    TODOS_BLOCK="$(printf '\n\n\xf0\x9f\x93\x8b **To-dos for today**\n%s' "$todos_list")"
    log "todos: $(printf '%s\n' "$todos_list" | grep -c '^- ')"
  fi
fi

# --- assemble extras (appended after the narrative) -------------------------
EXTRAS="$DEPLOY_BLOCK$TODOS_BLOCK"

# --- empty-day short circuit ------------------------------------------------
if [ "$HAS_ACTIVITY" -eq 0 ]; then
  log "no commit/session activity for window"
  if [ -n "$EXTRAS" ]; then
    # send just the extras (deploys / to-dos), stripping leading blank lines
    deliver "Daily Recap - $DATE_LABEL" "$(printf '%s' "$EXTRAS" | sed '/./,$!d')"
  elif [ "$SEND_WHEN_EMPTY" = "true" ]; then
    deliver "Daily Recap - $DATE_LABEL" "No git commits, uncommitted changes, or Claude Code sessions recorded for this period. Enjoy the quiet."
  else
    log "SEND_WHEN_EMPTY=false; skipping send"
  fi
  log "=== run end ==="
  exit 0
fi

# --- summarize --------------------------------------------------------------
SUMMARY=""
if [ "$USE_AI_SUMMARY" = "true" ] && [ -n "$CLAUDE_BIN" ]; then
  PROMPT="You are writing a brief daily work recap (a personal standup) for a developer. Based ONLY on the git activity and Claude Code session prompts below for ${DATE_LABEL}, write a concise, friendly narrative of what they worked on. Group by project/repo. Clearly separate what was SHIPPED/FIXED (commits) from WORK IN PROGRESS (uncommitted changes) and EXPLORED (Claude sessions). Use light Discord markdown (bold repo names, short bullets). Keep it under 1500 characters. No preamble, no sign-off, no 'Here is' headers. If something is unclear, summarize at a high level rather than guessing details. Do NOT claim anything was deployed, shipped to production, or released — deployment status is reported separately, so ignore it entirely."
  SUMMARY="$(printf '%s' "$REPORT" | "$CLAUDE_BIN" -p "$PROMPT" --output-format text 2>>"$LOG_FILE" || true)"
  [ -z "$SUMMARY" ] && log "AI summary empty (claude failed?) — falling back to raw report"
else
  log "AI summary disabled or claude not found — using raw report"
fi
[ -z "$SUMMARY" ] && SUMMARY="$REPORT"
SUMMARY="$SUMMARY$EXTRAS"

# --- send -------------------------------------------------------------------
if deliver "Daily Recap - $DATE_LABEL" "$SUMMARY"; then
  log "=== run end (delivered) ==="
else
  log "=== run end (delivery FAILED) ==="
  exit 1
fi
