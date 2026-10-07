export default function AdminLoading() {
  return (
    <div className="animate-pulse space-y-8" aria-hidden="true">
      <div className="h-7 w-48 rounded-lg bg-border/60" />
      <div className="h-32 rounded-xl border border-border bg-surface" />
      <div className="h-64 rounded-xl border border-border bg-surface" />
    </div>
  )
}
