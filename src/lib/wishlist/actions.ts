'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type WishlistActionState = {
  error: string | null
  saved: boolean
}

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>

const GENERIC_ERROR = 'We could not update your wishlist. Please try again.'
const UNAVAILABLE_ERROR = 'This item is not available right now.'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function findWishlistId(
  supabase: SupabaseServerClient,
  userId: string
): Promise<string | null> {
  const { data, error } = await supabase
    .from('wishlists')
    .select('id')
    .eq('user_id', userId)
    .maybeSingle()

  // A real query failure must never be read as "no wishlist exists"; throw so
  // the caller's safe error handling returns a generic message instead of a
  // false successful state.
  if (error) {
    throw new Error('wishlist_lookup_failed')
  }

  return data?.id ?? null
}

/**
 * One personal wishlist per customer (`wishlists_user_unique`). Creation is
 * race-safe: if two concurrent requests both insert, the loser receives 23505
 * and re-reads the winning row instead of failing.
 */
async function ensureWishlistId(
  supabase: SupabaseServerClient,
  userId: string
): Promise<string | null> {
  const existing = await findWishlistId(supabase, userId)

  if (existing) {
    return existing
  }

  const { data, error } = await supabase
    .from('wishlists')
    .insert({ user_id: userId })
    .select('id')
    .single()

  if (!error && data) {
    return data.id
  }

  if (error?.code === '23505') {
    return findWishlistId(supabase, userId)
  }

  return null
}

async function addToWishlist(
  supabase: SupabaseServerClient,
  userId: string,
  productId: string,
  previousSaved: boolean
): Promise<WishlistActionState> {
  // Application-flow rule: only save products the customer can currently see
  // and that are available. Ownership is still enforced by RLS below; this is
  // not a database invariant.
  const { data: product, error: productError } = await supabase
    .from('products')
    .select('id')
    .eq('id', productId)
    .eq('is_available', true)
    .maybeSingle()

  // A query failure is not "unavailable": fail generically and preserve state.
  if (productError) {
    return { error: GENERIC_ERROR, saved: previousSaved }
  }

  // No error and no row means the product is genuinely unavailable or hidden
  // by product RLS.
  if (!product) {
    return { error: UNAVAILABLE_ERROR, saved: previousSaved }
  }

  const wishlistId = await ensureWishlistId(supabase, userId)

  if (!wishlistId) {
    return { error: GENERIC_ERROR, saved: previousSaved }
  }

  // Duplicate adds are idempotent: ON CONFLICT DO NOTHING against
  // wishlist_items_unique. INSERT-only, matching the granted privileges.
  const { error } = await supabase
    .from('wishlist_items')
    .upsert(
      { wishlist_id: wishlistId, product_id: productId },
      { onConflict: 'wishlist_id,product_id', ignoreDuplicates: true }
    )

  if (error) {
    return { error: GENERIC_ERROR, saved: previousSaved }
  }

  revalidatePath('/wishlist')

  return { error: null, saved: true }
}

async function removeFromWishlist(
  supabase: SupabaseServerClient,
  userId: string,
  productId: string,
  previousSaved: boolean
): Promise<WishlistActionState> {
  // Throws on a real query failure so a database error is never treated as
  // "no wishlist" and never returns a false successful saved:false state.
  const wishlistId = await findWishlistId(supabase, userId)

  // Nothing to remove: idempotent no-op, no provider error surfaced.
  if (!wishlistId) {
    revalidatePath('/wishlist')

    return { error: null, saved: false }
  }

  // Removal is scoped to the caller's own wishlist and does not require the
  // product to be available or readable.
  const { error } = await supabase
    .from('wishlist_items')
    .delete()
    .eq('wishlist_id', wishlistId)
    .eq('product_id', productId)

  if (error) {
    return { error: GENERIC_ERROR, saved: previousSaved }
  }

  revalidatePath('/wishlist')

  return { error: null, saved: false }
}

export async function setWishlistItem(
  previousState: WishlistActionState,
  formData: FormData
): Promise<WishlistActionState> {
  const productId = String(formData.get('productId') ?? '')
  const intent = String(formData.get('intent') ?? '')

  if (
    !UUID_PATTERN.test(productId) ||
    (intent !== 'add' && intent !== 'remove')
  ) {
    return { error: GENERIC_ERROR, saved: previousState.saved }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // The session check and redirect stay outside the try/catch below so Next's
  // redirect control flow is never swallowed by provider error mapping.
  if (!userId) {
    redirect('/login')
  }

  try {
    return intent === 'add'
      ? await addToWishlist(supabase, userId, productId, previousState.saved)
      : await removeFromWishlist(
          supabase,
          userId,
          productId,
          previousState.saved
        )
  } catch {
    return { error: GENERIC_ERROR, saved: previousState.saved }
  }
}
