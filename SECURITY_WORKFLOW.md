# Velvet Grill — Security Workflow

## Scope

This file is the detailed security reference. General agent rules belong in `AGENTS.md`; architectural details belong in `ARCHITECTURE.md`.

## 1. Threat Model

Assume:

- browser input is attacker-controlled
- users can inspect and replay requests
- hidden UI is not access control
- client-provided prices are untrusted
- analytics can be spoofed
- retries and concurrent requests can happen

## 2. Security Priorities

1. Authentication
2. Authorization
3. Input validation
4. Server authority
5. Database integrity
6. RLS
7. Secret management
8. Transactional integrity
9. Auditability
10. Safe failure

## 3. Sensitive Operations

Human review is required for:

- role/admin authorization changes
- pricing/coupon/stock/order/payment logic
- RLS or permission changes
- schema/migration changes with security impact
- secret/configuration changes
- audit logging changes
- destructive database operations
- Git history rewrites
- production deployment configuration

## 4. Validation vs Authorization

Validation answers:

> Is this input structurally valid?

Authorization answers:

> Is this actor allowed to perform this action?

Both may be required.

Use Zod or equivalent strict validation at application boundaries.

## 5. Server Authority

Do not trust the browser for:

- final price
- discount amount
- coupon validity
- stock
- role
- order ownership
- order state
- payment state
- admin privileges
- dine-in table validity

The server/database must derive or verify authoritative values.

## 6. Database and RLS

- Keep RLS enabled.
- Test RLS behavior, not only SQL syntax.
- Use explicit column qualification where policy expressions could be ambiguous.
- Minimize client write permissions.
- Keep server-controlled tables server-controlled.
- Do not disable RLS as a shortcut.

## 7. Order, Payment, and Stock Integrity

- Enforce the order state transitions defined in `ARCHITECTURE.md` server-side.
- Enforce the payment state transitions defined in `ARCHITECTURE.md` server-side.
- Never accept order or payment state changes directly from the browser.
- Digital payment orders must satisfy the required payment condition before entering `PREPARING`.
- Cash orders may remain `UNPAID` while in `PREPARING` and become `PAID` when payment is confirmed at fulfillment.
- An order must not enter `COMPLETED` unless `orders.payment_status = PAID` (universal across payment methods).
- Use idempotency for retry-sensitive operations such as order creation, payment transitions, coupon usage, and stock mutation.
- Use an atomic database transaction for stock mutation and order creation when both operations must succeed together.
- Prefer a conditional atomic update or RPC/database function over a select-then-update stock pattern.
- Treat `SELECT ... FOR UPDATE` as a tool when required, not as a mandatory pattern.
- A failed stock mutation must not leave a partially created order.

### Notifications (in-app)

- Notification creation is server-authoritative and atomic with the business event; clients have no INSERT or DELETE on `public.notifications`.
- The recipient is derived server-side from `orders.user_id`, never from browser input.
- Customers may read, and toggle `is_read` on, only their own notifications. RLS plus a column-level `UPDATE (is_read)` grant enforce this; no other notification column is client-writable.

## 8. Dine-In Table Security

`table_id` from a URL, QR code, hidden form field, or browser state is untrusted.

At order finalization, verify:

- table exists
- table is active
- table is eligible for dine-in
- the order is allowed to use that table according to the current business rule

The server must resolve the client-provided `table_id` to the validated restaurant table record.

Only the server-validated table reference may be stored in the order.

Do not authorize a table solely because the client provided its identifier.

## 9. Secrets

Never:

- paste secrets into chat
- commit API keys
- hardcode service-role keys
- expose server secrets through `NEXT_PUBLIC_*`
- ask an agent to print secret values

If a secret may have leaked, rotate it.

## 10. Destructive Operations

Explicit human approval is required before:

- `supabase db reset`
- dropping tables/columns
- destructive data deletion
- disabling RLS
- broadening permissions
- rewriting migration history
- force pushing Git history

## 11. Security Review Checklist

Before completion of a security-sensitive change:

- [ ] authentication considered
- [ ] authorization enforced
- [ ] input validated
- [ ] server authority preserved
- [ ] order/payment state transitions remain valid
- [ ] dine-in table validation remains server-authoritative when applicable
- [ ] stock concurrency and atomicity considered when applicable
- [ ] RLS preserved/tested
- [ ] secrets protected
- [ ] retry/idempotency considered
- [ ] audit requirement considered
- [ ] relevant tests passed
