#!/usr/bin/env bash
#
# parkito-daily-recap configuration TEMPLATE.
#
#   cp config.example.sh config.sh   # then edit config.sh
#
# config.sh holds your private Discord webhook and is gitignored. Never commit it.

# ---------------------------------------------------------------------------
# REQUIRED — your Discord webhook URL.
# Discord -> your channel -> Edit Channel -> Integrations -> Webhooks ->
#            New Webhook -> Copy Webhook URL
# ---------------------------------------------------------------------------
DISCORD_WEBHOOK_URL="PASTE_YOUR_DISCORD_WEBHOOK_URL_HERE"

# ---------------------------------------------------------------------------
# Workspace to scan. Every immediate subfolder containing a .git is auto-included
# (plus the folder itself if it is a git repo). No need to list repos by hand.
# ---------------------------------------------------------------------------
WORKSPACE_DIR="$HOME/Parkito"

# Whose commits to include:
#   auto  -> only your commits, matched by your global `git config user.email`
#   ""    -> ALL commits in each repo, regardless of author
#   "you@example.com" -> an explicit email/name to match
GIT_AUTHOR_FILTER="auto"

# When the recap is sent (24-hour clock, local time). Used by install.sh.
RECAP_HOUR=8
RECAP_MINUTE=55

# How far back to summarize:
#   smart -> the previous day; on Mondays it reaches back to Friday (covers the weekend)
#   <N>   -> the last N days
LOOKBACK="smart"

# Skip weekends?  true | false
#   true  -> never deliver on Sat/Sun; Friday's work is reported Monday (via LOOKBACK=smart).
#            install.sh also schedules the job for weekdays only (Mon-Fri).
#   false -> deliver every day.
SKIP_WEEKENDS=true

# Include uncommitted / work-in-progress changes (git status)?  true | false
INCLUDE_UNCOMMITTED=true

# Include a summary of your Claude Code session prompts for this workspace?  true | false
INCLUDE_CLAUDE_SESSIONS=true

# Use the `claude` CLI to write a narrative summary?  true | false
#   true  -> AI-written recap (makes one network call to the Anthropic API)
#   false -> plain structured list, fully offline/deterministic
USE_AI_SUMMARY=true

# Still send a short "nothing recorded" note on quiet days?  true | false
SEND_WHEN_EMPTY=true

# --- Deployment detection ---------------------------------------------------
# The recap shows a "Deployed" line ONLY when something actually shipped (never
# a "you didn't deploy" message).
#
# Preferred: Netlify (true production deploys). Create a token at
#   Netlify -> User settings -> Applications -> Personal access tokens -> New token
# and paste it here. Leave empty to use the git fallback instead.
NETLIFY_AUTH_TOKEN=""
# Optional: limit to specific Netlify site names (space-separated). Empty = all sites.
NETLIFY_SITES=""

# Git fallback (used when NETLIFY_AUTH_TOKEN is empty, or Netlify is unreachable):
# detects new commits merged into the production branch (main/master) of these repos.
DEPLOY_REPOS="parkito-web parkito-host"
# Fetch the latest remote refs before checking, so merges show up even if you
# haven't pulled locally.  true | false
DEPLOY_GIT_FETCH=true

# Optional explicit binary paths (leave empty to auto-detect)
CLAUDE_BIN=""
JQ_BIN=""
