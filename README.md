# claude

Personal Claude Code plugin marketplace.

| Plugin | What it is |
|---|---|
| [`team`](plugins/team/README.md) | Generic agent team (front, back, database, designer, ai, reviewer) that combines with each repo's own specialists. Off by default |
| [`guardrails`](plugins/guardrails/README.md) | Safety rules enforced with hooks: no commit or push, database writes only on local databases, confirmation before destructive changes. On everywhere |
| [`sdd`](plugins/sdd/README.md) | Spec-Driven Development orchestrator on demand: `/sdd:new`, `/sdd:continue`, `/sdd:ff`. The protocol loads only when you use them |

## Install

```bash
claude plugin marketplace add ~/Code/agent-team-kit
claude plugin install guardrails@marcperez-plugins
claude plugin install team@marcperez-plugins
claude plugin install sdd@marcperez-plugins
```

Then, in each repo where you want the team:

```bash
claude plugin enable team@marcperez-plugins --scope project
```

## Miniverse

[`miniverse/`](miniverse) is the pixel-art office where the team works. The `team` plugin starts it and opens its window when a team session begins, and builds the office from the repo's `.claude/team.json`.

```bash
cd miniverse && npm install
scripts/login-item.sh install     # keep the server running from login (macOS LaunchAgent)
scripts/login-item.sh status
```

Characters: `scripts/fix-citizens.mjs && scripts/recolor-citizens.mjs` rebuilds the 8 looks from the 4 bundled sprites.

## Test

```bash
plugins/team/tests/run.sh
plugins/guardrails/tests/run.sh
```
