export type AnalyticsRangePreset = 'today' | '7d' | '30d'

export type AnalyticsRange = {
  from: string
  to: string
}

type AnalyticsRangeOption = {
  value: AnalyticsRangePreset
  label: string
  days: number
}

export const ANALYTICS_RANGE_OPTIONS: AnalyticsRangeOption[] = [
  { value: 'today', label: 'Today', days: 1 },
  { value: '7d', label: '7 days', days: 7 },
  { value: '30d', label: '30 days', days: 30 },
]

const FALLBACK_TIME_ZONE = 'Asia/Jakarta'

function shiftIsoDate(iso: string, deltaDays: number): string {
  const [year, month, day] = iso.split('-').map(Number)
  const shifted = new Date(Date.UTC(year, month - 1, day) + deltaDays * 86400000)

  return shifted.toISOString().slice(0, 10)
}

/**
 * Current calendar date in a named IANA time zone, as YYYY-MM-DD.
 * The zone must come from server-side restaurant_settings; never the browser.
 */
export function todayInTimeZone(timeZone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone }).format(new Date())
  } catch {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: FALLBACK_TIME_ZONE,
    }).format(new Date())
  }
}

export function rangeForPreset(
  preset: AnalyticsRangePreset,
  todayIso: string
): AnalyticsRange {
  const option = ANALYTICS_RANGE_OPTIONS.find((item) => item.value === preset)
  const days = option ? option.days : 7

  return { from: shiftIsoDate(todayIso, -(days - 1)), to: todayIso }
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

/**
 * Accepts a YYYY-MM-DD string only when it is a real calendar date.
 * Anything else returns null so the caller can fall back to a default range.
 */
export function parseIsoDate(value: unknown): string | null {
  if (typeof value !== 'string' || !ISO_DATE.test(value)) {
    return null
  }

  const [year, month, day] = value.split('-').map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null
  }

  return value
}

export function isoDaySpan(from: string, to: string): number {
  const [fy, fm, fd] = from.split('-').map(Number)
  const [ty, tm, td] = to.split('-').map(Number)

  return (
    (Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / 86400000
  )
}
