'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { reviewSubmissionSchema } from '@/lib/reviews/schemas'

export type ReviewActionState = {
  error: string | null
}

const GENERIC_ERROR = 'We could not submit your review. Please try again.'
const NOT_ELIGIBLE_ERROR =
  'You can only review items from your own completed orders.'
const DUPLICATE_ERROR = 'You have already reviewed this item.'
const INVALID_INPUT = 'Please check your review and try again.'

export async function submitReview(
  _previousState: ReviewActionState,
  formData: FormData
): Promise<ReviewActionState> {
  const parsed = reviewSubmissionSchema.safeParse({
    orderItemId: String(formData.get('orderItemId') ?? ''),
    rating: String(formData.get('rating') ?? ''),
    title: String(formData.get('title') ?? ''),
    content: String(formData.get('content') ?? ''),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: user_id is never taken from the form.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the try so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  // Ownership chain, verified explicitly. RLS read scope alone is not proof of
  // ownership, because privileged/admin read policies are broader. The client
  // supplies only orderItemId; product_id/order_id/user_id/status are derived or
  // enforced server-side. RLS and constraints remain the final authority.
  const { data: item, error: itemError } = await supabase
    .from('order_items')
    .select('id, order_id, product_id, orders(user_id, order_status)')
    .eq('id', parsed.data.orderItemId)
    .maybeSingle()

  if (itemError) {
    return { error: GENERIC_ERROR }
  }

  const owningOrder = item?.orders ?? null

  if (
    !item ||
    !owningOrder ||
    owningOrder.user_id !== userId ||
    owningOrder.order_status !== 'COMPLETED' ||
    !item.product_id
  ) {
    return { error: NOT_ELIGIBLE_ERROR }
  }

  // Best-effort slug lookup (public read) so the product page can be revalidated.
  const { data: product } = await supabase
    .from('products')
    .select('slug')
    .eq('id', item.product_id)
    .maybeSingle()

  try {
    const { error } = await supabase.from('reviews').insert({
      user_id: userId,
      product_id: item.product_id,
      order_item_id: item.id,
      rating: parsed.data.rating,
      title: parsed.data.title,
      content: parsed.data.content,
    })

    if (error) {
      if (error.code === '23505') {
        return { error: DUPLICATE_ERROR }
      }

      if (error.code === '42501') {
        return { error: NOT_ELIGIBLE_ERROR }
      }

      if (error.code === '23514') {
        return { error: INVALID_INPUT }
      }

      return { error: GENERIC_ERROR }
    }
  } catch {
    return { error: GENERIC_ERROR }
  }

  revalidatePath(`/orders/${item.order_id}`)

  if (product?.slug) {
    revalidatePath(`/menu/${product.slug}`)
  }

  return { error: null }
}
