# Velvet Grill

A security-conscious restaurant e-commerce portfolio project: a single-brand
steakhouse storefront with catalog, product options, wishlist, cart, checkout,
pickup and dine-in fulfillment, dummy payments, order history, reviews,
notifications, and a full admin backend.

> **Portfolio project — not a commercial restaurant platform.** All payments
> are simulated ("demo payment" buttons), the brand is fictional, and the
> data is deterministic local seed data. See `PRD.md` §1 and §8 for scope.

## Stack

- Next.js 16.4.0 (App Router) + TypeScript + Tailwind CSS
- Supabase (Auth, PostgreSQL + RLS, Storage)
- Zod for input validation
- pgTAP for database/RLS tests
- Git + GitHub · AI-assisted development via Command Code

## Documentation map

| Document | Purpose |
| --- | --- |
| `PRD.md` | Product requirements (FR-01…FR-33), NFRs, scope |
| `ARCHITECTURE.md` | System boundaries, order/payment state machines, RLS rules |
| `DESIGN_SYSTEM.md` | Brand tokens, typography, interaction rules |
| `SECURITY_WORKFLOW.md` | Threat model, server authority, destructive-op approval |
| `AI_WORKFLOW.md` | Plan → Implement → Test → Review → Verify → Commit workflow |
| `SKILLS_PLAN.md` | Agent skill strategy |
| `RELEASE_CHECKLIST.md` | Final smoke-test / acceptance checklist |
| `AGENTS.md` | Operating rules for coding agents |

## Quickstart

Prerequisites: **Node.js 22+**, **Docker** (for the local Supabase stack),
npm.

```bash
# 1. Install dependencies
npm install

# 2. Start the local Supabase stack (first run pulls images)
npx supabase start

# 3. Configure environment
cp .env.example .env.local
#    then fill in NEXT_PUBLIC_SUPABASE_URL and
#    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY from `npx supabase status`

# 4. Run the app
npm run dev
# → http://localhost:3000
```

**Migrations + seed data are not an automatic setup step.** The local
database is provisioned by `npx supabase db reset --local`, which
**destroys and recreates the database**. Under `SECURITY_WORKFLOW.md` §10
this is a destructive operation that requires explicit human approval and
is run by (or with the approval of) a human. Schema migration and demo
seed provisioning are separate requirements: for pending migrations on an
already-provisioned database, `npx supabase migration up --local` is the
non-destructive path — it does not run the demo seed, and seed data must
already exist or be provisioned through a separately reviewed, explicitly
approved procedure in the intended local/demo environment.

Supabase Studio: `http://127.0.0.1:54323` · Mailpit (local email inbox):
`http://127.0.0.1:54324`.

## Demo accounts (local/demo-only)

| Role | Email | Password |
| --- | --- | --- |
| Customer | `demo@velvetgrill.test` | `velvet-demo-2026` |
| Admin | `admin@velvetgrill.test` | `velvet-admin-2026` |

These accounts are **provisioned only by `supabase/seed.sql`** and are for
local development and portfolio review only. **Security requirement:** the
demo seed must not be executed in production or shared environments, and
these demo credentials must never be reused for real or administrative
accounts. Admin authorization is still enforced server-side and by RLS
(`FR-30`).

## Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | yes | Supabase project URL (local: `http://127.0.0.1:54321`) |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | yes | Publishable (anon) key — the app intentionally uses only the publishable key + RLS |
| `NEXT_PUBLIC_SITE_URL` | no | Canonical/OG base URL for `metadataBase`, robots, sitemap. Unset = `http://localhost:3000`. Set it only when a production deployment is approved; never point it at the Supabase API URL. |

Secrets stay server-side and out of source control: `.env*` is gitignored
(`.env.example` is the tracked exception).

## Testing

Prerequisites: Docker running, stack started (`npx supabase start`),
migrations applied.

```bash
npm run lint        # ESLint
npm run typecheck   # tsc --noEmit
npm run build       # production build
npm run test:unit   # Node unit tests (auth recovery-session suite)
npm run test:db     # full pgTAP suite via supabase test db
```

The pgTAP suites under `supabase/tests/` (38 test files) cover catalog,
auth/profiles, cart, wishlist, orders, pricing, snapshots, coupons,
payments, reviews, notifications, analytics, and admin authorization.
The recorded SEC-04 baseline is 887 passing assertions for `test:db`
and 15/15 passing tests for `test:unit`.

### Concurrency race proofs — isolated database only

