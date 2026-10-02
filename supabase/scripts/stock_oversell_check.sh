#!/usr/bin/env bash
#
# FR-21 — true two-session overselling check.
#
# Proves that two competing checkouts for the same final stock unit cannot
# oversell. This is NOT a pgTAP test and lives outside supabase/tests, so it is
# never collected by `supabase test db`. Run it manually against the local DB:
#
#   bash supabase/scripts/stock_oversell_check.sh
#
# It uses dedicated, fixed FR-21 fixtures only and never resets the database or
# mutates unrelated local data.
#
# Apply migrations first (preserving local data), WITHOUT a reset:
#   npx supabase migration up --local

set -euo pipefail

SUPABASE_DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

# Dedicated FR-21 concurrency fixtures (fixed ids).
USER_A='a2121212-0000-4000-8000-0000000000a1'
USER_B='b2121212-0000-4000-8000-0000000000b1'
CATEGORY='c2121212-0000-4000-8000-0000000000c1'
PRODUCT='d2121212-0000-4000-8000-0000000000d1'
CART_A='e2121212-0000-4000-8000-0000000000e1'
CART_B='f2121212-0000-4000-8000-0000000000f1'
ITEM_A='11212121-0000-4000-8000-0000000000a2'
ITEM_B='12212121-0000-4000-8000-0000000000b2'
KEY_A='fr21-race-a'
KEY_B='fr21-race-b'

TMP_DIR="$(mktemp -d)"
A_OUT="$TMP_DIR/session_a.out"
B_OUT="$TMP_DIR/session_b.out"
A_PID=""
B_PID=""

# ------------------------------------------------------------------
# psql transport: prefer host psql; otherwise use the already-running
# local DB container. Every build_psql_cmd + invocation is a separate
# process (and therefore a separate database backend): no session is
# shared between the setup, polling, session A, session B, verification
# and cleanup connections.
# ------------------------------------------------------------------
DB_CONTAINER="${FR21_DB_CONTAINER:-supabase_db_velvet-grill}"

if command -v psql >/dev/null 2>&1; then
  PSQL_MODE="host"
else
  PSQL_MODE="docker"
fi

PSQL_CMD=()

# build_psql_cmd <application_name> -> fills PSQL_CMD (does not execute).
# The application_name is propagated as PGAPPNAME: as an env var for host
# psql, and via docker exec -e for the container fallback.
build_psql_cmd() {
  local app_name="$1"
  if [ "$PSQL_MODE" = "host" ]; then
    PSQL_CMD=(env "PGAPPNAME=$app_name" psql "$SUPABASE_DB_URL" \
      -v ON_ERROR_STOP=1 -X)
  else
    PSQL_CMD=(docker exec -i -e "PGAPPNAME=$app_name" "$DB_CONTAINER" \
      psql -v ON_ERROR_STOP=1 -X -U postgres -d postgres)
  fi
}

# psql_run <application_name> [psql args...] -> foreground helper connection.
psql_run() {
  local app_name="$1"
  shift
  build_psql_cmd "$app_name"
  "${PSQL_CMD[@]}" "$@"
}

