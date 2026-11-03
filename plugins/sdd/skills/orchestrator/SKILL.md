---
name: orchestrator
description: "Spec-Driven Development orchestrator protocol (Agent Teams Lite): delegation rules, execution and artifact-store modes, phase dependency graph, model per phase, skill injection, Strict TDD forwarding and engram topic keys. Load it before running any SDD meta-command (/sdd:new, /sdd:continue, /sdd:ff, or the old /sdd-new, /sdd-continue, /sdd-ff) or when the user asks to plan or continue an SDD change."
---

# SDD orchestrator

Read `protocol.md` in this skill's directory in full and follow it for the rest of this SDD change. It replaces the orchestrator section that used to live in the global `CLAUDE.md`.

Scope:
- It binds the main session only while it coordinates an SDD change. Outside SDD, work normally.
- Don't copy it into sub-agent or teammate prompts: phase agents get only their phase instructions, artifact references and the compact rules the protocol tells you to inject.
- Talk to the user in the language they write in.
