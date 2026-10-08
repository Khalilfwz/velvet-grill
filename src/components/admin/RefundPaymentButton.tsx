'use client'

import { useActionState } from 'react'
import type { FormEvent } from 'react'
import { refundOrderPayment, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const initialState: AdminActionState = { error: null }

export default function RefundPaymentButton({
  orderId,
  orderNumber,
}: {
  orderId: string
  orderNumber?: string
}) {
  const [state, formAction] = useActionState(refundOrderPayment, initialState)

  function confirmRefund(event: FormEvent<HTMLFormElement>) {
    if (
      !window.confirm(
        `Refund order ${orderNumber ?? orderId}? This cannot be undone.`
      )
    ) {
      event.preventDefault()
    }
  }

  return (
    <form action={formAction} onSubmit={confirmRefund} className="space-y-2">
      {/* Identifier only; the database re-derives identity, admin
          authorization, the PAID source state, and the closed-order
          gate. A refund never changes the order status. */}
      <input type="hidden" name="orderId" value={orderId} />

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton
        label="Refund payment (full)"
        pendingLabel="Refunding…"
        ariaLabel={orderNumber ? `Refund payment for ${orderNumber}` : undefined}
      />
    </form>
  )
}
