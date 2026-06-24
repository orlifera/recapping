# Daily Dev Recap

Every weekday morning, this posts a short AI-written recap of **what you did the previous
day** across a folder of git repos — commits, work-in-progress, optional Claude Code
sessions — plus whether you **deployed**, and your **to-do list for today**, to a **Discord
channel** via webhook.

It runs **locally** via macOS `launchd`, so it works even when your editor is closed. The
only outbound call is to the Anthropic API to write the narrative (optional — turn it off
with `USE_AI_SUMMARY=false`).

> 🚀 **New here? Start with [`SETUP.md`](./SETUP.md)** for a 2-minute quick start.

## What it reports

- **Shipped / fixed** — your commits from the previous day, across every git repo in the
  workspace (auto-discovered; no need to list them).
- **In progress** — uncommitted changes (`git status`) per repo.
- **Deployed** — production deploys (via Netlify, or detected from merges into `main`/
  `master`). Only shown when you actually deployed — never a "you didn't deploy" message.
- **To-dos for today** — your own task list (see below).
- **Explored** *(optional)* — prompts from your Claude Code sessions, if you use Claude Code.

By default it runs **Mon–Fri** and never on weekends; **Friday's work is delivered Monday**.

## Setup

See [`SETUP.md`](./SETUP.md). In short:

```bash
cp config.example.sh config.sh     # then edit config.sh: paste your Discord webhook
chmod +x recap.sh install.sh uninstall.sh todo.sh
./recap.sh --dry-run               # preview in the terminal
./install.sh                       # schedule it (08:55, Mon–Fri)
```

Requirements: macOS, `jq` (`brew install jq`), and optionally the `claude` CLI for the AI
summary. All auto-detected.

## To-dos (what to do *today*)

Each recap ends with a **📋 To-dos for today** field — your own running task list, shown
verbatim. Manage it with `todo.sh`:

```bash
./todo.sh add "Finish the gate screen"   # add a task
./todo.sh                                # list open tasks
./todo.sh done 2                         # complete & remove task #2
./todo.sh clear                          # wipe the list
./todo.sh edit                           # edit the raw list in $EDITOR
```

Tasks persist until you mark them `done`. Completed tasks are logged to `todos.done.log`.
Handy alias (`~/.zshrc`): `alias todo="$(pwd)/todo.sh"`. The list lives in `todos.txt`
(gitignored — personal, not shared).

## Deployments

A **🚀 Deployed** line appears only when you actually shipped (never the absence of one):

- **Netlify (preferred, true production deploys).** Set `NETLIFY_AUTH_TOKEN` in `config.sh`
  (create one at **Netlify → User settings → Applications → Personal access tokens**). It
  reports any `production` deploy that reached `ready` during the window. Optionally set
  `NETLIFY_SITES="site-a site-b"` to limit which sites count (empty = all sites).
- **Git fallback (no token).** Set `DEPLOY_REPOS="repo-a repo-b"`; it `git fetch`es them and
  reports new commits merged into the production branch (`main`/`master`) during the window.

> The git fetch needs your git auth reachable; from `launchd` your SSH key is usually
> available via the Keychain. If a fetch can't run it uses your last-fetched refs — it may
> *miss* a very recent deploy, but never reports a false one. `DEPLOY_GIT_FETCH=false` skips it.

## Configuration

All settings live in `config.sh` (template: [`config.example.sh`](./config.example.sh)):

| Setting | Default | Meaning |
|---|---|---|
| `DISCORD_WEBHOOK_URL` | — | Your webhook (required). Gitignored. |
| `WORKSPACE_DIR` | `$HOME/code` | Folder to scan; each subfolder with a `.git` is included. |
| `REPO_INCLUDE` | `""` | Only include repos whose folder name matches these glob(s), e.g. `"app-*"`. Empty = all. The tool's own folder is always skipped. |
| `GIT_AUTHOR_FILTER` | `auto` | `auto` = only your commits; `""` = all; or an explicit email. |
| `RECAP_HOUR` / `RECAP_MINUTE` | `8` / `55` | Send time (24h, local). |
| `SKIP_WEEKENDS` | `true` | Run Mon–Fri only; Friday reported Monday. |
| `LOOKBACK` | `smart` | `smart` = yesterday (Fri–Sun on Mondays); or a number of days. |
| `INCLUDE_UNCOMMITTED` | `true` | Include work-in-progress. |
| `INCLUDE_CLAUDE_SESSIONS` | `false` | Include Claude Code session prompts (opt-in). |
| `USE_AI_SUMMARY` | `true` | `false` = plain list, fully offline. |
| `SEND_WHEN_EMPTY` | `true` | Send a short note on quiet days. |
| `NETLIFY_AUTH_TOKEN` | `""` | Netlify token → true production-deploy detection. |
| `NETLIFY_SITES` | `""` | Limit to specific Netlify site names. Empty = all. |
| `DEPLOY_REPOS` | `""` | Repos to check for merges to `main`/`master` (git fallback). |
| `DEPLOY_GIT_FETCH` | `true` | `git fetch` before checking. |

## Managing it

```bash
./recap.sh --dry-run                                       # preview anytime
launchctl kickstart -k gui/$(id -u)/com.dailyrecap.agent   # run the scheduled job now
launchctl list | grep dailyrecap                           # is it loaded?
./uninstall.sh                                             # stop the schedule
tail -f recap.log                                          # watch logs
```

## Sharing with a colleague

Fully generic — nothing is hardcoded to one machine. A colleague:

1. Clones the repo.
2. `cp config.example.sh config.sh`, pastes **their own** webhook (adjust `WORKSPACE_DIR`,
   `DEPLOY_REPOS`, etc. as needed).
3. `chmod +x *.sh && ./install.sh`.

`GIT_AUTHOR_FILTER="auto"` reads their own git email, so each person gets a recap of *their*
work. Everyone keeps their own `config.sh` (it's gitignored).

## Notes & limits

- **Mac must be awake at the scheduled time.** If asleep, `launchd` runs the job on next wake.
  To force a wake on weekdays: `sudo pmset repeat wakeorpoweron MTWRF 08:54:00`.
- **Secrets** live only in `config.sh` (gitignored) — webhook, Netlify token. Treat the
  webhook like a password.
- **Not macOS?** The collection logic in `recap.sh` is portable; only `install.sh` uses
  `launchd`. On Linux, schedule `recap.sh` with cron/systemd.

## Troubleshooting

- Nothing posted? Run `./recap.sh --dry-run` and check `recap.log`.
- `jq not found` → `brew install jq`.
- AI summary missing but a plain list arrived → the `claude` CLI wasn't found / not logged in
  (it falls back automatically).
- Test the webhook directly:
  ```bash
  curl -H 'Content-Type: application/json' -d '{"content":"recap test"}' "$DISCORD_WEBHOOK_URL"
  ```
