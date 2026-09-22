import Link from 'next/link'
import { Heart, ShoppingCart } from 'lucide-react'

export default function Navbar() {
  return (
    <header className="border-b border-border bg-surface">
      <nav className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
        <Link
          href="/"
          className="font-display text-2xl font-semibold text-brand"
        >
          Velvet Grill
        </Link>

        <div className="hidden items-center gap-8 md:flex">
          <Link
            href="/menu"
            className="text-sm font-medium text-foreground transition-colors hover:text-brand"
          >
            Menu
          </Link>

          <Link
            href="/about"
            className="text-sm font-medium text-foreground transition-colors hover:text-brand"
          >
            About
          </Link>

          <Link
            href="/wishlist"
            className="transition-colors hover:text-brand"
            aria-label="Wishlist"
          >
            <Heart size={20} />
          </Link>

          <Link
            href="/cart"
            className="transition-colors hover:text-brand"
            aria-label="Cart"
          >
            <ShoppingCart size={20} />
          </Link>

          <Link
            href="/login"
            className="rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light"
          >
            Login
          </Link>
        </div>
      </nav>
    </header>
  )
}
