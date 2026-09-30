import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'
import { selectPrimaryImage } from '@/lib/catalog/product-images'

export type CartLineOption = {
  groupName: string
  name: string
  priceDelta: number
  readable: boolean
}

export type CartLine = {
  itemId: string
  productId: string
  quantity: number
  productName: string | null
  productSlug: string | null
  primaryImagePath: string | null
  options: CartLineOption[]
  unitPrice: number | null
  lineTotal: number | null
}

export type CartSummary =
  | {
      ok: true
      lines: CartLine[]
      subtotal: number
      hasUnavailableLine: boolean
    }
  | { ok: false }

/**
 * Server-side cart loader shared by /cart and /checkout. Line totals and the
 * subtotal are derived from current database rows and remain display-only
 * estimates: order pricing is computed authoritatively inside `create_order`.
 *
 * A line is only priced when all of its metadata is currently readable, so a
 * hidden product/option never silently contributes a zero price.
 */
export async function loadCartSummary(
  supabase: SupabaseClient<Database>
): Promise<CartSummary> {
  const { data: cart, error: cartError } = await supabase
    .from('carts')
    .select(
      'id, cart_items(id, quantity, product_id, products(id, name, slug, base_price, product_images(id, storage_path, alt_text, is_primary, sort_order, created_at)))'
    )
    .maybeSingle()

  if (cartError) {
    console.error('Failed to load cart:', cartError.code)

    return { ok: false }
  }

  const items = cart?.cart_items ?? []
  const optionsByItem = new Map<string, CartLineOption[]>()

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

      return { ok: false }
    }

    for (const row of optionRows ?? []) {
      const option = row.product_options
      const group = option?.product_option_groups ?? null

      const list = optionsByItem.get(row.cart_item_id) ?? []

      list.push({
        groupName: group?.name ?? '',
        name: option?.name ?? '',
        priceDelta: option?.price_delta ?? 0,
        readable: option !== null && group !== null,
      })

      optionsByItem.set(row.cart_item_id, list)
    }
  }

  const lines: CartLine[] = items.map((item) => {
    const product = item.products
    const options = optionsByItem.get(item.id) ?? []
    const optionsReadable = options.every((option) => option.readable)

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
      itemId: item.id,
      productId: item.product_id,
      quantity: item.quantity,
      productName: product?.name ?? null,
      productSlug: product?.slug ?? null,
      primaryImagePath: primaryImage?.storage_path ?? null,
      options,
      unitPrice,
      lineTotal,
    }
  })

  const hasUnavailableLine = lines.some((line) => line.lineTotal === null)
  const subtotal = lines.reduce((sum, line) => sum + (line.lineTotal ?? 0), 0)

  return { ok: true, lines, subtotal, hasUnavailableLine }
}
