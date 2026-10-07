import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import ErrorState from '@/components/layout/ErrorState'
import {
  getProductImageUrl,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const ghostLinkClasses = `inline-flex items-center text-sm font-medium text-foreground transition-colors hover:text-brand ${focusClasses}`

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

export default async function Home() {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  const isAuthenticated = Boolean(claimsData?.claims)
  const userId =
    typeof claimsData?.claims?.sub === 'string' ? claimsData.claims.sub : null

  // Same profile-derived role source as the Navbar: the role comes from the
  // caller's own profile row, the same source the /admin guard reads. Admins
  // keep full backend order access; the hero only skips customer commerce
  // navigation.
  let isAdmin = false

  if (userId) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('role, is_active')
      .eq('id', userId)
      .maybeSingle()

    isAdmin = profile?.role === 'ADMIN' && profile.is_active === true
  }

  const [categoriesResult, productsResult, settingsResult, hoursResult] =
    await Promise.all([
      supabase
        .from('categories')
        .select('id, name, slug, description')
        .eq('is_active', true)
        .order('sort_order')
        .order('name'),
      supabase
        .from('products')
        .select(
          'id, name, slug, description, base_price, category_id, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at)'
        )
        .eq('is_available', true)
        .order('name')
        .order('id'),
      supabase
        .from('restaurant_settings')
        .select('restaurant_name, address, phone')
        .eq('id', 1)
        .maybeSingle(),
      supabase
        .from('business_hours')
        .select('day_of_week, opens_at, closes_at, is_closed')
        .order('day_of_week'),
    ])

  const { error: categoriesError } = categoriesResult
  const { error: productsError } = productsResult

  if (categoriesError || productsError) {
    console.error(
      'Failed to load storefront homepage:',
      categoriesError ?? productsError
    )

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <ErrorState message="The menu could not be loaded right now. Please try again shortly." />
        </div>
      </main>
    )
  }

  const activeCategories = categoriesResult.data ?? []
  const availableProducts = productsResult.data ?? []
  const settings = settingsResult.data ?? null
  const hours = hoursResult.data ?? []

  // Deterministic "Menu highlights": one available product per active category,
  // in category sort order, capped at six; fall back to the first six available
  // products when no category has an available product. Products carry an
  // explicit (name, id) ordering, so the result is stable across renders.
  const productsByCategory = new Map<string, typeof availableProducts>()

  for (const product of availableProducts) {
    const existing = productsByCategory.get(product.category_id)

    if (existing) {
      existing.push(product)
    } else {
      productsByCategory.set(product.category_id, [product])
    }
  }

  const perCategoryHighlights = activeCategories
    .map((category) => productsByCategory.get(category.id)?.[0])
    .filter((product): product is (typeof availableProducts)[number] =>
      Boolean(product)
    )

  const highlights = (
    perCategoryHighlights.length > 0
      ? perCategoryHighlights
      : availableProducts
  ).slice(0, 6)

  // Category tiles are image-led. The source product list carries an explicit
  // (name, id) ordering, so the first product with a primary image is a stable,
  // deterministic choice — never the incidental database return order.
  const categoryImageUrls = new Map<string, string>()

  for (const category of activeCategories) {
    const products = productsByCategory.get(category.id) ?? []

    for (const product of products) {
      const image = selectPrimaryImage(product.product_images)

      if (image) {
        categoryImageUrls.set(
          category.id,
          getProductImageUrl(supabase, image.storage_path)
        )
        break
      }
    }
  }

  // Hero imagery degrades gracefully: if no highlighted product has an image,
  // the hero renders as a single column with no image element.
  let heroProduct: (typeof highlights)[number] | null = null
  let heroImage: ReturnType<typeof selectPrimaryImage> = null

  for (const product of highlights) {
    const image = selectPrimaryImage(product.product_images)

    if (image) {
      heroProduct = product
      heroImage = image
      break
    }
  }

  const heroImageUrl = heroImage
    ? getProductImageUrl(supabase, heroImage.storage_path)
    : null

  const hoursByDay = new Map(hours.map((row) => [row.day_of_week, row]))
  const hasVisitInfo = Boolean(
    settings?.address || settings?.phone || hours.length > 0
  )
  const isEmptyCatalog =
    activeCategories.length === 0 && availableProducts.length === 0

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <section
          className={
            heroImageUrl ? 'grid gap-10 lg:grid-cols-12 lg:items-center' : ''
          }
        >
          <div className={heroImageUrl ? 'lg:col-span-5' : ''}>
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-brand">
              Velvet Grill
            </p>

            <h1 className="mt-4 font-display text-5xl font-medium leading-[1.05] tracking-tight text-balance text-foreground sm:text-6xl lg:text-7xl">
              A table worth slowing down for.
            </h1>

            <p className="mt-6 max-w-xl text-lg leading-8 text-zinc-600">
              Steak, burgers, drinks, and desserts — crafted for pickup or
              dine-in.
            </p>

            <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
              <Link
                href="/menu"
                className={`inline-flex items-center rounded-full bg-brand px-6 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
              >
                Browse the menu
              </Link>

              {!isAuthenticated && (
                <Link href="/login" className={ghostLinkClasses}>
                  Sign in
                </Link>
              )}

              {isAuthenticated && !isAdmin && (
                <Link href="/orders" className={ghostLinkClasses}>
                  View my orders
                </Link>
              )}
            </div>
          </div>

          {heroImageUrl && (
            <div className="lg:col-span-7">
              <div className="relative overflow-hidden rounded-2xl">
                <ProductImage
                  src={heroImageUrl}
                  alt={
                    heroImage?.alt_text ?? heroProduct?.name ?? 'Velvet Grill'
                  }
                  sizes="(max-width: 1024px) 100vw, 640px"
                  preload
                  className="aspect-[4/3] w-full lg:aspect-[6/5]"
                />

                {heroProduct && (
                  <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 via-black/15 to-transparent px-5 pb-5 pt-14">
                    <p className="font-display text-xl font-medium tracking-tight text-white sm:text-2xl">
                      {heroProduct.name}
                    </p>
                  </div>
                )}
              </div>
            </div>
          )}
        </section>

        {activeCategories.length > 0 && (
          <section className="mt-20">
            <h2 className="font-display text-3xl font-medium leading-tight tracking-tight text-balance text-foreground">
              Explore the menu
            </h2>

            <ul className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
              {activeCategories.map((category) => {
                const imageUrl = categoryImageUrls.get(category.id) ?? null

                return (
                  <li key={category.id}>
                    <Link
                      href={`/menu#category-${category.slug}`}
                      aria-label={`Browse ${category.name}`}
                      className={`group relative block overflow-hidden rounded-xl ${focusClasses}`}
                    >
                      <ProductImage
                        src={imageUrl}
                        alt=""
                        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 25vw"
                        className="aspect-[4/5] w-full"
                      />

                      <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent p-5">
                        <h3 className="font-display text-xl font-medium tracking-tight text-white">
                          {category.name}
                        </h3>

                        <p className="mt-1 text-xs font-medium uppercase tracking-wide text-white/80">
                          View dishes
                        </p>
                      </div>
                    </Link>
                  </li>
                )
              })}
            </ul>
          </section>
        )}

        {highlights.length > 0 && (
          <section className="mt-20">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="font-display text-3xl font-medium leading-tight tracking-tight text-foreground">
                Menu highlights
              </h2>

              <Link href="/menu" className={ghostLinkClasses}>
                See the full menu
              </Link>
            </div>

            <ul className="mt-8 grid gap-x-8 gap-y-12 sm:grid-cols-2 lg:grid-cols-3">
              {highlights.map((product) => {
                const primaryImage = selectPrimaryImage(product.product_images)

                return (
                  <li key={product.id}>
                    <Link
                      href={`/menu/${product.slug}`}
                      className={`group block ${focusClasses}`}
                    >
                      <ProductImage
                        src={
                          primaryImage
                            ? getProductImageUrl(
                                supabase,
                                primaryImage.storage_path
                              )
                            : null
                        }
                        alt=""
                        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
                        className="aspect-[4/3] w-full rounded-lg"
                      />

                      <h3 className="mt-4 font-display text-xl font-medium leading-snug tracking-tight text-foreground transition-colors group-hover:text-brand">
                        {product.name}
                      </h3>

                      {product.description && (
                        <p className="mt-2 text-sm leading-6 text-zinc-600">
                          {product.description}
                        </p>
                      )}

                      <p className="mt-3 font-medium text-brand tabular-nums">
                        {formatIDR(product.base_price)}
                      </p>
                    </Link>
                  </li>
                )
              })}
            </ul>
          </section>
        )}

        {isEmptyCatalog && (
          <section className="mt-16 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              Our menu is being prepared
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              New dishes will appear here soon. Please check back shortly.
            </p>
          </section>
        )}

        {hasVisitInfo && (
          <section className="mt-20 rounded-2xl bg-brand px-8 py-12 text-background sm:px-12">
            <h2 className="font-display text-3xl font-medium leading-tight tracking-tight text-white">
              Visit us
            </h2>

            <div className="mt-8 grid gap-10 sm:grid-cols-2">
              <div className="space-y-6 text-sm text-background/80">
                {settings?.address && (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/70">
                      Address
                    </h3>
                    <p className="mt-2">{settings.address}</p>
                  </div>
                )}

                {settings?.phone && (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/70">
                      Phone
                    </h3>
                    <p className="mt-2">{settings.phone}</p>
                  </div>
                )}
              </div>

              {hours.length > 0 && (
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-white/70">
                    Opening hours
                  </h3>

                  <ul className="mt-2 divide-y divide-white/10 text-sm">
                    {DAY_LABELS.map((label, dayOfWeek) => {
                      const row = hoursByDay.get(dayOfWeek)
                      const value = row
                        ? row.is_closed
                          ? 'Closed'
                          : formatHoursRange(row.opens_at, row.closes_at)
                        : '—'

                      return (
                        <li
                          key={label}
                          className="flex justify-between gap-4 py-2"
                        >
                          <span className="text-background/70">{label}</span>
                          <span className="text-background tabular-nums">
                            {value}
                          </span>
                        </li>
                      )
                    })}
                  </ul>
                </div>
              )}
            </div>
          </section>
        )}
      </div>
    </main>
  )
}
