'use client'

import { useActionState } from 'react'
import { Trash2 } from 'lucide-react'
import { removeCartItem, updateCartItemQuantity } from '@/lib/cart/actions'
import type { CartActionState } from '@/lib/cart/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const initialState: CartActionState = { error: null }

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

  const quantityId = `cart-line-quantity-${cartItemId}`
  const error = updateState.error ?? removeState.error

  return (
    <div className="flex flex-col gap-2">
      <form action={updateAction} className="flex flex-wrap items-end gap-2">
        <input type="hidden" name="cartItemId" value={cartItemId} />

        <div>
          <label
            htmlFor={quantityId}
            className="block text-sm font-medium text-foreground"
          >
            Quantity
          </label>
          <input
            id={quantityId}
            name="quantity"
            type="number"
            min={1}
            max={99}
            step={1}
            defaultValue={quantity}
            className={`mt-1 w-20 rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground ${focusClasses}`}
          />
        </div>

        <button
          type="submit"
          disabled={isUpdating}
          className={`rounded-full border border-border px-4 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
        >
          {isUpdating ? 'Updating…' : 'Update'}
        </button>
      </form>

      <form action={removeAction}>
        <input type="hidden" name="cartItemId" value={cartItemId} />

        <button
          type="submit"
          disabled={isRemoving}
          className={`inline-flex items-center gap-2 text-sm font-medium text-zinc-600 transition-colors hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
        >
          <Trash2 size={16} aria-hidden="true" />
          {isRemoving ? 'Removing…' : 'Remove'}
        </button>
      </form>

      {error && (
        <p role="alert" className="text-sm text-red-600">
          {error}
        </p>
      )}
    </div>
  )
}
