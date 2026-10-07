import { requireAdminPage } from '@/lib/admin/guard'
import CategoryForm from '@/components/admin/CategoryForm'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import StatusBadge from '@/components/admin/StatusBadge'

export const metadata = {
  title: 'Categories',
}

export default async function AdminCategoriesPage() {
  const { supabase } = await requireAdminPage()

  const { data: categories, error } = await supabase
    .from('categories')
    .select('id, name, slug, description, image_path, sort_order, is_active')
    .order('sort_order')
    .order('name')

  if (error) {
    console.error('Failed to load admin categories:', error)

    return (
      <div>
        <AdminPageHeading
          title="Categories"
          description="Create and update menu categories."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load categories.
        </p>
      </div>
    )
  }

  const rows = categories ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Categories"
        description="Create and update menu categories."
      />

      <section className="rounded-xl border border-border bg-surface p-6">
        <h2 className="font-display text-xl font-semibold text-brand">
          New category
        </h2>

        <div className="mt-4 max-w-xl">
          <CategoryForm />
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-xl font-semibold text-brand">
          All categories
        </h2>

        {rows.length === 0 ? (
          <EmptyState message="No categories yet." />
        ) : (
          <div className="space-y-3">
            {rows.map((category) => (
              <details
                key={category.id}
                className="rounded-xl border border-border bg-surface p-4"
              >
                <summary className="flex cursor-pointer flex-wrap items-center gap-3">
                  <span className="font-medium text-foreground">
                    {category.name}
                  </span>
                  <span className="text-sm text-zinc-500">/{category.slug}</span>
                  <StatusBadge
                    label={category.is_active ? 'Active' : 'Inactive'}
                    tone={category.is_active ? 'neutral' : 'muted'}
                  />
                </summary>

                <div className="mt-4 max-w-xl">
                  <CategoryForm
                    initial={{
                      id: category.id,
                      name: category.name,
                      slug: category.slug,
                      description: category.description,
                      imagePath: category.image_path,
                      sortOrder: category.sort_order,
                      isActive: category.is_active,
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
