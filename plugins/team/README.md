# `team` plugin

A generic agent team for Claude Code. Install it once and enable it in the projects that use it.

```
LEAD  (the main session; skill team:lead)
  ├── team:front      UI builder
  ├── team:back       API, logic and migrations builder
  ├── team:database   read-only data auditor
  ├── team:designer   design system and accessibility (proposes, front implements)
  ├── team:ai         LLM features: prompts, evals, cost, safety
  └── team:reviewer   final inspector
        └── shared workers: team:explorer · team:test-runner · team:docs-researcher
```

Teammates can't create their own team, but they can launch subagents. Workers are cheap (haiku and sonnet) and anyone can use them.

## Base profiles and repo specialists

There isn't a general team and a repo team: there is **one team** with members from two sources. The lead creates teammates both from the plugin's profiles and from the agents defined in the repo's `.claude/agents/`, and they all share the task list and message each other by name.

```
LEAD
  ├── team:front, team:back, team:reviewer…   base profiles (plugin)
  └── legal, payments, three…                 specialists (repo's .claude/agents/)
```

- A **specialist** is created when the repo needs judgement no base profile has: a regulation, a provider, a very specific technology. Template: `templates/specialist.md`.
- A base profile is **adapted to the repo with an addendum** (`context` in team.json) instead of being copied: the agent reads it at start and its rules override the generic ones.

## What's included

| Component | What it does |
|---|---|
| `agents/` | 6 profiles and 3 workers |
| `skills/setup` | `/team:setup`: reads the project, proposes roles and generates its configuration |
| `skills/lead` | Lead protocol: create, split, coordinate and close |
| `hooks/hooks.json` | TaskCompleted (checks + quick review), database guard and Miniverse bridge |
| `bin/db-query` | Read-only queries on the local database, for the database agent |
| `templates/` | Project configuration (`team.example.json`) and specialist template |

Agents reply to the user in the language they write in, even though their definitions are in English.

## Per-project configuration

Everything project-specific lives in `.claude/team.json`: for each role, which agent covers it (`agent`), which files it owns (`owns`) and its addendum (`context`); plus the quality checks, the read-only database connection and Miniverse. **Without that file the hooks do nothing**, not even the database guard.

A plugin can't set environment variables, so each project turns on in its `.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1", "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1" } }
```

Don't turn it on globally: with agent teams on, any named subagent becomes a teammate.

## Install

Once, from a terminal:

```bash
claude plugin marketplace add ~/Code/agent-team-kit
claude plugin install team@marcperez-plugins
```

The plugin ships with `defaultEnabled: false`: it stays **installed but off** in every project, so its agents don't show up where nobody configured them. In each repo where you want the team:

```bash
claude plugin enable team@marcperez-plugins --scope project
```

`--scope project` writes it to the repo's `.claude/settings.json` and shares it with whoever clones it; `--scope local` keeps it for you only. Then, in a new session of that repo: `/team:setup`.

## Test the scripts

```bash
plugins/team/tests/run.sh
```
