'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'
import { isPaymentMethod } from '@/lib/orders/payment'

export type PlaceOrderState = {
  error: string | null
}

export type ConfirmPaymentState = {
  error: string | null
}

const GENERIC_ERROR = 'We could not place your order. Please try again.'
const CART_EMPTY_ERROR = 'Your cart is empty.'
const UNAVAILABLE_ERROR =
  'Some items in your cart are no longer available. Please review your cart.'
const INVALID_SELECTION_ERROR =
  'Your selection is no longer valid. Please review your cart.'
const TABLE_ERROR = 'The selected table is not available.'
const DETAILS_ERROR = 'Please check your order details and try again.'

// The database raises one controlled error for every pickup-scheduling
// rejection (outside business hours, closed day, missing hours row, missing or
// invalid restaurant timezone). The UI must not distinguish them.
const PICKUP_HOURS_ERROR =
  'That pickup time is not available. Please choose a time during opening hours.'

// Single, non-revealing coupon message. The database raises one unified error
// for every coupon-unavailable condition (unknown, inactive, out of window,
// minimum not met, usage limits), so the UI must not distinguish them either.
const COUPON_ERROR = 'Coupon is invalid or unavailable.'

const CONFIRM_ERROR = 'We could not confirm your payment. Please try again.'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const MAX_NAME_LENGTH = 120
const MAX_PHONE_LENGTH = 32
const MAX_NOTE_LENGTH = 500

type CreateOrderArgs = Database['public']['Functions']['create_order']['Args']

// Supabase typegen declares every RPC parameter non-nullable, but exactly these
// four are intentionally NULL for the fulfillment type they do not apply to.
// Widening is limited to those keys; identity, name, the idempotency key and
// the (untrusted) coupon code stay non-nullable — an empty coupon string is
// normalised to "no coupon" by create_order. p_pickup_at is a restaurant-local
// wall-clock string (YYYY-MM-DDTHH:mm), not a resolved instant; create_order
// interprets it in the authoritative restaurant timezone.
type CreateOrderPayload = Omit<
  CreateOrderArgs,
  | 'p_customer_phone'
  | 'p_customer_note'
  | 'p_pickup_at'
  | 'p_restaurant_table_id'
> & {
  p_customer_phone: string | null
  p_customer_note: string | null
  p_pickup_at: string | null
  p_restaurant_table_id: string | null
}

/**
 * Maps the RPC's controlled messages to fixed user-facing text. Unknown
 * messages collapse to a generic error so no internal/provider detail reaches
 * the browser.
 */
function mapRpcError(message: string): string {
  switch (message) {
    case 'Your cart is empty':
      return CART_EMPTY_ERROR
    case 'Some items are no longer available':
      return UNAVAILABLE_ERROR
    case 'Some selected options are no longer available':
    case 'Your selection is no longer valid for this product':
      return INVALID_SELECTION_ERROR
    case 'The selected table is not available':
      return TABLE_ERROR
    case 'Coupon is invalid or unavailable':
      return COUPON_ERROR
    case 'Payment method is invalid':
      return DETAILS_ERROR
    case 'Pickup time is outside business hours':
      return PICKUP_HOURS_ERROR
    case 'Order key is invalid':
    case 'Customer name is invalid':
    case 'Customer phone is invalid':
    case 'Customer note is invalid':
    case 'Pickup details are invalid':
    case 'Dine-in details are invalid':
    case 'Fulfillment type is invalid':
      return DETAILS_ERROR
    default:
      return GENERIC_ERROR
  }
}

