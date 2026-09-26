# Velvet Grill — Pre-Command Code Documentation Pack

This pack contains the Markdown documentation required to prepare Velvet Grill for Command Code.

## Core references

- `PRD.md` — what the product is and what is in/out of scope
- `DESIGN_SYSTEM.md` — visual and interaction rules
- `ARCHITECTURE.md` — technical boundaries, state models, dine-in context, stock atomicity, and testing stack
- `AGENTS.md` — single entry point for agent behavior

## Supporting references

- `SECURITY_WORKFLOW.md` — detailed security rules
- `AI_WORKFLOW.md` — Plan → Implement → Test → Review → Verify → Commit
- `SKILLS_PLAN.md` — project and external skill strategy
- `PRE_COMMANDCODE_CHECKLIST.md` — final pre-install/subscription checklist

## Not included

The Command Code JSON configuration is intentionally excluded from this Markdown review pack. It will be reviewed separately before installation.

## Documentation principle

Avoid duplicating the same rule across documents.

Use each file for its own purpose:

```text
PRD              → what
DESIGN_SYSTEM    → how it should look/behave
ARCHITECTURE     → how the system works
AGENTS           → how the agent operates
SECURITY         → how security is enforced
AI_WORKFLOW      → how work is performed
SKILLS_PLAN      → how skills are selected
CHECKLIST        → readiness gate
```
