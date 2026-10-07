'use client'

import { useActionState, useId } from 'react'
import { updateOrderStatus, type AdminActionState } from '@/lib/admin/actions'
import {
  orderStatusLabel,
  type OrderStatus,
} from '@/lib/orders/order-status'
import SubmitButton from './SubmitButton'

const fieldClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const cellLabelClasses = 'block text-xs font-medium text-zinc-600'

const initialState: AdminActionState = { error: null }

export default function OrderStatusForm({
  orderId,
  currentStatus,
  allowedTransitions,
}: {
  orderId: string
  currentStatus: OrderStatus
  allowedTransitions: OrderStatus[]
}) {
  const uid = useId()
  const [state, formAction] = useActionState(updateOrderStatus, initialState)

  if (allowedTransitions.length === 0) {
    return <p className="text-xs text-zinc-500">No further actions</p>
  }

  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="orderId" value={orderId} />

      <div>
        <label className={cellLabelClasses} htmlFor={`${uid}-status`}>
          New status (current: {orderStatusLabel(currentStatus)})
        </label>
        <select
          id={`${uid}-status`}
          name="toStatus"
          defaultValue={allowedTransitions[0]}
          className={fieldClasses}
        >
          {allowedTransitions.map((status) => (
            <option key={status} value={status}>
              {orderStatusLabel(status)}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label className={cellLabelClasses} htmlFor={`${uid}-note`}>
          Note (optional)
        </label>
        <input
          id={`${uid}-note`}
          name="note"
          maxLength={500}
          className={fieldClasses}
        />
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton label="Update status" pendingLabel="Updating…" size="compact" />
    </form>
  )
}
