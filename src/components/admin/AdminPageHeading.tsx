export default function AdminPageHeading({
  title,
  description,
}: {
  title: string
  description: string
}) {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold text-foreground">
        {title}
      </h1>
      <p className="mt-1 text-sm text-zinc-600">{description}</p>
    </div>
  )
}
