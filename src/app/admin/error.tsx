'use client'

import { useEffect } from 'react'

export default function AdminError({
  error,
  retry,
}: {
  error: Error & { digest?: string }
  retry: () => void
}) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div className="rounded-xl border border-border bg-surface p-8" role="alert">
      <h2 className="font-display text-xl font-semibold text-foreground">
        Something went wrong
      </h2>
      <p className="mt-2 text-sm text-zinc-600">
        This admin page failed to render. Try again, or use the navigation to
        open another section.
      </p>
      <button
        type="button"
        onClick={retry}
        className="mt-4 inline-flex items-center justify-center rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
      >
        Try again
      </button>
    </div>
  )
}
