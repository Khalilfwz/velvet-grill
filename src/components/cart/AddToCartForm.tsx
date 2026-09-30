'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { ShoppingCart } from 'lucide-react'
import { addToCart } from '@/lib/cart/actions'
import type { CartActionState } from '@/lib/cart/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const initialState: CartActionState = { error: null }

type AddToCartFormProps = {
  productId: string
  optionIds: string[]
  complete: boolean
  isAuthenticated: boolean
}

export default function AddToCartForm({
  productId,
  optionIds,
  complete,
  isAuthenticated,
}: AddToCartFormProps) {
  const [state, formAction, isPending] = useActionState(
    addToCart,
    initialState
  )

  if (!isAuthenticated) {
    return (
      <Link
        href="/login"
        className={`inline-flex items-center gap-2 rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`}
      >
        <ShoppingCart size={18} aria-hidden="true" />
        Sign in to add to cart
      </Link>
    )
  }

  const quantityId = `cart-quantity-${productId}`

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="productId" value={productId} />

      {optionIds.map((optionId) => (
        <input key={optionId} type="hidden" name="optionIds" value={optionId} />
      ))}

      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={quantityId} className="block text-sm font-medium text-foreground">
            Quantity
          </label>
          <input
            id={quantityId}
            name="quantity"
            type="number"
            min={1}
            max={99}
            step={1}
            defaultValue={1}
            className={`mt-1 w-24 rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground ${focusClasses}`}
          />
        </div>

        <button
          type="submit"
          disabled={!complete || isPending}
          className={`inline-flex items-center gap-2 rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
        >
          <ShoppingCart size={18} aria-hidden="true" />
          {isPending ? 'Adding…' : 'Add to cart'}
        </button>
      </div>

      {!complete && (
        <p className="text-sm text-zinc-600">
          Choose the required options to add this item.
        </p>
      )}

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}
    </form>
  )
}
