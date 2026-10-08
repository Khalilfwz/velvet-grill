import Link from 'next/link'
import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import ReturnLink from '@/components/navigation/ReturnLink'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'
import {
  getProductImageUrl,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'
import { formatIDR } from '@/lib/format-currency'

export const metadata: Metadata = {
  title: 'Menu',
  description:
    'Browse the Velvet Grill menu — steak, burgers, drinks, and desserts, with options for pickup and dine-in orders.',
}

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default async function MenuPage() {
  const supabase = await createClient()

  const [categoriesResult, productsResult] = await Promise.all([
    supabase
      .from('categories')
      .select('id, name, slug, description, sort_order')
      .eq('is_active', true)
      .order('sort_order')
      .order('name'),
    supabase
      .from('products')
      .select(
        'id, name, description, base_price, category_id, slug, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at)'
      )
      .eq('is_available', true)
      .order('name'),
  ])

  const { data: categories, error: categoriesError } = categoriesResult
  const { data: products, error: productsError } = productsResult

  if (categoriesError || productsError) {
    console.error('Failed to fetch menu:', categoriesError ?? productsError)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <PageHeader title="Our Menu" />

          <ErrorState message="Failed to load menu." />
        </div>
      </main>
    )
  }

  const activeCategories = categories ?? []
  const availableProducts = products ?? []

  const productsByCategory = new Map<
    string,
    (typeof availableProducts)[number][]
  >()

  for (const product of availableProducts) {
    const existing = productsByCategory.get(product.category_id)

    if (existing) {
      existing.push(product)
    } else {
      productsByCategory.set(product.category_id, [product])
    }
  }

  const categoryGroups = activeCategories
    .map((category) => ({
      category,
      products: productsByCategory.get(category.id) ?? [],
    }))
    .filter((group) => group.products.length > 0)

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <PageHeader
          title="Our Menu"
          description="Explore our selection of steak, burgers, drinks, and desserts."
        />

        {categoryGroups.length > 0 && (
          <nav
            aria-label="Menu categories"
            className="sticky top-0 z-20 mt-8 overflow-x-auto border-b border-border bg-background/95 py-3 backdrop-blur"
          >
            <div className="flex gap-x-6 whitespace-nowrap">
              {categoryGroups.map((group) => (
                <Link
                  key={group.category.id}
                  href={`#category-${group.category.slug}`}
                  className={`text-xs font-semibold uppercase tracking-[0.2em] text-zinc-600 transition-colors hover:text-brand ${focusClasses}`}
                >
                  {group.category.name}
                </Link>
              ))}
            </div>
          </nav>
        )}

        {categoryGroups.length === 0 ? (
          <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              Our menu is being prepared
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              New dishes will appear here soon. Please check back shortly.
            </p>
          </div>
        ) : (
          <div className="mt-16 space-y-20">
            {categoryGroups.map((group) => (
              <section
                key={group.category.id}
                id={`category-${group.category.slug}`}
                className="scroll-mt-24"
              >
                <div className="mb-8">
                  <h2 className="font-display text-3xl font-medium leading-tight tracking-tight text-foreground">
                    {group.category.name}
                  </h2>

                  {group.category.description && (
                    <p className="mt-2 max-w-2xl text-sm leading-6 text-zinc-600">
                      {group.category.description}
                    </p>
                  )}
                </div>

                <div className="grid gap-x-8 gap-y-12 sm:grid-cols-2 lg:grid-cols-3">
                  {group.products.map((product) => {
                    const primaryImage = selectPrimaryImage(
                      product.product_images
                    )

                    return (
                      <article key={product.id}>
                        <ReturnLink
                          origin="menu"
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
                        </ReturnLink>
                      </article>
                    )
                  })}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </main>
  )
}
