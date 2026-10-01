export const PAYMENT_METHODS = [
  'CASH',
  'DUMMY_QRIS',
  'DUMMY_BANK_TRANSFER',
] as const

export type PaymentMethod = (typeof PAYMENT_METHODS)[number]

export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  CASH: 'Cash',
  DUMMY_QRIS: 'QRIS (dummy)',
  DUMMY_BANK_TRANSFER: 'Bank transfer (dummy)',
}

const PAYMENT_STATUS_LABELS: Record<string, string> = {
  UNPAID: 'Unpaid',
  PENDING: 'Pending',
  PAID: 'Paid',
  FAILED: 'Failed',
  EXPIRED: 'Expired',
  REFUNDED: 'Refunded',
}

export function isPaymentMethod(value: string): value is PaymentMethod {
  return (PAYMENT_METHODS as readonly string[]).includes(value)
}

export function paymentMethodLabel(method: string): string {
  return isPaymentMethod(method) ? PAYMENT_METHOD_LABELS[method] : '—'
}

export function paymentStatusLabel(status: string): string {
  return PAYMENT_STATUS_LABELS[status] ?? status
}
