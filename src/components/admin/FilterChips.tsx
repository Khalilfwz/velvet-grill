import Link from 'next/link'

export type FilterChipItem = {
  value: string
  label: string
  href: string
}

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default function FilterChips({
  items,
  activeValue,
  ariaLabel,
}: {
  items: FilterChipItem[]
  activeValue: string | null
  ariaLabel: string
}) {
  return (
    <nav
      aria-label={ariaLabel}
      className="flex flex-wrap items-center gap-3 text-sm"
    >
      {items.map((item) => {
        const active = item.value === activeValue

        return (
          <Link
            key={item.value}
            href={item.href}
            aria-current={active ? 'true' : undefined}
            className={`rounded-full border px-3 py-1 font-medium transition-colors ${focusClasses} ${
              active
                ? 'border-brand bg-brand/5 text-brand'
                : 'border-border text-zinc-600 hover:border-brand hover:text-brand'
            }`}
          >
            {item.label}
          </Link>
        )
      })}
    </nav>
  )
}
