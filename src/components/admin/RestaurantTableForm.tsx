'use client'

import { useActionState, useState, useId } from 'react'
import { useFormStatus } from 'react-dom'
import { saveRestaurantTable, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type RestaurantTableFormInitial = {
  id: string
  tableNumber: string
  capacity: number
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

export default function RestaurantTableForm({
  initial,
}: {
  initial?: RestaurantTableFormInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(
    saveRestaurantTable,
    initialState
  )
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

      <div>
        <label className={labelClasses} htmlFor={`${uid}-table-number`}>
          Table number
        </label>
        <input
          id={`${uid}-table-number`}
          name="tableNumber"
          defaultValue={initial?.tableNumber ?? ''}
          required
          maxLength={120}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-capacity`}>
          Capacity
        </label>
        <input
          id={`${uid}-capacity`}
          name="capacity"
          type="number"
          min={1}
          step={1}
          required
          defaultValue={initial?.capacity ?? 2}
          className={inputClasses}
        />
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
        label={initial ? 'Save table' : 'Create table'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
