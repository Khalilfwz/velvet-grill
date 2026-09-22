import { createClient } from '@/lib/supabase/server'

export default async function MenuPage() {
  const supabase = await createClient()

  const { data: products, error } = await supabase
    .from('products')
    .select(`
      id,
      name,
      description,
      base_price,
      category:categories (
        id,
        name,
        slug,
        sort_order
      )
    `)
    .order('name')

  if (error) {
    console.error('Failed to fetch menu:', error)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <h1 className="font-display text-4xl font-bold text-foreground">
            Our Menu
          </h1>

          <p className="mt-4 text-red-600">
            Failed to load menu.
          </p>
        </div>
      </main>
    )
  }

  const groupedProducts = products.reduce<
    Record<
      string,
      {
        category: NonNullable<(typeof products)[number]['category']>
        products: (typeof products)[number][]
      }
    >
  >((groups, product) => {
    if (!product.category) {
      return groups
    }

    const categoryId = product.category.id

    if (!groups[categoryId]) {
      groups[categoryId] = {
        category: product.category,
        products: [],
      }
    }

    groups[categoryId].products.push(product)

    return groups
  }, {})

  const categoryGroups = Object.values(groupedProducts).sort(
    (a, b) => a.category.sort_order - b.category.sort_order
  )

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-4xl font-bold text-foreground">
          Our Menu
        </h1>

        <p className="mt-4 max-w-2xl text-zinc-600">
          Explore our selection of steak, burgers, drinks, and desserts.
        </p>

        <div className="mt-12 space-y-14">
          {categoryGroups.map((group) => (
            <section key={group.category.id}>
              <div className="mb-6">
                <h2 className="font-display text-2xl font-semibold text-brand">
                  {group.category.name}
                </h2>
              </div>

              <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
                {group.products.map((product) => (
                  <article
                    key={product.id}
                    className="rounded-xl border border-border bg-surface p-6 shadow-sm"
                  >
                    <h3 className="font-display text-xl font-semibold text-foreground">
                      {product.name}
                    </h3>

                    {product.description && (
                      <p className="mt-2 text-sm leading-6 text-zinc-600">
                        {product.description}
                      </p>
                    )}

                    <p className="mt-4 font-medium text-brand">
                      {new Intl.NumberFormat('id-ID', {
                        style: 'currency',
                        currency: 'IDR',
                        maximumFractionDigits: 0,
                      }).format(product.base_price)}
                    </p>
                  </article>
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>
    </main>
  )
}
