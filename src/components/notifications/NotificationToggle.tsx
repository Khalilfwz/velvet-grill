'use client'

import { useActionState } from 'react'
import {
  setNotificationRead,
  type NotificationActionState,
} from '@/lib/notifications/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const initialState: NotificationActionState = { error: null }

export default function NotificationToggle({
  notificationId,
  isRead,
}: {
  notificationId: string
  isRead: boolean
}) {
  const [state, formAction, isPending] = useActionState(
    setNotificationRead,
    initialState
  )

  return (
    <form action={formAction} className="shrink-0">
      {/* Identifier + target state only; ownership is enforced server-side. */}
      <input type="hidden" name="notificationId" value={notificationId} />
      <input type="hidden" name="isRead" value={isRead ? 'false' : 'true'} />

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full border border-border px-4 py-1.5 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending
          ? 'Saving…'
          : isRead
            ? 'Mark as unread'
            : 'Mark as read'}
      </button>

      {state.error && (
        <p role="alert" className="mt-2 text-sm text-red-600">
          {state.error}
        </p>
      )}
    </form>
  )
}
