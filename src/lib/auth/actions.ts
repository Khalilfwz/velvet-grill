'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

/** Shared shape returned to the auth form. `null` means no message. */
export type AuthActionState = {
  error: string | null
}

// Mirrors auth.email.minimum_password_length in supabase/config.toml.
const PASSWORD_MIN_LENGTH = 6

// Supabase remains authoritative for every auth decision. These strings only
// replace the provider's wording, which must never reach the browser: provider
// messages can reveal whether an account exists or quote an environment policy.
const GENERIC_LOGIN_ERROR = 'Incorrect email or password.'
const INVALID_EMAIL_ERROR = 'Enter a valid email address.'
const SHORT_PASSWORD_ERROR = `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
const REGISTRATION_ERROR =
  'We could not create your account. Check your details, or sign in if you already have one.'

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
    return { error: GENERIC_LOGIN_ERROR }
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: GENERIC_LOGIN_ERROR }
  }

  redirect('/')
}

export async function signUp(
  _previousState: AuthActionState,
  formData: FormData
): Promise<AuthActionState> {
  const { email, password } = readCredentials(formData)

  if (!isStructurallyValidEmail(email)) {
    return { error: INVALID_EMAIL_ERROR }
  }

  if (password.length < PASSWORD_MIN_LENGTH) {
    return { error: SHORT_PASSWORD_ERROR }
  }

  const supabase = await createClient()
  const { data, error } = await supabase.auth.signUp({ email, password })

  // FR-06 is scoped to email confirmation being disabled, so a successful signup
  // returns a session. Anything else is reported with the same safe message; the
  // provider's error text is never surfaced. Enabling confirmation requires the
  // SSR confirmation/callback flow, which is out of scope here.
  if (error || !data.session) {
    return { error: REGISTRATION_ERROR }
  }

  redirect('/')
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()

  await supabase.auth.signOut({ scope: 'local' })

  redirect('/')
}
