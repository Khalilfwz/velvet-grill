import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function formatPickupAt(value: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(value))
}

export default async function OrderPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params

  if (!UUID_PATTERN.test(id)) {
    notFound()
  }

  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()

  if (!claimsData?.claims) {
    redirect('/login')
  }

  const { data: order, error } = await supabase
    .from('orders')
    .select(
      'id, order_number, order_status, payment_status, fulfillment_type, pickup_at, table_number_snapshot, customer_name_snapshot, customer_note, subtotal, discount_total, final_total, created_at, order_items(id, product_name_snapshot, base_price_snapshot, final_unit_price, quantity, subtotal, order_item_options(id, option_group_name_snapshot, option_name_snapshot, price_delta_snapshot))'
    )
    .eq('id', id)
    .maybeSingle()

  if (error) {
    console.error('Failed to load order:', error.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <p className="text-red-600">Failed to load your order.</p>
        </div>
      </main>
    )
  }

  if (!order) {
    notFound()
  }

  const items = order.order_items ?? []

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-4xl font-bold text-foreground">
          Order placed
        </h1>

        <p className="mt-2 text-zinc-600">
          Order <span className="font-medium text-foreground">{order.order_number}</span>
        </p>

        <section className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <dl className="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-zinc-600">Status</dt>
              <dd className="font-medium text-foreground">{order.order_status}</dd>
            </div>

            <div>
              <dt className="text-zinc-600">Fulfillment</dt>
              <dd className="font-medium text-foreground">
                {order.fulfillment_type === 'PICKUP' ? 'Pickup' : 'Dine-in'}
              </dd>
            </div>

            {order.fulfillment_type === 'PICKUP' && order.pickup_at && (
              <div>
                <dt className="text-zinc-600">Pickup time</dt>
                <dd className="font-medium text-foreground">
                  {formatPickupAt(order.pickup_at)}
                </dd>
              </div>
            )}

            {order.fulfillment_type === 'DINE_IN' &&
              order.table_number_snapshot && (
                <div>
                  <dt className="text-zinc-600">Table</dt>
                  <dd className="font-medium text-foreground">
                    {order.table_number_snapshot}
                  </dd>
                </div>
              )}

            <div>
              <dt className="text-zinc-600">Placed for</dt>
              <dd className="font-medium text-foreground">
                {order.customer_name_snapshot}
              </dd>
            </div>
          </dl>

          {order.customer_note && (
            <p className="mt-4 text-sm text-zinc-600">Note: {order.customer_note}</p>
          )}
        </section>

        <section className="mt-6 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Items
          </h2>

          <ul className="mt-4 space-y-4">
            {items.map((item) => (
              <li key={item.id} className="text-sm">
                <div className="flex justify-between gap-4">
                  <span className="text-foreground">
                    {item.product_name_snapshot}
                    <span className="text-zinc-600"> × {item.quantity}</span>
                  </span>

                  <span className="shrink-0 text-foreground">
                    {formatIDR(item.subtotal)}
                  </span>
                </div>

                {(item.order_item_options ?? []).length > 0 && (
                  <ul className="mt-1 space-y-1 text-zinc-600">
                    {(item.order_item_options ?? []).map((option) => (
                      <li key={option.id}>
                        {option.option_group_name_snapshot}:{' '}
                        {option.option_name_snapshot}
                        {option.price_delta_snapshot !== 0 &&
                          ` (${formatIDR(option.price_delta_snapshot)})`}
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
          </ul>

          <dl className="mt-6 space-y-2 border-t border-border pt-4 text-sm">
            <div className="flex justify-between">
              <dt className="text-zinc-600">Subtotal</dt>
              <dd className="text-foreground">{formatIDR(order.subtotal)}</dd>
            </div>

            <div className="flex justify-between">
              <dt className="text-zinc-600">Discount</dt>
              <dd className="text-foreground">
                {formatIDR(order.discount_total)}
              </dd>
            </div>

            <div className="flex justify-between">
              <dt className="font-medium text-foreground">Total</dt>
              <dd className="font-display text-xl font-medium text-brand">
                {formatIDR(order.final_total)}
              </dd>
            </div>
          </dl>
        </section>

        <Link
          href="/menu"
          className={`mt-8 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
        >
          Back to menu
        </Link>
      </div>
    </main>
  )
}
