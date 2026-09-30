import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProductImage from '@/components/catalog/ProductImage'
import CartLineControls from '@/components/cart/CartLineControls'
import {
  getProductImageUrl,
  selectPrimaryImage,
} from '@/lib/catalog/product-images'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

type LineOption = {
  groupName: string
  name: string
  priceDelta: number
  readable: boolean
}

export default async function CartPage() {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()

  if (!claimsData?.claims) {
    redirect('/login')
  }

  const { data: cart, error: cartError } = await supabase
    .from('carts')
    .select(
      'id, cart_items(id, quantity, product_id, products(id, name, slug, base_price, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at)))'
    )
    .maybeSingle()

  if (cartError) {
    console.error('Failed to load cart:', cartError.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-7xl">
          <h1 className="font-display text-4xl font-bold text-foreground">
            Your Cart
          </h1>

          <p className="mt-4 text-red-600">Failed to load your cart.</p>
        </div>
      </main>
    )
  }

  const items = cart?.cart_items ?? []
  const optionRowsByItem = new Map<string, LineOption[]>()

  if (items.length > 0) {
    const { data: optionRows, error: optionsError } = await supabase
      .from('cart_item_options')
      .select(
        'cart_item_id, product_options(id, name, price_delta, product_option_groups(id, name))'
      )
      .in(
        'cart_item_id',
        items.map((item) => item.id)
      )

    if (optionsError) {
      console.error('Failed to load cart options:', optionsError.code)

      return (
        <main className="min-h-screen bg-background px-6 py-12">
          <div className="mx-auto max-w-7xl">
            <h1 className="font-display text-4xl font-bold text-foreground">
              Your Cart
            </h1>

            <p className="mt-4 text-red-600">Failed to load your cart.</p>
          </div>
        </main>
      )
    }

    for (const row of optionRows ?? []) {
      const option = row.product_options
      const group = option?.product_option_groups ?? null

      const list = optionRowsByItem.get(row.cart_item_id) ?? []

      list.push({
        groupName: group?.name ?? '',
        name: option?.name ?? '',
        priceDelta: option?.price_delta ?? 0,
        readable: option !== null && group !== null,
      })

      optionRowsByItem.set(row.cart_item_id, list)
    }
  }

  const lines = items.map((item) => {
    const product = item.products
    const options = optionRowsByItem.get(item.id) ?? []
    const optionsReadable = options.every((option) => option.readable)

    // Only compute a line total when all metadata for the line is readable; a
    // hidden option price is never treated as zero.
    const unitPrice =
      product && optionsReadable
        ? product.base_price +
          options.reduce((sum, option) => sum + option.priceDelta, 0)
        : null

    const lineTotal = unitPrice !== null ? unitPrice * item.quantity : null
    const primaryImage = product
      ? selectPrimaryImage(product.product_images)
      : null

    return {
      item,
      product,
      options,
      optionsReadable,
      unitPrice,
      lineTotal,
      primaryImage,
    }
  })

  const hasUnavailableLine = lines.some((line) => line.lineTotal === null)
  const subtotal = lines.reduce(
    (sum, line) => sum + (line.lineTotal ?? 0),
    0
  )

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-7xl">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-4xl font-bold text-foreground">
          Your Cart
        </h1>

        <p className="mt-4 max-w-2xl text-zinc-600">
          Items you are planning to order.
        </p>

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
              {lines.map(
                ({
                  item,
                  product,
                  options,
                  optionsReadable,
                  unitPrice,
                  lineTotal,
                  primaryImage,
                }) => (
                  <li
                    key={item.id}
                    className="flex flex-col gap-6 rounded-xl border border-border bg-surface p-6 shadow-sm sm:flex-row"
                  >
                    <div className="w-full max-w-xs shrink-0">
                      <ProductImage
                        src={
                          product && primaryImage
                            ? getProductImageUrl(
                                supabase,
                                primaryImage.storage_path
                              )
                            : null
                        }
                        alt=""
                        sizes="(max-width: 640px) 100vw, 320px"
                        className="aspect-[4/3] w-full rounded-lg"
                      />
                    </div>

                    <div className="flex flex-1 flex-col gap-4">
                      {product ? (
                        <div>
                          <h2 className="font-display text-xl font-semibold text-foreground">
                            <Link
                              href={`/menu/${product.slug}`}
                              className={`transition-colors hover:text-brand ${focusClasses}`}
                            >
                              {product.name}
                            </Link>
                          </h2>

                          {options.length > 0 && (
                            <p className="mt-2 text-sm text-zinc-600">
                              {optionsReadable
                                ? options
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

                      {unitPrice !== null && lineTotal !== null && (
                        <p className="font-medium text-brand">
                          {formatIDR(lineTotal)}
                          <span className="ml-2 text-sm font-normal text-zinc-600">
                            ({item.quantity} × {formatIDR(unitPrice)})
                          </span>
                        </p>
                      )}

                      <CartLineControls
                        cartItemId={item.id}
                        quantity={item.quantity}
                      />
                    </div>
                  </li>
                )
              )}
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
            </div>
          </>
        )}
      </div>
    </main>
  )
}
