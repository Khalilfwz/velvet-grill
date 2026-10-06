import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProfileForm from '@/components/profile/ProfileForm'
import AvatarForm from '@/components/profile/AvatarForm'
import EmailChangeForm from '@/components/profile/EmailChangeForm'
import { getAvatarUrl } from '@/lib/profile/avatar'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export const metadata = {
  title: 'Profile',
}

export default async function ProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; email?: string }>
}) {
  const params = await searchParams
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
    .select('full_name, phone, avatar_path, role')
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

  // Account surface for both CUSTOMER and ADMIN. role/is_active are never
  // editable here.
  const isCustomer = profile.role === 'CUSTOMER'

  const avatarUrl = profile.avatar_path
    ? getAvatarUrl(supabase, profile.avatar_path)
    : null

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

        {params.error && (
          <p
            role="alert"
            className="mt-6 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"
          >
            We couldn&apos;t confirm that change. Please try again.
          </p>
        )}

        {params.email === 'pending' && (
          <p
            role="status"
            className="mt-6 rounded-lg border border-border bg-surface p-3 text-sm font-medium text-brand"
          >
            Email confirmation received. Complete the confirmation sent to the
            other email address.
          </p>
        )}

        {params.email === 'updated' && (
          <p
            role="status"
            className="mt-6 rounded-lg border border-border bg-surface p-3 text-sm font-medium text-brand"
          >
            Your email was updated.
          </p>
        )}

        <div className="mt-8 space-y-6">
          <section className="rounded-xl border border-border bg-surface p-6 shadow-sm">
            <h2 className="font-display text-xl font-semibold text-foreground">
              Photo
            </h2>
            <div className="mt-4">
              <AvatarForm avatarUrl={avatarUrl} />
            </div>
          </section>

          <section className="rounded-xl border border-border bg-surface p-6 shadow-sm">
            <h2 className="font-display text-xl font-semibold text-foreground">
              Details
            </h2>
            <div className="mt-4">
              <ProfileForm
                fullName={profile.full_name}
                phone={profile.phone}
                isCustomer={isCustomer}
              />
            </div>
          </section>

          <section className="rounded-xl border border-border bg-surface p-6 shadow-sm">
            <h2 className="font-display text-xl font-semibold text-foreground">
              Email
            </h2>
            <div className="mt-4">
              <EmailChangeForm currentEmail={email} />
            </div>
          </section>

          {isCustomer && (
            <Link
              href="/orders"
              className={`inline-block text-sm font-medium text-brand transition-colors hover:text-brand-light ${focusClasses}`}
            >
              View my orders →
            </Link>
          )}
        </div>
      </div>
    </main>
  )
}
