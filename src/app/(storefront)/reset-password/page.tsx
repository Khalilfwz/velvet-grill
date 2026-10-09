import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import ResetPasswordForm from '@/components/auth/ResetPasswordForm'
import PageHeader from '@/components/layout/PageHeader'
import {
  RECOVERY_GRANT_COOKIE,
  extractGrantClaims,
  getRecoveryGrantKey,
  isRecoveryGrantFor,
  parseRecoveryGrant,
} from '@/lib/auth/recovery-session'

export const metadata = {
  title: 'Reset password',
}

export default async function ResetPasswordPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = extractGrantClaims(data?.claims)

  // UX-level re-check of the same authorization the resetPassword action
  // enforces: only a live session bound to an HMAC-signed, short-lived
  // recovery grant (issued exclusively by /auth/confirm after server-verified
  // recovery-token checks) may see this page. Anything else — no session,
  // a password sign-in, an OTP/magic-link login, an expired or forged grant —
  // is routed to the request page, which can never dead-end.
  const cookieStore = await cookies()
  const grant = parseRecoveryGrant(
    cookieStore.get(RECOVERY_GRANT_COOKIE)?.value,
    getRecoveryGrantKey()
  )

  if (!isRecoveryGrantFor(grant, claims)) {
    redirect('/forgot-password')
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-md">
        <PageHeader
          title="Reset password"
          description="Choose a new password for your account."
        />

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <ResetPasswordForm />
        </div>
      </div>
    </main>
  )
}
