import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import CartLineControls from '@/components/cart/CartLineControls'
import ReturnLink from '@/components/navigation/ReturnLink'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'
import { getProductImageUrl } from '@/lib/catalog/product-images'
import { loadCartSummary } from '@/lib/cart/summary'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default async function CartPage() {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()

  if (!claimsData?.claims) {
    redirect('/login')
  }

  const summary = await loadCartSummary(supabase)

  if (!summary.ok) {
    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <PageHeader title="Your Cart" />

          <ErrorState message="Failed to load your cart." />
        </div>
      </main>
    )
  }

  const { lines, subtotal, hasUnavailableLine } = summary

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <PageHeader
          title="Your Cart"
          description="Items you are planning to order."
        />

        {lines.length === 0 ? (
          <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              Your cart is empty
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              Browse the menu and add the dishes you would like to order.
            </p>

            <Link
              href="/menu"
              className={`mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
            >
              Browse the menu
            </Link>
          </div>
        ) : (
          <>
            <ul className="mt-12 space-y-6">
              {lines.map((line) => (
                <li
                  key={line.itemId}
                  className="flex flex-col gap-6 rounded-xl border border-border bg-surface p-6 shadow-sm sm:flex-row"
                >
                  <div className="w-full max-w-xs shrink-0">
                    <ProductImage
                      src={
                        line.primaryImagePath
                          ? getProductImageUrl(supabase, line.primaryImagePath)
                          : null
                      }
                      alt=""
                      sizes="(max-width: 640px) 100vw, 320px"
                      className="aspect-[4/3] w-full rounded-lg"
                    />
                  </div>

                  <div className="flex flex-1 flex-col gap-4">
                    {line.productName ? (
                      <div>
                        <h2 className="font-display text-xl font-semibold text-foreground">
                          <ReturnLink
                            origin="cart"
                            href={`/menu/${line.productSlug}`}
                            className={`transition-colors hover:text-brand ${focusClasses}`}
                          >
                            {line.productName}
                          </ReturnLink>
                        </h2>

                        {line.options.length > 0 && (
                          <p className="mt-2 text-sm text-zinc-600">
                            {line.options.every((option) => option.readable)
                              ? line.options
                                  .map(
                                    (option) =>
                                      `${option.groupName}: ${option.name}`
                                  )
                                  .join(', ')
                              : 'Contains an unavailable option'}
                          </p>
                        )}
                      </div>
                    ) : (
                      <div>
                        <h2 className="font-display text-xl font-semibold text-foreground">
                          Unavailable product
                        </h2>

                        <p className="mt-2 text-sm text-zinc-600">
                          This item is no longer available. You can remove it
                          from your cart.
                        </p>
                      </div>
                    )}

                    {line.unitPrice !== null && line.lineTotal !== null ? (
                      <p className="font-medium text-brand">
                        {formatIDR(line.lineTotal)}
                        <span className="ml-2 text-sm font-normal text-zinc-600">
                          ({line.quantity} × {formatIDR(line.unitPrice)})
                        </span>
                      </p>
                    ) : (
                      <p className="text-sm text-zinc-600">Price unavailable</p>
                    )}

                    <CartLineControls
                      cartItemId={line.itemId}
                      quantity={line.quantity}
                    />
                  </div>
                </li>
              ))}
            </ul>

            <div className="mt-8 border-t border-border pt-6">
              {hasUnavailableLine ? (
                <p role="status" className="text-sm text-zinc-600">
                  Subtotal unavailable until unavailable items are removed or
                  updated.
                </p>
              ) : (
                <p className="flex items-baseline justify-between">
                  <span className="text-sm text-zinc-600">Subtotal</span>
                  <span className="font-display text-2xl font-medium text-brand">
                    {formatIDR(subtotal)}
                  </span>
                </p>
              )}

              <p className="mt-2 text-sm text-zinc-600">
                Estimates only. Final pricing is confirmed by the restaurant
                when your order is placed.
              </p>

              {hasUnavailableLine ? (
                <p className="mt-6 inline-block cursor-not-allowed rounded-full border border-border px-5 py-2 text-sm font-medium text-zinc-500">
                  Remove unavailable items before proceeding to checkout.
                </p>
              ) : (
                <Link
                  href="/checkout"
                  className={`mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
                >
                  Proceed to checkout
                </Link>
              )}
            </div>
          </>
        )}
      </div>
    </main>
  )
}