`stock_oversell_check.sh` (FR-21 overselling) and
`fr31_expiry_race_check.sh` (FR-31 expiry vs confirm) are two-session
race proofs that are **not** collected by `supabase test db`. They write
dedicated fixtures to, and run transactions against, their target
database.

> ⚠️ **Never run either race proof against the primary development
> database.** Concurrency tests must be pointed at a dedicated, isolated
> database using host `psql` — see the FR-21 caveat below.

- `fr31_expiry_race_check.sh` is fail-closed: it requires an explicit
  `SUPABASE_DB_URL` and `FR31_EXPECTED_SYSTEM_ID` (the expected
  `system_identifier` of the target), verifies the identifier read-only
  via `pg_control_system()` before touching anything, and aborts on
  mismatch. It has no default target, no Docker fallback, and requires
  host `psql`.
- `stock_oversell_check.sh` defaults to the local development database
  on port 54322 when no `SUPABASE_DB_URL` is supplied. If host `psql`
  is unavailable, it falls back to Docker mode and runs `psql` inside
  the development container (`supabase_db_velvet-grill`) — in that mode
  `SUPABASE_DB_URL` is ignored, so setting it alone does **not** make
  the script target an isolated database. For the isolated workflow,
  **host `psql` must be installed and on `PATH`** so the script runs in
  host mode; do not rely on the Docker fallback.

Isolated-environment requirements:

- A dedicated PostgreSQL database separate from the development stack,
  with the project migrations applied through a non-destructive path
  (for a local isolated Supabase project: `npx supabase migration up
  --local`). This command operates on the Supabase project associated
  with the current working directory and its configuration — run it in
  the intended isolated project; it does not isolate anything
  automatically. Never prepare a target with `supabase db reset` — it
  is destructive and human-approval-gated (see Quickstart above).
- Migrations must already be present: FR-31 aborts if
  `private.expire_stale_digital_payments()` is missing.

Example invocations against an isolated target. Configure
`$ISOLATED_DB_URL` (the isolated database URL) and
`$ISOLATED_SYSTEM_ID` (the target's `system_identifier`) and verify both
before running — the read-only check below prints the identifier FR-31
will compare against:

```bash
# Read-only verification of the target's system_identifier:
psql "$ISOLATED_DB_URL" -Atc \
  "select system_identifier::text from pg_control_system()"

SUPABASE_DB_URL="$ISOLATED_DB_URL" \
  bash supabase/scripts/stock_oversell_check.sh

SUPABASE_DB_URL="$ISOLATED_DB_URL" \
FR31_EXPECTED_SYSTEM_ID="$ISOLATED_SYSTEM_ID" \
  bash supabase/scripts/fr31_expiry_race_check.sh
```

## Dependency security (SEC-04)

The SEC-04 remediation pinned `next` and `eslint-config-next` at 16.4.0
and refreshed the transitive `sharp` 0.35.5 and `source-map-js` 1.2.2.
The production dependency audit (`npm audit --omit=dev`) reports
0 vulnerabilities.

**Open risk (SEC-04-RISK-01):** the full dependency audit reports five
High findings originating in the development-only `braces` dependency
chain (`braces` → `micromatch` → `fast-glob` →
`@next/eslint-plugin-next` → `eslint-config-next`; lint tooling only —
the production tree is unaffected). Re-verified during the AUDIT-04B
documentation update: `npm audit --include=dev` still reports them, and
the full dependency audit is not claimed to pass. No fix is claimed
here, and none of these results certifies the application as
production-secure. Note that npm can be configured to omit dev
dependencies (`npm config get omit`), which makes a plain `npm audit`
skip the development tree — use `npm audit --include=dev` when auditing
the full tree. See `SECURITY_WORKFLOW.md` for review requirements and
`RELEASE_CHECKLIST.md` §6 for the verification baseline.

## Screenshots

Captured from the running local application (`npm run dev`) using the
existing seeded catalog data. These captures do not exercise the demo
accounts or verify sign-in — see `RELEASE_CHECKLIST.md` for that flow.
More in `docs/screenshots/`.

![Velvet Grill homepage](docs/screenshots/home.png)

![Velvet Grill menu](docs/screenshots/menu.png)

![Product detail — Wagyu Ribeye Steak](docs/screenshots/product-detail.png)

## Deployment

No production deployment is configured — the project is local-first by
design. When a deployment is approved, set `NEXT_PUBLIC_SITE_URL` so
canonical/OG URLs resolve correctly, and provision real accounts through
proper operator account management. Do not execute the demo seed against
production or shared environments.
