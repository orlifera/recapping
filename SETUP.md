# Setup — Parkito Daily Recap

A 2-minute setup. Every weekday morning at **8:55am** you get a Discord message recapping
what you did the day before across your Parkito repos (commits, work-in-progress, Claude Code
sessions), whether you **deployed**, and your **to-do list for today**.

It runs locally on your Mac via `launchd`, so it works even when your editor/Claude Code is
closed. Full reference and options are in [`README.md`](./README.md).

---

## 1. Prerequisites

- **macOS** (uses `launchd` for scheduling).
- **jq** — `brew install jq`
- **Claude Code CLI** (optional, for the AI-written summary) — already installed if you use
  Claude Code. Without it, you get a plain structured list instead.

Quick check:
```bash
jq --version && claude --version
```

## 2. Get the code

```bash
git clone <REPO_URL> parkito-daily-recap
cd parkito-daily-recap
```
Put it wherever you like; it scans `~/Parkito` by default (change `WORKSPACE_DIR` if your repos
live elsewhere).

## 3. Create your config

```bash
cp config.example.sh config.sh
```
Open `config.sh` and set **your own** Discord webhook:
```bash
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXX/YYYY"
```
> Get a webhook: Discord → your channel → **Edit Channel → Integrations → Webhooks → New
> Webhook → Copy Webhook URL**. A one-person private server makes a great private feed.
>
> ⚠️ `config.sh` is gitignored — it holds your secret webhook and must never be committed.
> Everyone uses their **own** `config.sh`.

## 4. Make the scripts executable

```bash
chmod +x recap.sh install.sh uninstall.sh todo.sh
```

## 5. Test, then schedule

```bash
./recap.sh --dry-run     # preview in the terminal (no Discord post)
./recap.sh               # send one real recap to your Discord
./install.sh             # schedule it for 8:55am, Mon–Fri
```

That's it. ✅

---

## Optional extras

- **Deploy detection.** Out of the box it reports a deploy when commits land on
  `main`/`master` in `parkito-web`/`parkito-host`. For true production-deploy detection, add a
  Netlify token to `config.sh` (`NETLIFY_AUTH_TOKEN`) — see README → *Deployments*.
- **To-dos.** Add tasks that show up at the bottom of each recap:
  ```bash
  ./todo.sh add "Finish the gate screen"
  ./todo.sh            # list
  ./todo.sh done 1     # complete #1
  ```
  Handy alias (`~/.zshrc`): `alias todo="$PWD/todo.sh"`
- **Reliable wake-up.** launchd only fires while the Mac is awake; if it's asleep at 8:55 the
  job runs on next wake. To force a wake on weekdays:
  `sudo pmset repeat wakeorpoweron MTWRF 08:54:00`

## Everyday use

```bash
./recap.sh --dry-run                         # preview anytime
tail -f recap.log                            # see what happened
launchctl kickstart -k gui/$(id -u)/com.parkito.dailyrecap   # run the scheduled job now
./uninstall.sh                               # stop the schedule
```

## Defaults you can change in `config.sh`

| Setting | Default |
|---|---|
| Send time | `08:55`, Mon–Fri (`RECAP_HOUR`/`RECAP_MINUTE`, `SKIP_WEEKENDS`) |
| Workspace scanned | `~/Parkito` (`WORKSPACE_DIR`) |
| Whose commits | yours only, auto-detected (`GIT_AUTHOR_FILTER`) |
| AI summary | on (`USE_AI_SUMMARY`) |
| Deploy repos | `parkito-web parkito-host` (`DEPLOY_REPOS`) |

See [`README.md`](./README.md) for the complete list and troubleshooting.
