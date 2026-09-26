---
name: secure-nextjs
description: Apply Velvet Grill's secure Next.js boundaries for validation, authorization, secrets, and server authority.
---

# Secure Next.js

Follow `ARCHITECTURE.md` and `SECURITY_WORKFLOW.md`.

Check that:

- external input is validated
- authorization is enforced
- business-critical values are server-authoritative
- secrets remain server-side
- protected data is not exposed through client boundaries
- errors do not leak sensitive information

Do not weaken security controls to simplify implementation.
