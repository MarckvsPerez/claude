---
name: ff
description: "Fast-forward SDD planning for a change: proposal, specs, design and tasks back to back."
argument-hint: "<change-name>"
disable-model-invocation: true
---

1. Load the `sdd:orchestrator` skill with the Skill tool and read its `protocol.md` if you haven't in this session.
2. Run proposal → specs and design → tasks for the change named in the arguments, respecting the dependency graph, and stop before apply.

Arguments: $ARGUMENTS
