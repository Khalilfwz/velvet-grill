import { requireAdminPage } from '@/lib/admin/guard'
import CategoryForm from '@/components/admin/CategoryForm'

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
        <h1 className="font-display text-3xl font-bold text-foreground">
          Categories
        </h1>
        <p className="mt-4 text-red-600">Failed to load categories.</p>
      </div>
    )
  }

  const rows = categories ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Categories
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Create and update menu categories.
        </p>
      </div>

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
          <p className="text-sm text-zinc-600">No categories yet.</p>
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
                  {!category.is_active && (
                    <span className="rounded-full bg-border/60 px-2 py-0.5 text-xs text-zinc-600">
                      Inactive
                    </span>
                  )}
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
