#!/usr/bin/env bash
#
# FR-31 — true two-session confirm-vs-expiry race check.
#
# Proves the confirm_order_payment / payment-expiry interleavings are
# deadlock-free and deterministic:
#
#   Scenario 1 (confirmation wins): session A simulates confirm_order_
#   payment's first ORDER row lock and holds it; the expiry function runs
#   under that lock and must skip the order without an error; A then
#   commits PAID and a second expiry run never touches the order.
#
#   Scenario 2 (expiry wins): session B simulates the expiry function's
#   own order lock, expires the order while holding it; a concurrent
#   confirmation blocks on the ORDER lock (proving the canonical
#   ORDER -> PAYMENT lock order avoids deadlocks) and then fails closed
#   with 42501 once B commits.
#
# This is NOT a pgTAP test and lives outside supabase/tests, so it is
# never collected by `supabase test db`. Run it manually against the
# local DB:
#
#   bash supabase/scripts/fr31_expiry_race_check.sh
#
# It uses dedicated, fixed FR-31 fixtures only and never resets the
# database. Its expiry runs may expire OTHER stale pending digital
# payments found on the local dev data (that is the implemented
# behavior); all assertions are scoped to the FR-31 fixture rows.
#
# Apply migrations first (preserving local data), WITHOUT a reset:
#   npx supabase migration up --local

set -euo pipefail

SUPABASE_DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

# Dedicated FR-31 race fixtures (fixed ids).
USER_A='a0313131-0000-4000-8000-0000000000a1'
CATEGORY='c0313131-0000-4000-8000-0000000000c1'
PROD_A='d0313131-0000-4000-8000-0000000000d1'
PROD_B='e0313131-0000-4000-8000-0000000000e1'
ORDER_1='f0313131-0000-4000-8000-000000000001'
ORDER_2='f0313131-0000-4000-8000-000000000002'
PAY_1='bf031331-0000-4000-8000-000000000001'
PAY_2='bf031331-0000-4000-8000-000000000002'
ITEM_1='a0313131-0000-4000-8000-000000000001'
ITEM_2='a0313131-0000-4000-8000-000000000002'

TMP_DIR="$(mktemp -d)"
A_OUT="$TMP_DIR/session_a.out"
B_OUT="$TMP_DIR/session_b.out"
A2_OUT="$TMP_DIR/session_a2.out"
A_PID=""
B_PID=""
A2_PID=""

# ------------------------------------------------------------------
# psql transport: prefer host psql; otherwise use the already-running
# local DB container. Every build_psql_cmd + invocation is a separate
# process (and therefore a separate database backend): no session is
# shared between the setup, polling, session A, session B,
# verification and cleanup connections.
# ------------------------------------------------------------------
DB_CONTAINER="${FR31_DB_CONTAINER:-supabase_db_velvet-grill}"

if command -v psql >/dev/null 2>&1 && \
   [ "$(env PGAPPNAME=fr31_probe psql "$SUPABASE_DB_URL" -A -t -c 'select 1' 2>/dev/null)" = "1" ]; then
  PSQL_MODE="host"
elif [ "$(docker exec -i "$DB_CONTAINER" psql -A -t -X -U postgres -d postgres -c 'select 1' 2>/dev/null)" = "1" ]; then
  PSQL_MODE="docker"
else
  echo "FAIL: no working psql transport (host psql broken; docker exec failed)"
  exit 1
fi

PSQL_CMD=()

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

psql_run() {
  local app_name="$1"
  shift
  build_psql_cmd "$app_name"
  "${PSQL_CMD[@]}" "$@"
}

cleanup() {
  local rc=$?
  set +e

  if [ -n "$A_PID" ]; then kill "$A_PID" 2>/dev/null; fi
  if [ -n "$B_PID" ]; then kill "$B_PID" 2>/dev/null; fi
  if [ -n "$A2_PID" ]; then kill "$A2_PID" 2>/dev/null; fi
  wait 2>/dev/null

  psql_run fr31_cleanup -c "select pg_terminate_backend(pid) from pg_stat_activity \
    where application_name like 'fr31_%'" >/dev/null 2>&1 || true

  # Delete ONLY the dedicated FR-31 race fixtures, in FK-safe order.
  psql_run fr31_cleanup <<SQL >/dev/null 2>&1 || true
begin;
delete from public.order_status_history h
  using public.orders o
  where h.order_id = o.id and o.id in ('$ORDER_1', '$ORDER_2');
delete from public.notifications n
  where n.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.payments p
  where p.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.order_items oi
  where oi.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.orders
  where id in ('$ORDER_1', '$ORDER_2');
delete from public.products
  where id in ('$PROD_A', '$PROD_B');
delete from public.categories where id = '$CATEGORY';
delete from auth.users where id = '$USER_A';
commit;
SQL

  rm -rf "$TMP_DIR" 2>/dev/null || true

  trap - EXIT INT TERM
  exit "$rc"
}
trap cleanup EXIT INT TERM

