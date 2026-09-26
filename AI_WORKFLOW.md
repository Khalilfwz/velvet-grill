# Velvet Grill — AI Development Workflow

## Purpose

This defines how the human and coding agent collaborate. Detailed product, architecture, design, and security rules live in their dedicated documents.

## 1. Plan

Use plan mode for substantial tasks.

The plan should identify:

- affected files
- relevant requirement(s)
- architecture/security impact
- database impact
- validation/tests
- risks

Do not start broad implementation when the task boundary is unclear.

## 2. Implement

- Prefer the smallest coherent change.
- Reuse existing components/utilities.
- Follow existing project conventions.
- Avoid speculative refactoring.
- Avoid unrelated cleanup.

## 3. Test

Run the smallest meaningful validation set.

Examples:

```bash
npm run lint
npm run build
```

For database/RLS changes, run the relevant Supabase/pgTAP tests.

For critical user flows, use Playwright once those flows exist.

Do not run a full E2E suite for every UI change.

## 4. Review

Before commit:

```bash
git status
git diff
```

Check:

- unexpected files
- scope creep
- dependency changes
- client/server boundary
- security regressions
- design-system violations
- duplicated logic

## 5. Human Verification

The human must understand:

- what changed
- why it changed
- what was tested
- what remains uncertain

The agent must not use successful generation as evidence of correctness.

## 6. Commit

Only after review:

```bash
git add <specific-files>
git commit -m "..."
```

Do not push automatically.

## 7. Anti-Slop

Avoid:

- large abstractions for small problems
- unnecessary rewrites
- unnecessary dependencies
- decorative UI without purpose
- duplicate components
- verbose comments that restate obvious code
- unrelated scope expansion

For UI work, follow `DESIGN_SYSTEM.md`.

## 8. Token Efficiency

Prefer:

- focused tasks
- targeted file reads
- concise iterations
- separate sessions for unrelated work
- reusable project context
- concise responses

Token efficiency must never override correctness, security, accessibility, or maintainability.
