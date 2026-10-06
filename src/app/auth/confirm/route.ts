import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Fixed, app-owned destinations. No redirect target is ever read from the
// request, so a crafted link cannot bounce a user to an external origin.
const SIGNUP_SUCCESS = '/profile'
const SIGNUP_FAILURE = '/login?error=confirmation'
const EMAIL_CHANGE_FAILURE = '/profile?error=email_change'

/**
 * Supabase Auth email confirmation endpoint.
 *
 * The `type` query parameter selects the handler: `signup` confirms a new
 * account, `email_change` drives the double-confirm email change. Keeping the
 * two flows in separate handlers means neither can adopt the other's
 * semantics. Every path verifies the token_hash through the server Supabase
 * client so the resulting session is persisted in cookies by @supabase/ssr;
 * no session or cookie is ever constructed by hand.
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
