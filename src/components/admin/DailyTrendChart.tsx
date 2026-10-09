type DailyTrendPoint = {
  day: string
  value: number
}

type ChartProps = {
  points: DailyTrendPoint[]
  formatValue: (value: number) => string
  unitLabel?: string
}

function formatFullDate(day: string): string {
  const [year, month, date] = day.split('-').map(Number)

  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'UTC',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(new Date(Date.UTC(year, month - 1, date)))
}

function SingleDaySummary({ points, formatValue, unitLabel }: ChartProps) {
  const [point] = points

  return (
    <div className="rounded-xl border border-border bg-surface p-6">
      <p className="text-sm font-medium text-zinc-600">
        {formatFullDate(point.day)}
      </p>
      <p className="mt-2 flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <span className="break-words font-display text-4xl font-bold tabular-nums text-foreground">
          {formatValue(point.value)}
        </span>
        {unitLabel ? (
          <span className="text-sm text-zinc-600">{unitLabel}</span>
        ) : null}
      </p>
    </div>
  )
}

function DailyBars({ points, formatValue, unitLabel, title }: ChartProps & { title: string }) {
  const dayCount = points.length
  // Scale against the series maximum; the floor of 1 keeps an all-zero
  // series from dividing by zero.
  const max = Math.max(...points.map((point) => point.value), 1)

  // Only short ranges label every bar; dense ranges drop per-bar values
  // (avoiding a wall of "0"/"Rp 0") and thin out date labels instead.
  // Short ranges size columns to their content so long IDR values cannot
  // overlap; dense ranges keep a uniform fixed floor so bars stay even.
  const showValues = dayCount <= 7
  const labelEvery =
    dayCount <= 7 ? 1 : dayCount <= 31 ? 5 : Math.ceil(dayCount / 8)
  const columnMin =
    dayCount <= 7 ? 'min-w-fit' : dayCount <= 31 ? 'min-w-7' : 'min-w-5'
  const gap = dayCount <= 7 ? 'gap-2' : 'gap-1'

  return (
    <div className="overflow-x-auto rounded-xl border border-border bg-surface">
      <ol
        aria-label={`${title} by day`}
        className={`flex w-full items-end ${gap} p-4`}
      >
        {points.map((point, index) => {
          const showLabel = index % labelEvery === 0 || index === dayCount - 1
          const barHeight =
            point.value > 0
              ? `${Math.max((point.value / max) * 100, 3)}%`
              : '2px'
          const accessibleValue = unitLabel
            ? `${formatValue(point.value)} ${unitLabel}`
            : formatValue(point.value)

          return (
            <li
              key={point.day}
              className={`flex ${columnMin} flex-1 flex-col items-center gap-1`}
            >
              <span className="sr-only">{`${formatFullDate(point.day)}: ${accessibleValue}`}</span>
              {showValues ? (
                <span
                  aria-hidden="true"
                  className="whitespace-nowrap text-[10px] leading-none tabular-nums text-zinc-600"
                >
                  {formatValue(point.value)}
                </span>
              ) : null}
              <div aria-hidden="true" className="flex h-28 w-full items-end">
                <div
                  className={`w-full rounded-t ${
                    point.value > 0 ? 'bg-brand' : 'bg-zinc-300'
                  }`}
                  style={{ height: barHeight }}
                />
              </div>
              <span
                aria-hidden="true"
                className="h-4 whitespace-nowrap text-[10px] leading-none tabular-nums text-zinc-600"
              >
                {showLabel ? point.day.slice(5) : ''}
              </span>
            </li>
          )
        })}
      </ol>
    </div>
  )
}

export default function DailyTrendChart({
  title,
  caption,
  points,
  formatValue,
  unitLabel,
}: {
  title: string
  caption: string
} & ChartProps) {
  const dayCount = points.length

  return (
    <section className="space-y-4">
      <h2 className="font-display text-xl font-semibold text-foreground">
        {title}
      </h2>
      <figure className="space-y-3">
        <figcaption className="sr-only">{caption}</figcaption>
        {dayCount === 0 ? (
          <p className="rounded-xl border border-border bg-surface p-6 text-sm text-zinc-600">
            No daily data is available for this range.
          </p>
        ) : dayCount === 1 ? (
          <SingleDaySummary
            points={points}
            formatValue={formatValue}
            unitLabel={unitLabel}
          />
        ) : (
          <DailyBars
            title={title}
            points={points}
            formatValue={formatValue}
            unitLabel={unitLabel}
          />
        )}
      </figure>
    </section>
  )
}
