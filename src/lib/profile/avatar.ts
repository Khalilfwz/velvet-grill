import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

export const AVATARS_BUCKET = 'avatars'

export const AVATAR_MAX_BYTES = 2 * 1024 * 1024

export const AVATAR_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
] as const

export type AvatarMimeType = (typeof AVATAR_MIME_TYPES)[number]

// The object extension is derived from the validated MIME type, never from the
// uploaded filename.
const AVATAR_EXTENSION_BY_MIME: Record<AvatarMimeType, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
}

export function isAllowedAvatarMimeType(
  value: string
): value is AvatarMimeType {
  return (AVATAR_MIME_TYPES as readonly string[]).includes(value)
}

export function avatarExtensionForMime(mime: AvatarMimeType): string {
  return AVATAR_EXTENSION_BY_MIME[mime]
}

/**
 * A path is owned by the caller only when it sits under the caller's own
 * `<userId>/` folder and contains no traversal segments. Used before any
 * Storage delete so a client-supplied or stale path can never reach another
 * user's object.
 */
export function isOwnedAvatarPath(path: string, userId: string): boolean {
  if (!path.startsWith(`${userId}/`)) {
    return false
  }

  return !path.split('/').includes('..')
}

export function getAvatarUrl(
  supabase: SupabaseClient<Database>,
  storagePath: string
): string {
  return supabase.storage.from(AVATARS_BUCKET).getPublicUrl(storagePath).data
    .publicUrl
}
