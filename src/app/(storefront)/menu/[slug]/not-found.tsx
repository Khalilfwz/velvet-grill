import Link from 'next/link'

export default function ProductNotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-background px-6 py-16 text-center">
      <p className="text-sm font-medium uppercase tracking-widest text-brand">
        Velvet Grill
      </p>

      <h1 className="mt-3 font-display text-4xl font-bold text-foreground">
        Product not found
      </h1>

      <p className="mt-4 max-w-md text-zinc-600">
        This item is not available on our menu right now.
      </p>

      <div className="mt-8 flex flex-wrap justify-center gap-4">
        <Link
          href="/menu"
          className="rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Back to menu
        </Link>

        <Link
          href="/"
          className="rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Back to home
        </Link>
      </div>
    </main>
  )
}
