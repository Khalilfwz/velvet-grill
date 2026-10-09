'use client'

import { useActionState } from 'react'
import { changePassword } from '@/lib/auth/password-actions'
import type { PasswordActionState } from '@/lib/auth/password-actions'
import PasswordInput from '@/components/auth/PasswordInput'
import {
  PASSWORD_MIN_LENGTH,
  PASSWORD_MIN_LENGTH_HINT,
} from '@/lib/auth/password-policy'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const ERROR_ID = 'password-change-error'

const initialState: PasswordActionState = { error: null, notice: null }

export default function PasswordChangeForm() {
  const [state, formAction, isPending] = useActionState(
    changePassword,
    initialState
  )

  return (
    <form action={formAction} className="space-y-5">
      <PasswordInput
        id="current-password"
        name="currentPassword"
        label="Current password"
        autoComplete="current-password"
        required
        hasError={state.error ? true : false}
        errorId={ERROR_ID}
      />

      <PasswordInput
        id="new-password"
        name="password"
        label="New password"
        autoComplete="new-password"
        required
        minLength={PASSWORD_MIN_LENGTH}
        hasError={state.error ? true : false}
        errorId={ERROR_ID}
        hint={PASSWORD_MIN_LENGTH_HINT}
      />

      {state.error && (
        <p id={ERROR_ID} role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Saving…' : 'Change password'}
      </button>
    </form>
  )
}