echo "== FR-31 confirm-vs-expiry race check =="
echo "   db: $SUPABASE_DB_URL"

# ------------------------------------------------------------------
# The migration must already be applied (function + cron exist).
# ------------------------------------------------------------------
if ! psql_run fr31_gate -A -t -c "select to_regprocedure('private.expire_stale_digital_payments()') is not null" | grep -qx 't'; then
  echo "FAIL: private.expire_stale_digital_payments() is missing"
  echo "      run: npx supabase migration up --local"
  exit 1
fi

# ------------------------------------------------------------------
# Committed dedicated fixtures (idempotent: clear then insert).
# Orders are inserted directly (pre-FR-17-free path) and both payment
# rows are backdated 1 hour so both orders start expiry-eligible.
# Stock is preset to a simulated post-decrement value (10 - 2 = 8).
# ------------------------------------------------------------------
psql_run fr31_setup <<SQL
begin;
delete from public.order_status_history h
  using public.orders o
  where h.order_id = o.id and o.id in ('$ORDER_1', '$ORDER_2');
delete from public.notifications n
  where n.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.payments p
  where p.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.order_items oi
  where oi.order_id in ('$ORDER_1', '$ORDER_2');
delete from public.orders
  where id in ('$ORDER_1', '$ORDER_2');
delete from public.products
  where id in ('$PROD_A', '$PROD_B');
delete from public.categories where id = '$CATEGORY';
delete from auth.users where id = '$USER_A';

insert into auth.users (id, email)
values ('$USER_A', 'fr31-race-a@test.local');

update public.profiles
set full_name = 'FR-31 Race A'
where id = '$USER_A';

insert into public.categories (id, name, slug, is_active)
values ('$CATEGORY', 'FR-31 Race', 'fr31-race-cat', true);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values
  ('$PROD_A', '$CATEGORY', 'FR-31 Race A Unit', 'fr31-race-a-unit',
   100000, 8, true),
  ('$PROD_B', '$CATEGORY', 'FR-31 Race B Unit', 'fr31-race-b-unit',
   100000, 8, true);

insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values
  ('$ORDER_1', 'VG-FR31-RA1', '$USER_A', 'PICKUP',
   '2026-01-05T12:00:00Z'::timestamptz, 'FR-31 Race A',
   200000, 0, 200000, 'PENDING', 'PENDING_PAYMENT'),
  ('$ORDER_2', 'VG-FR31-RA2', '$USER_A', 'PICKUP',
   '2026-01-05T12:00:00Z'::timestamptz, 'FR-31 Race A',
   200000, 0, 200000, 'PENDING', 'PENDING_PAYMENT');

insert into public.payments (id, order_id, method, status, amount, created_at)
values
  ('$PAY_1', '$ORDER_1', 'DUMMY_QRIS', 'PENDING', 200000,
   now() - interval '1 hour'),
  ('$PAY_2', '$ORDER_2', 'DUMMY_QRIS', 'PENDING', 200000,
   now() - interval '1 hour');

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values
  ('$ITEM_1', '$ORDER_1', '$PROD_A', 'FR-31 Race A Unit',
   100000, 100000, 2, 200000),
  ('$ITEM_2', '$ORDER_2', '$PROD_B', 'FR-31 Race B Unit',
   100000, 100000, 2, 200000);
commit;
SQL

echo "   fixtures ready"

# ==================================================================
# SCENARIO 1: confirmation wins.
# ==================================================================

# Session A simulates confirm_order_payment's first lock. The RPC runs
# as SECURITY DEFINER (owner) where RLS does not apply, so the row lock
# is taken as the owner; under RLS a plain SELECT ... FOR UPDATE would
# also require the row to pass the table's UPDATE policy, and a
# customer claim has none (rows fail silently, no lock). The RPC call
# itself is made as the emulated customer.
build_psql_cmd fr31_sess_a
"${PSQL_CMD[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
select id from public.orders where id = '$ORDER_1' for update;
select pg_sleep(5);
set local role authenticated;
set local request.jwt.claim.sub = '$USER_A';
select public.confirm_order_payment('$ORDER_1');
COMMIT;
SQL
A_PID=$!