export async function placeOrder(
  _previousState: PlaceOrderState,
  formData: FormData
): Promise<PlaceOrderState> {
  const fulfillmentType = String(formData.get('fulfillmentType') ?? '')
  const name = String(formData.get('customerName') ?? '').trim()
  const phone = String(formData.get('customerPhone') ?? '').trim()
  const note = String(formData.get('customerNote') ?? '').trim()
  const pickupAtRaw = String(formData.get('pickupAt') ?? '').trim()
  const tableIdRaw = String(formData.get('tableId') ?? '').trim()
  const idempotencyKey = String(formData.get('idempotencyKey') ?? '').trim()
  // Untrusted identifier only. The schema sets no length limit on
  // coupons.code, so none is invented here; an empty value means "no coupon".
  const couponCode = String(formData.get('couponCode') ?? '').trim()
  const paymentMethod = String(formData.get('paymentMethod') ?? '')

  if (fulfillmentType !== 'PICKUP' && fulfillmentType !== 'DINE_IN') {
    return { error: DETAILS_ERROR }
  }

  if (!isPaymentMethod(paymentMethod)) {
    return { error: DETAILS_ERROR }
  }

  if (name.length < 1 || name.length > MAX_NAME_LENGTH) {
    return { error: DETAILS_ERROR }
  }

  if (phone.length > MAX_PHONE_LENGTH || note.length > MAX_NOTE_LENGTH) {
    return { error: DETAILS_ERROR }
  }

  // The key is an untrusted identifier generated by the server-rendered form;
  // it is never treated as identity or authorization.
  if (!UUID_PATTERN.test(idempotencyKey)) {
    return { error: DETAILS_ERROR }
  }

  let pickupAt: string | null = null
  let tableId: string | null = null

  if (fulfillmentType === 'PICKUP') {
    // The browser value is a restaurant-local wall-clock candidate, not an
    // instant. It is forwarded verbatim; create_order interprets it in the
    // authoritative restaurant timezone and enforces business hours. Only a
    // presence check lives here — the database re-validates shape and hours
    // independently and remains the sole scheduling authority.
    if (pickupAtRaw === '') {
      return { error: DETAILS_ERROR }
    }

    pickupAt = pickupAtRaw
  } else {
    if (!UUID_PATTERN.test(tableIdRaw)) {
      return { error: DETAILS_ERROR }
    }

    tableId = tableIdRaw
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the catch so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  const payload: CreateOrderPayload = {
    p_fulfillment_type: fulfillmentType,
    p_customer_name: name,
    p_customer_phone: phone === '' ? null : phone,
    p_customer_note: note === '' ? null : note,
    p_pickup_at: pickupAt,
    p_restaurant_table_id: tableId,
    p_idempotency_key: idempotencyKey,
    p_payment_method: paymentMethod,
    p_coupon_code: couponCode,
  }

  let orderId: string | null = null
  let errorMessage = ''

  try {
    // The generated Args type does not model the nullable parameters above;
    // this single, narrow assertion bridges that typegen gap.
    const { data: createdOrderId, error } = await supabase.rpc(
      'create_order',
      payload as CreateOrderArgs
    )

    if (error) {
      errorMessage = error.message ?? ''
    } else if (typeof createdOrderId === 'string') {
      orderId = createdOrderId
    }
  } catch {
    return { error: GENERIC_ERROR }
  }

  if (!orderId) {
    return { error: mapRpcError(errorMessage) }
  }

  // Success: revalidated outside the catch, then a deterministic redirect.
  revalidatePath('/cart')
  redirect(`/orders/${orderId}`)
}

/**
 * Confirms the authenticated customer's own pending digital payment. The RPC
 * is the only writer of payment state: the browser submits an order id, and
 * the database re-derives identity, ownership, method authorization, and the
 * legal source state. Any failure collapses to one generic message.
 */
export async function confirmOrderPayment(
  _previousState: ConfirmPaymentState,
  formData: FormData
): Promise<ConfirmPaymentState> {
  const orderId = String(formData.get('orderId') ?? '').trim()

  if (!UUID_PATTERN.test(orderId)) {
    return { error: CONFIRM_ERROR }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the catch so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  let failed = false

  try {
    const { error } = await supabase.rpc('confirm_order_payment', {
      p_order_id: orderId,
    })

    if (error) {
      failed = true
    }
  } catch {
    return { error: CONFIRM_ERROR }
  }

  if (failed) {
    return { error: CONFIRM_ERROR }
  }

  revalidatePath(`/orders/${orderId}`)

  return { error: null }
}
