import { orderStatusLabel } from '@/lib/orders/order-status'

// Restrained tones from the existing palette. The label text is always present,
// so state is never communicated by color alone.
const TONE_CLASSES: Record<string, string> = {
  PENDING_PAYMENT: 'border-border bg-background text-foreground',
  CONFIRMED: 'border-brand/30 bg-brand/5 text-brand',
  PREPARING: 'border-brand/30 bg-brand/5 text-brand',
  READY: 'border-brand bg-brand text-white',
  COMPLETED: 'border-border bg-surface text-foreground',
  CANCELLED: 'border-red-200 bg-red-50 text-red-700',
}

const DEFAULT_TONE = 'border-border bg-surface text-foreground'

export default function OrderStatusBadge({ status }: { status: string }) {
  const tone = TONE_CLASSES[status] ?? DEFAULT_TONE

  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${tone}`}
    >
      {orderStatusLabel(status)}
    </span>
  )
}
