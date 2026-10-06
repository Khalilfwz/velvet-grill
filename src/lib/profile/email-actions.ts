'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { emailChangeSchema } from '@/lib/profile/schemas'

export type EmailActionState = {
  error: string | null
  success: boolean
}

const GENERIC_ERROR = 'We could not update your email. Please try again.'
const INVALID_EMAIL = 'Enter a valid email address.'

/**
 * Requests an email change for the authenticated caller.
 *
 * The change is entirely handled by Supabase Auth (user-scoped updateUser);
 * no redirect origin is derived from the request. Confirmation links are
 * produced by the Auth Site URL plus the email_change template, and the change
 * only takes effect after the double-confirmation flow completes. Errors are
 * reported generically so account existence is never disclosed.
 */
export async function changeEmail(
  _previousState: EmailActionState,
  formData: FormData
): Promise<EmailActionState> {
  const parsed = emailChangeSchema.safeParse({
    email: String(formData.get('email') ?? ''),
  })

  if (!parsed.success) {
    return { error: INVALID_EMAIL, success: false }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: never taken from the browser.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  try {
    const { error } = await supabase.auth.updateUser({
      email: parsed.data.email,
    })

    if (error) {
      return { error: GENERIC_ERROR, success: false }
    }
  } catch {
    return { error: GENERIC_ERROR, success: false }
  }

  return { error: null, success: true }
}
