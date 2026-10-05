import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { formatIDR } from '@/lib/format-currency'
import { paymentStatusLabel } from '@/lib/orders/payment'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

function formatPlacedAt(value: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(value))
}

export default async function OrdersPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Ownership comes only from the authoritative session subject, never the
  // browser. Filtering by it keeps this page scoped to the caller even for an
  // admin, whose orders_admin_select policy would otherwise match every row.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  // No cap: this is the caller's real order history, newest first. Pagination is
  // deliberately deferred to later performance work.
  const { data: orders, error } = await supabase
    .from('orders')
    .select(
      'id, order_number, order_status, payment_status, fulfillment_type, pickup_at, table_number_snapshot, final_total, created_at'
    )
    .eq('user_id', userId)
    .order('created_at', { ascending: false })

  if (error) {
    console.error('Failed to fetch orders:', error.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <h1 className="font-display text-4xl font-bold text-foreground">
            My Orders
          </h1>

          <p className="mt-4 text-red-600">Failed to load your orders.</p>
        </div>
      </main>
    )
  }

  const rows = orders ?? []

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-4xl font-bold text-foreground">
          My Orders
        </h1>

        <p className="mt-4 max-w-2xl text-zinc-600">
          Your order history and current status.
        </p>

        {rows.length === 0 ? (
          <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              You haven&apos;t placed any orders yet
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              Browse the menu and place your first order.
            </p>

            <Link
              href="/menu"
              className={`mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
            >
              Browse the menu
            </Link>
          </div>
        ) : (
          <ul className="mt-12 space-y-4">
            {rows.map((order) => (
              <li key={order.id}>
                <Link
                  href={`/orders/${order.id}`}
                  className={`block rounded-xl border border-border bg-surface p-6 shadow-sm transition-colors hover:border-brand ${focusClasses}`}
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="font-display text-lg font-semibold text-foreground">
                      {order.order_number}
                    </span>

                    <span className="text-sm text-zinc-600">
                      {formatPlacedAt(order.created_at)}
                    </span>
                  </div>

                  <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
                    <div>
                      <dt className="text-zinc-600">Status</dt>
                      <dd className="font-medium text-foreground">
                        {order.order_status}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-zinc-600">Payment</dt>
                      <dd className="font-medium text-foreground">
                        {paymentStatusLabel(order.payment_status)}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-zinc-600">Fulfillment</dt>
                      <dd className="font-medium text-foreground">
                        {order.fulfillment_type === 'PICKUP' ? 'Pickup' : 'Dine-in'}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-zinc-600">
                        {order.fulfillment_type === 'PICKUP'
                          ? 'Pickup time'
                          : 'Table'}
                      </dt>
                      <dd className="font-medium text-foreground">
                        {order.fulfillment_type === 'PICKUP'
                          ? order.pickup_at
                            ? formatPlacedAt(order.pickup_at)
                            : '—'
                          : order.table_number_snapshot ?? '—'}
                      </dd>
                    </div>
                  </dl>

                  <p className="mt-4 flex items-baseline justify-between border-t border-border pt-4">
                    <span className="text-sm text-zinc-600">Total</span>
                    <span className="font-display text-xl font-medium text-brand">
                      {formatIDR(order.final_total)}
                    </span>
                  </p>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </main>
  )
}
