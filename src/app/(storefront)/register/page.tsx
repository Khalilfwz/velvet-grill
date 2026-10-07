import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import AuthForm from '@/components/auth/AuthForm'
import PageHeader from '@/components/layout/PageHeader'

export const metadata = {
  title: 'Create account',
}

export default async function RegisterPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()

  if (data?.claims) {
    redirect('/')
  }

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-md">
        <PageHeader
          title="Create an account"
          description="Register with your email address to start an account."
        />

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <AuthForm mode="register" />
        </div>
      </div>
    </main>
  )
}
