import { requireAdminPage } from '@/lib/admin/guard'
import RestaurantTableForm from '@/components/admin/RestaurantTableForm'

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
        <h1 className="font-display text-3xl font-bold text-foreground">Tables</h1>
        <p className="mt-4 text-red-600">Failed to load tables.</p>
      </div>
    )
  }

  const rows = tables ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">Tables</h1>
        <p className="mt-2 text-sm text-zinc-600">
          Create and update dine-in tables.
        </p>
      </div>

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
          <p className="text-sm text-zinc-600">No tables yet.</p>
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
                  {!table.is_active && (
                    <span className="rounded-full bg-border/60 px-2 py-0.5 text-xs text-zinc-600">
                      Inactive
                    </span>
                  )}
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
