import { createHmac, timingSafeEqual } from 'node:crypto'

/**
 * Recovery-grant authorization helpers.
 *
 * Setting a new password without the current one is authorized exclusively by
 * a signed, short-lived grant that the /auth/confirm route handler issues
 * AFTER a recovery token (`verifyOtp({ type: 'recovery' })`) has been verified
 * server-side. The grant is an HMAC-SHA256 signed receipt bound to the
 * verified session identity (`sub` + `session_id` claims of the fresh JWT):
 * every consumer re-verifies the signature with `timingSafeEqual`, the
 * expiry, and the binding against the live verified session. The JWT `amr`
 * claim is never consulted — recovery, OTP, and magic-link sessions are
 * indistinguishable through it, so it cannot authorize anything.
 *
 * The signing key comes from the dedicated server-only
 * AUTH_RECOVERY_GRANT_SECRET environment variable. A missing or too-short
 * secret fails closed: grants cannot be minted or validated, disabling the
 * reset flow entirely. There is no insecure fallback.
 *
 * The grant is not single-use in the server-side sense: deleting the cookie
 * after a successful reset invalidates the browser's copy, but a copied
 * grant can still be replayed within its TTL (at most
 * RECOVERY_GRANT_MAX_AGE_SECONDS) and only by the same live session, since
 * the binding must match the current `sub` and `session_id`.
 */

export const RECOVERY_GRANT_COOKIE = 'vg-recovery-grant'
export const RECOVERY_GRANT_MAX_AGE_SECONDS = 600

const MIN_SECRET_BYTES = 32
const MAX_GRANT_VALUE_CHARS = 256

/** Session identity extracted from server-verified JWT claims. */
export type RecoveryGrantClaims = {
  sub: string
  session_id: string
}

/** Decoded grant payload. Trusted only after signature and expiry checks. */
export type RecoveryGrant = {
  sub: string
  sid: string
  exp: number
}

/**
 * The dedicated signing secret as a key. Returns null when the variable is
 * unset or shorter than MIN_SECRET_BYTES — callers must fail closed.
 */
export function getRecoveryGrantKey(): Buffer | null {
  const secret = process.env.AUTH_RECOVERY_GRANT_SECRET

  if (typeof secret !== 'string' || secret.length === 0) {
    return null
  }

  const key = Buffer.from(secret, 'utf8')

  return key.byteLength >= MIN_SECRET_BYTES ? key : null
}

/**
 * Narrows untrusted claims to the identity fields a grant is bound to, or
 * null when `sub`/`session_id` are missing. Fail closed: a session without
 * a `session_id` claim can never receive or match a grant.
 */
export function extractGrantClaims(claims: unknown): RecoveryGrantClaims | null {
  if (!claims || typeof claims !== 'object') {
    return null
  }

  const sub = (claims as { sub?: unknown }).sub
  const sessionId = (claims as { session_id?: unknown }).session_id

  if (
    typeof sub !== 'string' ||
    sub.length === 0 ||
    typeof sessionId !== 'string' ||
    sessionId.length === 0
  ) {
    return null
  }

  return { sub, session_id: sessionId }
}

/**
 * Signs a grant receipt for the given verified session identity. Returns
 * null when the key is missing or the claims are unusable; callers must
 * fail closed. Value format: `base64url(payload).base64url(hmac)`.
 */
export function createRecoveryGrantValue(
  key: Buffer | null,
  claims: RecoveryGrantClaims | null | undefined,
  nowMs: number = Date.now()
): string | null {
  // Claims are re-validated here regardless of their static type: they
  // originate from an untrusted parse boundary somewhere up the call chain.
  if (
    !key ||
    !claims ||
    typeof claims.sub !== 'string' ||
    claims.sub.length === 0 ||
    typeof claims.session_id !== 'string' ||
    claims.session_id.length === 0
  ) {
    return null
  }

  const payload = Buffer.from(
    JSON.stringify({
      sub: claims.sub,
      sid: claims.session_id,
      exp: nowMs + RECOVERY_GRANT_MAX_AGE_SECONDS * 1000,
    })
  ).toString('base64url')

  return `${payload}.${sign(key, payload)}`
}

/**
 * Verifies a grant value: HMAC via timingSafeEqual, strict payload shape,
 * then expiry. Returns the decoded grant or null for anything malformed,
 * tampered, or expired.
 */
export function parseRecoveryGrant(
  value: string | null | undefined,
  key: Buffer | null,
  nowMs: number = Date.now()
): RecoveryGrant | null {
  if (!key || !value || value.length > MAX_GRANT_VALUE_CHARS) {
    return null
  }

  // base64url never contains dots, so a valid grant splits into exactly two.
  const parts = value.split('.')
  if (parts.length !== 2) {
    return null
  }

  const [payload, signature] = parts
  if (!isSignatureValid(key, payload, signature)) {
    return null
  }

  let decoded: unknown
  try {
    decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
  } catch {
    return null
  }

  if (!decoded || typeof decoded !== 'object') {
    return null
  }

  const sub = (decoded as { sub?: unknown }).sub
  const sid = (decoded as { sid?: unknown }).sid
  const exp = (decoded as { exp?: unknown }).exp

  if (
    typeof sub !== 'string' ||
    sub.length === 0 ||
    typeof sid !== 'string' ||
    sid.length === 0 ||
    typeof exp !== 'number' ||
    !Number.isFinite(exp)
  ) {
    return null
  }

  if (exp <= nowMs) {
    return null
  }

  return { sub, sid, exp }
}

/**
 * Whether a verified grant belongs to the live verified session. The cookie
 * alone is meaningless: both halves must identify the same session.
 */
export function isRecoveryGrantFor(
  grant: RecoveryGrant | null,
  claims: RecoveryGrantClaims | null | undefined
): boolean {
  if (!grant || !claims) {
    return false
  }

  return grant.sub === claims.sub && grant.sid === claims.session_id
}

function sign(key: Buffer, payload: string): string {
  return createHmac('sha256', key).update(payload).digest('base64url')
}

/**
 * Byte-length guard before timingSafeEqual (it throws on unequal lengths,
 * and the length itself is not secret), then a constant-time comparison of
 * the encoded signature bytes.
 */
function isSignatureValid(
  key: Buffer,
  payload: string,
  signature: string
): boolean {
  const expected = Buffer.from(sign(key, payload), 'utf8')
  const provided = Buffer.from(signature, 'utf8')

  if (provided.length !== expected.length) {
    return false
  }

  return timingSafeEqual(provided, expected)
}
