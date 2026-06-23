# Parkito Daily Recap

Every morning at **8:55am**, this posts a short AI-written recap of **what you did the
previous day** across your workspace — git commits, work-in-progress, and what you worked
on with Claude Code — followed by **your to-do list for today**, to a **Discord channel**
via webhook.

It runs **locally** via macOS `launchd`, so it works even when Claude Code (the app) is
closed. The only outbound call is to the Anthropic API to write the narrative (and that can
be turned off — see `USE_AI_SUMMARY`).

> 🚀 **New here? Start with [`SETUP.md`](./SETUP.md)** for a 2-minute quick start.

## What it reports

- **Shipped / fixed** — your git commits from the previous day, across every git repo in the
  workspace (auto-discovered; no need to list them).
- **In progress** — uncommitted changes (`git status`) per repo.
- **Explored** — the prompts from your Claude Code sessions for the workspace that day.
- **Deployed** — production deploys (via Netlify, or detected from merges into `main`/`master`).
  Only shown when you actually deployed — never a "you didn't deploy" message.

**Weekdays only.** By default it runs Mon–Fri and never on Sat/Sun. **Friday's work is
delivered Monday morning** (Monday's recap automatically reaches back through the weekend).
Set `SKIP_WEEKENDS=false` to run every day instead.

## Setup (≈3 minutes)

Requirements: macOS, [`jq`](https://jqlang.github.io/jq/) (`brew install jq`), and — if you
want the AI narrative — the `claude` CLI logged in. Both are auto-detected.

1. **Get a Discord webhook URL.**
   Discord → your channel → **Edit Channel** → **Integrations** → **Webhooks** →
   **New Webhook** → **Copy Webhook URL**.
   (A one-person private server works great as a private feed.)

2. **Create your config.**
   ```bash
   cd parkito-daily-recap
   cp config.example.sh config.sh
   ```
   Edit `config.sh` and paste your webhook into `DISCORD_WEBHOOK_URL`.
   Adjust `WORKSPACE_DIR` if your code lives somewhere other than `~/Parkito`.

3. **Make the scripts executable.**
   ```bash
   chmod +x recap.sh install.sh uninstall.sh
   ```

4. **Test it once.** Preview in the terminal without posting:
   ```bash
   ./recap.sh --dry-run
   ```
   Then do a real post to Discord:
   ```bash
   ./recap.sh
   ```

5. **Schedule it.**
   ```bash
   ./install.sh
   ```

That's it. To change the time, edit `RECAP_HOUR` / `RECAP_MINUTE` in `config.sh` and re-run
`./install.sh`.

## To-dos (what to do *today*)

Each recap ends with a **📋 To-dos for today** list — your own running task list, shown
verbatim (never rewritten by the AI). Manage it with `todo.sh`:

```bash
./todo.sh add "Finish the host gate screen"   # add a task
./todo.sh                                      # list open tasks
./todo.sh done 2                               # complete & remove task #2
./todo.sh clear                                # wipe the list
./todo.sh edit                                 # edit the raw list in $EDITOR
```

Tasks persist day to day until you mark them `done`, so the morning recap always shows
what's still open. Completed tasks are appended to `todos.done.log` with a timestamp.

Handy alias — add to `~/.zshrc` so you can run it from anywhere:
```bash
alias todo="$HOME/Parkito/parkito-daily-recap/todo.sh"
# then:  todo add "..."   /   todo done 1
```

The list lives in `todos.txt` (gitignored — personal, not shared).

## Deployments

The recap adds a **🚀 Deployed** line only when you actually shipped (it never reports the
absence of a deploy). Two ways it detects this:

- **Netlify (preferred, true production deploys).** Add a token in `config.sh`
  (`NETLIFY_AUTH_TOKEN`). Create one at **Netlify → User settings → Applications → Personal
  access tokens → New access token**. It then reports any `production` deploy that reached the
  `ready` state during the window. Optionally set `NETLIFY_SITES="site-a site-b"` to limit which
  sites count.
- **Git fallback (no token needed).** When no Netlify token is set, it `git fetch`es the repos in
  `DEPLOY_REPOS` (default `parkito-web parkito-host`) and reports new commits merged into the
  production branch (`main`/`master`) during the window — i.e. a release went out.

> The fetch needs your git auth to be reachable. From `launchd` your SSH key is usually
> available via the macOS Keychain; if a fetch can't run, it falls back to your last-fetched
> refs (it may then *miss* a very recent deploy, but it won't report a false one). Set
> `DEPLOY_GIT_FETCH=false` to skip fetching entirely.

## Configuration

All settings live in `config.sh` (see `config.example.sh` for the documented template):

| Setting | Default | Meaning |
|---|---|---|
| `DISCORD_WEBHOOK_URL` | — | Your webhook (required). Kept private; gitignored. |
| `WORKSPACE_DIR` | `$HOME/Parkito` | Folder to scan; each subfolder with a `.git` is included. |
| `GIT_AUTHOR_FILTER` | `auto` | `auto` = only your commits; `""` = all authors; or an explicit email. |
| `RECAP_HOUR` / `RECAP_MINUTE` | `8` / `55` | Send time (24h, local). |
| `LOOKBACK` | `smart` | `smart` = yesterday (Fri–Sun on Mondays); or a number of days. |
| `SKIP_WEEKENDS` | `true` | `true` = run Mon–Fri only, Friday reported Monday; `false` = daily. |
| `INCLUDE_UNCOMMITTED` | `true` | Include work-in-progress. |
| `INCLUDE_CLAUDE_SESSIONS` | `true` | Include Claude Code session prompts. |
| `USE_AI_SUMMARY` | `true` | `false` = plain list, fully offline. |
| `SEND_WHEN_EMPTY` | `true` | Send a short note on quiet days. |
| `NETLIFY_AUTH_TOKEN` | `""` | Netlify token → true production-deploy detection. Empty = git fallback. |
| `NETLIFY_SITES` | `""` | Limit to specific Netlify site names (space-separated). Empty = all. |
| `DEPLOY_REPOS` | `parkito-web parkito-host` | Repos to check for merges to `main`/`master`. |
| `DEPLOY_GIT_FETCH` | `true` | `git fetch` before checking so recent merges show up. |

## Managing it

```bash
launchctl kickstart -k gui/$(id -u)/com.parkito.dailyrecap   # run now under launchd
launchctl list | grep dailyrecap                             # is it loaded?
./uninstall.sh                                               # remove the schedule
tail -f recap.log                                            # watch logs
```

## Sharing with a colleague

It's fully generic — nothing is hardcoded to one machine. A colleague just:

1. Copies this folder.
2. `cp config.example.sh config.sh`, pastes **their own** webhook (and adjusts `WORKSPACE_DIR`
   if needed).
3. `chmod +x *.sh && ./install.sh`.

`GIT_AUTHOR_FILTER="auto"` reads their own git email, so each person gets a recap of *their*
work with no further edits.

## Notes & limits

- **Mac must be awake at the scheduled time.** If it's asleep, `launchd` runs the job at the
  next wake. (You could pair with a `pmset repeat wake` if you want a guaranteed wake-up.)
- **Privacy / secrets.** Your webhook lives only in `config.sh`, which `.gitignore` excludes.
  Anyone with the webhook URL can post to that channel — treat it like a password.
- **Not macOS?** The collection logic in `recap.sh` is portable; only `install.sh` is
  macOS-specific (`launchd`). On Linux, schedule `recap.sh` with cron/systemd instead.

## Troubleshooting

- Nothing posted? Run `./recap.sh` directly and check `recap.log`.
- `jq not found` → `brew install jq`.
- AI summary missing but a plain list arrived → the `claude` CLI wasn't found or not logged
  in; the script falls back to the raw report automatically.
- Test the webhook in isolation:
  ```bash
  curl -H 'Content-Type: application/json' -d '{"content":"recap test"}' "$DISCORD_WEBHOOK_URL"
  ```
