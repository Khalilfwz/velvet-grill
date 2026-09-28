import Link from 'next/link'

export default function ProductNotFound() {
  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-4xl">
        <h1 className="font-display text-4xl font-bold text-foreground">
          Product not found
        </h1>

        <p className="mt-4 max-w-2xl text-zinc-600">
          This item is not available on our menu right now.
        </p>

        <Link
          href="/menu"
          className="mt-6 inline-block font-medium text-brand transition-colors hover:text-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Back to menu
        </Link>
      </div>
    </main>
  )
}
