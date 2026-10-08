'use client'

import { useActionState, useState, useId } from 'react'
import { useFormStatus } from 'react-dom'
import { saveOption, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type OptionInitial = {
  id: string
  name: string
  priceDelta: number
  isAvailable: boolean
  sortOrder: number
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

export default function OptionForm({
  productId,
  productSlug,
  groupId,
  initial,
}: {
  productId: string
  productSlug: string
  groupId: string
  initial?: OptionInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveOption, initialState)
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
      <input type="hidden" name="groupId" value={groupId} />
      {initial && <input type="hidden" name="id" value={initial.id} />}

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={labelClasses} htmlFor={`${uid}-name`}>
            Option name
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
          <label className={labelClasses} htmlFor={`${uid}-price-delta`}>
            Price delta (IDR)
          </label>
          <input
            id={`${uid}-price-delta`}
            name="priceDelta"
            type="number"
            step="0.01"
            defaultValue={initial?.priceDelta ?? 0}
            className={inputClasses}
          />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
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

        <label className="mt-6 flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isAvailable"
            defaultChecked={initial?.isAvailable ?? true}
            className="focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
          />
          Available
        </label>
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SavedNote saved={state.saved ?? false} dirty={dirty} />

      <SubmitButton
        label={initial ? 'Save option' : 'Add option'}
        pendingLabel="Saving…"
      />
    </form>
  )
}
