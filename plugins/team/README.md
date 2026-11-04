# `team` plugin

A generic agent team for Claude Code. Install it once and enable it in the projects that use it.

```
LEAD  (the main session; /team:run or skill team:lead)
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
- Miniverse shows **who works**, not team.json's role names. The main office is this plugin's agents (`agents/*.md`) by their own names, with the same desks and looks in every repo: two roles run by the same profile (`front-cliente` and `front-admin`, both `team:front`) are one character, "Front", whose tasks carry the role (`front-admin · Edit · Admin.tsx`). The repo's own agents (`.claude/agents/*.md`) work in the **annex**: its own floor, 4 desks and a row of sofas, all with the same `repo-agent` look. Repo agents past the fourth, alphabetically, get no character: their work shows up as the lead's, labelled with their name (`pagos · Edit · checkout.ts`).
- A base profile is **adapted to the repo with an addendum** (`context` in team.json) instead of being copied: the agent reads it at start and its rules override the generic ones.

## What's included

| Component | What it does |
|---|---|
| `agents/` | 6 profiles and 3 workers |
| `skills/setup` | `/team:setup`: reads the project, proposes roles and generates its configuration |
| `skills/run` | `/team:run <change>`: sizes the change and runs it with the lead protocol |
| `skills/lead` | Lead protocol: size, create, split, coordinate and close |
| `hooks/hooks.json` | TaskCompleted (checks + quick review), database guard and Miniverse bridge |
| `bin/db-query` | Read-only queries on the local database, for the database agent |
| `bin/team-gate` | Runs the `gate.checks` once outside a task, for size S changes |
| `templates/` | Project configuration (`team.example.json`) and specialist template |

Agents reply to the user in the language they write in, even though their definitions are in English.

## Per-project configuration

Everything project-specific lives in `.claude/team.json`: for each role, which agent covers it (`agent`), which files it owns (`owns`) its addendum (`context`) and, optionally, a stronger model (`model`); plus the quality checks, the read-only database connection and Miniverse.

### Sizes

The lead sizes every change before creating anyone (`/team:run` or the `team:lead` skill):

| Size | When | How it runs |
|---|---|---|
| **S** | One role, ≤ 5 files, ≤ 150 lines, no contract, not risky | One plain subagent of that role, then `team-gate` once. No team, no reviewer |
| **M** | 2–3 roles, a contract between roles, or a small risky change | Only the affected roles + `reviewer` |
| **L** | 4+ roles, an openspec change, or risky and large | Full team, **after you confirm** |

Risk (money, permissions, authentication, personal data, migrations) raises the size to at least M. Writing "size S/M/L" in the request overrides the lead's choice.

### Cost

Every profile runs on sonnet by default (haiku for `explorer` and `test-runner`). `opus` is reserved for roles with `"model": "opus"` in team.json and for the `reviewer` of risky changes (money, permissions, authentication, personal data, migrations), which the lead raises on its own.

The quality gate runs every time a task closes, so it is split by cost:

| Key | When it runs | What goes there |
|---|---|---|
| `gate.checks` | Every closed task, by the TaskCompleted hook | Fast, scoped checks: `tsc --noEmit --incremental`, `eslint --cache {files}`. `{files}` becomes the changed files matching `when`; `cwd` runs the check in a subfolder with relative paths |
| `gate.final` | Once, by the `reviewer` at the end | Slow, whole-project checks: build, full suite |
| `gate.review` + `gate.reviewMinLines` | Every closed task above the threshold | Sonnet review of the task's diff; smaller tasks are left to the final reviewer | **Without that file the hooks do nothing**, not even the database guard.

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

### Workspace: one team across several repos

A workspace is a folder that is **not** a repo and holds the repos as symlinks. The configuration lives there, so no repo is touched:

```bash
mkdir -p ~/Giunti/ws-<name> && cd ~/Giunti/ws-<name>
ln -s ../repo-api repo-api && ln -s ../repo-front repo-front   # one per repo
claude plugin enable team@marcperez-plugins --scope project
claude   # then /team:setup
```

Patterns carry the repo folder as prefix (`owns: ["repo-api/*"]`, `cwd: "repo-api"`), and the gate reads each repo's `git diff` on its own. A folder that groups repos (`psy-portal/{psy-portal-front,psy-portal-back}`) can be linked whole: repos one level down are found too, with the full path as prefix. Open Claude in the workspace folder, never inside one of the repos. The workspace may live inside another repo (even a stray `git init` in `$HOME`): what matters is that it isn't a repo's top folder.

## Test the scripts

```bash
plugins/team/tests/run.sh
```
