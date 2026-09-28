import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function ProductPage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const supabase = await createClient()

  const { data: product, error } = await supabase
    .from('products')
    .select('id, name, description, base_price, categories(is_active)')
    .eq('slug', slug)
    .eq('is_available', true)
    .maybeSingle()

  if (error) {
    console.error('Failed to fetch product:', error)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <p className="text-red-600">Failed to load product.</p>
        </div>
      </main>
    )
  }

  if (!product || !product.categories?.is_active) {
    notFound()
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <Link
          href="/menu"
          className="text-sm font-medium text-brand transition-colors hover:text-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Back to menu
        </Link>

        <h1 className="mt-6 font-display text-4xl font-bold text-foreground">
          {product.name}
        </h1>

        {product.description && (
          <p className="mt-4 max-w-2xl leading-7 text-zinc-600">
            {product.description}
          </p>
        )}

        <p className="mt-6 text-2xl font-medium text-brand">
          {new Intl.NumberFormat('id-ID', {
            style: 'currency',
            currency: 'IDR',
            maximumFractionDigits: 0,
          }).format(product.base_price)}
        </p>
      </div>
    </main>
  )
}
