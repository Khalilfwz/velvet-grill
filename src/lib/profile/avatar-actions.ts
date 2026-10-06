'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import {
  AVATARS_BUCKET,
  AVATAR_MAX_BYTES,
  avatarExtensionForMime,
  isAllowedAvatarMimeType,
  isOwnedAvatarPath,
} from '@/lib/profile/avatar'

export type AvatarActionState = {
  error: string | null
  success: boolean
}

const GENERIC_ERROR = 'We could not update your photo. Please try again.'
const INVALID_FILE = 'Choose a JPEG, PNG, or WebP image up to 2 MB.'
const MISSING_FILE = 'Choose an image to upload.'

async function resolveUserId(): Promise<string> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: never taken from the browser.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  return userId
}

/**
 * Uploads a new avatar for the authenticated caller and points their own
 * profile row at it. The object path is unique and owner-scoped; the DB write
 * is proven before the previous object is removed. Storage deletes only run
 * against paths that pass isOwnedAvatarPath for this caller.
 */
export async function uploadAvatar(
  _previousState: AvatarActionState,
  formData: FormData
): Promise<AvatarActionState> {
  const userId = await resolveUserId()
  const supabase = await createClient()

  const file = formData.get('avatar')

  if (!(file instanceof File) || file.size === 0) {
    return { error: MISSING_FILE, success: false }
  }

  const mime = file.type

  if (file.size > AVATAR_MAX_BYTES || !isAllowedAvatarMimeType(mime)) {
    return { error: INVALID_FILE, success: false }
  }

  const extension = avatarExtensionForMime(mime)

  const { data: current, error: currentError } = await supabase
    .from('profiles')
    .select('avatar_path')
    .eq('id', userId)
    .maybeSingle()

  if (currentError || !current) {
    return { error: GENERIC_ERROR, success: false }
  }

  const previousPath = current.avatar_path
  const nextPath = `${userId}/avatar-${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 10)}.${extension}`

  const { error: uploadError } = await supabase.storage
    .from(AVATARS_BUCKET)
    .upload(nextPath, file, { contentType: mime, upsert: false })

  if (uploadError) {
    return { error: GENERIC_ERROR, success: false }
  }

  const { data: updated, error: updateError } = await supabase
    .from('profiles')
    .update({ avatar_path: nextPath })
    .eq('id', userId)
    .select('id')
    .maybeSingle()

  if (updateError || !updated) {
    // Best-effort cleanup of the object we just uploaded. Still gated by the
    // invariant that every Storage delete must pass isOwnedAvatarPath.
    if (isOwnedAvatarPath(nextPath, userId)) {
      await supabase.storage.from(AVATARS_BUCKET).remove([nextPath])
    }

    return { error: GENERIC_ERROR, success: false }
  }

  // Only after the row is proven updated, best-effort remove the old object.
  if (
    previousPath &&
    previousPath !== nextPath &&
    isOwnedAvatarPath(previousPath, userId)
  ) {
    await supabase.storage.from(AVATARS_BUCKET).remove([previousPath])
  }

  revalidatePath('/profile')

  return { error: null, success: true }
}

/**
 * Clears the authenticated caller's avatar. The profile row is updated to null
 * and proven first; only then is the previous owned object removed.
 */
export async function removeAvatar(): Promise<AvatarActionState> {
  const userId = await resolveUserId()
  const supabase = await createClient()

  const { data: current, error: currentError } = await supabase
    .from('profiles')
    .select('avatar_path')
    .eq('id', userId)
    .maybeSingle()

  if (currentError || !current) {
    return { error: GENERIC_ERROR, success: false }
  }

  const previousPath = current.avatar_path

  const { data: updated, error: updateError } = await supabase
    .from('profiles')
    .update({ avatar_path: null })
    .eq('id', userId)
    .select('id')
    .maybeSingle()

  if (updateError || !updated) {
    return { error: GENERIC_ERROR, success: false }
  }

  if (previousPath && isOwnedAvatarPath(previousPath, userId)) {
    await supabase.storage.from(AVATARS_BUCKET).remove([previousPath])
  }

  revalidatePath('/profile')

  return { error: null, success: true }
}
