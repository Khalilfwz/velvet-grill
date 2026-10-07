export default function EmptyState({ message }: { message: string }) {
  return (
    <div className="rounded-xl border border-border bg-surface p-8">
      <p className="text-center text-sm text-zinc-600">{message}</p>
    </div>
  )
}
