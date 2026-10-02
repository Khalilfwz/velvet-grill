import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import ProductForm from '@/components/admin/ProductForm'
import { formatIDR } from '@/lib/format-currency'

export const metadata = {
  title: 'Products',
}

export default async function AdminProductsPage() {
  const { supabase } = await requireAdminPage()

  const [categoriesResult, productsResult] = await Promise.all([
    supabase
      .from('categories')
      .select('id, name, sort_order')
      .order('sort_order')
      .order('name'),
    supabase
      .from('products')
      .select(
        'id, name, slug, base_price, stock, is_available, is_featured, category_id, categories(name, is_active)'
      )
      .order('name'),
  ])

  if (categoriesResult.error || productsResult.error) {
    console.error(
      'Failed to load admin products:',
      categoriesResult.error ?? productsResult.error
    )

    return (
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Products
        </h1>
        <p className="mt-4 text-red-600">Failed to load products.</p>
      </div>
    )
  }

  const categories = categoriesResult.data ?? []
  const products = productsResult.data ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Products
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Create products and manage details, images, and options.
        </p>
      </div>

      {categories.length === 0 ? (
        <p className="rounded-xl border border-border bg-surface p-6 text-sm text-zinc-600">
          Create a category before adding products.
        </p>
      ) : (
        <section className="rounded-xl border border-border bg-surface p-6">
          <h2 className="font-display text-xl font-semibold text-brand">
            New product
          </h2>

          <div className="mt-4 max-w-xl">
            <ProductForm categories={categories} />
          </div>
        </section>
      )}

      <section className="space-y-4">
        <h2 className="font-display text-xl font-semibold text-brand">
          All products
        </h2>

        {products.length === 0 ? (
          <p className="text-sm text-zinc-600">No products yet.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Name</th>
                  <th className="px-4 py-3 font-medium">Category</th>
                  <th className="px-4 py-3 font-medium">Price</th>
                  <th className="px-4 py-3 font-medium">Stock</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {products.map((product) => (
                  <tr
                    key={product.id}
                    className="border-b border-border last:border-b-0"
                  >
                    <td className="px-4 py-3">
                      <span className="font-medium text-foreground">
                        {product.name}
                      </span>
                      <span className="ml-2 text-zinc-500">
                        /{product.slug}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {product.categories?.name ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {formatIDR(product.base_price)}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">{product.stock}</td>
                    <td className="px-4 py-3">
                      {product.is_available ? (
                        <span className="text-emerald-700">Available</span>
                      ) : (
                        <span className="text-zinc-500">Hidden</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        href={`/admin/products/${product.id}`}
                        className="font-medium text-brand hover:text-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
                      >
                        Edit
                      </Link>
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
