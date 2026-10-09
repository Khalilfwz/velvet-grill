'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type CartActionState = {
  error: string | null
  notice?: string | null
}

const GENERIC_ERROR = 'We could not update your cart. Please try again.'
const UNAVAILABLE_ERROR = 'This item is not available right now.'
const INVALID_SELECTION_ERROR =
  'Some of your selected options are no longer available. Please review your choices.'
const NOT_FOUND_ERROR = 'That cart item is no longer available.'
const QUANTITY_LIMIT_ERROR =
  'That would exceed the quantity limit for a single item.'

// Success notices returned to the client for non-navigating cart mutations.
const ADDED_NOTICE = 'Added to cart.'
const UPDATED_NOTICE = 'Quantity updated.'

// Application-flow limit only. The database invariant is quantity > 0.
const MAX_QUANTITY = 99

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function parseUuid(value: FormDataEntryValue | null): string | null {
  const raw = typeof value === 'string' ? value : ''

  return UUID_PATTERN.test(raw) ? raw : null
}

function parseQuantity(value: FormDataEntryValue | null): number | null {
  const raw = typeof value === 'string' ? value.trim() : ''

  if (!/^\d+$/.test(raw)) {
    return null
  }

  const quantity = Number.parseInt(raw, 10)

  if (quantity < 1 || quantity > MAX_QUANTITY) {
    return null
  }

  return quantity
}

// Maps the add_cart_item RPC's controlled messages to fixed user-facing
// text. Unknown messages collapse to a generic error so no internal detail
// reaches the browser.
function mapAddRpcError(message: string): string {
  switch (message) {
    case 'Cart product is unavailable':
      return UNAVAILABLE_ERROR
    case 'Cart options are invalid':
      return INVALID_SELECTION_ERROR
    case 'Cart quantity limit exceeded':
      return QUANTITY_LIMIT_ERROR
    default:
      return GENERIC_ERROR
  }
}

export async function addToCart(
  _previousState: CartActionState,
  formData: FormData
): Promise<CartActionState> {
  const productId = parseUuid(formData.get('productId'))
  const quantity = parseQuantity(formData.get('quantity'))
  const optionIds = formData
    .getAll('optionIds')
    .filter((value): value is string => typeof value === 'string')

  if (!productId || quantity === null) {
    return { error: GENERIC_ERROR }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the catch so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  // Merging, option validation, quantity limits, and cart creation are
  // enforced by add_cart_item in a single server-authoritative transaction;
  // this action only parses untrusted input and maps controlled errors.
  let result: CartActionState

  try {
    const { error } = await supabase.rpc('add_cart_item', {
      p_product_id: productId,
      p_quantity: quantity,
      p_option_ids: optionIds,
    })

    result = error
      ? { error: mapAddRpcError(error.message ?? '') }
      : { error: null }
  } catch {
    result = { error: GENERIC_ERROR }
  }

  if (result.error) {
    return result
  }

  // Success: stay on the product page. Refresh the cart and the storefront
  // layout (Navbar cart count), then return an inline notice. The
  // /login redirect for unauthenticated callers is preserved above.
  revalidatePath('/cart')
  revalidatePath('/', 'layout')

  return { error: null, notice: ADDED_NOTICE }
}

export async function updateCartItemQuantity(
  _previousState: CartActionState,
  formData: FormData
): Promise<CartActionState> {
  const cartItemId = parseUuid(formData.get('cartItemId'))
  const quantity = parseQuantity(formData.get('quantity'))

  if (!cartItemId || quantity === null) {
    return { error: GENERIC_ERROR }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  let result: CartActionState

  try {
    // RLS scopes this to the caller's own cart; select() reveals whether an
    // owned row was actually updated instead of assuming success.
    const { data: updated, error } = await supabase
      .from('cart_items')
      .update({ quantity })
      .eq('id', cartItemId)
      .select('id')

    if (error) {
      result = { error: GENERIC_ERROR }
    } else if (!updated || updated.length === 0) {
      result = { error: NOT_FOUND_ERROR }
    } else {
      result = { error: null }
    }
  } catch {
    result = { error: GENERIC_ERROR }
  }

  if (result.error) {
    return result
  }

  revalidatePath('/cart')
  revalidatePath('/', 'layout')

  return { error: null, notice: UPDATED_NOTICE }
}

export async function removeCartItem(
  _previousState: CartActionState,
  formData: FormData
): Promise<CartActionState> {
  const cartItemId = parseUuid(formData.get('cartItemId'))

  if (!cartItemId) {
    return { error: GENERIC_ERROR }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  let result: CartActionState

  try {
    // RLS scopes the delete to the caller's own cart; an absent row is a safe
    // no-op, but a provider failure must never be reported as success.
    const { error } = await supabase
      .from('cart_items')
      .delete()
      .eq('id', cartItemId)

    result = error ? { error: GENERIC_ERROR } : { error: null }
  } catch {
    result = { error: GENERIC_ERROR }
  }

  if (result.error) {
    return result
  }

  revalidatePath('/cart')
  revalidatePath('/', 'layout')

  return result
}
