import { NextResponse, type NextRequest } from 'next/server'
import { cookies } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import {
  RECOVERY_GRANT_COOKIE,
  RECOVERY_GRANT_MAX_AGE_SECONDS,
  createRecoveryGrantValue,
  extractGrantClaims,
  getRecoveryGrantKey,
} from '@/lib/auth/recovery-session'

// Fixed, app-owned destinations. No redirect target is ever read from the
// request, so a crafted link cannot bounce a user to an external origin.
const SIGNUP_SUCCESS = '/profile'
const SIGNUP_FAILURE = '/login?error=confirmation'
const EMAIL_CHANGE_FAILURE = '/profile?error=email_change'
const RECOVERY_FAILURE = '/login?error=recovery'

/**
 * Supabase Auth email confirmation endpoint.
 *
 * The `type` query parameter selects the handler: `signup` confirms a new
 * account, `email_change` drives the double-confirm email change, and
 * `recovery` starts password reset. Keeping the flows in separate handlers
 * means none can adopt the others' semantics. Every path verifies the
 * token_hash through the server Supabase client so the resulting session is
 * persisted in cookies by @supabase/ssr; no session or cookie is ever
 * constructed by hand.
 */
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const tokenHash = searchParams.get('token_hash')
  const type = searchParams.get('type')

  if (type === 'signup') {
    return confirmSignup(request, tokenHash)
  }

  if (type === 'email_change') {
    return confirmEmailChange(request, tokenHash)
  }

  if (type === 'recovery') {
    return confirmRecovery(request, tokenHash)
  }

  // Unknown or missing type: fail safe without revealing anything.
  return NextResponse.redirect(new URL(SIGNUP_FAILURE, request.url))
}

/**
 * Confirms a new account. A successful verifyOtp returns an authenticated
 * session that @supabase/ssr writes into response cookies, so the user arrives
 * at /profile already signed in. Invalid, expired, or already-used tokens
 * simply return a generic failure.
 */
async function confirmSignup(
  request: NextRequest,
  tokenHash: string | null
): Promise<NextResponse> {
  if (!tokenHash) {
    return NextResponse.redirect(new URL(SIGNUP_FAILURE, request.url))
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.verifyOtp({
    type: 'signup',
    token_hash: tokenHash,
  })

  if (error) {
    return NextResponse.redirect(new URL(SIGNUP_FAILURE, request.url))
  }

  return NextResponse.redirect(new URL(SIGNUP_SUCCESS, request.url))
}

/**
 * Confirms an email change. With double_confirm_changes, Supabase keeps the
 * pending address on the user as `new_email` until the FINAL confirmation
 * completes. A remaining `new_email` therefore means this was the first of the
 * two confirmations; its absence means the change has been applied.
 */
async function confirmEmailChange(
  request: NextRequest,
  tokenHash: string | null
): Promise<NextResponse> {
  const failure = NextResponse.redirect(
    new URL(EMAIL_CHANGE_FAILURE, request.url)
  )

  if (!tokenHash) {
    return failure
  }

  const supabase = await createClient()
  const { data: verified, error } = await supabase.auth.verifyOtp({
    type: 'email_change',
    token_hash: tokenHash,
  })

  if (error) {
    return failure
  }

  const pendingEmail = verified.user?.new_email
  const isPending =
    typeof pendingEmail === 'string' && pendingEmail.length > 0

  return NextResponse.redirect(
    new URL(
      isPending ? '/profile?email=pending' : '/profile?email=updated',
      request.url
    )
  )
}

/**
 * Starts password recovery. A successful verifyOtp returns an authenticated
 * session that @supabase/ssr writes into response cookies, and — only here,
 * only for recovery — mints an HMAC-signed, short-lived recovery grant cookie
 * bound to the verified session identity. The reset page and the reset
 * password action re-verify that grant against the live session before
 * accepting a new password. Invalid, expired, or already-used tokens simply
 * return a generic failure; so does a missing signing secret (fail closed:
 * the consumed token forces the user to request a fresh email).
 */
async function confirmRecovery(
  request: NextRequest,
  tokenHash: string | null
): Promise<NextResponse> {
  const failure = NextResponse.redirect(new URL(RECOVERY_FAILURE, request.url))

  if (!tokenHash) {
    return failure
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.verifyOtp({
    type: 'recovery',
    token_hash: tokenHash,
  })

  if (error) {
    return failure
  }

  // The grant is derived from the freshly verified claims only — never from
  // request data — and cannot be minted without the signing secret.
  const { data } = await supabase.auth.getClaims()
  const grantValue = createRecoveryGrantValue(
    getRecoveryGrantKey(),
    extractGrantClaims(data?.claims)
  )

  if (!grantValue) {
    return failure
  }

  const cookieStore = await cookies()
  cookieStore.set(RECOVERY_GRANT_COOKIE, grantValue, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: RECOVERY_GRANT_MAX_AGE_SECONDS,
  })

  return NextResponse.redirect(new URL('/reset-password', request.url))
}
