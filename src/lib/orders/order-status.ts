import type { Database } from '@/lib/supabase/database.types'

export type OrderStatus = Database['public']['Enums']['order_status']

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
