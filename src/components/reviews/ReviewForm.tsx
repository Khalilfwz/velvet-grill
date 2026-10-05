'use client'

import { useActionState } from 'react'
import { submitReview, type ReviewActionState } from '@/lib/reviews/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const fieldClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground ${focusClasses}`

const initialState: ReviewActionState = { error: null }

export default function ReviewForm({ orderItemId }: { orderItemId: string }) {
  const [state, formAction, isPending] = useActionState(
    submitReview,
    initialState
  )

  const ratingId = `review-rating-${orderItemId}`
  const titleId = `review-title-${orderItemId}`
  const contentId = `review-content-${orderItemId}`

  return (
    <form
      action={formAction}
      className="mt-4 space-y-3 rounded-lg border border-border bg-background p-4"
    >
      <p className="text-sm font-medium text-foreground">Write a review</p>

      <input type="hidden" name="orderItemId" value={orderItemId} />

      <div>
        <label htmlFor={ratingId} className={labelClasses}>
          Rating
        </label>
        <select
          id={ratingId}
          name="rating"
          required
          defaultValue=""
          className={fieldClasses}
        >
          <option value="" disabled>
            Select a rating
          </option>
          {[1, 2, 3, 4, 5].map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor={titleId} className={labelClasses}>
          Title <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <input
          id={titleId}
          name="title"
          type="text"
          maxLength={120}
          className={fieldClasses}
        />
      </div>

      <div>
        <label htmlFor={contentId} className={labelClasses}>
          Review <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <textarea
          id={contentId}
          name="content"
          rows={3}
          maxLength={2000}
          className={fieldClasses}
        />
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Submitting…' : 'Submit review'}
      </button>
    </form>
  )
}
