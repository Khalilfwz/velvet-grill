import { requireAdminPage } from '@/lib/admin/guard'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import FilterChips from '@/components/admin/FilterChips'
import { formatIDR } from '@/lib/format-currency'
import {
  ANALYTICS_RANGE_OPTIONS,
  isoDaySpan,
  parseIsoDate,
  rangeForPreset,
  todayInTimeZone,
} from '@/lib/admin/analytics-range'

export const metadata = {
  title: 'Analytics',
}

const DEFAULT_TIME_ZONE = 'Asia/Jakarta'
const MAX_RANGE_DAYS = 365

type AnalyticsMetrics = {
  total_orders: number
  orders_pending_payment: number
  orders_confirmed: number
  orders_preparing: number
  orders_ready: number
  orders_completed: number
  orders_cancelled: number
  payments_unpaid: number
  payments_pending: number
  payments_paid: number
  payments_failed: number
  payments_expired: number
  payments_refunded: number
  fulfillment_pickup: number
  fulfillment_dine_in: number
  gross_order_value: number
}

const EMPTY_METRICS: AnalyticsMetrics = {
  total_orders: 0,
  orders_pending_payment: 0,
  orders_confirmed: 0,
  orders_preparing: 0,
  orders_ready: 0,
  orders_completed: 0,
  orders_cancelled: 0,
  payments_unpaid: 0,
  payments_pending: 0,
  payments_paid: 0,
  payments_failed: 0,
  payments_expired: 0,
  payments_refunded: 0,
  fulfillment_pickup: 0,
  fulfillment_dine_in: 0,
  gross_order_value: 0,
}

const ORDER_STATUS_ROWS: { label: string; key: keyof AnalyticsMetrics }[] = [
  { label: 'Pending payment', key: 'orders_pending_payment' },
  { label: 'Confirmed', key: 'orders_confirmed' },
  { label: 'Preparing', key: 'orders_preparing' },
  { label: 'Ready', key: 'orders_ready' },
  { label: 'Completed', key: 'orders_completed' },
  { label: 'Cancelled', key: 'orders_cancelled' },
]

const PAYMENT_STATUS_ROWS: { label: string; key: keyof AnalyticsMetrics }[] = [
  { label: 'Unpaid', key: 'payments_unpaid' },
  { label: 'Pending', key: 'payments_pending' },
  { label: 'Paid', key: 'payments_paid' },
  { label: 'Failed', key: 'payments_failed' },
  { label: 'Expired', key: 'payments_expired' },
  { label: 'Refunded', key: 'payments_refunded' },
]

const FULFILLMENT_ROWS: { label: string; key: keyof AnalyticsMetrics }[] = [
  { label: 'Pickup', key: 'fulfillment_pickup' },
  { label: 'Dine-in', key: 'fulfillment_dine_in' },
]

