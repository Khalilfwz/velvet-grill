'use client'

import { useActionState, useState, useId } from 'react'
import { useFormStatus } from 'react-dom'
import {
  saveRestaurantSettings,
  type AdminActionState,
} from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'
import { adminInputClasses, adminLabelClasses } from './form-styles'

const groupClasses = 'text-sm font-semibold text-foreground'

export type RestaurantSettingsFormInitial = {
  restaurantName: string
  address: string | null
  phone: string | null
  timezone: string
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

export default function RestaurantSettingsForm({
  initial,
}: {
  initial: RestaurantSettingsFormInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(
    saveRestaurantSettings,
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
      className="space-y-6"
    >
      <fieldset className="space-y-4">
        <legend className={groupClasses}>Restaurant</legend>

        <div>
          <label className={adminLabelClasses} htmlFor={`${uid}-name`}>
            Restaurant name
          </label>
          <input
            id={`${uid}-name`}
            name="restaurantName"
            defaultValue={initial.restaurantName}
            readOnly
            required
            maxLength={120}
            className={adminInputClasses}
          />
          <p className="mt-1 text-xs text-zinc-500">
            The Velvet Grill brand name is fixed and cannot be changed here.
          </p>
        </div>
      </fieldset>

      <fieldset className="space-y-4">
        <legend className={groupClasses}>Contact &amp; locale</legend>

        <div>
          <label className={adminLabelClasses} htmlFor={`${uid}-address`}>
            Address
          </label>
          <textarea
            id={`${uid}-address`}
            name="address"
            defaultValue={initial.address ?? ''}
            maxLength={1000}
            rows={3}
            className={adminInputClasses}
          />
        </div>

        <div>
          <label className={adminLabelClasses} htmlFor={`${uid}-phone`}>
            Phone
          </label>
          <input
            id={`${uid}-phone`}
            name="phone"
            defaultValue={initial.phone ?? ''}
            maxLength={32}
            className={adminInputClasses}
          />
        </div>

        <div>
          <label className={adminLabelClasses} htmlFor={`${uid}-timezone`}>
            Timezone
          </label>
          <input
            id={`${uid}-timezone`}
            name="timezone"
            defaultValue={initial.timezone}
            required
            maxLength={120}
            className={adminInputClasses}
          />
        </div>

        <p className="text-sm text-zinc-600">Currency: IDR (fixed)</p>
      </fieldset>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SavedNote saved={state.saved ?? false} dirty={dirty} />

      <SubmitButton label="Save settings" pendingLabel="Saving…" />
    </form>
  )
}
