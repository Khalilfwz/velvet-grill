import ForgotPasswordForm from '@/components/auth/ForgotPasswordForm'
import PageHeader from '@/components/layout/PageHeader'

export const metadata = {
  title: 'Forgot password',
}

export default function ForgotPasswordPage() {
  // Deliberately no authenticated redirect: requesting another reset email
  // is harmless, and the form itself discloses nothing about accounts.
  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-md">
        <PageHeader
          title="Forgot password"
          description="Request a link to set a new password for your account."
        />

        <div className="mt-8 rounded-xl border border-border bg-surface p-6 shadow-sm">
          <ForgotPasswordForm />
        </div>
      </div>
    </main>
  )
}
