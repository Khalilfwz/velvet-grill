'use client'

import { useActionState, useId } from 'react'
import { saveProduct, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type ProductFormCategory = {
  id: string
  name: string
}

export type ProductFormInitial = {
  id: string
  name: string
  slug: string
  description: string | null
  categoryId: string
  basePrice: number
  stock: number
  isAvailable: boolean
  isFeatured: boolean
}

const initialState: AdminActionState = { error: null }

export default function ProductForm({
  categories,
  initial,
}: {
  categories: ProductFormCategory[]
  initial?: ProductFormInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveProduct, initialState)

  return (
    <form action={formAction} className="space-y-4">
      {initial && (
        <>
          <input type="hidden" name="id" value={initial.id} />
          <input type="hidden" name="previousSlug" value={initial.slug} />
        </>
      )}

      <div>
        <label className={labelClasses} htmlFor={`${uid}-name`}>
          Name
        </label>
        <input
          id={`${uid}-name`}
          name="name"
          defaultValue={initial?.name ?? ''}
          required
          maxLength={120}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-slug`}>
          Slug
        </label>
        <input
          id={`${uid}-slug`}
          name="slug"
          defaultValue={initial?.slug ?? ''}
          required
          maxLength={80}
          pattern="[a-z0-9]+(-[a-z0-9]+)*"
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-category`}>
          Category
        </label>
        <select
          id={`${uid}-category`}
          name="categoryId"
          defaultValue={initial?.categoryId ?? categories[0]?.id ?? ''}
          required
          className={inputClasses}
        >
          {categories.map((category) => (
            <option key={category.id} value={category.id}>
              {category.name}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-description`}>
          Description
        </label>
        <textarea
          id={`${uid}-description`}
          name="description"
          defaultValue={initial?.description ?? ''}
          maxLength={1000}
          rows={3}
          className={inputClasses}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={labelClasses} htmlFor={`${uid}-base-price`}>
            Base price (IDR)
          </label>
          <input
            id={`${uid}-base-price`}
            name="basePrice"
            type="number"
            min={0}
            step="0.01"
            defaultValue={initial?.basePrice ?? 0}
            required
            className={inputClasses}
          />
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-stock`}>
            Stock
          </label>
          <input
            id={`${uid}-stock`}
            name="stock"
            type="number"
            min={0}
            step={1}
            defaultValue={initial?.stock ?? 0}
            required
            className={inputClasses}
          />
        </div>
      </div>

      <div className="flex flex-wrap gap-6">
        <label className="flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isAvailable"
            defaultChecked={initial?.isAvailable ?? true}
          />
          Available
        </label>

        <label className="flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isFeatured"
            defaultChecked={initial?.isFeatured ?? false}
          />
          Featured
        </label>
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton
        label={initial ? 'Save product' : 'Create product'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
