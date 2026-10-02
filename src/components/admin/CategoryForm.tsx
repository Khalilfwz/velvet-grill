'use client'

import { useActionState, useId } from 'react'
import { saveCategory, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type CategoryFormInitial = {
  id: string
  name: string
  slug: string
  description: string | null
  imagePath: string | null
  sortOrder: number
  isActive: boolean
}

const initialState: AdminActionState = { error: null }

export default function CategoryForm({
  initial,
}: {
  initial?: CategoryFormInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveCategory, initialState)

  return (
    <form action={formAction} className="space-y-4">
      {initial && <input type="hidden" name="id" value={initial.id} />}

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

      <div>
        <label className={labelClasses} htmlFor={`${uid}-image-path`}>
          Image path
        </label>
        <input
          id={`${uid}-image-path`}
          name="imagePath"
          defaultValue={initial?.imagePath ?? ''}
          maxLength={255}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-sort-order`}>
          Sort order
        </label>
        <input
          id={`${uid}-sort-order`}
          name="sortOrder"
          type="number"
          min={0}
          defaultValue={initial?.sortOrder ?? 0}
          className={inputClasses}
        />
      </div>

      <label className="flex items-center gap-2 text-sm text-foreground">
        <input
          type="checkbox"
          name="isActive"
          defaultChecked={initial?.isActive ?? true}
        />
        Active
      </label>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton
        label={initial ? 'Save category' : 'Create category'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
