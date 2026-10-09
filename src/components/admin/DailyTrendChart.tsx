type DailyTrendPoint = {
  day: string
  value: number
}

export default function DailyTrendChart({
  title,
  caption,
  points,
  formatValue,
  emptyNote,
}: {
  title: string
  caption: string
  points: DailyTrendPoint[]
  formatValue: (value: number) => string
  emptyNote?: string
}) {
  // Scale against the series maximum; the floor of 1 keeps an all-zero
  // series from dividing by zero.
  const max = Math.max(...points.map((point) => point.value), 1)

  return (
    <section className="space-y-4">
      <h2 className="font-display text-xl font-semibold text-foreground">
        {title}
      </h2>
      <figure className="space-y-2">
        <figcaption className="sr-only">{caption}</figcaption>
        <div className="overflow-x-auto rounded-xl border border-border bg-surface">
          <div className="flex min-w-max items-end gap-1.5 p-4">
            {points.map((point) => {
              const barHeight =
                point.value > 0
                  ? `${Math.max((point.value / max) * 100, 3)}%`
                  : '2px'

              return (
                <div
                  key={point.day}
                  className="flex min-w-12 flex-none flex-col items-center gap-1 whitespace-nowrap"
                >
                  <span className="text-[10px] leading-none tabular-nums text-zinc-600">
                    {formatValue(point.value)}
                  </span>
                  <div
                    className="flex h-28 w-full items-end"
                    aria-hidden="true"
                  >
                    <div
                      className={`w-full rounded-t ${
                        point.value > 0 ? 'bg-brand' : 'bg-zinc-300'
                      }`}
                      style={{ height: barHeight }}
                    />
                  </div>
                  <span className="text-[10px] leading-none tabular-nums text-zinc-600">
                    {point.day.slice(5)}
                  </span>
                </div>
              )
            })}
          </div>
        </div>
        {emptyNote ? (
          <p className="text-sm text-zinc-600">{emptyNote}</p>
        ) : null}
      </figure>
    </section>
  )
}
