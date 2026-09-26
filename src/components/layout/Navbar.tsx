import Link from 'next/link'
import { Heart, ShoppingCart } from 'lucide-react'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default function Navbar() {
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

          <Link
            href="/login"
            className={`rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light ${focusClasses}`}
          >
            Login
          </Link>
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

            <Link
              href="/login"
              className={`block rounded-lg px-3 py-2 text-sm font-medium text-white bg-brand hover:bg-brand-light ${focusClasses}`}
            >
              Login
            </Link>
          </div>
        </details>
      </nav>
    </header>
  )
}
