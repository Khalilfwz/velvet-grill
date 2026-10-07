import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import CheckoutForm from '@/components/checkout/CheckoutForm'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'
import { loadCartSummary } from '@/lib/cart/summary'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default async function CheckoutPage({
  searchParams,
}: {
  searchParams: Promise<{ table_id?: string }>
}) {
  const { table_id } = await searchParams
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()

  if (!claimsData?.claims) {
    redirect('/login')
  }

  const summary = await loadCartSummary(supabase)

  if (!summary.ok) {
    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <PageHeader title="Checkout" />

          <ErrorState message="Failed to load your cart." />
        </div>
      </main>
    )
  }

  if (summary.lines.length === 0) {
    redirect('/cart')
  }

  const [tablesResult, profileResult] = await Promise.all([
    supabase
      .from('restaurant_tables')
      .select('id, table_number')
      .eq('is_active', true)
      .order('table_number'),
    supabase.from('profiles').select('full_name, phone').maybeSingle(),
  ])

  const tables = (tablesResult.data ?? []).map((table) => ({
    id: table.id,
    tableNumber: table.table_number,
  }))

  // The browser-supplied table id is only an identifier: it is accepted as a
  // preselection when it matches a currently active table, and is revalidated
  // again inside create_order before anything is stored.
  const initialTableId =
    typeof table_id === 'string' &&
    UUID_PATTERN.test(table_id) &&
    tables.some((table) => table.id === table_id)
      ? table_id
      : null

  const profile = profileResult.data
  const idempotencyKey = crypto.randomUUID()

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <Link
          href="/cart"
          className={`text-sm font-medium text-brand transition-colors hover:text-brand-light ${focusClasses}`}
        >
          Back to cart
        </Link>

        <div className="mt-6">
          <PageHeader title="Checkout" />
        </div>

        <section className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <h2 className="font-display text-xl font-semibold text-foreground">
            Order summary
          </h2>

          <ul className="mt-4 space-y-3">
            {summary.lines.map((line) => (
              <li key={line.itemId} className="flex justify-between gap-4 text-sm">
                <span className="text-foreground">
                  {line.productName ?? 'Unavailable product'}
                  <span className="text-zinc-600"> × {line.quantity}</span>
                  {line.options.length > 0 && (
                    <span className="block text-zinc-600">
                      {line.options
                        .map((option) => `${option.groupName}: ${option.name}`)
                        .join(', ')}
                    </span>
                  )}
                </span>

                <span className="shrink-0 text-foreground">
                  {line.lineTotal !== null ? formatIDR(line.lineTotal) : '—'}
                </span>
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-6 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <CheckoutForm
            tables={tables}
            defaultName={profile?.full_name ?? ''}
            defaultPhone={profile?.phone ?? ''}
            initialTableId={initialTableId}
            estimate={summary.hasUnavailableLine ? null : summary.subtotal}
            hasUnavailableLine={summary.hasUnavailableLine}
            idempotencyKey={idempotencyKey}
          />
        </section>
      </div>
    </main>
  )
}
