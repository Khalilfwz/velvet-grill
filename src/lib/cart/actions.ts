'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import {
  buildProductOptionGroups,
  isGroupSatisfied,
} from '@/lib/catalog/product-options'
import type { OptionSelections } from '@/lib/catalog/product-options'

export type CartActionState = {
  error: string | null
  notice?: string | null
}

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>

const GENERIC_ERROR = 'We could not update your cart. Please try again.'
const UNAVAILABLE_ERROR = 'This item is not available right now.'
const INVALID_SELECTION_ERROR =
  'Some of your selected options are no longer available. Please review your choices.'
const NOT_FOUND_ERROR = 'That cart item is no longer available.'

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

// A real query failure must never be read as "no cart exists".
async function findCartId(
  supabase: SupabaseServerClient,
  userId: string
): Promise<string | null> {
  const { data, error } = await supabase
    .from('carts')
    .select('id')
    .eq('user_id', userId)
    .maybeSingle()

  if (error) {
    throw new Error('cart_lookup_failed')
  }

  return data?.id ?? null
}

// One cart per customer (`carts_user_unique`); the loser of a race sees 23505
// and re-reads the winning row.
async function ensureCartId(
  supabase: SupabaseServerClient,
  userId: string
): Promise<string | null> {
  const existing = await findCartId(supabase, userId)

  if (existing) {
    return existing
  }

  const { data, error } = await supabase
    .from('carts')
    .insert({ user_id: userId })
    .select('id')
    .single()

  if (!error && data) {
    return data.id
  }

  if (error?.code === '23505') {
    return findCartId(supabase, userId)
  }

  return null
}

type OptionValidation =
  | { ok: true; optionIds: string[] }
  | { ok: false; error: string }

/**
 * Server-authoritative option validation. Reads the product's active groups and
 * available options from the database and reuses the FR-05 pure helpers, so the
 * server rule cannot drift from the client's display rule. The
 * `cart_item_options_insert_valid` RLS policy remains the database backstop.
 */
async function resolveValidOptionIds(
  supabase: SupabaseServerClient,
  productId: string,
  submitted: string[]
): Promise<OptionValidation> {
  const unique = Array.from(new Set(submitted))

  const { data: groupRows, error: groupsError } = await supabase
    .from('product_option_groups')
    .select(
      'id, name, selection_type, min_selections, max_selections, is_required, sort_order, is_active, product_options(id, group_id, name, price_delta, is_available, sort_order)'
    )
    .eq('product_id', productId)
    .eq('is_active', true)

  if (groupsError) {
    return { ok: false, error: GENERIC_ERROR }
  }

  const groups = groupRows ?? []
  const options = groups.flatMap((group) => group.product_options ?? [])

  const clientGroups = buildProductOptionGroups(groups, options)
  const availableOptionIds = new Set(
    clientGroups.flatMap((group) => group.options.map((option) => option.id))
  )

  // Membership + availability: every submitted id must be a currently available
  // option of this product (belonging to another product is rejected here).
  if (unique.some((optionId) => !availableOptionIds.has(optionId))) {
    return { ok: false, error: INVALID_SELECTION_ERROR }
  }

  const selections: OptionSelections = {}

  for (const group of clientGroups) {
    const selected = unique.filter((optionId) =>
      group.options.some((option) => option.id === optionId)
    )

    if (selected.length > 0) {
      selections[group.id] = selected
    }
  }

  // Required groups, min/max, and SINGLE/MULTIPLE cardinality.
  const complete = clientGroups.every((group) =>
    isGroupSatisfied(group, selections[group.id] ?? [])
  )

  if (!complete) {
    return { ok: false, error: INVALID_SELECTION_ERROR }
  }

  return { ok: true, optionIds: unique }
}

async function insertCartItem(
  supabase: SupabaseServerClient,
  userId: string,
  productId: string,
  quantity: number,
  submittedOptionIds: string[]
): Promise<CartActionState> {
  const { data: product, error: productError } = await supabase
    .from('products')
    .select('id')
    .eq('id', productId)
    .eq('is_available', true)
    .maybeSingle()

  // A query failure is not "unavailable".
  if (productError) {
    return { error: GENERIC_ERROR }
  }

  if (!product) {
    return { error: UNAVAILABLE_ERROR }
  }

  const validation = await resolveValidOptionIds(
    supabase,
    productId,
    submittedOptionIds
  )

  if (!validation.ok) {
    return { error: validation.error }
  }

  const cartId = await ensureCartId(supabase, userId)

  if (!cartId) {
    return { error: GENERIC_ERROR }
  }

  const { data: item, error: itemError } = await supabase
    .from('cart_items')
    .insert({ cart_id: cartId, product_id: productId, quantity })
    .select('id')
    .single()

  if (itemError || !item) {
    return { error: GENERIC_ERROR }
  }

  if (validation.optionIds.length > 0) {
    const { error: optionsError } = await supabase
      .from('cart_item_options')
      .insert(
        validation.optionIds.map((optionId) => ({
          cart_item_id: item.id,
          product_option_id: optionId,
        }))
      )

    if (optionsError) {
      // Compensation, not transaction atomicity: this multi-step write is not a
      // single transaction, so the just-created item is removed on failure.
      const { error: cleanupError } = await supabase
        .from('cart_items')
        .delete()
        .eq('id', item.id)

      if (cleanupError) {
        console.error('Cart item compensation failed for item', item.id)
      }

      return { error: GENERIC_ERROR }
    }
  }

  return { error: null }
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

  let result: CartActionState

  try {
    result = await insertCartItem(
      supabase,
      userId,
      productId,
      quantity,
      optionIds
    )
  } catch {
    return { error: GENERIC_ERROR }
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
