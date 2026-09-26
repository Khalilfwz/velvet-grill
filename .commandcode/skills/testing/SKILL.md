---
name: testing
description: Choose the smallest meaningful validation set for Velvet Grill changes.
---

# Testing

Use `ARCHITECTURE.md` for the test stack.

1. Identify the behavior changed.
2. Run the smallest relevant test first.
3. Use Supabase CLI/pgTAP for database and RLS behavior.
4. Use Vitest/RTL when unit/component coverage is warranted.
5. Use Playwright for critical end-to-end flows once they exist.
6. Do not claim success when checks were skipped.
7. Report warnings separately from failures.
