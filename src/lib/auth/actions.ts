'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PASSWORD_MIN_LENGTH } from '@/lib/auth/password-policy'

/** Shared shape returned to the auth form. `null` means no message. */
export type AuthActionState = {
  error: string | null
  notice: string | null
}

// Supabase remains authoritative for every auth decision. These strings only
// replace the provider's wording, which must never reach the browser: provider
// messages can reveal whether an account exists or quote an environment policy.
const GENERIC_LOGIN_ERROR = 'Incorrect email or password.'
// Uniform and account-independent: 429s are provider limiter responses keyed
// on IP/project, so the same throttling message is shown regardless of what
// was submitted.
const RATE_LIMITED_ERROR =
  'Too many attempts. Please try again in a few minutes.'
const INVALID_EMAIL_ERROR = 'Enter a valid email address.'
const SHORT_PASSWORD_ERROR = `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
const REGISTRATION_ERROR =
  'We could not create your account. Check your details, or sign in if you already have one.'
const CONFIRM_ACCOUNT_NOTICE =
  'Check your email to confirm your account, then sign in.'

function isStructurallyValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

function readCredentials(formData: FormData): {
  email: string
  password: string
} {
  return {
    email: String(formData.get('email') ?? '').trim(),
    password: String(formData.get('password') ?? ''),
  }
}

export async function signIn(
  _previousState: AuthActionState,
  formData: FormData
): Promise<AuthActionState> {
  const { email, password } = readCredentials(formData)

  if (!isStructurallyValidEmail(email) || password.length === 0) {
    return { error: GENERIC_LOGIN_ERROR, notice: null }
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    if (error.code === 'over_request_rate_limit' || error.status === 429) {
      return { error: RATE_LIMITED_ERROR, notice: null }
    }
    return { error: GENERIC_LOGIN_ERROR, notice: null }
  }

  redirect('/')
}

export async function signUp(
  _previousState: AuthActionState,
  formData: FormData
): Promise<AuthActionState> {
  const { email, password } = readCredentials(formData)

  if (!isStructurallyValidEmail(email)) {
    return { error: INVALID_EMAIL_ERROR, notice: null }
  }

  if (password.length < PASSWORD_MIN_LENGTH) {
    return { error: SHORT_PASSWORD_ERROR, notice: null }
  }

  const supabase = await createClient()
  const { data, error } = await supabase.auth.signUp({ email, password })

  if (error) {
    return { error: REGISTRATION_ERROR, notice: null }
  }

  // Email confirmation is enabled, so a successful signup does not assume an
  // authenticated session. Confirmations return a session only when the
  // project disables confirmations; otherwise the user must confirm by email
  // first. Supabase Auth remains the authority for both outcomes.
  if (data.session) {
    redirect('/')
  }

  return { error: null, notice: CONFIRM_ACCOUNT_NOTICE }
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()

  await supabase.auth.signOut({ scope: 'local' })

  redirect('/')
}
