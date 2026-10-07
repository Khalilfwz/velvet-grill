import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { formatIDR } from '@/lib/format-currency'
import ConfirmPaymentButton from '@/components/orders/ConfirmPaymentButton'
import ReviewForm from '@/components/reviews/ReviewForm'
import BackLink from '@/components/navigation/BackLink'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'
import OrderStatusBadge from '@/components/orders/OrderStatusBadge'
import { paymentMethodLabel, paymentStatusLabel } from '@/lib/orders/payment'

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
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { id } = await params
  const { from } = await searchParams

  if (!UUID_PATTERN.test(id)) {
    notFound()
  }

  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  const userId =
    typeof claimsData?.claims?.sub === 'string' ? claimsData.claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  const { data: order, error } = await supabase
    .from('orders')
    .select(
      'id, user_id, order_number, order_status, payment_status, fulfillment_type, pickup_at, table_number_snapshot, customer_name_snapshot, customer_note, subtotal, discount_total, final_total, coupon_code_snapshot, created_at, payments(method, status, paid_at), order_items(id, product_name_snapshot, base_price_snapshot, final_unit_price, quantity, subtotal, order_item_options(id, option_group_name_snapshot, option_name_snapshot, price_delta_snapshot))'
    )
    .eq('id', id)
    .maybeSingle()

  if (error) {
    console.error('Failed to load order:', error.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <PageHeader title="Order" />

          <ErrorState message="Failed to load your order." />
        </div>
      </main>
    )
  }

  if (!order) {
    notFound()
  }

  const items = order.order_items ?? []

  // Review controls are for the order's owner only. `order.user_id` is read
  // server-side solely for this check and is never displayed; broader admin read
  // policies must not grant customer review controls on someone else's order.
  const isOwner = order.user_id === userId

  // The caller's own reviews for this order's items, so an already-reviewed item
  // shows a summary instead of a second form. reviews_select_own scopes this.
  const reviewedByItemId = new Map<string, { rating: number; status: string }>()

  if (isOwner && items.length > 0) {
    const { data: reviewRows } = await supabase
      .from('reviews')
      .select('order_item_id, rating, status')
      .eq('user_id', userId)
      .in(
        'order_item_id',
        items.map((item) => item.id)
      )

    for (const row of reviewRows ?? []) {
      reviewedByItemId.set(row.order_item_id, {
        rating: row.rating,
        status: row.status,
      })
    }
  }

  // FR-17 requires exactly one payment row per order. Historical/seeded orders
  // (created before FR-17) have none, so the method falls back to "—"; the
  // aggregate state always comes from orders.payment_status.
  const payments = order.payments ?? []
  const payment = payments.length === 1 ? payments[0] : null

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <div className="mt-2 flex flex-wrap items-center gap-3">
          <h1 className="font-display text-4xl font-bold text-foreground">
            Order {order.order_number}
          </h1>

          <OrderStatusBadge status={order.order_status} />
        </div>

        <section className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <dl className="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-zinc-600">Status</dt>
              <dd className="mt-0.5">
                <OrderStatusBadge status={order.order_status} />
              </dd>
            </div>

            <div>
              <dt className="text-zinc-600">Fulfillment</dt>
              <dd className="font-medium text-foreground">
                {order.fulfillment_type === 'PICKUP' ? 'Pickup' : 'Dine-in'}
              </dd>
            </div>

            <div>
              <dt className="text-zinc-600">Payment</dt>
              <dd className="font-medium text-foreground">
                {payment ? paymentMethodLabel(payment.method) : '—'}
              </dd>
            </div>

            <div>
              <dt className="text-zinc-600">Payment status</dt>
              <dd className="font-medium text-foreground">
                {paymentStatusLabel(order.payment_status)}
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

          {/* Offer a payment action only when the order and the single payment
              row agree on the state; inconsistent state is left untouched. */}
          {payment &&
            (payment.method === 'DUMMY_QRIS' ||
              payment.method === 'DUMMY_BANK_TRANSFER') &&
            payment.status === 'PENDING' &&
            order.payment_status === 'PENDING' && (
              <ConfirmPaymentButton orderId={order.id} />
            )}

          {payment &&
            payment.method === 'CASH' &&
            payment.status === 'UNPAID' &&
            order.payment_status === 'UNPAID' && (
              <p className="mt-4 text-sm text-zinc-600">
                Pay with cash at fulfillment.
              </p>
            )}
        </section>

        <section className="mt-6 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Items
          </h2>

          <ul className="mt-4 space-y-4">
            {items.map((item) => {
              const review = reviewedByItemId.get(item.id)

              return (
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

                  {isOwner && order.order_status === 'COMPLETED' && (
                    review ? (
                      <p className="mt-3 text-sm text-zinc-600">
                        You rated this {review.rating}/5
                        {review.status === 'HIDDEN' &&
                          ' (hidden by moderation)'}
                      </p>
                    ) : (
                      <ReviewForm orderItemId={item.id} />
                    )
                  )}
                </li>
              )
            })}
          </ul>

          <dl className="mt-6 space-y-2 border-t border-border pt-4 text-sm">
            <div className="flex justify-between">
              <dt className="text-zinc-600">Subtotal</dt>
              <dd className="text-foreground">{formatIDR(order.subtotal)}</dd>
            </div>

            {order.discount_total > 0 && (
              <div className="flex justify-between">
                <dt className="text-zinc-600">Discount</dt>
                <dd className="text-foreground">
                  {formatIDR(order.discount_total)}
                </dd>
              </div>
            )}

            {order.coupon_code_snapshot && (
              <div className="flex justify-between">
                <dt className="text-zinc-600">Coupon</dt>
                <dd className="text-foreground">
                  {order.coupon_code_snapshot}
                </dd>
              </div>
            )}

            <div className="flex justify-between">
              <dt className="font-medium text-foreground">Total</dt>
              <dd className="font-display text-xl font-medium text-brand">
                {formatIDR(order.final_total)}
              </dd>
            </div>
          </dl>
        </section>

        <BackLink
          route="order-detail"
          from={from}
          className={`mt-8 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
        />
      </div>
    </main>
  )
}
