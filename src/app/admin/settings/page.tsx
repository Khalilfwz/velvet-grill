import { requireAdminPage } from '@/lib/admin/guard'
import RestaurantSettingsForm from '@/components/admin/RestaurantSettingsForm'
import AdminPageHeading from '@/components/admin/AdminPageHeading'

export const metadata = {
  title: 'Settings',
}

export default async function AdminSettingsPage() {
  const { supabase } = await requireAdminPage()

  const { data: settings, error } = await supabase
    .from('restaurant_settings')
    .select('restaurant_name, address, phone, timezone')
    .eq('id', 1)
    .maybeSingle()

  if (error) {
    console.error('Failed to load restaurant settings:', error)

    return (
      <div>
        <AdminPageHeading
          title="Settings"
          description="Update the restaurant contact details."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load restaurant settings.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Settings"
        description="Update the restaurant contact details."
      />

      <section className="rounded-xl border border-border bg-surface p-6">
        <div className="max-w-2xl">
          <RestaurantSettingsForm
            initial={{
              restaurantName: settings?.restaurant_name ?? 'Velvet Grill',
              address: settings?.address ?? null,
              phone: settings?.phone ?? null,
              timezone: settings?.timezone ?? 'Asia/Jakarta',
            }}
          />
        </div>
      </section>
    </div>
  )
}
