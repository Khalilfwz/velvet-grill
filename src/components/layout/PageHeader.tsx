type PageHeaderProps = {
  title: string
  eyebrow?: string
  description?: string
}

export default function PageHeader({
  title,
  eyebrow = 'Velvet Grill',
  description,
}: PageHeaderProps) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.2em] text-brand">
        {eyebrow}
      </p>

      <h1 className="mt-3 font-display text-4xl font-medium leading-tight tracking-tight text-balance text-foreground sm:text-5xl">
        {title}
      </h1>

      {description && (
        <p className="mt-4 max-w-2xl text-base leading-7 text-zinc-600">
          {description}
        </p>
      )}
    </div>
  )
}
