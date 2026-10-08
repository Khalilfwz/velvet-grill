'use client'

import { useEffect } from 'react'

export default function StorefrontError({
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
    <main className="min-h-screen bg-background px-6 py-12">
      <div
        className="mx-auto max-w-3xl rounded-xl border border-border bg-surface p-8 shadow-sm"
        role="alert"
      >
        <h2 className="font-display text-xl font-semibold text-foreground">
          Something went wrong
        </h2>

        <p className="mt-2 text-sm text-zinc-600">
          This page failed to render. Try again, or use the navigation to open
          another section.
        </p>

        <button
          type="button"
          onClick={retry}
          className="mt-4 inline-flex items-center justify-center rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        >
          Try again
        </button>
      </div>
    </main>
  )
}