function BreakdownTable({
  title,
  labelHeader,
  rows,
  metrics,
}: {
  title: string
  labelHeader: string
  rows: { label: string; key: keyof AnalyticsMetrics }[]
  metrics: AnalyticsMetrics
}) {
  // Share denominators stay local to each breakdown: the explicit sum of the
  // rows listed in that table, never a cross-table or RPC-derived figure.
  const total = rows.reduce((sum, row) => sum + Number(metrics[row.key]), 0)

  return (
    <section className="space-y-4">
      <h2 className="font-display text-xl font-semibold text-foreground">
        {title}
      </h2>
      <div className="overflow-hidden rounded-xl border border-border bg-surface">
        <table className="w-full text-left text-sm">
          <caption className="sr-only">
            {title} breakdown; share is each row divided by the sum of the rows
            listed in this table.
          </caption>
          <thead className="border-b border-border text-zinc-600">
            <tr>
              <th scope="col" className="px-4 py-3 font-medium">
                {labelHeader}
              </th>
              <th scope="col" className="px-4 py-3 text-right font-medium">
                Orders
              </th>
              <th scope="col" className="px-4 py-3 text-right font-medium">
                Share
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => {
              const value = Number(metrics[row.key])
              const share =
                total > 0 ? `${Math.round((value / total) * 100)}%` : '—'

              return (
                <tr
                  key={row.key}
                  className="border-b border-border last:border-b-0"
                >
                  <td className="px-4 py-3 text-zinc-600">{row.label}</td>
                  <td className="px-4 py-3 text-right text-foreground tabular-nums">
                    {value}
                  </td>
                  <td className="px-4 py-3 text-right text-zinc-600 tabular-nums">
                    {share}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </section>
  )
}

export default async function AdminAnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { supabase } = await requireAdminPage()
  const params = await searchParams

  // The timezone comes from server-side restaurant_settings, never the browser.
  const { data: settings } = await supabase
    .from('restaurant_settings')
    .select('timezone')
    .eq('id', 1)
    .maybeSingle()

  const timeZone = settings?.timezone ?? DEFAULT_TIME_ZONE
  const todayIso = todayInTimeZone(timeZone)
  const defaultRange = rangeForPreset('7d', todayIso)

  const fromParam = parseIsoDate(params.from)
  const toParam = parseIsoDate(params.to)
  const isValidRange =
    fromParam !== null &&
    toParam !== null &&
    fromParam <= toParam &&
    isoDaySpan(fromParam, toParam) <= MAX_RANGE_DAYS

  const from = isValidRange ? fromParam : defaultRange.from
  const to = isValidRange ? toParam : defaultRange.to

  const { data, error } = await supabase.rpc('admin_operational_analytics', {
    p_from: from,
    p_to: to,
  })

  if (error) {
    console.error('Failed to load admin analytics:', error)

    return (
      <div>
        <AdminPageHeading
          title="Analytics"
          description="Operational order metrics for the selected range, computed from transactional orders."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load analytics.
        </p>
      </div>
    )
  }

  const metrics: AnalyticsMetrics = data?.[0]
    ? { ...EMPTY_METRICS, ...data[0] }
    : EMPTY_METRICS

  const rangeChips = ANALYTICS_RANGE_OPTIONS.map((option) => {
    const range = rangeForPreset(option.value, todayIso)

    return {
      value: `${range.from}..${range.to}`,
      label: option.label,
      href: `/admin/analytics?from=${range.from}&to=${range.to}`,
    }
  })

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Analytics"
        description="Operational order metrics for the selected range, computed from transactional orders."
      />

      <div className="space-y-3">
        <FilterChips
          ariaLabel="Analytics date range"
          activeValue={`${from}..${to}`}
          items={rangeChips}
        />
        <p className="text-sm text-zinc-600">
          Range: {from} to {to} ({timeZone})
        </p>
      </div>

      <section className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-border bg-surface p-6">
          <p className="text-sm text-zinc-600">Total orders</p>
          <p className="mt-1 font-display text-3xl font-bold text-foreground">
            {metrics.total_orders}
          </p>
        </div>

        <div className="rounded-xl border border-border bg-surface p-6">
          <p className="text-sm text-zinc-600">
            Gross order value (excl. cancelled)
          </p>
          <p className="mt-1 font-display text-3xl font-bold text-foreground">
            {formatIDR(Number(metrics.gross_order_value))}
          </p>
        </div>
      </section>

      {metrics.total_orders === 0 && (
        <EmptyState message="No orders in this range." />
      )}

      <div className="grid gap-8 lg:grid-cols-3">
        <BreakdownTable
          title="Order status"
          labelHeader="Status"
          rows={ORDER_STATUS_ROWS}
          metrics={metrics}
        />

        <BreakdownTable
          title="Payment status"
          labelHeader="Status"
          rows={PAYMENT_STATUS_ROWS}
          metrics={metrics}
        />

        <BreakdownTable
          title="Fulfillment"
          labelHeader="Type"
          rows={FULFILLMENT_ROWS}
          metrics={metrics}
        />
      </div>
    </div>
  )
}
