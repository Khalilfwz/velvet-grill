import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import AuthForm from '@/components/auth/AuthForm'

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>
}) {
  const params = await searchParams

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()

  if (data?.claims) {
    redirect('/')
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-md">
        <p className="text-sm font-medium uppercase tracking-widest text-brand">
          Velvet Grill
        </p>

        <h1 className="mt-2 font-display text-3xl font-bold text-foreground">
          Sign in
        </h1>

        <p className="mt-2 text-sm leading-6 text-zinc-600">
          Sign in to manage your account, wishlist, and orders.
        </p>

        {params.error === 'confirmation' && (
          <p
            role="alert"
            className="mt-6 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"
          >
            That confirmation link is invalid or has expired. Sign in, or
            register again to get a new link.
          </p>
        )}

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <AuthForm mode="login" />
        </div>
      </div>
    </main>
  )
}
