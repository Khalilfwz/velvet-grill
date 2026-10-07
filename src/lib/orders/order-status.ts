import type { Database } from '@/lib/supabase/database.types'

export type OrderStatus = Database['public']['Enums']['order_status']

export type PaymentStatus = Database['public']['Enums']['payment_status']

/**
 * Mirrors the authoritative transition graph enforced by
 * public.update_order_status (migrations 20261001000001 / 20261002000000).
 * The UI only offers these edges; the database remains the final authority.
 */
export const ORDER_STATUS_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  PENDING_PAYMENT: ['CONFIRMED', 'CANCELLED'],
  CONFIRMED: ['PREPARING', 'CANCELLED'],
  PREPARING: ['READY'],
  READY: ['COMPLETED'],
  COMPLETED: [],
  CANCELLED: [],
}

export function nextOrderStatuses(status: OrderStatus): OrderStatus[] {
  return ORDER_STATUS_TRANSITIONS[status]
}

const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  PENDING_PAYMENT: 'Awaiting payment',
  CONFIRMED: 'Confirmed',
  PREPARING: 'Preparing',
  READY: 'Ready',
  COMPLETED: 'Completed',
  CANCELLED: 'Cancelled',
}

/** Customer-facing label for an order status; mirrors paymentStatusLabel. */
export function orderStatusLabel(status: string): string {
  return ORDER_STATUS_LABELS[status as OrderStatus] ?? status
}

/**
 * Payment-aware transitions for the admin UI. Mirrors the BUG-02 invariant
 * enforced by public.update_order_status (migration 20261006000001):
 * READY -> COMPLETED requires payment_status = 'PAID'. Defense-in-depth only;
 * the database remains the final authority.
 */
export function nextOrderStatusesForOrder(
  status: OrderStatus,
  paymentStatus: PaymentStatus
): OrderStatus[] {
  const next = nextOrderStatuses(status)

  if (status === 'READY' && paymentStatus !== 'PAID') {
    return next.filter((candidate) => candidate !== 'COMPLETED')
  }

  return next
}
