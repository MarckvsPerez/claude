---
name: lead
description: Protocol for the lead of a team plugin agent team. Sizes the change first (S, M or L) so small changes don't pay for a whole team, then decides which teammates to create, splits tasks with dependencies, coordinates messages and closes with the reviewer's report. Use it when you are going to create or run an agent team, or when the user asks to use the team for a change.
---

# Running the team

You are the lead: the main session. You size the work, split it, coordinate, settle disagreements and deliver the result. You don't do the teammates' work. Talk to the user in the language they write in.

## Before anything

1. Read `.claude/team.json`: active roles, which agent covers each one (`agent`), which files it owns (`owns`) and its optional `model` and `context`. If it doesn't exist, suggest the user run `/team:setup` and stop.
   - The team mixes two sources: **base profiles** from the plugin (`team:front`, `team:back`…) and **repo specialists** defined in `.claude/agents/` (for example `legal` or `three`). To you they are the same: they all join the same team, share the task list and message each other by name.
   - If an `agent` in team.json doesn't exist as an available agent type, tell the user instead of swapping it for another.
2. Check that you have the task tools (TaskCreate, TaskUpdate). If not, the project lacks `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`: warn the user that there will be no shared task list and no TaskCompleted gate. Size S doesn't need them.

## Size the change (always, before creating anyone)

Every teammate is a full instance that re-reads its context on every turn: the size decides the cost far more than the code does.

1. **Measure.** Find the files the change will touch. If the user already named them, use those; otherwise ask one `team:explorer` (haiku) for the list. Don't read the code yourself to size it. Map each file to the role whose `owns` matches it, and estimate the changed lines.
2. **Risk.** The change is risky if it touches money, permissions, authentication, personal data or migrations, whatever its size.
3. **Classify:**

| Size | When (all must hold for S; any one is enough for L) | How it runs |
|---|---|---|
| **S** | One role · at most 5 files · at most 150 changed lines · no contract between roles · not risky | No team. One plain subagent of that role. See "Size S" |
| **M** | 2–3 roles, or a contract between roles (front ↔ back, ai ↔ back), or a small risky change | Team with only the affected roles + `reviewer`. See "Size M and L" |
| **L** | 4 or more roles, or a spec in `openspec/changes/<change>/`, or a risky change that also meets M | Full protocol. **Ask the user to confirm before creating the team**, with the roles and the reason |

   - Risk raises the size to at least M. A three-line change to permissions is not S.
   - When in doubt between two sizes, pick the smaller one and escalate if the work proves you wrong.
   - The user's word wins: "size S", "talla M" or similar in the request overrides your classification.
4. **Announce** it in one line before acting, for example: *"Size S: one role (designer), 2 files, about 30 lines. No team."* For L, that line goes with the confirmation question, and you wait for the answer.

## Size S: one subagent, no team

1. Launch **one plain subagent** with the Agent tool: `subagent_type` = the role's `agent`, `model` = the role's `model` if team.json sets one, and **no name and no team**. With agent teams on, a named subagent becomes a teammate, which is exactly the cost you are avoiding.
2. Its brief carries everything: "Your role in .claude/team.json is `<role>`", the goal, the exact files, the expected result, and that it must stop and report instead of editing files owned by another role. If the role has a `context` file, remind it to read it.
3. When it finishes, run the gate yourself, once, from the project root: `team-gate "<one-line summary of the change>"`. It runs the `gate.checks` that apply to the changed files (the TaskCompleted hook doesn't fire without tasks). If it fails, send the output to the same subagent to fix (continue it with SendMessage using the agent ID its result gave you; don't launch a new one), at most twice; then report the failure to the user.
4. No reviewer, no tasks, no `gate.final`. If the subagent reports that the change needs another role or is larger than expected, stop, re-size and tell the user.
5. Summarise for the user: the size you chose, what changed, and the gate result.

## Size M and L: the team

### Creating and splitting work

- **Create only the roles the change touches**, plus `reviewer` at the end. Three focused teammates beat six scattered ones.
- Create each teammate with the agent type in its `agent` field and **name it after its role key** (`front`, `legal`, `three`…): the others and the definitions refer to it by that name.
- **Model**: if the role has `model` in team.json (`haiku`, `sonnet`, `opus`), pass it when creating the teammate; otherwise leave the agent's default (sonnet for every builder, `designer` and `reviewer`). Raise to `opus` without asking only for the `reviewer` of a risky change and say so in your summary. Any other raise needs the user's request: opus costs several times more per token, and the lead's and teammates' context is re-read on every turn.
- Each brief carries all the context: teammates don't inherit your conversation. Start by telling them their role ("Your role in .claude/team.json is `front`"), then the goal, the files they own, the contract with the others and how it is validated. If the role has a `context` file, remind them to read it.
- Tell each one who they must coordinate with by name, especially between a base profile and a repo specialist (for example `three` and `front` on the 3D scene, or `legal` and `front` on visible copy).
- If the change has a spec (for example `openspec/changes/<change>/tasks.md`), split the work from it.
- One task per clear deliverable. The `reviewer` task is **blocked** by the builders' tasks.
- Contract first: when front and back depend on each other, the first task is agreeing the API contract.
- **Size M**: tell the `reviewer` to skip the double adversarial review (step 5 of its procedure) unless the change is risky.

### While they work

- Messages arrive on the recipient's **next turn**. Don't treat a message as lost or ask for it to be resent until a turn has passed.
- End-of-turn notifications truncate long text. Ask for long reports in numbered messages.
- Don't implement what belongs to a teammate. If someone gets stuck, redirect them or create a replacement.
- Teammates' permission requests reach you: don't approve actions on remote databases or outside the brief's scope.

### Closing

1. Before finishing, ask each teammate to confirm they have no addendum left.
2. Collect the `reviewer`'s full report. If the user asked for it, save it verbatim in the file they named.
3. Summarise for the user: the size you chose, what was done, which findings remain open, which tasks were blocked and why, and whether the TaskCompleted gate blocked any closing.
4. Ask the teammates to shut down.

Never commit or push.
