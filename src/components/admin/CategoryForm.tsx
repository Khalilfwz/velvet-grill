'use client'

import { useActionState, useState, useId } from 'react'
import { useFormStatus } from 'react-dom'
import { saveCategory, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'
import { adminInputClasses, adminLabelClasses } from './form-styles'

const helperClasses = 'mt-1 text-xs text-zinc-500'

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

function SavedNote({ saved, dirty }: { saved: boolean; dirty: boolean }) {
  const { pending } = useFormStatus()

  if (!saved || dirty || pending) {
    return null
  }

  return (
    <p role="status" className="text-sm text-brand">
      Saved.
    </p>
  )
}

export default function CategoryForm({
  initial,
}: {
  initial?: CategoryFormInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveCategory, initialState)
  const [dirty, setDirty] = useState(false)

  function handleSubmit(formData: FormData) {
    setDirty(false)
    formAction(formData)
  }

  return (
    <form
      action={handleSubmit}
      onChange={() => setDirty(true)}
      className="space-y-4"
    >
      {initial && <input type="hidden" name="id" value={initial.id} />}
      {/* Storefront category imagery is derived from product images, so the
          path is no longer editable here. It is still submitted so saving
          another field does not silently clear existing data. */}
      <input
        type="hidden"
        name="imagePath"
        value={initial?.imagePath ?? ''}
      />

      <div>
        <label className={adminLabelClasses} htmlFor={`${uid}-name`}>
          Name
        </label>
        <input
          id={`${uid}-name`}
          name="name"
          defaultValue={initial?.name ?? ''}
          required
          maxLength={120}
          className={adminInputClasses}
        />
      </div>

      <div>
        <label className={adminLabelClasses} htmlFor={`${uid}-slug`}>
          Slug
        </label>
        <input
          id={`${uid}-slug`}
          name="slug"
          defaultValue={initial?.slug ?? ''}
          required
          maxLength={80}
          pattern="[a-z0-9]+(-[a-z0-9]+)*"
          className={adminInputClasses}
        />
      </div>

      <div>
        <label className={adminLabelClasses} htmlFor={`${uid}-description`}>
          Description
        </label>
        <textarea
          id={`${uid}-description`}
          name="description"
          defaultValue={initial?.description ?? ''}
          maxLength={1000}
          rows={3}
          className={adminInputClasses}
        />
      </div>

      <div>
        <label className={adminLabelClasses} htmlFor={`${uid}-sort-order`}>
          Display order
        </label>
        <input
          id={`${uid}-sort-order`}
          name="sortOrder"
          type="number"
          min={0}
          defaultValue={initial?.sortOrder ?? 0}
          className={adminInputClasses}
        />
        <p className={helperClasses}>Lower numbers appear first.</p>
      </div>

      <label className="flex items-center gap-2 text-sm text-foreground">
        <input
          type="checkbox"
          name="isActive"
          defaultChecked={initial?.isActive ?? true}
          className="focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        />
        Active
      </label>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SavedNote saved={state.saved ?? false} dirty={dirty} />

      <SubmitButton
        label={initial ? 'Save category' : 'Create category'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
