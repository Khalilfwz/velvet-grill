#!/usr/bin/env bash
# ============================================================
# BUG-03 cross-session concurrency verification
#
# pgTAP is single-session, so commit-time cross-session
# behavior is verified here: two real sessions race to insert
# the same (cart, product, empty option set) line. The deferred
# uniqueness triggers serialize on the parent carts row at
# commit, so exactly one session may commit; the other must be
# rejected with the duplicate-line error and no lost quantity.
#
# Both sessions insert BEFORE either commits (each blocks on a
# shared advisory handshake lock), then commit — exercising the
# designed mechanism: the winner's commit-time check cannot see
# the loser's uncommitted row and passes; the loser's check runs
# after waiting on the carts row lock and sees the committed
# winner, so it aborts.
#
# Usage:
#   supabase/migrations must be applied first (e.g. run
#   `npm run test:db` once, or `supabase db reset`).
#   SUPABASE_DB_URL overrides the default local database URL.
#
# This script makes no concurrency claim unless it is actually
# executed and passes.
# ============================================================

set -euo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

FIX_USER='9e111111-1111-1111-1111-111111111111'
FIX_CATEGORY='9e222222-2222-2222-2222-222222222222'
FIX_PRODUCT='9e333333-3333-3333-3333-333333333333'
FIX_CART='9e444444-4444-4444-4444-444444444444'
FIX_LINE_A='9e555551-1111-1111-1111-111111111111'
FIX_LINE_B='9e555552-2222-2222-2222-222222222222'

cleanup() {
  psql "$DB_URL" -v ON_ERROR_STOP=0 -q >/dev/null 2>&1 <<SQL || true
    delete from public.cart_items where id in ('$FIX_LINE_A', '$FIX_LINE_B');
    delete from public.carts where id = '$FIX_CART';
    delete from public.products where id = '$FIX_PRODUCT';
    delete from public.categories where id = '$FIX_CATEGORY';
    delete from auth.users where id = '$FIX_USER';
SQL
}
trap cleanup EXIT

# ---- fixtures ----

if ! psql "$DB_URL" -v ON_ERROR_STOP=1 -q <<SQL
  insert into auth.users (id, email)
  values ('$FIX_USER', 'bug03-concurrency@test.local');

  insert into public.categories (id, name, slug, is_active)
  values ('$FIX_CATEGORY', 'BUG03 Concurrency', 'bug03-concurrency', true);

  insert into public.products (id, category_id, name, slug, base_price, stock, is_available)
  values ('$FIX_PRODUCT', '$FIX_CATEGORY', 'BUG03 Concurrency Steak', 'bug03-concurrency-steak', 100000, 10, true);

  insert into public.carts (id, user_id)
  values ('$FIX_CART', '$FIX_USER');
SQL
then
  echo "FAIL: fixtures could not be created. Apply migrations first (e.g. npm run test:db)." >&2
  exit 1
fi

# ---- the race ----
#
# Sessions run as the table owner on purpose: the constraint
# triggers fire for every role, which is the property under
# test. Handshake locks 830101/830102 make both inserts happen
# before either commit; xact-scoped locks release at commit.

run_session() {
  local line_id="$1" lock_first="$2" lock_second="$3"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -q <<SQL
    begin;
    insert into public.cart_items (id, cart_id, product_id, quantity)
    values ('$line_id', '$FIX_CART', '$FIX_PRODUCT', 1);
    select pg_advisory_xact_lock($lock_first);
    select pg_advisory_xact_lock($lock_second);
    commit;
SQL
}

A_OUT="$(mktemp)"
B_OUT="$(mktemp)"
trap 'cleanup; rm -f "$A_OUT" "$B_OUT"' EXIT

run_session "$FIX_LINE_A" 830101 830102 >"$A_OUT" 2>&1 &
PID_A=$!
run_session "$FIX_LINE_B" 830101 830102 >"$B_OUT" 2>&1 &
PID_B=$!

A_RC=0
B_RC=0
wait "$PID_A" || A_RC=$?
wait "$PID_B" || B_RC=$?

# ---- assertions ----

FAILURES=0

ok() { echo "  ok - $1"; }
not_ok() { echo "  not ok - $1"; FAILURES=$((FAILURES + 1)); }

WINNERS=$(( (A_RC == 0 ? 1 : 0) + (B_RC == 0 ? 1 : 0) ))
if [ "$WINNERS" -eq 1 ]; then
  ok "exactly one of the two racing commits succeeded"
else
  not_ok "expected exactly one successful commit, got $WINNERS (A rc=$A_RC, B rc=$B_RC)"
fi

LOSER_OUT="$B_OUT"
[ "$A_RC" -ne 0 ] && LOSER_OUT="$A_OUT"
if grep -qi "duplicate cart line" "$LOSER_OUT"; then
  ok "the losing commit was rejected with the duplicate-line error"
else
  not_ok "the losing commit failed without the duplicate-line error"
  echo "  loser output:" >&2
  sed 's/^/    /' "$LOSER_OUT" >&2
fi

LINE_COUNT="$(psql "$DB_URL" -tA -c \
  "select count(*) from public.cart_items where cart_id = '$FIX_CART' and product_id = '$FIX_PRODUCT';")"
if [ "$LINE_COUNT" -eq 1 ]; then
  ok "exactly one line remains for the product in the cart"
else
  not_ok "expected 1 committed line, found $LINE_COUNT"
fi

LINE_QUANTITY="$(psql "$DB_URL" -tA -c \
  "select coalesce(sum(quantity), 0) from public.cart_items where cart_id = '$FIX_CART' and product_id = '$FIX_PRODUCT';")"
if [ "$LINE_QUANTITY" -eq 1 ]; then
  ok "the losing insert was fully rolled back (no lost or phantom quantity)"
else
  not_ok "expected total quantity 1, found $LINE_QUANTITY"
fi

rm -f "$A_OUT" "$B_OUT"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: concurrent identical adds cannot both commit"
  exit 0
fi

echo "FAIL: $FAILURES concurrency assertion(s) failed" >&2
exit 1
