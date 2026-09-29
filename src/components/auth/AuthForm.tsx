'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { signIn, signUp } from '@/lib/auth/actions'
import type { AuthActionState } from '@/lib/auth/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const inputClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-4 py-3 text-sm text-foreground ${focusClasses}`

const ERROR_ID = 'auth-error'

const initialState: AuthActionState = { error: null }

type AuthFormProps = {
  mode: 'login' | 'register'
}

export default function AuthForm({ mode }: AuthFormProps) {
  const isRegister = mode === 'register'

  const [state, formAction, isPending] = useActionState(
    isRegister ? signUp : signIn,
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
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? ERROR_ID : undefined}
          className={inputClasses}
        />
      </div>

      <div>
        <label htmlFor="password" className={labelClasses}>
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete={isRegister ? 'new-password' : 'current-password'}
          required
          minLength={isRegister ? 6 : 1}
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? ERROR_ID : undefined}
          className={inputClasses}
        />

        {isRegister && (
          <p className="mt-1 text-sm text-zinc-600">
            At least 6 characters.
          </p>
        )}
      </div>

      {state.error && (
        <p id={ERROR_ID} role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className={`w-full rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending
          ? 'Please wait…'
          : isRegister
            ? 'Create account'
            : 'Sign in'}
      </button>

      <p className="text-sm text-zinc-600">
        {isRegister ? (
          <>
            Already have an account?{' '}
            <Link
              href="/login"
              className={`font-medium text-brand transition-colors hover:text-brand-light ${focusClasses}`}
            >
              Sign in
            </Link>
          </>
        ) : (
          <>
            New here?{' '}
            <Link
              href="/register"
              className={`font-medium text-brand transition-colors hover:text-brand-light ${focusClasses}`}
            >
              Create an account
            </Link>
          </>
        )}
      </p>
    </form>
  )
}