cleanup() {
  local rc=$?
  set +e

  # 1. Terminate/wait any still-running child psql sessions so none retains
  #    the product/order locks.
  if [ -n "$A_PID" ]; then kill "$A_PID" 2>/dev/null; fi
  if [ -n "$B_PID" ]; then kill "$B_PID" 2>/dev/null; fi
  wait 2>/dev/null

  # 2. Terminate only our scoped race backends (by application_name).
  psql_run fr21_cleanup -c "select pg_terminate_backend(pid) from pg_stat_activity \
    where application_name in ('fr21_sess_a', 'fr21_sess_b')" >/dev/null 2>&1 || true

  # 3. Delete ONLY the dedicated FR-21 fixtures, in FK-safe order.
  psql_run fr21_cleanup <<SQL >/dev/null 2>&1 || true
begin;
delete from public.coupon_usages cu
  using public.orders o
  where cu.order_id = o.id and o.user_id in ('$USER_A', '$USER_B');
delete from public.order_item_options oio
  using public.order_items oi
  join public.orders o on o.id = oi.order_id
  where oio.order_item_id = oi.id and o.user_id in ('$USER_A', '$USER_B');
delete from public.order_status_history h
  using public.orders o
  where h.order_id = o.id and o.user_id in ('$USER_A', '$USER_B');
delete from public.payments p
  using public.orders o
  where p.order_id = o.id and o.user_id in ('$USER_A', '$USER_B');
delete from public.order_items oi
  using public.orders o
  where oi.order_id = o.id and o.user_id in ('$USER_A', '$USER_B');
delete from public.orders where user_id in ('$USER_A', '$USER_B');
delete from public.cart_item_options cio
  using public.cart_items ci
  join public.carts c on c.id = ci.cart_id
  where cio.cart_item_id = ci.id and c.user_id in ('$USER_A', '$USER_B');
delete from public.cart_items ci
  using public.carts c
  where ci.cart_id = c.id and c.user_id in ('$USER_A', '$USER_B');
delete from public.carts where user_id in ('$USER_A', '$USER_B');
delete from public.products where id = '$PRODUCT';
delete from public.categories where id = '$CATEGORY';
delete from auth.users where id in ('$USER_A', '$USER_B');
commit;
SQL

  rm -rf "$TMP_DIR" 2>/dev/null || true

  # 4. Clear traps and preserve the original exit status.
  trap - EXIT INT TERM
  exit "$rc"
}
trap cleanup EXIT INT TERM

echo "== FR-21 stock oversell check =="
echo "   db: $SUPABASE_DB_URL"

# ------------------------------------------------------------------
# Committed dedicated fixtures (idempotent: clear then insert).
# ------------------------------------------------------------------
psql_run fr21_setup <<SQL
delete from public.cart_item_options cio
  using public.cart_items ci
  join public.carts c on c.id = ci.cart_id
  where cio.cart_item_id = ci.id and c.user_id in ('$USER_A', '$USER_B');
delete from public.cart_items ci
  using public.carts c
  where ci.cart_id = c.id and c.user_id in ('$USER_A', '$USER_B');
delete from public.carts where user_id in ('$USER_A', '$USER_B');
delete from public.orders where user_id in ('$USER_A', '$USER_B');
delete from public.products where id = '$PRODUCT';
delete from public.categories where id = '$CATEGORY';
delete from auth.users where id in ('$USER_A', '$USER_B');

insert into auth.users (id, email) values
  ('$USER_A', 'fr21-race-a@test.local'),
  ('$USER_B', 'fr21-race-b@test.local');

insert into public.categories (id, name, slug, is_active)
values ('$CATEGORY', 'FR-21 Race', 'fr21-race-cat', true);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  '$PRODUCT', '$CATEGORY', 'FR-21 Race Unit', 'fr21-race-unit',
  100000, 1, true
);

insert into public.carts (id, user_id) values
  ('$CART_A', '$USER_A'),
  ('$CART_B', '$USER_B');

insert into public.cart_items (id, cart_id, product_id, quantity) values
  ('$ITEM_A', '$CART_A', '$PRODUCT', 1),
  ('$ITEM_B', '$CART_B', '$PRODUCT', 1);
SQL

echo "   fixtures ready: product $PRODUCT stock=1"

# ------------------------------------------------------------------
# Session A: acquire the final unit, hold the lock, then commit.
# ------------------------------------------------------------------
build_psql_cmd fr21_sess_a
"${PSQL_CMD[@]}" >"$A_OUT" 2>&1 <<SQL &
\set VERBOSITY verbose
BEGIN;
set local role authenticated;
set local request.jwt.claim.sub = '$USER_A';
select public.create_order(
  'PICKUP', 'FR-21 Race A', null, null,
  now() + interval '2 hours', null, '$KEY_A', 'CASH'
);
select pg_sleep(5);
COMMIT;
SQL
A_PID=$!

