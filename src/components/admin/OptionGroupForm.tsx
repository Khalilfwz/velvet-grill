'use client'

import { useActionState, useState, useId } from 'react'
import { useFormStatus } from 'react-dom'
import { saveOptionGroup, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type OptionGroupInitial = {
  id: string
  name: string
  selectionType: 'SINGLE' | 'MULTIPLE'
  minSelections: number
  maxSelections: number | null
  isRequired: boolean
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

export default function OptionGroupForm({
  productId,
  productSlug,
  initial,
}: {
  productId: string
  productSlug: string
  initial?: OptionGroupInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveOptionGroup, initialState)
  const [dirty, setDirty] = useState(false)

  function handleSubmit(formData: FormData) {
    setDirty(false)
    formAction(formData)
  }

  return (
    <form
      action={handleSubmit}
      onChange={() => setDirty(true)}
      className="space-y-3"
    >
      <input type="hidden" name="productId" value={productId} />
      <input type="hidden" name="productSlug" value={productSlug} />
      {initial && <input type="hidden" name="id" value={initial.id} />}

      <div>
        <label className={labelClasses} htmlFor={`${uid}-name`}>
          Group name
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

      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <label className={labelClasses} htmlFor={`${uid}-selection-type`}>
            Selection type
          </label>
          <select
            id={`${uid}-selection-type`}
            name="selectionType"
            defaultValue={initial?.selectionType ?? 'SINGLE'}
            className={inputClasses}
          >
            <option value="SINGLE">Single</option>
            <option value="MULTIPLE">Multiple</option>
          </select>
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-min`}>
            Min selections
          </label>
          <input
            id={`${uid}-min`}
            name="minSelections"
            type="number"
            min={0}
            step={1}
            defaultValue={initial?.minSelections ?? 0}
            className={inputClasses}
          />
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-max`}>
            Max selections
          </label>
          <input
            id={`${uid}-max`}
            name="maxSelections"
            type="number"
            min={1}
            step={1}
            defaultValue={initial?.maxSelections ?? ''}
            className={inputClasses}
          />
        </div>
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

      <div className="flex flex-wrap gap-6">
        <label className="flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isRequired"
            defaultChecked={initial?.isRequired ?? false}
            className="focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
          />
          Required
        </label>

        <label className="flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isActive"
            defaultChecked={initial?.isActive ?? true}
            className="focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
          />
          Active
        </label>
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SavedNote saved={state.saved ?? false} dirty={dirty} />

      <SubmitButton
        label={initial ? 'Save group' : 'Add group'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
