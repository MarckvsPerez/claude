---
name: setup
description: Prepares a project to work with the team plugin's agent team. Reads the repository, proposes which roles are needed and which files each one owns, and generates .claude/team.json and the project configuration. Use it when the user wants to set up, configure or adapt the agent team in a project.
disable-model-invocation: true
---

# Set up the team in this project

You will leave the project ready for a lead session to create the `team` plugin's agent team. The goal is not to copy another project's configuration, but to generate THIS one from its real code.

Talk to the user in the language they write in, including the proposal in step 2.

## 1. Explore before proposing

With the `team:explorer` worker or with Read, Grep and Glob, find out:

- The project rules: `AGENTS.md` or `CLAUDE.md`.
- The stack: manifests (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`…), frameworks and their versions.
- The layout: where the UI, the API, the migrations, the styles and design tokens, the code that calls AI models and the documentation live.
- How quality is checked: typecheck, lint and test scripts for each package. Tell unit tests apart from tests that write to a database.
- The local database: engine, `docker compose` and published port, and the environment file with its variable names. **Don't read or show secret values**: names only.

## 2. Propose and wait for confirmation

Present the user a proposal with:

- **Base profiles** needed from the plugin's (`front`, `back`, `database`, `designer`, `ai`, `reviewer`) and which don't apply, with the reason.
- **Repo specialists**: what this project needs that no base profile covers well, such as a specific regulation (`legal`), a payment provider (`payments`) or a very specific technology (`three` for 3D and motion). Only when they bring their own judgement; don't duplicate a base profile under another name.
- **Context addenda** for the base profiles: what a base profile needs to know about this repo (versions, conventions, critical modules). One file per role, for example `docs/agents/front.md`, instead of copying the whole definition.
- For each role, the file patterns it owns (`owns`). No file can have two owners; shared files are assigned to one role and the others ask by message.
- The model per role (`model`), only where the default isn't enough. Every profile runs on sonnet (haiku for `explorer` and `test-runner`); propose `opus` only for roles whose judgement justifies paying several times more per token (a regulation specialist, a reviewer in a repo that handles money or personal data). The lead already raises the reviewer to opus for risky changes.
- The quality gate, split by cost, because it runs **every time a task closes**:
  - `gate.checks`: fast and scoped. Typecheck with an incremental cache (`tsc --noEmit --incremental`) and lint of the changed files only, with `{files}` in `run` (the gate replaces it with the changed files that match `when`; with `cwd`, it runs in that subfolder and the paths are relative to it, which is useful in monorepos such as `frontend/` and `backend/`). Use `--cache` when the linter supports it.
  - `gate.final`: slow, whole-project checks (`next build` or equivalent, the full unit suite). The `reviewer` runs them once, at the end of the change. Tests that write to a database **don't** go in either list.
- Whether to turn on the automatic per-task review (`gate.review`) and from what size (`gate.reviewMinLines`, for example 40). Warn that each review is one model call per closed task, and that below the threshold the final reviewer covers it.
- The read-only database configuration, if there is a database.
- Whether they want to watch the team in Miniverse.

**Don't write anything until the user confirms or adjusts the proposal.**

## 3. Generate the configuration

After confirmation:

1. Write `.claude/team.json` following the template `${CLAUDE_PLUGIN_ROOT}/templates/team.example.json`. Each role has `agent` (`team:<profile>` for base profiles, the repo agent's name for specialists), `owns` and, if they apply, `context` and `model`. Patterns are shell globs: `src/*` includes subfolders.
   - For each specialist, create `.claude/agents/<name>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/specialist.md`, with the repo's concrete criteria.
   - For each addendum, create the `context` file with concrete, verifiable rules, not generalities.
2. In the project's `.claude/settings.json`, add without removing what's already there:
   ```json
   { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1", "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1" } }
   ```
   Explain why it goes here and not in the global configuration: with agent teams on, any named subagent Claude launches becomes a teammate, and that isn't wanted in every project. Task tools are off by default on newer models, and without them there is no shared task list and TaskCompleted never fires.
3. If there is a database: don't create the user yourself. Write to `.claude/db/readonly-user.sql` the SQL to create a SELECT-only user on the local database, for the user to run, and tell them which variables to add to their environment file.
4. Add a short "Agent team" section to `AGENTS.md` or `CLAUDE.md`: the active roles, that the lead creates them from the `agent` in `.claude/team.json`, that changes go through `/team:run <change>` (or the `team:lead` skill), which sizes them first so small changes don't create a team.
5. If the project already had its own agents in `.claude/agents/`, decide with the user which become team specialists, which are replaced by a base profile with an addendum, and which are retired. They coexist with the plugin's (`front` and `team:front` are different agents).
6. If the project already had its own quality gate, database guard or Miniverse hooks in `.claude/settings.json`, point them out: with the plugin on they would run twice. Propose removing them, but don't delete them without confirmation.

## 4. Check

- `jq . .claude/team.json` with no errors.
- Feed the quality gate script a test task and confirm it exits 0 when there are no relevant changes:
  `echo '{"task_subject":"test"}' | CLAUDE_PROJECT_DIR="$PWD" "${CLAUDE_PLUGIN_ROOT}/scripts/quality-gate.sh"; echo $?`
- Remind the user that the new configuration loads when a new session starts.

Never commit or push.
