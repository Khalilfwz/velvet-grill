import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import { signOut } from '@/lib/auth/actions'
import SignOutButton from '@/components/auth/SignOutButton'
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
      <a
        href="#main-content"
        className={`sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-lg focus:border focus:border-border focus:bg-surface focus:px-4 focus:py-2 focus:text-sm focus:font-medium focus:text-foreground focus:shadow-sm ${focusClasses}`}
      >
        Skip to content
      </a>

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
              <SignOutButton
                className={`rounded-full border border-border px-4 py-1.5 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`}
              />
            </form>
          </div>
        </nav>
      </div>

      <main
        id="main-content"
        tabIndex={-1}
        className="mx-auto max-w-6xl px-6 py-8 outline-none"
      >
        {children}
      </main>
    </div>
  )
}
