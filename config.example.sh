#!/usr/bin/env bash
# =============================================================================
#  daily-recap — configuration template
# =============================================================================
#  Copy this file to config.sh and fill in your own values:
#
#      cp config.example.sh config.sh
#
#  config.sh is gitignored — it holds your private webhook/token and must never
#  be committed. This template is safe to commit and share.
# =============================================================================


# -----------------------------------------------------------------------------
#  REQUIRED
# -----------------------------------------------------------------------------

# Discord webhook the recap is posted to.
#   Discord → your channel → Edit Channel → Integrations → Webhooks
#           → New Webhook → Copy Webhook URL
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXXXXXX/YYYYYYYY"

# Folder to scan. Every immediate subfolder containing a .git is picked up
# automatically (and the folder itself if it is a repo) — no need to list repos.
WORKSPACE_DIR="$HOME/code"

# Limit which repos are included, by folder-name glob(s), space-separated.
# Empty = every git repo in WORKSPACE_DIR. (The recap tool's own folder is
# ALWAYS skipped, regardless of this setting.)
#   e.g.  REPO_INCLUDE="myproject-*"   or   REPO_INCLUDE="api web mobile"
REPO_INCLUDE=""


# -----------------------------------------------------------------------------
#  SCHEDULE & SCOPE
# -----------------------------------------------------------------------------

# Send time, 24h local clock (applied by install.sh).
RECAP_HOUR=8
RECAP_MINUTE=55

# Skip weekends?  true → run Mon–Fri only; Friday's work is reported Monday.
SKIP_WEEKENDS=true

# How far back to summarize.
#   smart → the previous day (on Mondays, reaches back to Friday)
#   <N>   → the last N days
LOOKBACK="smart"

# Whose commits to include.
#   auto              → only yours (matched by your global `git config user.email`)
#   ""                → everyone's commits
#   "you@example.com" → a specific email/name
GIT_AUTHOR_FILTER="auto"

# Include uncommitted work-in-progress (git status)?
INCLUDE_UNCOMMITTED=true

# Send a short note even on days with nothing to report?
SEND_WHEN_EMPTY=true


# -----------------------------------------------------------------------------
#  AI SUMMARY  (optional — needs the `claude` CLI; falls back to a plain list)
# -----------------------------------------------------------------------------

# true  → narrative recap written by the `claude` CLI (one API call per run)
# false → plain structured list, fully offline
USE_AI_SUMMARY=true


# -----------------------------------------------------------------------------
#  CLAUDE CODE SESSIONS  (optional — only relevant if you use Claude Code)
# -----------------------------------------------------------------------------

# Fold your Claude Code session prompts for this workspace into the recap.
# Leave false unless you use Claude Code.
INCLUDE_CLAUDE_SESSIONS=false


# -----------------------------------------------------------------------------
#  DEPLOY DETECTION  (a "Deployed" line is shown ONLY when you actually shipped)
# -----------------------------------------------------------------------------

# Option A — Netlify (true production deploys). Recommended if you host on Netlify.
#   Create a token: Netlify → User settings → Applications →
#                   Personal access tokens → New access token
NETLIFY_AUTH_TOKEN=""

# Limit to specific Netlify sites (space-separated site names, e.g. "my-app my-marketing").
# Leave empty to check every site in your account.
NETLIFY_SITES=""

# Option B — git fallback (used when no Netlify token is set). Lists the repos
# whose production branch (main/master) means "deployed", e.g. "web-app api".
# Empty = deploy detection off.
DEPLOY_REPOS=""

# git fetch before checking, so merges show up even if you haven't pulled locally.
DEPLOY_GIT_FETCH=true


# -----------------------------------------------------------------------------
#  ADVANCED (usually leave blank — auto-detected)
# -----------------------------------------------------------------------------
CLAUDE_BIN=""
JQ_BIN=""

# Seconds to wait for network connectivity before the run's first network call.
# A scheduled job can fire the instant the Mac wakes, before Wi-Fi is back; this
# polls until the connection is up (then proceeds regardless). 0 disables the wait.
NETWORK_WAIT_SECS=60
