---
name: supabase-security
description: Apply Velvet Grill's Supabase/PostgreSQL security rules for RLS, ownership, migrations, and transactional integrity.
---

# Supabase Security

Follow `ARCHITECTURE.md` and `SECURITY_WORKFLOW.md`.

Check that:

- RLS remains enabled and tested
- ownership is explicit
- server-controlled writes remain protected
- schema changes use migrations
- generated types are not manually edited
- stock/order/payment changes preserve transaction and idempotency rules

Destructive database operations require human approval.