# Readiness gate: A holds ORDER 1's row lock inside its open txn.
ready=0
for _ in $(seq 1 100); do
  if [ "$(psql_run fr31_poll -A -t -c "select 1 from pg_stat_activity \
      where application_name = 'fr31_sess_a' \
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

echo "   session A holds the order row lock (inside pg_sleep)"

# B runs the expiry function UNDER A's lock: skip-locked on the order
# row must make it return without error (0 or more of other dev-table
# rows may expire; the FR-31 fixture order must remain untouched).
if ! psql_run fr31_exp_b1 >"$B_OUT" 2>&1 <<SQL
select private.expire_stale_digital_payments();
SQL
then
  echo "FAIL: expiry run errored while a confirmation held the order lock"
  cat "$B_OUT"
  exit 1
fi

PENDING_CHECK="$(psql_run fr31_verify -A -t -c "select status from public.payments \
  where id = '$PAY_1'")"
if [ "$PENDING_CHECK" != "PENDING" ]; then
  echo "FAIL: expiry run mutated order 1 while its lock was held ('$PENDING_CHECK')"
  exit 1
fi

echo "   expiry run skipped the locked order without error"

# Collect A (PAID commit) before the next expiry run.
set +e
wait "$A_PID"; A_RC=$?
A_PID=""
set -e

if [ "$A_RC" != "0" ] || ! grep -q 'PAID' "$A_OUT"; then
  echo "FAIL: session A did not commit PAID (rc=$A_RC)"
  cat "$A_OUT"
  exit 1
fi

# Second expiry run: the confirmed PAID order is never expired.
if ! psql_run fr31_exp_b2 >"$B_OUT" 2>&1 <<SQL
select private.expire_stale_digital_payments();
SQL
then
  echo "FAIL: post-confirmation expiry run errored"
  cat "$B_OUT"
  exit 1
fi

ST1="$(psql_run fr31_verify -A -t -c "select p.status || '/' || o.payment_status || '/' || o.order_status \
  from public.payments p join public.orders o on o.id = p.order_id \
  where o.id = '$ORDER_1'")"
if [ "$ST1" != "PAID/PAID/PENDING_PAYMENT" ]; then
  echo "FAIL: confirmation-win final state is '$ST1', expected PAID/PAID/PENDING_PAYMENT"
  exit 1
fi

HIST1="$(psql_run fr31_verify -A -t -c "select count(*) from public.order_status_history \
  where order_id = '$ORDER_1'")"
NOTIF_CANCEL="$(psql_run fr31_verify -A -t -c "select count(*) from public.notifications \
  where order_id = '$ORDER_1' and title = 'Order cancelled'")"
STOCK_A="$(psql_run fr31_verify -A -t -c "select stock from public.products where id = '$PROD_A'")"

if [ "$HIST1" != "0" ] || [ "$NOTIF_CANCEL" != "0" ]; then
  echo "FAIL: confirmation-win ran expiry side effects (history=$HIST1 cancelled-notif=$NOTIF_CANCEL)"
  exit 1
fi
if [ "$STOCK_A" != "8" ]; then
  echo "FAIL: confirmation-win restocked stock (stock=$STOCK_A, expected 8)"
  exit 1
fi

echo "   scenario 1 coherent: PAID/PAID/PENDING_PAYMENT, no expiry side effects"

# ==================================================================
# SCENARIO 2: expiry wins.
# ==================================================================

# Session B rebuilds the ORDER 2 fixture inside its own transaction
# (scenario 1's expiry run legitimately expired it while it was
# unlocked): payments back to PENDING + reserved stock 8, history and
# notifications dropped, then it takes the order row lock and expires
# the order inside the SAME transaction. Keeping reset + lock + expiry
# in one transaction means the scheduled cron job can never race the
# fixture reset.
build_psql_cmd fr31_sess_b
"${PSQL_CMD[@]}" >"$B_OUT" 2>&1 <<SQL &
BEGIN;
update public.payments set status = 'PENDING', paid_at = null where id = '$PAY_2';
update public.products set stock = 8 where id = '$PROD_B';
delete from public.order_status_history where order_id = '$ORDER_2';
delete from public.notifications where order_id = '$ORDER_2';
update public.orders set payment_status = 'PENDING', order_status = 'PENDING_PAYMENT' where id = '$ORDER_2';
select id from public.orders where id = '$ORDER_2' for update;
select private.expire_stale_digital_payments();
select pg_sleep(8);
COMMIT;
SQL
B_PID=$!

# Readiness gate: B has committed the expiry in-txn and is now sleeping.
ready=0
for _ in $(seq 1 100); do
  if [ "$(psql_run fr31_poll -A -t -c "select 1 from pg_stat_activity \
      where application_name = 'fr31_sess_b' \
        and wait_event_type = 'Timeout' and wait_event = 'PgSleep' limit 1")" = "1" ]; then
    ready=1
    break
  fi
  sleep 0.1
done

if [ "$ready" != "1" ]; then
  echo "FAIL: session B never reached the pg_sleep wait state"
  exit 1
fi

echo "   session B holds the order row lock with staged expiry writes"

# Session A attempts confirmation concurrently: it must block on the
# ORDER lock (canonical ORDER -> PAYMENT lock order; no deadlock), and
# fail closed with 42501 once B commits EXPIRED.
build_psql_cmd fr31_sess_a2
"${PSQL_CMD[@]}" >"$A2_OUT" 2>&1 <<SQL &
\set VERBOSITY verbose
BEGIN;
set local role authenticated;
set local request.jwt.claim.sub = '$USER_A';
select public.confirm_order_payment('$ORDER_2');
COMMIT;
SQL
A2_PID=$!

contended=0
for _ in $(seq 1 80); do
  if [ "$(psql_run fr31_poll -A -t -c "select 1 from pg_stat_activity \
      where application_name = 'fr31_sess_a2' \
        and wait_event_type = 'Lock' limit 1")" = "1" ]; then
    contended=1
    break
  fi
  sleep 0.1
done

if [ "$contended" != "1" ]; then
  echo "FAIL: confirmation session was never observed blocked on the order lock"
  exit 1
fi

echo "   confirmation blocks on the order lock (no deadlock cycle)"

# Collect both outcomes.
set +e
wait "$B_PID"; B_RC=$?
B_PID=""
wait "$A2_PID"; A2_RC=$?
A2_PID=""
set -e

if [ "$B_RC" != "0" ]; then
  echo "FAIL: expiry session exited $B_RC"
  cat "$B_OUT"
  exit 1
fi

if [ "$A2_RC" = "0" ]; then
  echo "FAIL: confirmation unexpectedly succeeded against an expired order"
  echo "--- confirmation output ---"; cat "$A2_OUT"
  exit 1
fi

if ! grep -q '42501' "$A2_OUT" || ! grep -q 'Payment cannot be confirmed' "$A2_OUT"; then
  echo "FAIL: confirmation did not fail closed with 42501"
  echo "--- confirmation output ---"; cat "$A2_OUT"
  exit 1
fi

if grep -qi 'deadlock' "$B_OUT" "$A_OUT" "$A2_OUT"; then
  echo "FAIL: a deadlock was detected in one of the sessions"
  exit 1
fi

ST2="$(psql_run fr31_verify -A -t -c "select p.status || '/' || o.payment_status || '/' || o.order_status \
  from public.payments p join public.orders o on o.id = p.order_id \
  where o.id = '$ORDER_2'")"
if [ "$ST2" != "EXPIRED/EXPIRED/CANCELLED" ]; then
  echo "FAIL: expiry-win final state is '$ST2', expected EXPIRED/EXPIRED/CANCELLED"
  exit 1
fi

HIST2="$(psql_run fr31_verify -A -t -c "select count(*) from public.order_status_history \
  where order_id = '$ORDER_2'")"
NOTIF2_OK="$(psql_run fr31_verify -A -t -c "select count(*) from public.notifications \
  where order_id = '$ORDER_2' and title = 'Order cancelled'")"
NOTIF2_BAD="$(psql_run fr31_verify -A -t -c "select count(*) from public.notifications \
  where order_id = '$ORDER_2' and title = 'Payment received'")"
STOCK_B="$(psql_run fr31_verify -A -t -c "select stock from public.products where id = '$PROD_B'")"

if [ "$HIST2" != "1" ] || [ "$NOTIF2_OK" != "1" ] || [ "$NOTIF2_BAD" != "0" ]; then
  echo "FAIL: expiry-win side effects wrong (history=$HIST2 cancelled=$NOTIF2_OK received=$NOTIF2_BAD)"
  exit 1
fi
if [ "$STOCK_B" != "10" ]; then
  echo "FAIL: expiry-win restocked stock wrong (stock=$STOCK_B, expected 10 = 8 + 2 exactly once)"
  exit 1
fi

echo "   scenario 2 coherent: EXPIRED/EXPIRED/CANCELLED, confirmation failed closed"
echo "PASS: confirm-vs-expiry deterministic"
echo "      both interleavings commit exactly one outcome; no deadlocks; no split state"
