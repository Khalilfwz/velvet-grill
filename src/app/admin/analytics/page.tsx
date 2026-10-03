import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
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

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

function chipClasses(active: boolean): string {
  return `rounded-full border px-3 py-1 font-medium transition-colors ${focusClasses} ${
    active
      ? 'border-brand text-brand'
      : 'border-border text-zinc-600 hover:border-brand hover:text-brand'
  }`
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
        <h1 className="font-display text-3xl font-bold text-foreground">
          Analytics
        </h1>
        <p className="mt-4 text-red-600">Failed to load analytics.</p>
      </div>
    )
  }

  const metrics: AnalyticsMetrics = data?.[0]
    ? { ...EMPTY_METRICS, ...data[0] }
    : EMPTY_METRICS

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Analytics
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Operational order metrics for the selected range, computed from
          transactional orders.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        {ANALYTICS_RANGE_OPTIONS.map((option) => {
          const range = rangeForPreset(option.value, todayIso)
          const active = range.from === from && range.to === to

          return (
            <Link
              key={option.value}
              href={`/admin/analytics?from=${range.from}&to=${range.to}`}
              className={chipClasses(active)}
            >
              {option.label}
            </Link>
          )
        })}
      </div>

      <p className="text-sm text-zinc-600">
        Range: {from} to {to} ({timeZone})
      </p>

      <section className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-border bg-surface p-6">
          <p className="text-sm font-medium text-zinc-600">Total orders</p>
          <p className="mt-2 font-display text-3xl font-bold text-foreground">
            {metrics.total_orders}
          </p>
        </div>

        <div className="rounded-xl border border-border bg-surface p-6">
          <p className="text-sm font-medium text-zinc-600">
            Gross order value (excl. cancelled)
          </p>
          <p className="mt-2 font-display text-3xl font-bold text-foreground">
            {formatIDR(Number(metrics.gross_order_value))}
          </p>
        </div>
      </section>

      {metrics.total_orders === 0 && (
        <p className="text-sm text-zinc-600">No orders in this range.</p>
      )}

      <div className="grid gap-8 lg:grid-cols-3">
        <section className="space-y-4">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Order status
          </h2>
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Orders</th>
                </tr>
              </thead>
              <tbody>
                {ORDER_STATUS_ROWS.map((row) => (
                  <tr
                    key={row.key}
                    className="border-b border-border last:border-b-0"
                  >
                    <td className="px-4 py-3 text-zinc-600">{row.label}</td>
                    <td className="px-4 py-3 text-foreground">
                      {metrics[row.key]}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section className="space-y-4">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Payment status
          </h2>
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Orders</th>
                </tr>
              </thead>
              <tbody>
                {PAYMENT_STATUS_ROWS.map((row) => (
                  <tr
                    key={row.key}
                    className="border-b border-border last:border-b-0"
                  >
                    <td className="px-4 py-3 text-zinc-600">{row.label}</td>
                    <td className="px-4 py-3 text-foreground">
                      {metrics[row.key]}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section className="space-y-4">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Fulfillment
          </h2>
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Type</th>
                  <th className="px-4 py-3 font-medium">Orders</th>
                </tr>
              </thead>
              <tbody>
                {FULFILLMENT_ROWS.map((row) => (
                  <tr
                    key={row.key}
                    className="border-b border-border last:border-b-0"
                  >
                    <td className="px-4 py-3 text-zinc-600">{row.label}</td>
                    <td className="px-4 py-3 text-foreground">
                      {metrics[row.key]}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  )
}
