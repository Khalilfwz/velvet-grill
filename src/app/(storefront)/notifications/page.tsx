import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ReturnLink from '@/components/navigation/ReturnLink'
import NotificationToggle from '@/components/notifications/NotificationToggle'
import PageHeader from '@/components/layout/PageHeader'
import ErrorState from '@/components/layout/ErrorState'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

function formatWhen(value: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(value))
}

export const metadata = {
  title: 'Notifications',
}

export default async function NotificationsPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const claims = data?.claims
  // Ownership comes only from the authoritative session subject, never the
  // browser.
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  if (!userId) {
    redirect('/login')
  }

  // Customer-only surface: resolve the caller's role from their own profile,
  // the same authority the Navbar and admin guard use, and send active admins
  // to the admin destination.
  const { data: profile } = await supabase
    .from('profiles')
    .select('role, is_active')
    .eq('id', userId)
    .maybeSingle()

  if (profile?.role === 'ADMIN' && profile.is_active === true) {
    redirect('/admin/products')
  }

  const { data: notifications, error } = await supabase
    .from('notifications')
    .select('id, type, title, message, order_id, is_read, created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })

  if (error) {
    console.error('Failed to load notifications:', error.code)

    return (
      <main className="min-h-screen bg-background px-6 py-12">
        <div className="mx-auto max-w-3xl">
          <PageHeader title="Notifications" />

          <ErrorState message="Failed to load your notifications." />
        </div>
      </main>
    )
  }

  const rows = notifications ?? []

  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-3xl">
        <PageHeader
          title="Notifications"
          description="Updates about your orders and payments."
        />

        {rows.length === 0 ? (
          <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
            <p className="font-display text-xl font-semibold text-foreground">
              You&apos;re all caught up
            </p>

            <p className="mt-2 text-sm text-zinc-600">
              Order and payment updates will appear here.
            </p>

            <Link
              href="/menu"
              className={`mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
            >
              Browse the menu
            </Link>
          </div>
        ) : (
          <ul className="mt-12 space-y-4">
            {rows.map((notification) => (
              <li
                key={notification.id}
                className={`rounded-xl border border-border bg-surface p-6 shadow-sm ${
                  notification.is_read ? '' : 'border-l-4 border-l-brand'
                }`}
              >
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      {notification.order_id ? (
                        <ReturnLink
                          origin="notifications"
                          href={`/orders/${notification.order_id}`}
                          className={`font-display text-lg font-semibold text-foreground hover:text-brand ${focusClasses}`}
                        >
                          {notification.title}
                        </ReturnLink>
                      ) : (
                        <span className="font-display text-lg font-semibold text-foreground">
                          {notification.title}
                        </span>
                      )}

                      {!notification.is_read && (
                        <span
                          className="rounded-full bg-brand px-2 py-0.5 text-xs font-semibold text-white"
                          aria-label="Unread notification"
                        >
                          Unread
                        </span>
                      )}
                    </div>

                    <p className="mt-2 text-sm text-zinc-600">
                      {notification.message}
                    </p>

                    <time
                      dateTime={notification.created_at}
                      className="mt-2 block text-xs text-zinc-500"
                    >
                      {formatWhen(notification.created_at)}
                    </time>
                  </div>

                  <NotificationToggle
                    notificationId={notification.id}
                    isRead={notification.is_read}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </main>
  )
}
