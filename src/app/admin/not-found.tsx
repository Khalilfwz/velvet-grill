import Link from 'next/link'

/**
 * Admin-context 404. Renders inside the guarded admin shell for authenticated
 * admins (e.g. an unknown product id). The copy stays generic so it reveals
 * nothing privileged if it is ever reached without authorization.
 */
export default function AdminNotFound() {
  return (
    <div className="mx-auto max-w-xl py-16 text-center">
      <h1 className="font-display text-3xl font-bold text-foreground">
        Not found
      </h1>

      <p className="mt-3 text-zinc-600">
        The requested page or record could not be found.
      </p>

      <Link
        href="/admin/products"
        className="mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
      >
        Back to products
      </Link>
    </div>
  )
}
