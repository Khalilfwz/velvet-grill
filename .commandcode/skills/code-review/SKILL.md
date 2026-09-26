---
name: code-review
description: Review Velvet Grill changes before commit.
---

# Code Review

Use the project references rather than duplicating their full rules.

Review for:

- PRD compliance
- architecture boundaries
- security regressions
- accessibility
- performance
- unnecessary dependencies
- unnecessary scope
- test coverage appropriate to the change

Run:

```bash
git diff
git status
```

and relevant validation commands before declaring completion.
