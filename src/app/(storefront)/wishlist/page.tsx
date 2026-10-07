import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import ReturnLink from '@/components/navigation/ReturnLink'
import WishlistButton from '@/components/wishlist/WishlistButton'
import {
  getProductImageUrl,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default async function WishlistPage() {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()

  if (!claimsData?.claims) {
    redirect('/login')
  }

  // No `products!inner`: the product embed is left-joined, so a wishlist row
  // whose related product is hidden by product RLS stays visible and removable.
  const { data: items, error } = await supabase
    .from('wishlist_items')
    .select(
      'id, product_id, created_at, products(id, name, slug, base_price, is_available, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at))'
    )
    .order('created_at', { ascending: false })

  if (error) {
    // Log only safe, minimal context; never the full provider object.
    console.error('Failed to fetch wishlist:', error.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <h1 className="font-display text-4xl font-bold text-foreground">
            Your Wishlist
          </h1>

          <p className="mt-4 text-red-600">Failed to load your wishlist.</p>
        </div>
      </main>
    )
  }

  const wishlistItems = items ?? []

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-4xl font-bold text-foreground">
          Your Wishlist
        </h1>

        <p className="mt-4 max-w-2xl text-zinc-600">
          Products you have saved for later.
        </p>

        {wishlistItems.length === 0 ? (
          <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              Your wishlist is empty
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              Browse the menu and save the dishes you want to come back to.
            </p>

            <Link
              href="/menu"
              className={`mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
            >
              Browse the menu
            </Link>
          </div>
        ) : (
          <ul className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {wishlistItems.map((item) => {
              const product = item.products
              const primaryImage = product
                ? selectPrimaryImage(product.product_images)
                : null

              return (
                <li
                  key={item.id}
                  className="flex h-full flex-col overflow-hidden rounded-xl border border-border bg-surface shadow-sm"
                >
                  {product ? (
                    <ReturnLink
                      origin="wishlist"
                      href={`/menu/${product.slug}`}
                      className={`block ${focusClasses}`}
                    >
                      <ProductImage
                        src={
                          primaryImage
                            ? getProductImageUrl(supabase, primaryImage.storage_path)
                            : null
                        }
                        alt=""
                        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
                        className="aspect-[4/3] w-full"
                      />

                      <div className="p-6 pb-0">
                        <h2 className="font-display text-xl font-semibold text-foreground">
                          {product.name}
                        </h2>

                        <p className="mt-4 font-medium text-brand">
                          {formatIDR(product.base_price)}
                        </p>
                      </div>
                    </ReturnLink>
                  ) : (
                    <div className="p-6 pb-0">
                      <h2 className="font-display text-xl font-semibold text-foreground">
                        Unavailable product
                      </h2>

                      <p className="mt-2 text-sm text-zinc-600">
                        This item is no longer available. You can remove it from
                        your wishlist.
                      </p>
                    </div>
                  )}

                  <div className="mt-auto p-6">
                    <WishlistButton
                      productId={item.product_id}
                      initialSaved
                      isAuthenticated
                    />
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </main>
  )
}
