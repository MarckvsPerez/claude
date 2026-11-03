---
name: run
description: "Runs a change with the agent team, sized first: S goes to a single subagent, M to a small team, L to the full team after your confirmation."
argument-hint: "<change to make> [size S|M|L]"
disable-model-invocation: true
---

1. Load the `team:lead` skill with the Skill tool if it isn't loaded in this session.
2. Follow it for the change below, starting with "Size the change". If the arguments name a size, it overrides your classification.

Change: $ARGUMENTS
