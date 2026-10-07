'use client'

import { useActionState } from 'react'
import { Minus, Plus, Trash2 } from 'lucide-react'
import { removeCartItem, updateCartItemQuantity } from '@/lib/cart/actions'
import type { CartActionState } from '@/lib/cart/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const stepperButtonClasses = `inline-flex h-9 w-9 items-center justify-center rounded-lg border border-border text-foreground transition-colors hover:border-brand hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`

const initialState: CartActionState = { error: null }

const MIN_QUANTITY = 1
const MAX_QUANTITY = 99

type CartLineControlsProps = {
  cartItemId: string
  quantity: number
}

export default function CartLineControls({
  cartItemId,
  quantity,
}: CartLineControlsProps) {
  const [updateState, updateAction, isUpdating] = useActionState(
    updateCartItemQuantity,
    initialState
  )
  const [removeState, removeAction, isRemoving] = useActionState(
    removeCartItem,
    initialState
  )

  // One cart line is a single mutation boundary: while either mutation is in
  // flight, every control for this line is disabled so update and remove can
  // never be submitted concurrently for the same item.
  const isMutating = isUpdating || isRemoving
  const error = updateState.error ?? removeState.error

  return (
    <div className="flex flex-col gap-2">
      <form action={updateAction} className="flex items-end gap-2">
        <input type="hidden" name="cartItemId" value={cartItemId} />

        <div
          role="group"
          aria-label="Quantity"
          aria-busy={isUpdating}
          className="flex items-center gap-1"
        >
          <button
            type="submit"
            name="quantity"
            value={quantity - 1}
            disabled={isMutating || quantity <= MIN_QUANTITY}
            aria-label="Decrease quantity"
            className={stepperButtonClasses}
          >
            <Minus size={16} aria-hidden="true" />
          </button>

          <span
            aria-live="polite"
            className="min-w-8 text-center text-sm font-medium text-foreground"
          >
            {quantity}
          </span>

          <button
            type="submit"
            name="quantity"
            value={quantity + 1}
            disabled={isMutating || quantity >= MAX_QUANTITY}
            aria-label="Increase quantity"
            className={stepperButtonClasses}
          >
            <Plus size={16} aria-hidden="true" />
          </button>
        </div>
      </form>

      <form action={removeAction}>
        <input type="hidden" name="cartItemId" value={cartItemId} />

        <button
          type="submit"
          disabled={isMutating}
          className={`inline-flex items-center gap-2 text-sm font-medium text-zinc-600 transition-colors hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
        >
          <Trash2 size={16} aria-hidden="true" />
          {isRemoving ? 'Removing…' : 'Remove'}
        </button>
      </form>

      {updateState.notice && !error && (
        <p role="status" className="text-sm font-medium text-brand">
          {updateState.notice}
        </p>
      )}

      {error && (
        <p role="alert" className="text-sm text-red-600">
          {error}
        </p>
      )}
    </div>
  )
}
