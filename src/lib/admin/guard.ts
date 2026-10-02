import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type AdminContext = {
  supabase: Awaited<ReturnType<typeof createClient>>
  userId: string
}

type AdminResolution = AdminContext | 'unauthenticated' | 'forbidden'

async function resolveAdmin(): Promise<AdminResolution> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    return 'unauthenticated'
  }

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('role, is_active')
    .eq('id', userId)
    .maybeSingle()

  if (error || !profile || profile.role !== 'ADMIN' || !profile.is_active) {
    return 'forbidden'
  }

  return { supabase, userId }
}

/**
 * Page-level guard. Unauthenticated visitors are sent to login; authenticated
 * non-admins get a 404 so the admin surface is not disclosed.
 */
export async function requireAdminPage(): Promise<AdminContext> {
  const result = await resolveAdmin()

  if (result === 'unauthenticated') {
    redirect('/login')
  }

  if (result === 'forbidden') {
    notFound()
  }

  return result
}

/**
 * Defensive server-side check for mutations. Returns null for unauthenticated or
 * non-admin callers; the authoritative gate remains the RPC's is_admin() check.
 */
export async function getAdminContext(): Promise<AdminContext | null> {
  const result = await resolveAdmin()

  return result === 'unauthenticated' || result === 'forbidden' ? null : result
}
