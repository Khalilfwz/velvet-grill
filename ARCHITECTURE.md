# Velvet Grill — Architecture

## 1. Purpose

This document defines system boundaries and business-critical technical rules. Product goals belong in `PRD.md`; visual rules belong in `DESIGN_SYSTEM.md`; agent operating rules belong in `AGENTS.md` and `AI_WORKFLOW.md`.

## 2. Stack

- Next.js 16
- TypeScript
- Tailwind CSS
- Supabase
- PostgreSQL
- Supabase Auth
- Supabase Storage
- Zod
- React Hook Form
- Lucide React
- Git
- GitHub
- Command Code for AI-assisted development

## 3. Runtime Boundaries

```text
Browser
  ↓
Next.js App Router
  ↓
Server-side application logic
  ↓
Supabase
  ├── Auth
  ├── PostgreSQL
  └── Storage
```

### Client

Responsible for presentation, interaction state, input collection, and safe optimistic UI.

### Server

Responsible for authorization, authoritative pricing, coupon validation, stock/order/payment orchestration, and other business-critical operations.

### Database

Responsible for persistence, relational integrity, constraints, RLS, transactional truth, and modeled audit records.

## 4. Core Data Model

Core entities include:

- profiles
- categories
- products
- product_images
- product_option_groups
- product_options
- carts
- cart_items
- cart_item_options
- wishlists
- wishlist_items
- orders
- order_items
- order_item_options
- payments
- order_status_history
- coupons
- coupon_usages
- reviews
- notifications
- restaurant_tables
- business_hours
- restaurant_settings
- analytics_events
- admin_audit_logs

The exact implemented schema is authoritative. This document describes intended architecture and must not be treated as permission to invent conflicting columns/enums.

## 5. Identity and Roles

Supabase Auth is the identity source.

`profiles.id` is linked 1:1 to `auth.users.id`.

Supported application roles:

- `CUSTOMER`
- `ADMIN`

There is intentionally no `MANAGER` role.

Customers cannot self-promote.

## 6. Server Authority

The browser must not be authoritative for:

- price
- discount amount
- coupon validity
- stock availability
- order ownership
- order status
- payment status
- user role
- admin privileges

Business-critical values are derived or verified server-side.

Detailed enforcement rules belong in `SECURITY_WORKFLOW.md`.

## 7. Database Change Rules

- All schema changes use migrations.
- `supabase/seed.sql` contains deterministic development data, not schema definition.
- `database.types.ts` is generated from the database and must not be manually edited.
- After schema changes, update generated types and run relevant tests.
- Do not silently modify historical migrations.

## 8. RLS

RLS is part of the database security boundary.

- Customer-owned records require ownership checks.
- Admin-only records require admin authorization.
- Server-controlled tables must not expose arbitrary client writes.
- Policy expressions should use explicit column qualification where ambiguity is possible.
- RLS behavior must be tested, not only syntax-checked.

## 9. Order Lifecycle

The order lifecycle is a business state machine.

### Canonical target lifecycle

```text
PENDING_PAYMENT
      ↓
  CONFIRMED
      ↓
  PREPARING
      ↓
    READY
      ↓
  COMPLETED
```

### Allowed transitions

| Current State     | Next State  | Condition                                                                |
| ----------------- | ----------- | ------------------------------------------------------------------------ |
| `PENDING_PAYMENT` | `CONFIRMED` | Order is valid and required payment/fulfillment conditions are satisfied |
| `CONFIRMED`       | `PREPARING` | Order is accepted and eligible for preparation                           |
| `PREPARING`       | `READY`     | Preparation is complete                                                  |
| `READY`           | `COMPLETED` | Order is fulfilled/handed over and `payment_status = PAID`                |
| `PENDING_PAYMENT` | `CANCELLED` | Order is cancelled before confirmation                                   |
| `CONFIRMED`       | `CANCELLED` | Cancellation is still permitted by business rules                        |

### Transition rules

- `PENDING_PAYMENT → CONFIRMED` only after order acceptance and a valid payment/fulfillment policy.
- `CONFIRMED → PREPARING` only when the order is eligible to enter preparation.
- `PREPARING → READY` only after preparation is complete.
- `READY → COMPLETED` only after fulfillment/handover and only when `payment_status = PAID`.
- A cancellation path must be explicitly defined per cancellable state before implementation.

### Cash policy

Cash is a fulfillment-time payment method.

For cash orders:

- The order may enter PREPARING while payment remains UNPAID.
- Cash payment must be recorded as PAID when payment is confirmed at fulfillment.
- The order may enter COMPLETED only after the fulfillment process is completed.
- Before `READY → COMPLETED`, an admin must confirm payment through the separate payment-confirmation action so `payment_status` becomes `PAID`.

For digital payment methods:

- Required payment conditions must be satisfied before the order enters PREPARING.

The implemented database enum/check constraints remain authoritative for the actual state names and allowed values.

## 10. Payment Lifecycle

Payment state is independent from order state.

### Canonical target lifecycle

```text
UNPAID
  ↓
PENDING
  ├──→ PAID
  ├──→ FAILED
  └──→ EXPIRED

PAID
  ↓
REFUNDED
```

### Payment method rules

Digital payment methods must follow the payment lifecycle above.

- `PAID` is required before a digital-payment order enters `PREPARING`.
- `FAILED` and `EXPIRED` payments must not be treated as successful payment.
- The browser must not directly change payment state.

