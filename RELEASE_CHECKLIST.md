# Velvet Grill — Release Checklist

Final smoke-test and acceptance checklist for a portfolio release. Walk it
top to bottom on a freshly migrated and seeded local environment (see §0 —
the database reset is a human-gated destructive operation, not a routine
step). Expected outcomes come from `PRD.md` and `ARCHITECTURE.md`
(§9 order lifecycle, §10 payment lifecycle).

> **Demo accounts are local/demo-only.** They exist only after running
> `supabase/seed.sql` (local development).
> **Security requirement:** do not execute the demo seed in production or
> shared environments, and never reuse these credentials.

## 0. Prerequisites

- [ ] Docker running
- [ ] `npm install` completed
- [ ] `.env.local` created from `.env.example` with values from `npx supabase status`
- [ ] Local stack running: `npx supabase start`
- [ ] Database migrated + seeded — human-gated, **not** a routine setup
      step: `npx supabase db reset --local` destroys and recreates the
      local database and requires explicit human approval under
      `SECURITY_WORKFLOW.md` §10. Schema migration and demo seed
      provisioning are separate requirements: `npx supabase migration up
      --local` is the non-destructive path for pending migrations on an
      existing database (operates on the Supabase project tied to the
      current working directory) — it does not run the demo seed. Seed
      data must already exist or be provisioned through a separately
      reviewed, explicitly approved procedure in the intended
      local/demo environment; never run seed SQL against an existing
      database automatically.

## 1. Automated gates

| Command | Expected |
| --- | --- |
| `npm run lint` | no errors |
| `npm run typecheck` | no errors |
| `npm run build` | build completes, no type errors |
| `npm run test:unit` | all unit tests pass (recorded baseline 15/15) |
| `git diff --check` | no whitespace/conflict-marker issues |
| `npm run test:db` | all pgTAP suites pass (38 test files; recorded baseline 887 passing assertions) |

### Concurrency race proofs — isolated database only

⚠️ Do **not** run either race proof against the primary development
database. Point both scripts at a dedicated, isolated database with the
project migrations applied, and run them with host `psql` installed (see
README → "Concurrency race proofs"). Neither script is collected by
`supabase test db`.

| Command | Expected |
| --- | --- |
| `SUPABASE_DB_URL="$ISOLATED_DB_URL" bash supabase/scripts/stock_oversell_check.sh` | no oversell (FR-21 race proof) |
| `SUPABASE_DB_URL="$ISOLATED_DB_URL" FR31_EXPECTED_SYSTEM_ID="$ISOLATED_SYSTEM_ID" bash supabase/scripts/fr31_expiry_race_check.sh` | expiry path deterministic (FR-31 race proof) |

Configure and verify `$ISOLATED_DB_URL` and `$ISOLATED_SYSTEM_ID` (the
target's `system_identifier`) before running. `fr31_expiry_race_check.sh`
requires the explicit database URL and expected system identifier and
aborts otherwise (no default target, no Docker fallback).
`stock_oversell_check.sh` defaults to the development database on port
54322 when no target is supplied and, if host `psql` is unavailable,
falls back to a development Docker container where `SUPABASE_DB_URL` is
ignored — host `psql` is required so it runs in host mode.

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

Recorded baseline evidence for these criteria is summarized in §6; each
criterion stays pending until verified through the human sign-off in §7.

## 6. Recorded verification status (SEC-04 baseline)

Recorded after the SEC-04 dependency remediation. These are recorded
results, not a re-certification — re-run the gates above on a fresh
environment before release.

| Check | Recorded result |
| --- | --- |
| `npm run test:unit` | 15/15 passing |
| `npm run test:db` (pgTAP) | 38 test files, 887 passing assertions |
| Manual E2E + security verification (reported) | 41/41 PASS |
| SEC-04 focused runtime regression | 7/7 PASS |
| Production dependency audit (`npm audit --omit=dev`) | 0 vulnerabilities |
| Full dependency audit (`npm audit --include=dev`) | 5 high findings (dev-only `braces` chain — open risk, see below) |

Dependency remediation recorded in this baseline: `next` 16.4.0,
`eslint-config-next` 16.4.0, `sharp` 0.35.5, `source-map-js` 1.2.2.

Known open risk (re-verified during AUDIT-04B):

- **SEC-04-RISK-01** — the full dependency audit reports five High
  findings from the development-only `braces` chain (`eslint-config-next`
  lint tooling; the production audit is clean). The full dependency audit
  is **not** claimed to pass and no fix is claimed here. npm can be
  configured to omit dev dependencies (`npm config get omit`), which
  makes a plain `npm audit` skip the development tree — audit with
  `npm audit --include=dev`.

These recorded results do not certify the application as
production-secure.

## 7. Sign-off

Automated and reported manual checks (§1, §6) may be recorded as
completed for the SEC-04 baseline. Everything not verified there —
including §5 release criteria and the full dependency audit — remains
pending until verified by a human.

- Automated gates: recorded for the SEC-04 baseline (§1, §6) — re-run on
  a fresh environment before release.
- Storefront path verified by: ______________  date: __________
- Admin path verified by: ______________  date: __________
- Notifications verified by: ______________  date: __________
- Release sign-off (human approval; destructive operations and any
  deployment remain gated per `SECURITY_WORKFLOW.md`):
  ______________  date: __________
