'use client'

import { useActionState } from 'react'
import { moderateReview, type AdminActionState } from '@/lib/admin/actions'
import type { Database } from '@/lib/supabase/database.types'
import SubmitButton from './SubmitButton'

type ReviewStatus = Database['public']['Enums']['review_status']

const initialState: AdminActionState = { error: null }

export default function ReviewModerationForm({
  reviewId,
  status,
}: {
  reviewId: string
  status: ReviewStatus
}) {
  const [state, formAction] = useActionState(moderateReview, initialState)
  const nextStatus: ReviewStatus =
    status === 'PUBLISHED' ? 'HIDDEN' : 'PUBLISHED'
  const isHiding = nextStatus === 'HIDDEN'

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
        label={isHiding ? 'Hide review' : 'Publish review'}
        pendingLabel={isHiding ? 'Hiding…' : 'Publishing…'}
        className={isHiding ? 'bg-red-700 hover:bg-red-800' : ''}
      />
    </form>
  )
}
