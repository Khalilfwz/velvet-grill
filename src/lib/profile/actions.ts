'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { profileUpdateSchema } from '@/lib/profile/schemas'

export type ProfileActionState = {
  error: string | null
  success: boolean
}

const GENERIC_ERROR = 'We could not update your profile. Please try again.'
const INVALID_INPUT = 'Please check your details and try again.'

/**
 * Updates the authenticated customer's own profile.
 *
 * Only full_name and phone are accepted and written. The caller id is derived
 * from the authoritative session subject, never from the form, and the update
 * is scoped to that id. The existing profiles_update_own RLS policy plus the
 * column-level UPDATE (full_name, phone, avatar_path) grant remain the
 * underlying authority; role, is_active, email, avatar_path, and arbitrary
 * fields are never addressable from here.
 */
export async function updateProfile(
  _previousState: ProfileActionState,
  formData: FormData
): Promise<ProfileActionState> {
  const parsed = profileUpdateSchema.safeParse({
    fullName: String(formData.get('fullName') ?? ''),
    phone: String(formData.get('phone') ?? ''),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT, success: false }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: the caller id is never taken from the form.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the try so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  try {
    // A profiles row is a required 1:1 record. Returning the updated id proves
    // the caller's row existed and was updated; zero rows returned (missing or
    // non-writable row) is not success.
    const { data: updated, error } = await supabase
      .from('profiles')
      .update({
        full_name: parsed.data.fullName,
        phone: parsed.data.phone,
      })
      .eq('id', userId)
      .select('id')
      .maybeSingle()

    if (error || !updated) {
      return { error: GENERIC_ERROR, success: false }
    }
  } catch {
    return { error: GENERIC_ERROR, success: false }
  }

  revalidatePath('/profile')

  return { error: null, success: true }
}
