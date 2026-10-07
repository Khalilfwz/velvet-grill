import { requireAdminPage } from '@/lib/admin/guard'
import BusinessHoursForm from '@/components/admin/BusinessHoursForm'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import StatusBadge from '@/components/admin/StatusBadge'

export const metadata = {
  title: 'Business hours',
}

const DAY_LABELS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
]

export default async function AdminHoursPage() {
  const { supabase } = await requireAdminPage()

  const { data: hours, error } = await supabase
    .from('business_hours')
    .select('day_of_week, opens_at, closes_at, is_closed')
    .order('day_of_week')

  if (error) {
    console.error('Failed to load business hours:', error)

    return (
      <div>
        <AdminPageHeading
          title="Business hours"
          description="Set the opening hours for each day of the week."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load business hours.
        </p>
      </div>
    )
  }

  const byDay = new Map((hours ?? []).map((row) => [row.day_of_week, row]))

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Business hours"
        description="Set the opening hours for each day of the week."
      />

      <section className="space-y-3">
        {DAY_LABELS.map((label, dayOfWeek) => {
          const row = byDay.get(dayOfWeek)

          return (
            <details
              key={dayOfWeek}
              className="rounded-xl border border-border bg-surface p-4"
            >
              <summary className="flex cursor-pointer flex-wrap items-center gap-3">
                <span className="font-medium text-foreground">{label}</span>
                {row ? (
                  row.is_closed ? (
                    <StatusBadge tone="muted" label="Closed" />
                  ) : (
                    <span className="font-medium text-foreground">
                      {row.opens_at?.slice(0, 5)} – {row.closes_at?.slice(0, 5)}
                    </span>
                  )
                ) : (
                  <span className="text-sm text-zinc-500">Not set</span>
                )}
              </summary>

              <div className="mt-4 max-w-xl">
                <BusinessHoursForm
                  key={`${dayOfWeek}:${row?.is_closed ?? false}:${row?.opens_at ?? ''}:${row?.closes_at ?? ''}`}
                  initial={{
                    dayOfWeek,
                    isClosed: row?.is_closed ?? false,
                    opensAt: row?.opens_at ?? null,
                    closesAt: row?.closes_at ?? null,
                  }}
                />
              </div>
            </details>
          )
        })}
      </section>
    </div>
  )
}
