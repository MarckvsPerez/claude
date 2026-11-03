---
name: new
description: "Start a new SDD change: init guard, then exploration and proposal through sub-agents."
argument-hint: "<change-name>"
disable-model-invocation: true
---

1. Load the `sdd:orchestrator` skill with the Skill tool and read its `protocol.md` if you haven't in this session.
2. Start the change named in the arguments: run the SDD Init Guard, ask the execution mode and the artifact store if this is the first SDD command of the session, then delegate `sdd-explore` and `sdd-propose`.

Arguments: $ARGUMENTS
