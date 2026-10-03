import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import OrderStatusForm from '@/components/admin/OrderStatusForm'
import { nextOrderStatuses, type OrderStatus } from '@/lib/orders/order-status'
import { formatIDR } from '@/lib/format-currency'

export const metadata = {
  title: 'Orders',
}

const ORDER_STATUSES: OrderStatus[] = [
  'PENDING_PAYMENT',
  'CONFIRMED',
  'PREPARING',
  'READY',
  'COMPLETED',
  'CANCELLED',
]

function isOrderStatus(value: string): value is OrderStatus {
  return (ORDER_STATUSES as string[]).includes(value)
}

function formatDateTime(value: string | null): string {
  if (!value) {
    return '—'
  }

  return new Date(value).toLocaleString('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

export default async function AdminOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { supabase } = await requireAdminPage()
  const params = await searchParams
  const statusParam = typeof params.status === 'string' ? params.status : ''
  const statusFilter = isOrderStatus(statusParam) ? statusParam : null

  const ordersQuery = supabase
    .from('orders')
    .select(
      'id, order_number, customer_name_snapshot, fulfillment_type, table_number_snapshot, pickup_at, final_total, payment_status, order_status, created_at'
    )
    .order('created_at', { ascending: false })
    .limit(100)

  const { data: orders, error } = statusFilter
    ? await ordersQuery.eq('order_status', statusFilter)
    : await ordersQuery

  if (error) {
    console.error('Failed to load admin orders:', error)

    return (
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Orders
        </h1>
        <p className="mt-4 text-red-600">Failed to load orders.</p>
      </div>
    )
  }

  const rows = orders ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Orders
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Advance or cancel orders through the approved lifecycle.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Link
          href="/admin/orders"
          className={`rounded-full border px-3 py-1 font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand ${
            statusFilter
              ? 'border-border text-zinc-600 hover:border-brand hover:text-brand'
              : 'border-brand text-brand'
          }`}
        >
          All
        </Link>
        {ORDER_STATUSES.map((status) => (
          <Link
            key={status}
            href={`/admin/orders?status=${status}`}
            className={`rounded-full border px-3 py-1 font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand ${
              statusFilter === status
                ? 'border-brand text-brand'
                : 'border-border text-zinc-600 hover:border-brand hover:text-brand'
            }`}
          >
            {status}
          </Link>
        ))}
      </div>

      <section className="space-y-4">
        {rows.length === 0 ? (
          <p className="text-sm text-zinc-600">No orders found.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Order</th>
                  <th className="px-4 py-3 font-medium">Customer</th>
                  <th className="px-4 py-3 font-medium">Fulfillment</th>
                  <th className="px-4 py-3 font-medium">Total</th>
                  <th className="px-4 py-3 font-medium">Payment</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Created</th>
                  <th className="px-4 py-3 font-medium">Update</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((order) => (
                  <tr
                    key={order.id}
                    className="border-b border-border align-top last:border-b-0"
                  >
                    <td className="px-4 py-3 font-medium text-foreground">
                      {order.order_number}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {order.customer_name_snapshot}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {order.fulfillment_type === 'DINE_IN'
                        ? `Dine-in · Table ${order.table_number_snapshot ?? '—'}`
                        : `Pickup · ${formatDateTime(order.pickup_at)}`}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {formatIDR(order.final_total)}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {order.payment_status}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {order.order_status}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {formatDateTime(order.created_at)}
                    </td>
                    <td className="px-4 py-3">
                      <OrderStatusForm
                        orderId={order.id}
                        currentStatus={order.order_status}
                        allowedTransitions={nextOrderStatuses(
                          order.order_status
                        )}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}
