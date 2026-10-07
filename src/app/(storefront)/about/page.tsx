import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import PageHeader from '@/components/layout/PageHeader'
import {
  getProductImageUrl,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const DAY_LABELS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
]

function formatHoursRange(
  opensAt: string | null,
  closesAt: string | null
): string {
  if (!opensAt || !closesAt) {
    return 'Closed'
  }

  return `${opensAt.slice(0, 5)} – ${closesAt.slice(0, 5)}`
}

export const metadata = {
  title: 'About',
}

export default async function AboutPage() {
  const supabase = await createClient()

  const [settingsResult, hoursResult, productsResult] = await Promise.all([
    supabase
      .from('restaurant_settings')
      .select('restaurant_name, address, phone')
      .eq('id', 1)
      .maybeSingle(),
    supabase
      .from('business_hours')
      .select('day_of_week, opens_at, closes_at, is_closed')
      .order('day_of_week'),
    supabase
      .from('products')
      .select(
        'name, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at)'
      )
      .eq('is_available', true)
      .order('name')
      .order('id'),
  ])

  const settings = settingsResult.data ?? null
  const hours = hoursResult.data ?? []
  const hoursByDay = new Map(hours.map((row) => [row.day_of_week, row]))
  const hasContact = Boolean(settings?.address || settings?.phone)

  // Single editorial anchor image. The product list carries an explicit
  // (name, id) ordering, so the first available product with a primary image is
  // a deterministic, read-only choice — never the incidental return order.
  let anchorImageUrl: string | null = null

  for (const product of productsResult.data ?? []) {
    const image = selectPrimaryImage(product.product_images)

    if (image) {
      anchorImageUrl = getProductImageUrl(supabase, image.storage_path)
      break
    }
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <section
          className={
            anchorImageUrl ? 'grid gap-10 lg:grid-cols-12 lg:items-center' : ''
          }
        >
          <div className={anchorImageUrl ? 'lg:col-span-6' : ''}>
            <PageHeader
              title="About"
              description="Velvet Grill is a single-brand restaurant serving steak, burgers, drinks, and desserts for pickup and dine-in."
            />
          </div>

          {anchorImageUrl && (
            <div className="lg:col-span-6">
              <ProductImage
                src={anchorImageUrl}
                alt="A dish from the Velvet Grill menu"
                sizes="(max-width: 1024px) 100vw, 520px"
                className="aspect-[4/3] w-full rounded-2xl"
              />
            </div>
          )}
        </section>

        <section className="mt-16">
          <h2 className="font-display text-2xl font-medium tracking-tight text-foreground">
            What to expect
          </h2>

          <p className="mt-4 max-w-2xl text-base leading-7 text-zinc-600">
            A menu built around steak and main courses, with casual burgers and
            bites alongside. Drinks and desserts cover the rest of the table,
            and everything is available for dine-in or pickup.
          </p>

          <Link
            href="/menu"
            className={`mt-8 inline-flex items-center rounded-full bg-brand px-6 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
          >
            Browse the menu
          </Link>
        </section>

        {(hasContact || hours.length > 0) && (
          <section className="mt-16 grid gap-10 border-t border-border pt-10 sm:grid-cols-2">
            {hasContact && (
              <div>
                <h2 className="font-display text-xl font-medium tracking-tight text-foreground">
                  Visit us
                </h2>

                <div className="mt-4 space-y-4 text-sm text-zinc-600">
                  {settings?.address && (
                    <div>
                      <h3 className="font-medium text-foreground">Address</h3>
                      <p className="mt-1">{settings.address}</p>
                    </div>
                  )}

                  {settings?.phone && (
                    <div>
                      <h3 className="font-medium text-foreground">Phone</h3>
                      <p className="mt-1">{settings.phone}</p>
                    </div>
                  )}
                </div>
              </div>
            )}

            {hours.length > 0 && (
              <div
                className={
                  hasContact ? 'sm:border-l sm:border-border sm:pl-10' : ''
                }
              >
                <h2 className="font-display text-xl font-medium tracking-tight text-foreground">
                  Opening hours
                </h2>

                <ul className="mt-4 space-y-1 text-sm text-zinc-600">
                  {DAY_LABELS.map((label, dayOfWeek) => {
                    const row = hoursByDay.get(dayOfWeek)
                    const value = row
                      ? row.is_closed
                        ? 'Closed'
                        : formatHoursRange(row.opens_at, row.closes_at)
                      : '—'

                    return (
                      <li key={label} className="flex justify-between gap-4">
                        <span>{label}</span>
                        <span className="text-foreground tabular-nums">
                          {value}
                        </span>
                      </li>
                    )
                  })}
                </ul>
              </div>
            )}
          </section>
        )}
      </div>
    </main>
  )
}
