'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { requestPasswordReset } from '@/lib/auth/password-actions'
import type { PasswordActionState } from '@/lib/auth/password-actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const inputClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-4 py-3 text-sm text-foreground ${focusClasses}`

const ERROR_ID = 'forgot-password-error'

const initialState: PasswordActionState = { error: null, notice: null }

export default function ForgotPasswordForm() {
  const [state, formAction, isPending] = useActionState(
    requestPasswordReset,
    initialState
  )

  return (
    <form action={formAction} className="space-y-5">
      <div>
        <label htmlFor="email" className={labelClasses}>
          Email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? ERROR_ID : undefined}
          className={inputClasses}
        />
      </div>

      {state.error && (
        <p id={ERROR_ID} role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      {state.notice && !state.error && (
        <div role="status" className="space-y-1 text-sm font-medium text-brand">
          <p>{state.notice}</p>
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
        className={`w-full rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Sending…' : 'Send reset link'}
      </button>

      <p className="text-sm text-zinc-600">
        Remembered it?{' '}
        <Link
          href="/login"
          className={`font-medium text-brand transition-colors hover:text-brand-light ${focusClasses}`}
        >
          Sign in
        </Link>
      </p>
    </form>
  )
}
