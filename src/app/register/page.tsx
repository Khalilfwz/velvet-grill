import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import AuthForm from '@/components/auth/AuthForm'

export default async function RegisterPage() {
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
          Create an account
        </h1>

        <p className="mt-2 text-sm leading-6 text-zinc-600">
          Register with your email address to start an account.
        </p>

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <AuthForm mode="register" />
        </div>
      </div>
    </main>
  )
}
