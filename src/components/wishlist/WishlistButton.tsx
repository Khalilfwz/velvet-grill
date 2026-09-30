'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { Heart } from 'lucide-react'
import { setWishlistItem } from '@/lib/wishlist/actions'
import type { WishlistActionState } from '@/lib/wishlist/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

type WishlistButtonProps = {
  productId: string
  initialSaved: boolean
  isAuthenticated: boolean
}

export default function WishlistButton({
  productId,
  initialSaved,
  isAuthenticated,
}: WishlistButtonProps) {
  const [state, formAction, isPending] = useActionState(setWishlistItem, {
    error: null,
    saved: initialSaved,
  } satisfies WishlistActionState)

  if (!isAuthenticated) {
    return (
      <Link
        href="/login"
        className={`inline-flex items-center gap-2 rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`}
      >
        <Heart size={18} aria-hidden="true" />
        Sign in to save
      </Link>
    )
  }

  const saved = state.saved
  const intent = saved ? 'remove' : 'add'

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="productId" value={productId} />
      <input type="hidden" name="intent" value={intent} />

      <button
        type="submit"
        disabled={isPending}
        aria-pressed={saved}
        className={`inline-flex items-center gap-2 rounded-full border px-5 py-2 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
          saved
            ? 'border-brand bg-brand text-white hover:bg-brand-light'
            : 'border-border text-foreground hover:border-brand hover:text-brand'
        } ${focusClasses}`}
      >
        <Heart size={18} aria-hidden="true" fill={saved ? 'currentColor' : 'none'} />
        {isPending
          ? saved
            ? 'Removing…'
            : 'Saving…'
          : saved
            ? 'Remove from wishlist'
            : 'Save to wishlist'}
      </button>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}
    </form>
  )
}
