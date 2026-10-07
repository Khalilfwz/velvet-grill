import Link from 'next/link'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

type ErrorStateProps = {
  message: string
  actionHref?: string
  actionLabel?: string
}

// Page/load/resource-level failure only. Inline form, action, and validation
// errors keep their own role="alert" treatment next to the relevant control.
export default function ErrorState({
  message,
  actionHref = '/menu',
  actionLabel = 'Browse the menu',
}: ErrorStateProps) {
  return (
    <div className="mt-12 rounded-xl border border-border bg-surface p-8 shadow-sm">
      <p className="font-display text-xl font-semibold text-foreground">
        Something went wrong
      </p>

      <p className="mt-2 text-sm text-zinc-600">{message}</p>

      <Link
        href={actionHref}
        className={`mt-6 inline-block rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand ${focusClasses}`}
      >
        {actionLabel}
      </Link>
    </div>
  )
}
