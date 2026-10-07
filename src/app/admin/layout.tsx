import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import { signOut } from '@/lib/auth/actions'
import AdminNav from '@/components/admin/AdminNav'

export const metadata = {
  title: 'Admin',
}

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default async function AdminLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  await requireAdminPage()

  return (
    <div className="min-h-screen bg-background">
      <div className="border-b border-border bg-surface">
        <nav className="mx-auto flex max-w-6xl items-center gap-4 px-6 py-4">
          <span className="font-display text-xl font-semibold text-brand">
            Admin
          </span>

          <div className="ml-auto flex items-center md:ml-4">
            <AdminNav />
          </div>

          <div className="hidden items-center gap-4 md:flex">
            <Link
              href="/menu"
              className={`text-sm font-medium text-zinc-600 transition-colors hover:text-brand ${focusClasses}`}
            >
              View site
            </Link>

            <form action={signOut}>
              <button
                type="submit"
                className={`rounded-full border border-border px-4 py-1.5 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`}
              >
                Sign out
              </button>
            </form>
          </div>
        </nav>
      </div>

      <main className="mx-auto max-w-6xl px-6 py-8">{children}</main>
    </div>
  )
}
