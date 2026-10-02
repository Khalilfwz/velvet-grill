'use client'

import { useActionState, useId } from 'react'
import {
  saveRestaurantSettings,
  type AdminActionState,
} from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type RestaurantSettingsFormInitial = {
  restaurantName: string
  address: string | null
  phone: string | null
  timezone: string
}

const initialState: AdminActionState = { error: null }

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

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <label className={labelClasses} htmlFor={`${uid}-name`}>
          Restaurant name
        </label>
        <input
          id={`${uid}-name`}
          name="restaurantName"
          defaultValue={initial.restaurantName}
          required
          maxLength={120}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-address`}>
          Address
        </label>
        <textarea
          id={`${uid}-address`}
          name="address"
          defaultValue={initial.address ?? ''}
          maxLength={1000}
          rows={3}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-phone`}>
          Phone
        </label>
        <input
          id={`${uid}-phone`}
          name="phone"
          defaultValue={initial.phone ?? ''}
          maxLength={32}
          className={inputClasses}
        />
      </div>

      <div>
        <label className={labelClasses} htmlFor={`${uid}-timezone`}>
          Timezone
        </label>
        <input
          id={`${uid}-timezone`}
          name="timezone"
          defaultValue={initial.timezone}
          required
          maxLength={120}
          className={inputClasses}
        />
      </div>

      <p className="text-sm text-zinc-600">Currency: IDR (fixed)</p>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SubmitButton label="Save settings" pendingLabel="Saving…" />
    </form>
  )
}
