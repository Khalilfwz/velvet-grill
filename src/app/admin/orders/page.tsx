import { requireAdminPage } from '@/lib/admin/guard'
import OrderStatusForm from '@/components/admin/OrderStatusForm'
import ConfirmCashPaymentButton from '@/components/admin/ConfirmCashPaymentButton'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import FilterChips from '@/components/admin/FilterChips'
import OrderStatusBadge from '@/components/orders/OrderStatusBadge'
import StatusBadge, { type StatusBadgeTone } from '@/components/admin/StatusBadge'
import {
  nextOrderStatusesForOrder,
  orderStatusLabel,
  type OrderStatus,
} from '@/lib/orders/order-status'
import { paymentMethodLabel, paymentStatusLabel } from '@/lib/orders/payment'
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

function paymentTone(status: string): StatusBadgeTone {
  if (status === 'PAID') {
    return 'brand'
  }

  if (status === 'FAILED' || status === 'EXPIRED' || status === 'REFUNDED') {
    return 'danger'
  }

  return 'neutral'
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
      'id, order_number, customer_name_snapshot, fulfillment_type, table_number_snapshot, pickup_at, final_total, payment_status, order_status, created_at, payments(method, status)'
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
        <AdminPageHeading
          title="Orders"
          description="Advance or cancel orders through the approved lifecycle."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load orders.
        </p>
      </div>
    )
  }

  const rows = orders ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Orders"
        description="Advance or cancel orders through the approved lifecycle."
      />

      <FilterChips
        ariaLabel="Filter orders by status"
        activeValue={statusFilter ?? 'ALL'}
        items={[
          { value: 'ALL', label: 'All', href: '/admin/orders' },
          ...ORDER_STATUSES.map((status) => ({
            value: status,
            label: orderStatusLabel(status),
            href: `/admin/orders?status=${status}`,
          })),
        ]}
      />

      <section>
        {rows.length === 0 ? (
          <EmptyState
            message={
              statusFilter
                ? 'No orders with this status.'
                : 'No orders found.'
            }
          />
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <div className="overflow-x-auto">
              <table className="w-full min-w-[880px] text-left text-sm">
                <thead className="border-b border-border text-zinc-600">
                  <tr>
                    <th className="px-4 py-3 font-medium">Order</th>
                    <th className="px-4 py-3 font-medium">Fulfillment</th>
                    <th className="px-4 py-3 font-medium">Total</th>
                    <th className="px-4 py-3 font-medium">Payment</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 font-medium">Created</th>
                    <th className="px-4 py-3 font-medium">Update</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((order) => {
                    const payments = order.payments ?? []
                    const payment = payments.length === 1 ? payments[0] : null
                    const methodLabel = payment
                      ? paymentMethodLabel(payment.method)
                      : '—'
                    const paymentStatus = payment
                      ? payment.status
                      : order.payment_status
                    // Mirror the RPC's UX restrictions only: exactly one payment
                    // row, CASH method, both representations UNPAID. The RPC
                    // stays authoritative, and this control is never offered for
                    // QRIS or bank transfer.
                    const canConfirmCash =
                      payment !== null &&
                      payment.method === 'CASH' &&
                      payment.status === 'UNPAID' &&
                      order.payment_status === 'UNPAID'

                    return (
                      <tr
                        key={order.id}
                        className="border-b border-border align-top last:border-b-0"
                      >
                        <td className="px-4 py-3">
                          <span className="block font-medium text-foreground">
                            {order.order_number}
                          </span>
                          <span className="block text-xs text-zinc-500">
                            {order.customer_name_snapshot}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-zinc-600">
                          {order.fulfillment_type === 'DINE_IN'
                            ? `Dine-in · Table ${order.table_number_snapshot ?? '—'}`
                            : `Pickup · ${formatDateTime(order.pickup_at)}`}
                        </td>
                        <td className="px-4 py-3 text-zinc-600">
                          {formatIDR(order.final_total)}
                        </td>
                        <td className="px-4 py-3">
                          <div className="space-y-1.5">
                            <span className="block text-foreground">
                              {methodLabel}
                            </span>
                            <StatusBadge
                              label={paymentStatusLabel(paymentStatus)}
                              tone={paymentTone(paymentStatus)}
                            />
                          </div>
                        </td>
                        <td className="px-4 py-3">
                          <OrderStatusBadge status={order.order_status} />
                        </td>
                        <td className="px-4 py-3 text-zinc-600">
                          {formatDateTime(order.created_at)}
                        </td>
                        <td className="px-4 py-3">
                          <div className="space-y-2">
                            {canConfirmCash && (
                              <ConfirmCashPaymentButton orderId={order.id} />
                            )}
                            <OrderStatusForm
                              orderId={order.id}
                              currentStatus={order.order_status}
                              allowedTransitions={nextOrderStatusesForOrder(
                                order.order_status,
                                order.payment_status
                              )}
                            />
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}
