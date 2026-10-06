'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type NotificationActionState = {
  error: string | null
}

const GENERIC_ERROR = 'We could not update that notification. Please try again.'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Marks the authenticated customer's own notification read or unread.
 *
 * The browser supplies only the notification id and the target boolean. The
 * recipient is derived from the authoritative session subject, and the write is
 * scoped by both id and user_id. The existing notifications_update_own RLS
 * policy plus the column-level UPDATE (is_read) grant remain the underlying
 * authority; no other notification column is addressable from here.
 */
export async function setNotificationRead(
  _previousState: NotificationActionState,
  formData: FormData
): Promise<NotificationActionState> {
  const notificationId = String(formData.get('notificationId') ?? '').trim()
  const isReadRaw = String(formData.get('isRead') ?? '')

  if (!UUID_PATTERN.test(notificationId)) {
    return { error: GENERIC_ERROR }
  }

  // Accept only the canonical boolean representation.
  if (isReadRaw !== 'true' && isReadRaw !== 'false') {
    return { error: GENERIC_ERROR }
  }

  const isRead = isReadRaw === 'true'

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity is authoritative: user_id is never taken from the form.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Session check stays outside the try so redirect control flow propagates.
  if (!userId) {
    redirect('/login')
  }

  try {
    const { error } = await supabase
      .from('notifications')
      .update({ is_read: isRead })
      .eq('id', notificationId)
      .eq('user_id', userId)

    if (error) {
      return { error: GENERIC_ERROR }
    }
  } catch {
    return { error: GENERIC_ERROR }
  }

  revalidatePath('/notifications')
  // Refresh the storefront layout so the Navbar unread count stays accurate.
  revalidatePath('/', 'layout')

  return { error: null }
}
