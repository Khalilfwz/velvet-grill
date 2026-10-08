'use client'

import { useActionState } from 'react'
import { confirmCashPayment, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const initialState: AdminActionState = { error: null }

export default function ConfirmCashPaymentButton({
  orderId,
  orderNumber,
}: {
  orderId: string
  orderNumber?: string
}) {
  const [state, formAction] = useActionState(confirmCashPayment, initialState)

  return (
    <form action={formAction} className="space-y-2">
      {/* Identifier only; the database re-derives identity, admin
          authorization, the CASH method, and the source state. */}
      <input type="hidden" name="orderId" value={orderId} />

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton
        label="Confirm cash payment"
        pendingLabel="Confirming…"
        ariaLabel={
          orderNumber ? `Confirm cash payment for ${orderNumber}` : undefined
        }
      />
    </form>
  )
}
