// Restrained tones drawn only from the existing palette. The label text is
// always present, so state is never communicated by color alone.
const TONE_CLASSES = {
  neutral: 'border-border bg-surface text-foreground',
  brand: 'border-brand/30 bg-brand/5 text-brand',
  muted: 'border-transparent bg-border/60 text-zinc-600',
  danger: 'border-red-200 bg-red-50 text-red-700',
} as const

export type StatusBadgeTone = keyof typeof TONE_CLASSES

export default function StatusBadge({
  label,
  tone = 'neutral',
}: {
  label: string
  tone?: StatusBadgeTone
}) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${TONE_CLASSES[tone]}`}
    >
      {label}
    </span>
  )
}
