'use client'

import { useActionState } from 'react'
import { moderateReview, type AdminActionState } from '@/lib/admin/actions'
import type { Database } from '@/lib/supabase/database.types'
import SubmitButton from './SubmitButton'

type ReviewStatus = Database['public']['Enums']['review_status']

const initialState: AdminActionState = { error: null }

export default function ReviewModerationForm({
  reviewId,
  reviewTitle,
  status,
}: {
  reviewId: string
  reviewTitle?: string | null
  status: ReviewStatus
}) {
  const [state, formAction] = useActionState(moderateReview, initialState)
  const nextStatus: ReviewStatus =
    status === 'PUBLISHED' ? 'HIDDEN' : 'PUBLISHED'
  const isHiding = nextStatus === 'HIDDEN'
  const actionLabel = isHiding ? 'Hide review' : 'Publish review'

  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="reviewId" value={reviewId} />
      <input type="hidden" name="status" value={nextStatus} />

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton
        label={actionLabel}
        pendingLabel={isHiding ? 'Hiding…' : 'Publishing…'}
        variant={isHiding ? 'danger' : 'default'}
        size="compact"
        ariaLabel={
          reviewTitle ? `${actionLabel} — ${reviewTitle}` : undefined
        }
      />
    </form>
  )
}
