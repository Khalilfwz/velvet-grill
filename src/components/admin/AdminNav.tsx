'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Menu } from 'lucide-react'
import { signOut } from '@/lib/auth/actions'

const NAV_GROUPS = [
  {
    label: 'Catalog',
    items: [
      { href: '/admin/categories', label: 'Categories' },
      { href: '/admin/products', label: 'Products' },
    ],
  },
  {
    label: 'Orders',
    items: [
      { href: '/admin/orders', label: 'Orders' },
      { href: '/admin/reviews', label: 'Reviews' },
    ],
  },
  {
    label: 'Venue',
    items: [
      { href: '/admin/tables', label: 'Tables' },
      { href: '/admin/hours', label: 'Hours' },
      { href: '/admin/settings', label: 'Settings' },
    ],
  },
  {
    label: 'Insights',
    items: [
      { href: '/admin/analytics', label: 'Analytics' },
      { href: '/admin/audit', label: 'Audit' },
    ],
  },
] as const

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

function isItemActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`)
}

function desktopLinkClasses(active: boolean): string {
  return `rounded-lg px-2.5 py-1 text-sm font-medium transition-colors ${focusClasses} ${
    active ? 'bg-brand/5 text-brand' : 'text-foreground hover:text-brand'
  }`
}

function drawerLinkClasses(active: boolean): string {
  return `block rounded-lg px-3 py-2 text-sm transition-colors ${focusClasses} ${
    active
      ? 'bg-brand/5 font-medium text-brand'
      : 'text-foreground hover:bg-background'
  }`
}

export default function AdminNav() {
  const pathname = usePathname()

  return (
    <>
      <nav
        aria-label="Admin sections"
        className="hidden items-center gap-1 md:flex"
      >
        {NAV_GROUPS.map((group, index) => (
          <div
            key={group.label}
            className={`flex items-center gap-1 ${index > 0 ? 'ml-2 border-l border-border pl-4' : ''}`}
          >
            {group.items.map((item) => {
              const active = isItemActive(pathname, item.href)

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={active ? 'page' : undefined}
                  className={desktopLinkClasses(active)}
                >
                  {item.label}
                </Link>
              )
            })}
          </div>
        ))}
      </nav>

      <details className="relative md:hidden">
        <summary
          aria-label="Open admin menu"
          className={`flex cursor-pointer list-none items-center justify-center rounded-md p-2 text-foreground ${focusClasses}`}
        >
          <Menu size={20} aria-hidden="true" />
        </summary>

        <div className="absolute right-0 top-full z-10 mt-2 w-56 rounded-xl border border-border bg-surface p-2 shadow-lg">
          {NAV_GROUPS.map((group) => (
            <div key={group.label} className="py-1">
              <p className="px-3 pb-1 text-xs font-medium uppercase tracking-wide text-zinc-500">
                {group.label}
              </p>
              {group.items.map((item) => {
                const active = isItemActive(pathname, item.href)

                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    aria-current={active ? 'page' : undefined}
                    className={drawerLinkClasses(active)}
                  >
                    {item.label}
                  </Link>
                )
              })}
            </div>
          ))}

          <div className="mt-1 border-t border-border pt-2">
            <Link
              href="/menu"
              className={`block rounded-lg px-3 py-2 text-sm text-zinc-600 transition-colors hover:bg-background ${focusClasses}`}
            >
              View site
            </Link>

            <form action={signOut}>
              <button
                type="submit"
                className={`block w-full rounded-lg border border-border px-3 py-2 text-left text-sm font-medium text-foreground transition-colors hover:bg-background ${focusClasses}`}
              >
                Sign out
              </button>
            </form>
          </div>
        </div>
      </details>
    </>
  )
}
