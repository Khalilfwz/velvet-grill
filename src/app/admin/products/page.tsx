import { requireAdminPage } from '@/lib/admin/guard'
import ProductForm from '@/components/admin/ProductForm'
import ReturnLink from '@/components/navigation/ReturnLink'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import StatusBadge from '@/components/admin/StatusBadge'
import { Star } from 'lucide-react'
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
        <AdminPageHeading
          title="Products"
          description="Create products and manage details, images, and options."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load products.
        </p>
      </div>
    )
  }

  const categories = categoriesResult.data ?? []
  const products = productsResult.data ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Products"
        description="Create products and manage details, images, and options."
      />

      {categories.length === 0 ? (
        <EmptyState message="Create a category before adding products." />
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
          <EmptyState message="No products yet." />
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <div
              role="region"
              aria-label="Products"
              tabIndex={0}
              className="overflow-x-auto focus-visible:outline-2 -outline-offset-2 focus-visible:outline-brand"
            >
              <table className="w-full min-w-[640px] text-left text-sm">
                <caption className="sr-only">
                  Product catalog with stock, availability, and edit links.
                </caption>
                <thead className="border-b border-border text-zinc-600">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-medium">Name</th>
                    <th scope="col" className="px-4 py-3 font-medium">Category</th>
                    <th scope="col" className="px-4 py-3 font-medium">Price</th>
                    <th scope="col" className="px-4 py-3 font-medium">Stock</th>
                    <th scope="col" className="px-4 py-3 font-medium">Status</th>
                    <th scope="col" className="px-4 py-3">
                      <span className="sr-only">Actions</span>
                    </th>
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
                        {product.is_featured && (
                          <>
                            {' '}
                            <Star
                              size={14}
                              aria-hidden="true"
                              className="inline fill-current text-brand"
                            />
                            <span className="sr-only">Featured</span>
                          </>
                        )}
                        <span className="ml-2 text-zinc-500">
                          /{product.slug}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        {product.categories?.name ?? '—'}
                        {product.categories &&
                          !product.categories.is_active && (
                            <span className="text-zinc-500"> (inactive)</span>
                          )}
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        {formatIDR(product.base_price)}
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-zinc-600">{product.stock}</span>
                        {product.stock === 0 && (
                          <span className="ml-2">
                            <StatusBadge tone="muted" label="Sold out" />
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <StatusBadge
                          label={product.is_available ? 'Available' : 'Hidden'}
                          tone={product.is_available ? 'neutral' : 'muted'}
                        />
                      </td>
                      <td className="px-4 py-3 text-right">
                        <ReturnLink
                          origin="admin-products"
                          href={`/admin/products/${product.id}`}
                          className="font-medium text-brand hover:text-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
                        >
                          Edit
                        </ReturnLink>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}
