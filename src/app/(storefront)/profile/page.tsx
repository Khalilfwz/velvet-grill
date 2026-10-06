import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProfileForm from '@/components/profile/ProfileForm'

export const metadata = {
  title: 'Profile',
}

export default async function ProfilePage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Identity and email come only from the authoritative session claims, never
  // from the browser.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null
  const email = typeof claims?.email === 'string' ? claims.email : null

  if (!userId) {
    redirect('/login')
  }

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('full_name, phone, role, is_active')
    .eq('id', userId)
    .maybeSingle()

  // A profiles row is a required 1:1 record, so a missing row is a load
  // failure rather than an empty profile to edit.
  if (error || !profile) {
    console.error(
      'Failed to load profile:',
      error?.code ?? 'missing profile row'
    )

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-md">
          <h1 className="font-display text-4xl font-bold text-foreground">
            Profile
          </h1>

          <p className="mt-4 text-red-600">Failed to load your profile.</p>
        </div>
      </main>
    )
  }

  // Customer-only surface: active admins use the admin panel instead.
  if (profile.role === 'ADMIN' && profile.is_active === true) {
    redirect('/admin/products')
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-md">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-3xl font-bold text-foreground">
          Profile
        </h1>

        <p className="mt-2 text-sm leading-6 text-zinc-600">
          Manage the details associated with your account.
        </p>

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <ProfileForm
            fullName={profile.full_name}
            phone={profile.phone}
            email={email}
          />
        </div>
      </div>
    </main>
  )
}
