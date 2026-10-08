import { notFound } from 'next/navigation'
import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import ProductOptions from '@/components/catalog/ProductOptions'
import BackLink from '@/components/navigation/BackLink'
import AddToCartForm from '@/components/cart/AddToCartForm'
import WishlistButton from '@/components/wishlist/WishlistButton'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'
import {
  getProductImageUrl,
  orderProductImages,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'
import { buildProductOptionGroups } from '@/lib/catalog/product-options'
import { formatIDR } from '@/lib/format-currency'

function formatReviewDate(value: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(value))
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>
}): Promise<Metadata> {
  const { slug } = await params
  const supabase = await createClient()

  const { data: product } = await supabase
    .from('products')
    .select('name, description')
    .eq('slug', slug)
    .eq('is_available', true)
    .maybeSingle()

  if (!product) {
    return {}
  }

  return {
    title: product.name,
    description: product.description?.slice(0, 160),
  }
}

export default async function ProductPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { slug } = await params
  const { from } = await searchParams
  const supabase = await createClient()

  const { data: product, error } = await supabase
    .from('products')
    .select(
      'id, name, description, base_price, categories(is_active, name), product_images(id, storage_path, alt_text, is_primary, sort_order, created_at), product_option_groups(id, name, selection_type, min_selections, max_selections, is_required, sort_order, is_active, product_options(id, group_id, name, price_delta, is_available, sort_order))'
    )
    .eq('slug', slug)
    .eq('is_available', true)
    .maybeSingle()

  if (error) {
    console.error('Failed to fetch product:', error)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-4xl">
          <PageHeader title="Product" eyebrow="Menu" />

          <ErrorState message="Failed to load product." />
        </div>
      </main>
    )
  }

  if (!product || !product.categories?.is_active) {
    notFound()
  }

  const heroImage = selectPrimaryImage(product.product_images)
  const heroImageUrl = heroImage
    ? getProductImageUrl(supabase, heroImage.storage_path)
    : null
  const extraImages = orderProductImages(product.product_images).filter(
    (image) => image.id !== heroImage?.id
  )

  const optionGroups = buildProductOptionGroups(
    product.product_option_groups ?? [],
    (product.product_option_groups ?? []).flatMap(
      (group) => group.product_options ?? []
    )
  )

  // Published reviews only. The explicit status filter keeps HIDDEN reviews out
  // of the storefront for every viewer, including an admin browsing the menu.
  const { data: reviewRows } = await supabase
    .from('reviews')
    .select('id, rating, title, content, created_at')
    .eq('product_id', product.id)
    .eq('status', 'PUBLISHED')
    .order('created_at', { ascending: false })

  const reviews = reviewRows ?? []
  const reviewCount = reviews.length
  const averageRating =
    reviewCount > 0
      ? reviews.reduce((sum, review) => sum + review.rating, 0) / reviewCount
      : 0

  const { data: claimsData } = await supabase.auth.getClaims()
  const isAuthenticated = Boolean(claimsData?.claims)

  let initialSaved = false

  if (isAuthenticated) {
    const { data: savedItem } = await supabase
      .from('wishlist_items')
      .select('id')
      .eq('product_id', product.id)
      .maybeSingle()

    initialSaved = Boolean(savedItem)
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-6xl">
        <BackLink
          route="menu-product"
          from={from}
          className="inline-flex items-center rounded-full border border-brand px-5 py-2 text-sm font-medium text-brand transition-colors hover:bg-brand/5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        />

        <div className="mt-6 grid gap-10 lg:grid-cols-12">
          <div className="lg:col-span-7 lg:sticky lg:top-8 lg:self-start">
            <ProductImage
              src={heroImageUrl}
              alt={heroImage?.alt_text ?? product.name}
              sizes="(max-width: 1024px) 100vw, 640px"
              preload
              className="aspect-[4/3] w-full rounded-2xl"
            />

            {extraImages.length > 0 && (
              <div className="mt-4 grid grid-cols-3 gap-3">
                {extraImages.map((image) => (
                  <ProductImage
                    key={image.id}
                    src={getProductImageUrl(supabase, image.storage_path)}
                    alt={image.alt_text ?? product.name}
                    sizes="(max-width: 640px) 33vw, 160px"
                    className="aspect-square rounded-lg"
                  />
                ))}
              </div>
            )}
          </div>

          <div className="lg:col-span-5">
            {product.categories?.name && (
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-brand">
                {product.categories.name}
              </p>
            )}

            <h1 className="mt-3 font-display text-4xl font-medium leading-tight tracking-tight text-foreground sm:text-5xl">
              {product.name}
            </h1>

            {product.description && (
              <p className="mt-4 leading-7 text-zinc-600">
                {product.description}
              </p>
            )}

            <div className="mt-6">
              <WishlistButton
                productId={product.id}
                initialSaved={initialSaved}
                isAuthenticated={isAuthenticated}
              />
            </div>

            {optionGroups.length === 0 ? (
              <div className="mt-8 rounded-xl border border-border bg-surface p-6">
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-600">
                  Price
                </p>

                <p className="mt-2 font-display text-3xl font-medium text-brand tabular-nums">
                  {formatIDR(product.base_price)}
                </p>

                <div className="mt-6">
                  <AddToCartForm
                    productId={product.id}
                    optionIds={[]}
                    complete
                    isAuthenticated={isAuthenticated}
                  />
                </div>
              </div>
            ) : (
              <div className="mt-8">
                <p className="text-sm text-zinc-600">
                  Base price:{' '}
                  <span className="text-base font-medium text-brand tabular-nums">
                    {formatIDR(product.base_price)}
                  </span>
                </p>

                <ProductOptions
                  basePrice={product.base_price}
                  groups={optionGroups}
                  productId={product.id}
                  isAuthenticated={isAuthenticated}
                />
              </div>
            )}
          </div>
        </div>

        <section className="mt-12 border-t border-border pt-8">
          <h2 className="font-display text-2xl font-semibold text-foreground">
            Reviews
          </h2>

          {reviewCount === 0 ? (
            <p className="mt-4 text-sm text-zinc-600">No reviews yet.</p>
          ) : (
            <>
              <p className="mt-2 text-sm text-zinc-600">
                {averageRating.toFixed(1)} out of 5 · {reviewCount}{' '}
                {reviewCount === 1 ? 'review' : 'reviews'}
              </p>

              <ul className="mt-6 space-y-4">
                {reviews.map((review) => (
                  <li
                    key={review.id}
                    className="rounded-xl border border-border bg-surface p-6 shadow-sm"
                  >
                    <p className="font-medium text-brand" aria-hidden="true">
                      {'★'.repeat(review.rating)}
                      {'☆'.repeat(5 - review.rating)}
                    </p>
                    <span className="sr-only">
                      {`${review.rating} out of 5`}
                    </span>

                    {review.title && (
                      <p className="mt-2 font-display text-lg font-semibold text-foreground">
                        {review.title}
                      </p>
                    )}

                    {review.content && (
                      <p className="mt-2 text-sm leading-6 text-zinc-600">
                        {review.content}
                      </p>
                    )}

                    <p className="mt-3 text-xs text-zinc-600">
                      {formatReviewDate(review.created_at)}
                    </p>
                  </li>
                ))}
              </ul>
            </>
          )}
        </section>
      </div>
    </main>
  )
}
