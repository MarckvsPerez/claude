# `guardrails` plugin

Enforces with hooks the rules that can't be left to the model's memory. An instruction in `CLAUDE.md` can be forgotten or skipped; a `PreToolUse` hook runs before every command, also in auto mode and when the command was approved beforehand.

| Rule | Decision |
|---|---|
| `git commit`, `git push`, `gh pr create/merge`, `gh repo create/delete/sync` | **Deny** |
| Database write to a remote target, or one that may write (SQL from a file) without a visible local target | **Deny** |
| Migration or database write without an explicit host (`npx sequelize-cli db:migrate`, `prisma migrate deploy`…) | **Ask** |
| Database write to a verified local target (127.0.0.1 without a tunnel, `docker compose exec`, local socket) | Allow |
| Reads on any database (`SELECT`, `EXPLAIN`…) | Allow |
| `git reset --hard`, `git clean -f`, `git checkout -- .`, `git restore .`, `git stash drop/clear`, `git branch -D` | **Ask** |
| `rm -r` outside the project and temp folders, or with a broad wildcard | **Ask** |

It watches `Bash`, `Monitor` and the desktop app's terminal (`mcp__terminal__run_in_terminal`).

## How it decides whether a database is local

- `ssh`, `kubectl exec`, `gcloud`, `aws ssm`, `heroku`, `fly ssh`, `railway run` → remote.
- `docker exec` or `docker compose exec` without `DOCKER_HOST`, `--context` or `-H` → local.
- A host in `-h`, `--host`, a connection URL or `DB_HOST=`/`PGHOST=`… → local only if it is `127.0.0.1`, `localhost`, `::1` or `0.0.0.0`, **and** the port isn't served by a tunnel (`ssh`, `kubectl`, `cloud-sql-proxy`, `socat`…).
- A client without a host uses the local socket → local. A migration without a host → unknown → ask.
- If locality can't be confirmed and the command may write to a remote target, it is treated as remote.

## Known limits

- It scans the full command text, quoted parts included: `sh -c "git push"` is blocked, but so is `echo "git push"`.
- It can't see through shell aliases or scripts: an `npm run deploy` that runs `git push` inside isn't detected.
- Migrations read their target from their own configuration, which the guard doesn't open: that's why it asks instead of deciding.

## Install

This plugin goes **global and enabled**, because these are rules for all your projects:

```bash
claude plugin install guardrails@marcperez-plugins
```

## Test

```bash
plugins/guardrails/tests/run.sh
```
