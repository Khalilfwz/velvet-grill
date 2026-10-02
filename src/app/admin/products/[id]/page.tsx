import Link from 'next/link'
import { notFound } from 'next/navigation'
import { requireAdminPage } from '@/lib/admin/guard'
import ProductForm from '@/components/admin/ProductForm'
import ProductImageForm from '@/components/admin/ProductImageForm'
import OptionGroupForm from '@/components/admin/OptionGroupForm'
import OptionForm from '@/components/admin/OptionForm'
import { orderProductImages } from '@/lib/catalog/product-images'

export const metadata = {
  title: 'Edit product',
}

export default async function AdminProductDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const { supabase } = await requireAdminPage()

  const [productResult, categoriesResult] = await Promise.all([
    supabase
      .from('products')
      .select(
        'id, name, slug, description, category_id, base_price, stock, is_available, is_featured, product_images(id, storage_path, alt_text, sort_order, is_primary, created_at), product_option_groups(id, name, selection_type, min_selections, max_selections, is_required, sort_order, is_active, product_options(id, group_id, name, price_delta, is_available, sort_order))'
      )
      .eq('id', id)
      .maybeSingle(),
    supabase
      .from('categories')
      .select('id, name, sort_order')
      .order('sort_order')
      .order('name'),
  ])

  const { data: product, error } = productResult

  if (error) {
    console.error('Failed to load admin product:', error)

    return (
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Product
        </h1>
        <p className="mt-4 text-red-600">Failed to load product.</p>
      </div>
    )
  }

  if (!product) {
    notFound()
  }

  const categories = categoriesResult.data ?? []
  const images = orderProductImages(product.product_images ?? [])
  const groups = [...(product.product_option_groups ?? [])].sort((a, b) => {
    if (a.sort_order !== b.sort_order) {
      return a.sort_order - b.sort_order
    }

    return a.name.localeCompare(b.name)
  })

  return (
    <div className="space-y-10">
      <div>
        <Link
          href="/admin/products"
          className="text-sm font-medium text-brand transition-colors hover:text-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Back to products
        </Link>

        <h1 className="mt-4 font-display text-3xl font-bold text-foreground">
          {product.name}
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          /menu/{product.slug}
          {!product.is_available && ' · hidden from the public menu'}
        </p>
      </div>

      <section className="rounded-xl border border-border bg-surface p-6">
        <h2 className="font-display text-xl font-semibold text-brand">
          Details
        </h2>

        <div className="mt-4 max-w-xl">
          <ProductForm
            categories={categories}
            initial={{
              id: product.id,
              name: product.name,
              slug: product.slug,
              description: product.description,
              categoryId: product.category_id,
              basePrice: product.base_price,
              stock: product.stock,
              isAvailable: product.is_available,
              isFeatured: product.is_featured,
            }}
          />
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-xl font-semibold text-brand">
          Images
        </h2>

        <div className="space-y-4">
          {images.map((image) => (
            <div
              key={image.id}
              className="rounded-xl border border-border bg-surface p-4"
            >
              <ProductImageForm
                productId={product.id}
                productSlug={product.slug}
                initial={{
                  id: image.id,
                  storagePath: image.storage_path,
                  altText: image.alt_text,
                  sortOrder: image.sort_order,
                  isPrimary: image.is_primary,
                }}
              />
            </div>
          ))}

          <div className="rounded-xl border border-dashed border-border bg-surface p-4">
            <h3 className="text-sm font-semibold text-foreground">Add image</h3>
            <div className="mt-3 max-w-xl">
              <ProductImageForm
                productId={product.id}
                productSlug={product.slug}
              />
            </div>
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-xl font-semibold text-brand">
          Option groups
        </h2>

        <div className="space-y-4">
          {groups.map((group) => {
            const options = [...(group.product_options ?? [])].sort((a, b) => {
              if (a.sort_order !== b.sort_order) {
                return a.sort_order - b.sort_order
              }

              return a.name.localeCompare(b.name)
            })

            return (
              <div
                key={group.id}
                className="rounded-xl border border-border bg-surface p-4"
              >
                <OptionGroupForm
                  productId={product.id}
                  productSlug={product.slug}
                  initial={{
                    id: group.id,
                    name: group.name,
                    selectionType: group.selection_type,
                    minSelections: group.min_selections,
                    maxSelections: group.max_selections,
                    isRequired: group.is_required,
                    sortOrder: group.sort_order,
                    isActive: group.is_active,
                  }}
                />

                <div className="mt-6 space-y-4 border-t border-border pt-4">
                  <h3 className="text-sm font-semibold text-foreground">
                    Options
                  </h3>

                  {options.map((option) => (
                    <div
                      key={option.id}
                      className="rounded-lg border border-border p-3"
                    >
                      <OptionForm
                        productId={product.id}
                        productSlug={product.slug}
                        groupId={group.id}
                        initial={{
                          id: option.id,
                          name: option.name,
                          priceDelta: option.price_delta,
                          isAvailable: option.is_available,
                          sortOrder: option.sort_order,
                        }}
                      />
                    </div>
                  ))}

                  <div className="rounded-lg border border-dashed border-border p-3">
                    <p className="text-sm font-medium text-foreground">
                      Add option
                    </p>
                    <div className="mt-3">
                      <OptionForm
                        productId={product.id}
                        productSlug={product.slug}
                        groupId={group.id}
                      />
                    </div>
                  </div>
                </div>
              </div>
            )
          })}

          <div className="rounded-xl border border-dashed border-border bg-surface p-4">
            <h3 className="text-sm font-semibold text-foreground">
              Add option group
            </h3>
            <div className="mt-3 max-w-xl">
              <OptionGroupForm
                productId={product.id}
                productSlug={product.slug}
              />
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}
