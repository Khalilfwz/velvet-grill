import { createClient } from '@/lib/supabase/server'

export default async function Home() {
  const supabase = await createClient()

  const { data: products, error } = await supabase
    .from('products')
    .select('id, name, base_price')
    .order('name')

  if (error) {
    console.error('Failed to fetch products:', error)

    return (
      <>

        <main className="flex min-h-screen items-center justify-center bg-background p-8">
          <div className="rounded-lg border border-border bg-surface p-6 shadow-sm">
            <h1 className="text-xl font-semibold text-red-600">
              Failed to load products
            </h1>
            <p className="mt-2 text-sm text-foreground">
              Database query failed. Check the server logs.
            </p>
          </div>
        </main>
      </>
    )
  }

  return (
    <>

      <main className="min-h-screen bg-background p-8">
        <div className="mx-auto max-w-4xl">
          <h1 className="font-display text-3xl font-bold text-brand">
            Velvet Grill
          </h1>

          <p className="mt-2 text-zinc-600">
            Products loaded from Supabase Local.
          </p>

          <div className="mt-8 grid gap-4 sm:grid-cols-2">
            {products.map((product) => (
              <div
                key={product.id}
                className="rounded-xl border border-border bg-surface p-5 shadow-sm"
              >
                <h2 className="text-lg font-semibold text-zinc-900">
                  {product.name}
                </h2>

                <p className="mt-2 text-zinc-600">
                  {new Intl.NumberFormat('id-ID', {
                    style: 'currency',
                    currency: 'IDR',
                    maximumFractionDigits: 0,
                  }).format(product.base_price)}
                </p>
              </div>
            ))}
          </div>
        </div>
      </main>
    </>
  )
}
