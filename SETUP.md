# Setup — Daily Dev Recap

A 2-minute setup. Every weekday morning at **08:55** you get a Discord message recapping what
you did the day before across your git repos (commits, work-in-progress, optional Claude Code
sessions), whether you **deployed**, and your **to-do list for today**.

It runs locally on your Mac via `launchd`, so it works even when your editor is closed. Full
reference and options are in [`README.md`](./README.md).

---

## 1. Prerequisites

- **macOS** (uses `launchd` for scheduling).
- **jq** — `brew install jq`
- **Claude CLI** (optional, for the AI-written summary). Without it you get a plain list.

Quick check:
```bash
jq --version
```

## 2. Get the code

```bash
git clone <REPO_URL> daily-recap
cd daily-recap
```

## 3. Create your config

```bash
cp config.example.sh config.sh
```
Open `config.sh` and set at least these:
```bash
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXX/YYYY"   # your webhook
WORKSPACE_DIR="$HOME/code"                                         # folder holding your repos
```
> Get a webhook: Discord → your channel → **Edit Channel → Integrations → Webhooks → New
> Webhook → Copy Webhook URL**. A one-person private server makes a great private feed.
>
> ⚠️ `config.sh` is gitignored — it holds your secrets (webhook, any Netlify token) and must
> never be committed. Everyone uses their **own** `config.sh`.

## 4. Make the scripts executable

```bash
chmod +x recap.sh install.sh uninstall.sh todo.sh
```

## 5. Test, then schedule

```bash
./recap.sh --dry-run     # preview in the terminal (no Discord post)
./recap.sh               # send one real recap to your Discord
./install.sh             # schedule it for 08:55, Mon–Fri
```

That's it. ✅

---

## Optional extras

- **Deploy detection.** Add a Netlify token to `config.sh` (`NETLIFY_AUTH_TOKEN`) for true
  production-deploy detection, or set `DEPLOY_REPOS="repo-a repo-b"` to detect merges into
  `main`/`master`. See README → *Deployments*.
- **To-dos.** Tasks that show up at the bottom of each recap:
  ```bash
  ./todo.sh add "Finish the gate screen"
  ./todo.sh            # list
  ./todo.sh done 1     # complete #1
  ```
  Handy alias (`~/.zshrc`): `alias todo="$(pwd)/todo.sh"`
- **Reliable wake-up.** launchd only fires while the Mac is awake; if it's asleep at 08:55 the
  job runs on next wake. To force a weekday wake:
  `sudo pmset repeat wakeorpoweron MTWRF 08:54:00`

## Everyday use

```bash
./recap.sh --dry-run                                       # preview anytime
tail -f recap.log                                          # see what happened
launchctl kickstart -k gui/$(id -u)/com.dailyrecap.agent   # run the scheduled job now
./uninstall.sh                                             # stop the schedule
```

## Common settings in `config.sh`

| Setting | Default |
|---|---|
| Send time | `08:55`, Mon–Fri (`RECAP_HOUR`/`RECAP_MINUTE`, `SKIP_WEEKENDS`) |
| Workspace scanned | `$HOME/code` (`WORKSPACE_DIR`) |
| Whose commits | yours only, auto-detected (`GIT_AUTHOR_FILTER`) |
| AI summary | on (`USE_AI_SUMMARY`) |
| Claude Code sessions | off (`INCLUDE_CLAUDE_SESSIONS`) |
| Deploy detection | Netlify token or `DEPLOY_REPOS` |

See [`README.md`](./README.md) for the complete list and troubleshooting.
