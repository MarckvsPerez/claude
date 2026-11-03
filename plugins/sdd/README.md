# `sdd` plugin

Spec-Driven Development orchestrator **on demand**.

Before, the orchestrator protocol (~13 KB) lived in the global `CLAUDE.md`: every session, subagent and teammate loaded it and read "delegate ALL real work", even when it only had to edit a CSS file. Now it loads only when you ask for SDD.

| Command | What it does |
|---|---|
| `/sdd:new <change>` | Init guard, then exploration + proposal through sub-agents |
| `/sdd:continue [change]` | Next dependency-ready phase |
| `/sdd:ff <change>` | Proposal → specs + design → tasks, stops before apply |

The three commands load the `sdd:orchestrator` skill, whose `protocol.md` is the full protocol (delegation, modes, model per phase, skill injection, Strict TDD forwarding, engram topic keys).

The phase skills (`sdd-init`, `sdd-explore`, `sdd-apply`, `sdd-verify`…) and `_shared/` stay in `~/.claude/skills/`, where the gentle-ai installer puts them.

## Install

```bash
claude plugin marketplace update marcperez-plugins
claude plugin install sdd@marcperez-plugins
```

It only adds four skill descriptions to the listing, so it can stay enabled globally. To have it in a single repo instead: `claude plugin disable sdd@marcperez-plugins` and `claude plugin enable sdd@marcperez-plugins --scope project` there.

## Caveat

The gentle-ai installer writes the orchestrator block into `~/.claude/CLAUDE.md` between `<!-- gentle-ai:sdd-orchestrator -->` markers. If you run it again, remove that block again or the protocol will be loaded twice.
