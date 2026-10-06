'use client'

import { useActionState } from 'react'
import { updateProfile, type ProfileActionState } from '@/lib/profile/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const inputClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-4 py-3 text-sm text-foreground ${focusClasses}`

const ERROR_ID = 'profile-error'

const initialState: ProfileActionState = { error: null, success: false }

type ProfileFormProps = {
  fullName: string | null
  phone: string | null
  isCustomer: boolean
}

export default function ProfileForm({
  fullName,
  phone,
  isCustomer,
}: ProfileFormProps) {
  const [state, formAction, isPending] = useActionState(
    updateProfile,
    initialState
  )

  return (
    <form action={formAction} className="space-y-5">
      <div>
        <label htmlFor="fullName" className={labelClasses}>
          Full name
        </label>
        <input
          id="fullName"
          name="fullName"
          type="text"
          autoComplete="name"
          maxLength={120}
          defaultValue={fullName ?? ''}
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? ERROR_ID : undefined}
          className={inputClasses}
        />
      </div>

      {isCustomer && (
        <div>
          <label htmlFor="phone" className={labelClasses}>
            Phone
          </label>
          <input
            id="phone"
            name="phone"
            type="tel"
            autoComplete="tel"
            maxLength={32}
            defaultValue={phone ?? ''}
            aria-invalid={state.error ? true : undefined}
            aria-describedby={state.error ? ERROR_ID : undefined}
            className={inputClasses}
          />
        </div>
      )}

      {state.error && (
        <p id={ERROR_ID} role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      {state.success && !state.error && (
        <p role="status" className="text-sm font-medium text-brand">
          Profile updated.
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className={`rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Saving…' : 'Save changes'}
      </button>
    </form>
  )
}
