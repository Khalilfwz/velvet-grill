# Velvet Grill — Release Checklist

Final smoke-test and acceptance checklist for a portfolio release. Walk it
top to bottom on a freshly reset local environment. Expected outcomes come
from `PRD.md` and `ARCHITECTURE.md` (§9 order lifecycle, §10 payment
lifecycle).

> **Demo accounts are local/demo-only.** They exist only after running
> `supabase/seed.sql` (local development).
> **Security requirement:** do not execute the demo seed in production or
> shared environments, and never reuse these credentials.

## 0. Prerequisites

- [ ] Docker running
- [ ] `npm install` completed
- [ ] `.env.local` created from `.env.example` with values from `npx supabase status`
- [ ] Local stack running: `npx supabase start`
- [ ] Database migrated + seeded: `npx supabase db reset --local`
      ⚠️ Destroys and recreates the local database — requires separate human
      approval under `SECURITY_WORKFLOW.md` §10.

## 1. Automated gates

| Command | Expected |
| --- | --- |
| `npm run lint` | no errors |
| `npm run typecheck` | no errors |
| `npm run build` | build completes, no type errors |
| `git diff --check` | no whitespace/conflict-marker issues |
| `npm run test:db` | all pgTAP suites pass (34 files) |
| `bash supabase/scripts/stock_oversell_check.sh` | no oversell (FR-21 race proof) |
| `bash supabase/scripts/fr31_expiry_race_check.sh` | expiry path deterministic (FR-31 race proof) |

## 2. Storefront smoke path

Guest browsing:

- [ ] `/` renders hero, menu highlights, hours, contact — no error states
- [ ] `/menu` lists active categories with products grouped by category order
- [ ] `/menu/<slug>` shows images, options, price, published reviews
- [ ] Unknown product URL shows the product not-found page
- [ ] Browser tab titles are distinct on `/`, `/menu`, and a product page

Customer flow — fresh account registration:

- [ ] Register a new account → confirmation email visible in Mailpit
      (`http://127.0.0.1:54324`) → confirm → redirected signed in

Customer flow — demo customer sign-in (seeded account; see README for the
local demo password):

- [ ] Sign in as `demo@velvetgrill.test` → catalog and account surfaces load
- [ ] Wishlist: add/remove a product
- [ ] Cart: add product with options; quantity steppers; server-calculated totals
- [ ] Checkout (pickup): order placed, payment page shown
- [ ] "Complete demo payment" → payment PAID, order CONFIRMED
- [ ] Checkout (dine-in with a table id): order placed and validated
- [ ] Digital payment left alone → automatic expiry: payment EXPIRED,
      order CANCELLED (FR-31); coupon usage released, stock restored
- [ ] Order history shows statuses; order detail shows status history
- [ ] Notification(s) received for CONFIRMED / CANCELLED (see §4)

## 3. Admin smoke path

Sign in as `admin@velvetgrill.test` (local demo password in README):

- [ ] `/admin` redirects to `/admin/products`; admin nav shows all sections
- [ ] Catalog: create/edit category, product, option group, option
- [ ] Orders: advance a CONFIRMED order CONFIRMED → PREPARING → READY
- [ ] Digital-payment order cannot enter PREPARING before PAID
- [ ] READY → COMPLETED blocked while payment is unpaid (BUG-02);
      after "confirm cash payment" it succeeds
- [ ] Payment confirmation on a CANCELLED order is rejected (FR-33)
- [ ] Refund on a cancelled/completed PAID order → REFUNDED, order status
      unchanged (FR-31)
- [ ] Reviews: moderate (publish/hide) a review
- [ ] Analytics: operational + financial numbers consistent with orders
- [ ] Audit: sensitive admin actions listed in `/admin/audit`
- [ ] Non-admin account cannot reach admin pages or admin RPCs

## 4. Notifications (FR-23)

- [ ] ORDER CONFIRMED notification on confirmation
- [ ] ORDER READY notification when marked ready
- [ ] ORDER COMPLETED notification on completion
- [ ] ORDER CANCELLED notification on cancellation
- [ ] PAYMENT PAID notification on payment confirmation
- [ ] No duplicates on retry; unread badge clears after reading

## 5. Release criteria (PRD §9 mapping)

- [ ] 9.1 Core user flows work end-to-end (§2, §3 above)
- [ ] 9.2 Business-critical values stay server-authoritative (pgTAP pricing/stock/coupon suites green)
- [ ] 9.3 RLS/security tests pass (`npm run test:db`)
- [ ] 9.4 UI matches the design system (screenshots reviewed against `DESIGN_SYSTEM.md`)
- [ ] 9.5 Repository understandable without hidden assumptions (README + docs map current)
- [ ] 9.6 AI-assisted changes reviewable in Git (clean, scoped diff)
- [ ] 9.7 Deployment does not expose secrets (no real keys in repo; `.env*` ignored; `.env.example` has placeholders only)

## 6. Sign-off

- Automated gates run by: ______________  date: __________
- Storefront path verified by: ______________  date: __________
- Admin path verified by: ______________  date: __________
- Notifications verified by: ______________  date: __________
