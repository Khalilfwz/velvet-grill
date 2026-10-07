import { requireAdminPage } from '@/lib/admin/guard'
import RestaurantTableForm from '@/components/admin/RestaurantTableForm'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import StatusBadge from '@/components/admin/StatusBadge'

export const metadata = {
  title: 'Tables',
}

export default async function AdminTablesPage() {
  const { supabase } = await requireAdminPage()

  const { data: tables, error } = await supabase
    .from('restaurant_tables')
    .select('id, table_number, capacity, is_active')
    .order('table_number')

  if (error) {
    console.error('Failed to load admin tables:', error)

    return (
      <div>
        <AdminPageHeading
          title="Tables"
          description="Create and update dine-in tables."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load tables.
        </p>
      </div>
    )
  }

  const rows = tables ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Tables"
        description="Create and update dine-in tables."
      />

      <section className="rounded-xl border border-border bg-surface p-6">
        <h2 className="font-display text-xl font-semibold text-brand">
          New table
        </h2>

        <div className="mt-4 max-w-xl">
          <RestaurantTableForm />
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-xl font-semibold text-brand">
          All tables
        </h2>

        {rows.length === 0 ? (
          <EmptyState message="No tables yet." />
        ) : (
          <div className="space-y-3">
            {rows.map((table) => (
              <details
                key={table.id}
                className="rounded-xl border border-border bg-surface p-4"
              >
                <summary className="flex cursor-pointer flex-wrap items-center gap-3">
                  <span className="font-medium text-foreground">
                    {table.table_number}
                  </span>
                  <span className="text-sm text-zinc-500">
                    Capacity {table.capacity}
                  </span>
                  <StatusBadge
                    label={table.is_active ? 'Active' : 'Inactive'}
                    tone={table.is_active ? 'neutral' : 'muted'}
                  />
                </summary>

                <div className="mt-4 max-w-xl">
                  <RestaurantTableForm
                    initial={{
                      id: table.id,
                      tableNumber: table.table_number,
                      capacity: table.capacity,
                      isActive: table.is_active,
                    }}
                  />
                </div>
              </details>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