Cash follows a separate fulfillment-time rule:

- Cash orders may remain `UNPAID` while in `PREPARING`.
- Cash payment becomes `PAID` when payment is confirmed at fulfillment.
- Cash orders do not use `PENDING`, `FAILED`, or `EXPIRED` as digital payment states.

The implemented DB enum/check constraints remain the authoritative representation.

Payment transitions must be validated server-side and must not be accepted from the browser.

### Payment Method Rules

- An order must not enter `COMPLETED` unless `payment_status = PAID`. This invariant is universal across payment methods.
- `PAID` does not itself advance `order_status`; payment confirmation (`confirm_order_payment`) and order completion (`update_order_status`) are separate admin actions, and completion never confirms payment.

Digital payment methods:
- Payment must progress through the payment lifecycle.
- `PAID` is required before a digital-payment order enters `PREPARING`.

Cash:
- Payment may remain `UNPAID` while the order is being prepared.
- Cash payment becomes `PAID` when payment is confirmed at fulfillment.
- Cash orders do not use digital payment states such as `PENDING`, `FAILED`, or `EXPIRED`.

## 11. Dine-In Table Context

Recommended UX:

```text
Table QR
  ↓
/menu?table_id=<opaque-id>
  ↓
cart/order context
  ↓
server validates table at checkout
  ↓
order stores the validated table reference
```

Rules:

- `table_id` supplied by the browser is untrusted.
- The server must verify that the table exists and is active/eligible for dine-in.
- The server must resolve the client-provided `table_id` to the validated restaurant table record.
- Only the server-validated table reference may be stored in the order.
- A stale, disabled, or invalid table must prevent finalizing a dine-in order.
- The exact URL/QR format can evolve without changing the security rule.

If the current schema lacks a validated table reference on the order, add it through a migration before implementing the final checkout flow.

## 12. Stock Concurrency and Atomicity

When stock is enabled, never use a separate:

```text
SELECT stock
→ business logic
→ UPDATE stock
```

sequence as the authority for availability.

Preferred pattern:

```text
BEGIN
  verify/order data
  atomically decrement stock only when sufficient
  create/update order records
COMMIT
```

For a single stock row, an atomic conditional update such as:

```sql
UPDATE products
SET stock = stock - :quantity
WHERE id = :product_id
  AND stock >= :quantity
RETURNING stock;
```

may be sufficient inside the transaction.

For more complex multi-row inventory logic, use a PostgreSQL transaction or RPC/database function that preserves atomicity.

`SELECT ... FOR UPDATE` is an available locking technique, not a requirement when a simpler atomic statement provides the needed guarantee.

If any stock operation fails, the checkout transaction must not create a partially committed order.

## 13. Idempotency

Retry-sensitive operations should use an idempotency strategy where duplicates would be harmful.

Where practical, idempotency should be enforced server-side and supported by database uniqueness constraints or persisted idempotency keys.

Examples:

- order creation
- payment state transitions
- coupon usage
- stock mutation

UI controls such as disabling a button must not be treated as an idempotency mechanism.

## 14. Analytics

Analytics are supplementary.

Transactional tables remain the source of truth for:

- revenue
- completed orders
- payment state
- financial totals

Client-originated behavioral events must not redefine financial truth.

## 15. Testing Stack

### Database and RLS

**Supabase CLI + pgTAP**

This is already the existing database test approach and should remain the source for RLS/database policy tests.

### Unit/component

**Vitest + React Testing Library**

Planned when application logic/components require unit or integration coverage. Do not install simply for the sake of having a framework.

### End-to-end

**Playwright**

Planned for critical user flows such as authentication and checkout once those flows exist.

### Validation

Use the smallest relevant layer for the change. Do not run a full E2E suite for a purely presentational change.


## 16. UI Architecture

- Prefer server-side data fetching when practical.
- Use client components for interactive browser state and event handling.
- Do not move logic client-side merely for convenience.
- Keep UI effects separate from business-critical rules.

## 17. Architectural Invariants

1. Security-sensitive logic remains server-side.
2. Database changes use migrations.
3. RLS remains enabled and tested.
4. Historical transaction data remains interpretable.
5. Client input is untrusted.
6. Analytics do not replace transactional truth.
7. AI-generated code remains human-reviewable.
8. Interactive UI never overrides security or data integrity.

## 18. Notifications

Notifications are persistent, in-app customer records in `public.notifications`. They are not email, SMS, push, or realtime.

- Recipients: customers only. Admin notifications are out of scope.
- Events (locked): ORDER `CONFIRMED`, `READY`, `COMPLETED`, `CANCELLED`; PAYMENT `PAID`.
- Creation is server-authoritative and atomic with the business event: `public.update_order_status` writes the ORDER notifications and `public.confirm_order_payment` writes the PAYMENT notification, in the same transaction as the state change. `create_order` does not notify.
- The recipient is derived from `orders.user_id`, never from the browser. An order with no owner produces no notification.
- Notifications are created only on genuine transitions; the existing replay guards in both RPCs prevent duplicates on retry.
- Delivery surface: in-app only, at `/notifications`, with an unread indicator in the navigation. A notification's `order_id` links to the related order.
- Read state: `is_read`, toggled per notification by its owner. Clients have no INSERT or DELETE; they may update only `is_read`, and only for their own rows (RLS plus a column-level grant).
- Retention: kept indefinitely for the current scope.
