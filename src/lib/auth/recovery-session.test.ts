import assert from 'node:assert/strict'
import { createHmac } from 'node:crypto'
import { describe, test } from 'node:test'
import {
  RECOVERY_GRANT_MAX_AGE_SECONDS,
  createRecoveryGrantValue,
  extractGrantClaims,
  getRecoveryGrantKey,
  isRecoveryGrantFor,
  parseRecoveryGrant,
} from './recovery-session.ts'

const NOW = 1_700_000_000_000
const TTL_MS = RECOVERY_GRANT_MAX_AGE_SECONDS * 1000

const KEY_A = Buffer.alloc(32, 0x61)
const KEY_B = Buffer.alloc(32, 0x62)

const CLAIMS_A = {
  sub: '11111111-1111-1111-1111-111111111111',
  session_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
}
// Same session, different user (cross-account binding).
const CLAIMS_B = { sub: '22222222-2222-2222-2222-222222222222', session_id: CLAIMS_A.session_id }
// Same user, different session (cross-session binding).
const CLAIMS_S2 = { sub: CLAIMS_A.sub, session_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }

function signPayload(key: Buffer, payload: string): string {
  return createHmac('sha256', key).update(payload).digest('base64url')
}

function signedValue(key: Buffer, payload: unknown): string {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${encoded}.${signPayload(key, encoded)}`
}

describe('recovery grant happy path', () => {
  test('round-trips create → parse and binds to the live session', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)

    const grant = parseRecoveryGrant(value, KEY_A, NOW + 1000)
    assert.ok(grant)
    assert.equal(grant.sub, CLAIMS_A.sub)
    assert.equal(grant.sid, CLAIMS_A.session_id)
    assert.equal(grant.exp, NOW + TTL_MS)
    assert.equal(isRecoveryGrantFor(grant, CLAIMS_A), true)
  })

  test('accepts a grant at the last moment before expiry', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)
    assert.ok(parseRecoveryGrant(value, KEY_A, NOW + TTL_MS - 1))
  })
})

describe('recovery grant negative cases', () => {
  test('rejects an expired grant even with a valid signature', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)
    assert.equal(parseRecoveryGrant(value, KEY_A, NOW + TTL_MS), null)
    assert.equal(parseRecoveryGrant(value, KEY_A, NOW + TTL_MS + 1), null)
  })

  test('rejects a forged payload carrying a valid signature', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    const other = createRecoveryGrantValue(KEY_A, CLAIMS_S2, NOW)
    assert.ok(value)
    assert.ok(other)

    const [, signature] = value.split('.')
    const [otherPayload] = other.split('.')
    const forged = `${otherPayload}.${signature}`

    assert.equal(parseRecoveryGrant(forged, KEY_A, NOW + 1000), null)
  })

  test('rejects a forward-shifted expiry with the original signature', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)

    const [payload, signature] = value.split('.')
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    decoded.exp = NOW + 24 * 60 * 60 * 1000
    const tampered = `${Buffer.from(JSON.stringify(decoded)).toString('base64url')}.${signature}`

    assert.equal(parseRecoveryGrant(tampered, KEY_A, NOW), null)
  })

  test('rejects an altered signature', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)

    const [payload, signature] = value.split('.')
    const altered = signature[0] === 'A' ? `B${signature.slice(1)}` : `A${signature.slice(1)}`
    assert.notEqual(altered, signature)

    assert.equal(parseRecoveryGrant(`${payload}.${altered}`, KEY_A, NOW + 1000), null)
  })

  test('rejects a grant signed with the wrong key', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)
    assert.equal(parseRecoveryGrant(value, KEY_B, NOW + 1000), null)
  })

  test('rejects a grant bound to a different user', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)
    const grant = parseRecoveryGrant(value, KEY_A, NOW + 1000)
    assert.equal(isRecoveryGrantFor(grant, CLAIMS_B), false)
  })

  test('rejects a grant bound to a different session', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)
    const grant = parseRecoveryGrant(value, KEY_A, NOW + 1000)
    assert.equal(isRecoveryGrantFor(grant, CLAIMS_S2), false)
  })

  test('never authorizes from AMR claims alone (recovery regression)', () => {
    // Local GoTrue reports recovery as `otp`, so otp/magiclink/recovery AMR
    // methods are indistinguishable — they must authorize nothing by itself.
    const amrClaims = {
      ...CLAIMS_A,
      amr: [{ method: 'otp', timestamp: Math.floor(NOW / 1000) }],
      recovery: null,
    }

    assert.equal(isRecoveryGrantFor(null, amrClaims), false)
    assert.equal(createRecoveryGrantValue(KEY_A, null, NOW), null)
  })

  test('create/parse fail closed without a key', () => {
    const value = createRecoveryGrantValue(KEY_A, CLAIMS_A, NOW)
    assert.ok(value)

    assert.equal(createRecoveryGrantValue(null, CLAIMS_A, NOW), null)
    assert.equal(parseRecoveryGrant(value, null, NOW + 1000), null)
  })

  test('getRecoveryGrantKey fails closed on missing or short secrets', () => {
    const original = process.env.AUTH_RECOVERY_GRANT_SECRET
    try {
      delete process.env.AUTH_RECOVERY_GRANT_SECRET
      assert.equal(getRecoveryGrantKey(), null)

      process.env.AUTH_RECOVERY_GRANT_SECRET = 'too-short'
      assert.equal(getRecoveryGrantKey(), null)

      process.env.AUTH_RECOVERY_GRANT_SECRET = 'k'.repeat(32)
      const key = getRecoveryGrantKey()
      assert.ok(key)
      assert.equal(key.byteLength, 32)
    } finally {
      if (original === undefined) {
        delete process.env.AUTH_RECOVERY_GRANT_SECRET
      } else {
        process.env.AUTH_RECOVERY_GRANT_SECRET = original
      }
    }
  })

  test('extractGrantClaims fails closed without usable identity', () => {
    assert.equal(extractGrantClaims(null), null)
    assert.equal(extractGrantClaims(undefined), null)
    assert.equal(extractGrantClaims('nope'), null)
    assert.equal(extractGrantClaims({}), null)
    assert.equal(extractGrantClaims({ sub: CLAIMS_A.sub }), null)
    assert.equal(extractGrantClaims({ sub: '', session_id: CLAIMS_A.session_id }), null)
    assert.equal(extractGrantClaims({ sub: 42, session_id: CLAIMS_A.session_id }), null)

    const claims = extractGrantClaims({
      ...CLAIMS_A,
      amr: [{ method: 'recovery', timestamp: 1 }],
    })
    assert.deepEqual(claims, { sub: CLAIMS_A.sub, session_id: CLAIMS_A.session_id })
  })

  test('createRecoveryGrantValue rejects unusable claims', () => {
    assert.equal(createRecoveryGrantValue(KEY_A, { sub: '', session_id: 'y' }, NOW), null)
    assert.equal(createRecoveryGrantValue(KEY_A, { sub: 'x', session_id: '' }, NOW), null)
    assert.equal(createRecoveryGrantValue(KEY_A, undefined, NOW), null)
  })

  test('rejects malformed cookie values', () => {
    const cases = [
      '',
      'garbage',
      'a.b.c',
      'x.y',
      'a'.repeat(257),
      // Correctly shaped but unsigned payload.
      `${Buffer.from(
        JSON.stringify({ sub: CLAIMS_A.sub, sid: CLAIMS_A.session_id, exp: NOW + TTL_MS })
      ).toString('base64url')}.${'A'.repeat(43)}`,
      // Signed but with wrong payload types.
      signedValue(KEY_A, { sub: 42, sid: CLAIMS_A.session_id, exp: NOW + TTL_MS }),
      signedValue(KEY_A, { sub: CLAIMS_A.sub, sid: '', exp: NOW + TTL_MS }),
      signedValue(KEY_A, { sub: CLAIMS_A.sub, sid: CLAIMS_A.session_id, exp: 'soon' }),
      signedValue(KEY_A, { sub: CLAIMS_A.sub, sid: CLAIMS_A.session_id }),
      signedValue(KEY_A, { sid: CLAIMS_A.session_id, exp: NOW + TTL_MS }),
      signedValue(KEY_A, 'not-an-object'),
    ]

    for (const value of cases) {
      assert.equal(parseRecoveryGrant(value, KEY_A, NOW + 1000), null, value.slice(0, 40))
    }
  })
})
