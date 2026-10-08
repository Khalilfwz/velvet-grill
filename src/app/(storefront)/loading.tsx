export default function StorefrontLoading() {
  return (
    <main className="min-h-screen bg-background px-6 py-12">
      <div className="mx-auto max-w-3xl" aria-hidden="true">
        <div className="animate-pulse space-y-8">
          <div className="h-4 w-24 rounded bg-border/60" />
          <div className="h-10 w-64 rounded-lg bg-border/60" />
          <div className="h-44 rounded-xl border border-border bg-surface" />
        </div>
      </div>
    </main>
  )
}
