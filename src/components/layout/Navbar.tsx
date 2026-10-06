import Link from 'next/link'
import { Bell, Heart, ShoppingCart, User } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { signOut } from '@/lib/auth/actions'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const loginLinkClasses = `rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`

const signOutButtonClasses = `rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`

export default async function Navbar() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()

  const claims = data?.claims
  const email = typeof claims?.email === 'string' ? claims.email : null
  const userId = typeof claims?.sub === 'string' ? claims.sub : null

  // Reuse the existing session/profile pattern: the role comes from the caller's
  // own profile row, the same source the /admin guard reads. Guests and
  // customers resolve to false, so only active admins see the entry.
  let isAdmin = false

  if (userId) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('role, is_active')
      .eq('id', userId)
      .maybeSingle()

    isAdmin = profile?.role === 'ADMIN' && profile.is_active === true
  }

  // Unread notification count for the customer entry. RLS already scopes rows
  // to the caller; the explicit user_id filter is defence-in-depth. The
  // (user_id, is_read) index supports this head-only count.
  let unreadCount = 0

  if (userId && !isAdmin) {
    const { count } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('is_read', false)

    unreadCount = count ?? 0
  }

  return (
    <header className="border-b border-border bg-surface">
      <nav className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
        <Link
          href="/"
          className={`font-display text-2xl font-semibold text-brand ${focusClasses}`}
        >
          Velvet Grill
        </Link>

        <div className="hidden items-center gap-8 md:flex">
          <Link
            href="/menu"
            className={`text-sm font-medium text-foreground transition-colors hover:text-brand ${focusClasses}`}
          >
            Menu
          </Link>

          <Link
            href="/about"
            className={`text-sm font-medium text-foreground transition-colors hover:text-brand ${focusClasses}`}
          >
            About
          </Link>

          <Link
            href="/wishlist"
            className={`transition-colors hover:text-brand ${focusClasses}`}
            aria-label="Wishlist"
          >
            <Heart size={20} />
          </Link>

          <Link
            href="/cart"
            className={`transition-colors hover:text-brand ${focusClasses}`}
            aria-label="Cart"
          >
            <ShoppingCart size={20} />
          </Link>

          {email ? (
            <div className="flex items-center gap-4">
              {!isAdmin && (
                <Link
                  href="/orders"
                  className={`text-sm font-medium text-foreground transition-colors hover:text-brand ${focusClasses}`}
                >
                  My Orders
                </Link>
              )}

              {!isAdmin && (
                <Link
                  href="/notifications"
                  aria-label={
                    unreadCount > 0
                      ? `Notifications (${unreadCount} unread)`
                      : 'Notifications'
                  }
                  className={`relative transition-colors hover:text-brand ${focusClasses}`}
                >
                  <Bell size={20} />

                  {unreadCount > 0 && (
                    <span className="absolute -right-2 -top-2 min-w-[1rem] rounded-full bg-brand px-1 text-center text-[10px] font-semibold leading-4 text-white">
                      {unreadCount > 99 ? '99+' : unreadCount}
                    </span>
                  )}
                </Link>
              )}

              {!isAdmin && (
                <Link
                  href="/profile"
                  aria-label="Profile"
                  className={`transition-colors hover:text-brand ${focusClasses}`}
                >
                  <User size={20} />
                </Link>
              )}

              {isAdmin && (
                <Link
                  href="/admin/products"
                  className={`rounded-full border border-brand px-4 py-1.5 text-sm font-medium text-brand transition-colors hover:bg-brand hover:text-white ${focusClasses}`}
                >
                  Admin
                </Link>
              )}

              <span
                className="max-w-[12rem] truncate text-sm text-zinc-600"
                title={email}
              >
                {email}
              </span>

              <form action={signOut}>
                <button type="submit" className={signOutButtonClasses}>
                  Sign out
                </button>
              </form>
            </div>
          ) : (
            <Link href="/login" className={loginLinkClasses}>
              Login
            </Link>
          )}
        </div>

        <details className="relative md:hidden">
          <summary
            className={`cursor-pointer list-none rounded-md px-3 py-2 text-sm font-medium text-foreground ${focusClasses}`}
          >
            Menu
          </summary>

          <div className="absolute right-0 top-full z-10 mt-2 w-48 rounded-xl border border-border bg-surface p-2 shadow-lg">
            <Link
              href="/menu"
              className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
            >
              Menu
            </Link>

            <Link
              href="/about"
              className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
            >
              About
            </Link>

            <Link
              href="/wishlist"
              className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
            >
              Wishlist
            </Link>

            <Link
              href="/cart"
              className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
            >
              Cart
            </Link>

            {email ? (
              <>
                {!isAdmin && (
                  <Link
                    href="/orders"
                    className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
                  >
                    My Orders
                  </Link>
                )}

                {!isAdmin && (
                  <Link
                    href="/notifications"
                    className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
                  >
                    {unreadCount > 0
                      ? `Notifications (${unreadCount})`
                      : 'Notifications'}
                  </Link>
                )}

                {!isAdmin && (
                  <Link
                    href="/profile"
                    className={`block rounded-lg px-3 py-2 text-sm text-foreground hover:bg-background ${focusClasses}`}
                  >
                    Profile
                  </Link>
                )}

                {isAdmin && (
                  <Link
                    href="/admin/products"
                    className={`block rounded-lg px-3 py-2 text-sm font-medium text-brand hover:bg-background ${focusClasses}`}
                  >
                    Admin panel
                  </Link>
                )}

                <p className="truncate px-3 py-2 text-sm text-zinc-600" title={email}>
                  {email}
                </p>

                <form action={signOut}>
                  <button
                    type="submit"
                    className={`block w-full rounded-lg border border-border px-3 py-2 text-left text-sm font-medium text-foreground hover:bg-background ${focusClasses}`}
                  >
                    Sign out
                  </button>
                </form>
              </>
            ) : (
              <Link
                href="/login"
                className={`block rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-light ${focusClasses}`}
              >
                Login
              </Link>
            )}
          </div>
        </details>
      </nav>
    </header>
  )
}
