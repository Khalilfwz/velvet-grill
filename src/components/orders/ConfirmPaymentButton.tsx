'use client'

import { useActionState } from 'react'
import { confirmOrderPayment } from '@/lib/orders/actions'
import type { ConfirmPaymentState } from '@/lib/orders/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const initialState: ConfirmPaymentState = { error: null }

export default function ConfirmPaymentButton({ orderId }: { orderId: string }) {
  const [state, formAction, isPending] = useActionState(
    confirmOrderPayment,
    initialState
  )

  return (
    <form action={formAction} className="mt-4">
      {/* Identifier only; the database re-derives identity and authorization. */}
      <input type="hidden" name="orderId" value={orderId} />

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Confirming…' : 'Simulate payment'}
      </button>

      {state.error && (
        <p role="alert" className="mt-2 text-sm text-red-600">
          {state.error}
        </p>
      )}
    </form>
  )
}
