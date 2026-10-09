'use server'

import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import { PASSWORD_MIN_LENGTH } from '@/lib/auth/password-policy'
import {
  RECOVERY_GRANT_COOKIE,
  extractGrantClaims,
  getRecoveryGrantKey,
  isRecoveryGrantFor,
  parseRecoveryGrant,
} from '@/lib/auth/recovery-session'

/** Shared shape returned to the password forms. `null` means no message. */
export type PasswordActionState = {
  error: string | null
  notice: string | null
}

// Supabase remains authoritative for every auth decision. These strings only
// replace the provider's wording, which must never reach the browser: provider
// messages can reveal whether an account exists or quote an environment
// policy. Reset-request responses are identical for existing and non-existing
// accounts so account existence is never disclosed.
const GENERIC_UPDATE_ERROR =
  'We could not update your password. Please try again.'
const SHORT_PASSWORD_ERROR = `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
const CURRENT_PASSWORD_ERROR = 'Current password is incorrect.'
// Uniform and account-independent: 429s are provider limiter responses keyed
// on IP/project, so the same throttling message is shown regardless of what
// was submitted.
const RATE_LIMITED_ERROR =
  'Too many attempts. Please try again in a few minutes.'
const INVALID_EMAIL_ERROR = 'Enter a valid email address.'
const RESET_REQUEST_NOTICE =
  'If an account exists for that email, a password reset link has been sent.'

function isStructurallyValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

/**
 * Requests a password reset email for the submitted address.
 *
 * resetPasswordForEmail is called without a redirectTo: the recovery template
 * links to the app-owned /auth/confirm endpoint on the trusted Site URL, and
 * every redirect from there is a fixed destination. The generic notice is
 * returned unconditionally — provider errors are logged server-side only —
 * so the response can never reveal whether the account exists.
 */
export async function requestPasswordReset(
  _previousState: PasswordActionState,
  formData: FormData
): Promise<PasswordActionState> {
  const email = String(formData.get('email') ?? '').trim()

  if (!isStructurallyValidEmail(email)) {
    return { error: INVALID_EMAIL_ERROR, notice: null }
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.resetPasswordForEmail(email)

  if (error) {
    console.error('Password reset request failed:', error.code)
  }

  return { error: null, notice: RESET_REQUEST_NOTICE }
}

/**
 * Sets a new password for a session authorized by the recovery flow.
 *
 * Authorization requires an HMAC-signed, short-lived recovery grant cookie
 * that only /auth/confirm mints after server-verified recovery-token checks,
 * bound to the live session's `sub` and `session_id`. The JWT `amr` claim is
 * never consulted: password, OTP, and magic-link sessions hold no grant and
 * are redirected to /forgot-password. A session from a normal password
 * sign-in changes passwords through the profile flow, which verifies the
 * current password first.
 *
 * The grant cookie is deleted after a successful reset. This invalidates the
 * browser's copy only: a copied grant remains replayable within its TTL
 * (at most ten minutes) and only by the same live session. See also the
 * provider-level limitation noted on changePassword: with
 * secure_password_change disabled, GoTrue itself accepts password updates
 * from any valid session, so these app-layer checks are defense-in-depth.
 */
export async function resetPassword(
  _previousState: PasswordActionState,
  formData: FormData
): Promise<PasswordActionState> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  // Identity comes only from the server-verified session, never the browser.
  const claims = extractGrantClaims(data?.claims)

  if (!claims) {
    redirect('/forgot-password')
  }

  const cookieStore = await cookies()
  const grant = parseRecoveryGrant(
    cookieStore.get(RECOVERY_GRANT_COOKIE)?.value,
    getRecoveryGrantKey()
  )

  if (!isRecoveryGrantFor(grant, claims)) {
    redirect('/forgot-password')
  }

  const password = String(formData.get('password') ?? '')

  if (password.length < PASSWORD_MIN_LENGTH) {
    return { error: SHORT_PASSWORD_ERROR, notice: null }
  }

  try {
    const { error } = await supabase.auth.updateUser({ password })

    if (error) {
      return { error: GENERIC_UPDATE_ERROR, notice: null }
    }
  } catch {
    return { error: GENERIC_UPDATE_ERROR, notice: null }
  }

  // Invalidate the grant before redirect() (which throws). This removes the
  // browser's copy; see the doc comment for the residual replay window.
  cookieStore.delete(RECOVERY_GRANT_COOKIE)

  redirect('/')
}

/**
 * Changes the password of the authenticated caller.
 *
 * Identity comes only from the authoritative session claims, never from the
 * browser. The current password is verified server-side via
 * signInWithPassword before updateUser, aligning with ASVS password-change
 * guidance. While secure_password_change is disabled, this check lives in
 * this action rather than in GoTrue, so it is a defense-in-depth control
 * rather than an absolute boundary: a stolen session could still call
 * GoTrue directly. A successful verification issues a fresh session, so the
 * cookie rotation is expected.
 */
export async function changePassword(
  _previousState: PasswordActionState,
  formData: FormData
): Promise<PasswordActionState> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: never taken from the browser.
  const email = typeof claims?.email === 'string' ? claims.email : null

  if (!email) {
    redirect('/login')
  }

  const currentPassword = String(formData.get('currentPassword') ?? '')
  const newPassword = String(formData.get('password') ?? '')

  if (newPassword.length < PASSWORD_MIN_LENGTH) {
    return { error: SHORT_PASSWORD_ERROR, notice: null }
  }

  try {
    const { error: verifyError } = await supabase.auth.signInWithPassword({
      email,
      password: currentPassword,
    })

    if (verifyError) {
      if (
        verifyError.code === 'over_request_rate_limit' ||
        verifyError.status === 429
      ) {
        return { error: RATE_LIMITED_ERROR, notice: null }
      }
      return { error: CURRENT_PASSWORD_ERROR, notice: null }
    }

    const { error } = await supabase.auth.updateUser({ password: newPassword })

    if (error) {
      return { error: GENERIC_UPDATE_ERROR, notice: null }
    }
  } catch {
    return { error: GENERIC_UPDATE_ERROR, notice: null }
  }

  redirect('/profile?password=updated')
}
