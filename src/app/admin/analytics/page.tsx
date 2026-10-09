import { requireAdminPage } from '@/lib/admin/guard'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import DailyTrendChart from '@/components/admin/DailyTrendChart'
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
  settled_orders: number
  gross_settled_value: number
  refunded_value: number
  net_collected_value: number
  avg_settled_order_value: number | null
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
  settled_orders: 0,
  gross_settled_value: 0,
  refunded_value: 0,
  net_collected_value: 0,
  avg_settled_order_value: null,
}

type TopProduct = {
  product_key: string
  product_name: string
  units_fulfilled: number
}

type DailyTrendPoint = {
  day: string
  orders_created: number
  net_collected_value: number
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
          <tfoot className="border-t border-border bg-zinc-50/60">
            <tr>
              <td className="px-4 py-3 font-medium text-zinc-600">Total</td>
              <td className="px-4 py-3 text-right font-medium text-foreground tabular-nums">
                {total}
              </td>
              <td className="px-4 py-3 text-right font-medium text-zinc-600 tabular-nums">
                {total > 0 ? '100%' : '—'}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>
  )
}

function MetricCard({
  label,
  value,
  detail,
  featured = false,
}: {
  label: string
  value: string
  detail?: string
  featured?: boolean
}) {
  return (
    <div
      className={`flex flex-col gap-2 rounded-xl border p-5 ${
        featured ? 'border-brand/40 bg-brand/5' : 'border-border bg-surface'
      }`}
    >
      <p
        className={`text-sm font-medium ${
          featured ? 'text-brand' : 'text-zinc-600'
        }`}
      >
        {label}
      </p>
      <p
        className={`break-words font-display font-bold tabular-nums text-foreground ${
          featured ? 'text-3xl sm:text-4xl' : 'text-2xl sm:text-3xl'
        }`}
      >
        {value}
      </p>
      {detail ? (
        <p className="text-xs leading-relaxed text-zinc-500">{detail}</p>
      ) : null}
    </div>
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

  // Same resolved range as the operational analytics RPC above.
  const { data: topProductsData, error: topProductsError } = await supabase
    .rpc('admin_top_products', {
      p_from: from,
      p_to: to,
    })
  const topProducts: TopProduct[] = topProductsData ?? []

  // Same resolved range as the operational analytics RPC above.
  const { data: dailyData, error: dailyError } = await supabase.rpc(
    'admin_daily_analytics',
    {
      p_from: from,
      p_to: to,
    }
  )
  const dailyTrend: DailyTrendPoint[] = dailyData ?? []

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
        <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-zinc-600">
          <span>
            Showing{' '}
            <span className="font-medium text-foreground">{from}</span> to{' '}
            <span className="font-medium text-foreground">{to}</span>
          </span>
          <span className="rounded-full border border-border px-2 py-0.5 text-xs">
            {timeZone}
          </span>
        </p>
      </div>

      <section
        aria-label="Summary metrics"
        className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
      >
        <MetricCard
          featured
          label="Net collected value"
          value={formatIDR(Number(metrics.net_collected_value))}
          detail="Orders whose current payment status is PAID."
        />
        <MetricCard
          label="Total orders"
          value={String(metrics.total_orders)}
          detail="All orders created in the selected range."
        />
        <MetricCard
          label="Booked order value"
          value={formatIDR(Number(metrics.gross_order_value))}
          detail="Excludes cancelled orders."
        />
        <MetricCard
          label="Gross settled value"
          value={formatIDR(Number(metrics.gross_settled_value))}
          detail="Payment status PAID or REFUNDED."
        />
        <MetricCard
          label="Refunded value"
          value={formatIDR(Number(metrics.refunded_value))}
          detail="Payment status REFUNDED."
        />
        <MetricCard
          label="Average settled order value"
          value={
            metrics.avg_settled_order_value === null
              ? '—'
              : formatIDR(Number(metrics.avg_settled_order_value))
          }
          detail="Gross settled value ÷ settled orders."
        />
      </section>

      <div className="space-y-1.5 text-sm leading-relaxed text-zinc-600">
        <p>
          <span className="font-medium text-foreground">
            Average settled order value
          </span>{' '}
          is gross settled value divided by settled orders (orders with payment
          status PAID or REFUNDED), and is shown as — when there are no settled
          orders.
        </p>
        <p>
          Financial metrics are attributed to each order&apos;s creation date in
          the restaurant timezone ({timeZone}), not the payment-event date.
        </p>
        <p>
          Payments in this project are simulated for demonstration; these
          figures are not real revenue.
        </p>
      </div>

      {metrics.total_orders === 0 && (
        <EmptyState message="No orders were created in this range." />
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

      {dailyError ? (
        <p role="alert" className="text-sm text-red-600">
          Failed to load daily trend analytics.
        </p>
      ) : (
        <div className="space-y-8">
          <DailyTrendChart
            title="Daily orders created"
            caption="Orders created each day in the selected range, in the restaurant timezone. Short ranges label each bar with its exact order count; every day's exact count is also announced to assistive technology. CANCELLED orders are included."
            points={dailyTrend.map((row) => ({
              day: row.day,
              value: Number(row.orders_created),
            }))}
            formatValue={(value) => String(value)}
            unitLabel="orders"
          />

          <DailyTrendChart
            title="Daily net collected"
            caption="Net collected value each day in the selected range, in the restaurant timezone. Short ranges label each bar with its exact IDR amount; every day's exact amount is also announced to assistive technology. Only orders whose current payment status is PAID contribute; refunded, unpaid, pending, failed, and expired orders contribute zero."
            points={dailyTrend.map((row) => ({
              day: row.day,
              value: Number(row.net_collected_value),
            }))}
            formatValue={formatIDR}
          />
        </div>
      )}

      <section className="space-y-4">
        <div>
          <h2 className="font-display text-xl font-semibold text-foreground">
            Top products
          </h2>
          <p className="mt-1 text-sm text-zinc-600">
            Top 5 by units fulfilled in completed orders.
          </p>
        </div>
        {topProductsError ? (
          <p role="alert" className="text-sm text-red-600">
            Failed to load top products.
          </p>
        ) : topProducts.length === 0 ? (
          <EmptyState message="No completed product sales in this range." />
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">
                Top 5 products ranked by units fulfilled: the summed order-item
                quantity of completed orders in the selected range, including
                completed orders later refunded. Products removed from the
                catalog keep their historical order snapshot names.
              </caption>
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Rank
                  </th>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Product
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Units fulfilled
                  </th>
                </tr>
              </thead>
              <tbody>
                {topProducts.map((product, index) => (
                  <tr
                    key={product.product_key}
                    className="border-b border-border last:border-b-0"
                  >
                    <td className="px-4 py-3 tabular-nums text-zinc-500">
                      {index + 1}
                    </td>
                    <td className="px-4 py-3 text-foreground">
                      {product.product_name}
                    </td>
                    <td className="px-4 py-3 text-right font-medium text-foreground tabular-nums">
                      {Number(product.units_fulfilled)}
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
