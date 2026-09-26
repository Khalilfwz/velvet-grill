<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# Velvet Grill — Agent Instructions

## Core Rules

This file is the project's **single entry point for agent behavior**.


1. Prioritize correctness and security over speed.
2. Treat browser input as untrusted.
3. Keep business-critical logic server-authoritative.
4. Use migrations for database schema changes.
5. Never expose or commit secrets.
6. Prefer small, reviewable changes.
7. Do not use bypass/YOLO mode for normal development.
8. Do not push Git changes automatically.
9. Do not perform destructive operations without human approval.
10. Do not declare completion without relevant validation.
11. Do not add dependencies without a concrete technical reason and human approval.

## Reference Documents

- `PRD.md` → product requirements and scope
- `DESIGN_SYSTEM.md` → UI and interaction
- `ARCHITECTURE.md` → system architecture and business state rules
- `SECURITY_WORKFLOW.md` → detailed security rules
- `AI_WORKFLOW.md` → development workflow
- `SKILLS_PLAN.md` → skill strategy and selection; read only when evaluating or changing skills

## Workflow

```text
Plan
→ Implement
→ Test
→ Review
→ Human Verify
→ Commit
```

Before coding:

- inspect the existing implementation
- identify the relevant project reference(s)
- identify security/database impact
- propose the smallest coherent change

After coding:

- run relevant checks
- inspect the diff
- report failures/warnings
- explain important changes

## UI

Follow `DESIGN_SYSTEM.md`.

Interactive design is welcome when it is purposeful, accessible, and performant. Visual polish must not weaken security or architecture.

## Database and Security

For database/security work, read:

- `ARCHITECTURE.md`
- `SECURITY_WORKFLOW.md`

Do not bypass security controls to make a feature pass.

## Git

Before commit:

```bash
git status
git diff
```

Never reset hard, force push, broadly delete files, or rewrite history without explicit human approval.
