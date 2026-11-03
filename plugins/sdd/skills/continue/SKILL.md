---
name: continue
description: "Run the next dependency-ready SDD phase of a change through sub-agents."
argument-hint: "[change-name]"
disable-model-invocation: true
---

1. Load the `sdd:orchestrator` skill with the Skill tool and read its `protocol.md` if you haven't in this session.
2. Recover the change's state (Recovery Rule), find the next phases whose dependencies are done and delegate them. If no change is named and there is more than one in progress, ask which one.

Arguments: $ARGUMENTS
