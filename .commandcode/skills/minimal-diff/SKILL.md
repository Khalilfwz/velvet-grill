---
name: minimal-diff
description: Keep Velvet Grill changes small, intentional, and reviewable.
---

# Minimal Diff

Use when implementing, fixing, refactoring, or polishing.

- Inspect existing patterns first.
- Modify only necessary files.
- Reuse existing components/utilities.
- Avoid speculative abstraction and unrelated cleanup.
- Do not add a dependency without a concrete need.
- Preserve security/error-handling behavior.
- Report unrelated issues instead of silently fixing them.
- Summarize changed files before completion.

Project architecture and security rules remain authoritative.
