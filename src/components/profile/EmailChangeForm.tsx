'use client'

import { useActionState } from 'react'
import { changeEmail, type EmailActionState } from '@/lib/profile/email-actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const inputClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-4 py-3 text-sm text-foreground ${focusClasses}`

const ERROR_ID = 'email-change-error'

const initialState: EmailActionState = { error: null, success: false }

type EmailChangeFormProps = {
  currentEmail: string | null
}

export default function EmailChangeForm({
  currentEmail,
}: EmailChangeFormProps) {
  const [state, formAction, isPending] = useActionState(
    changeEmail,
    initialState
  )

  return (
    <form action={formAction} className="space-y-5">
      <div>
        <label htmlFor="email" className={labelClasses}>
          New email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
          defaultValue={currentEmail ?? ''}
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? ERROR_ID : undefined}
          className={inputClasses}
        />
        <p className="mt-1 text-sm text-zinc-600">
          Both your current and your new email address must confirm before the
          change completes.
        </p>
      </div>

      {state.error && (
        <p id={ERROR_ID} role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      {state.success && !state.error && (
        <div role="status" className="space-y-1 text-sm font-medium text-brand">
          <p>
            Confirmation links were sent to both your current and new email
            address.
          </p>
          <p className="text-zinc-600">
            Complete both confirmations for the change to take effect.
          </p>
          {process.env.NODE_ENV === 'development' && (
            <a
              href="http://localhost:54324"
              className={`inline-block text-sm font-medium text-brand underline-offset-2 hover:underline ${focusClasses}`}
            >
              Open local inbox
            </a>
          )}
        </div>
      )}

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Sending…' : 'Change email'}
      </button>
    </form>
  )
}