# Readiness gate: wait until A is inside pg_sleep (create_order has returned,
# stock UPDATE executed, transaction open, product lock retained).
ready=0
for _ in $(seq 1 100); do
  if [ "$(psql_run fr21_poll -A -t -c "select 1 from pg_stat_activity \
      where application_name = 'fr21_sess_a' \
        and wait_event_type = 'Timeout' and wait_event = 'PgSleep' limit 1")" = "1" ]; then
    ready=1
    break
  fi
  sleep 0.1
done

if [ "$ready" != "1" ]; then
  echo "FAIL: session A never reached the pg_sleep wait state"
  exit 1
fi

echo "   session A holds the final unit (inside pg_sleep)"

# ------------------------------------------------------------------
# Session B: contend for the same final unit.
# ------------------------------------------------------------------
build_psql_cmd fr21_sess_b
"${PSQL_CMD[@]}" >"$B_OUT" 2>&1 <<SQL &
\set VERBOSITY verbose
BEGIN;
set local role authenticated;
set local request.jwt.claim.sub = '$USER_B';
select public.create_order(
  'PICKUP', 'FR-21 Race B', null, null,
  now() + interval '2 hours', null, '$KEY_B', 'CASH'
);
COMMIT;
SQL
B_PID=$!

# Contention proof: B must be blocked on a lock while A is still open.
contended=0
for _ in $(seq 1 50); do
  if [ "$(psql_run fr21_poll -A -t -c "select 1 from pg_stat_activity \
      where application_name = 'fr21_sess_b' \
        and wait_event_type = 'Lock' limit 1")" = "1" ]; then
    contended=1
    break
  fi
  sleep 0.1
done

if [ "$contended" != "1" ]; then
  echo "FAIL: session B was never observed contending on a lock"
  exit 1
fi

echo "   session B is blocked on the product row lock (real contention)"

# Collect outcomes (do not abort on child failure).
set +e
wait "$A_PID"; A_RC=$?
A_PID=""
wait "$B_PID"; B_RC=$?
B_PID=""
set -e

# ------------------------------------------------------------------
# Verify outcomes.
# ------------------------------------------------------------------
if [ "$A_RC" != "0" ]; then
  echo "FAIL: session A exited $A_RC"
  echo "--- session A output ---"; cat "$A_OUT"
  exit 1
fi
if ! grep -Eq '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$A_OUT"; then
  echo "FAIL: session A did not return an order id"
  echo "--- session A output ---"; cat "$A_OUT"
  exit 1
fi

if [ "$B_RC" = "0" ]; then
  echo "FAIL: session B unexpectedly succeeded (oversell)"
  echo "--- session B output ---"; cat "$B_OUT"
  exit 1
fi
if ! grep -q '22023' "$B_OUT" || ! grep -q 'Some items are no longer available' "$B_OUT"; then
  echo "FAIL: session B did not fail with the expected 22023 unavailable error"
  echo "--- session B output ---"; cat "$B_OUT"
  exit 1
fi

STOCK="$(psql_run fr21_verify -A -t -c "select stock from public.products where id = '$PRODUCT'")"
ORDER_COUNT="$(psql_run fr21_verify -A -t -c "select count(*) from public.orders \
  where idempotency_key in ('$KEY_A', '$KEY_B')")"
WINNER="$(psql_run fr21_verify -A -t -c "select idempotency_key from public.orders \
  where idempotency_key in ('$KEY_A', '$KEY_B')")"

if [ "$STOCK" != "0" ]; then
  echo "FAIL: final stock is '$STOCK', expected 0"
  exit 1
fi
if [ "$ORDER_COUNT" != "1" ]; then
  echo "FAIL: committed competing orders = '$ORDER_COUNT', expected 1"
  exit 1
fi
if [ "$WINNER" != "$KEY_A" ]; then
  echo "FAIL: winning order is '$WINNER', expected '$KEY_A'"
  exit 1
fi

echo "PASS: oversell prevented"
echo "      session A committed ($KEY_A); session B rejected (22023)"
echo "      final stock = 0; exactly one competing order committed (A)"
