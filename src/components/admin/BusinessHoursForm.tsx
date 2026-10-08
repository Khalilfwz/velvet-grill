'use client'

import { useActionState, useState, useId, useRef } from 'react'
import { useFormStatus } from 'react-dom'
import { saveBusinessHours, type AdminActionState } from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand disabled:cursor-not-allowed disabled:opacity-60'
const labelClasses = 'block text-sm font-medium text-foreground'

export type BusinessHoursFormInitial = {
  dayOfWeek: number
  isClosed: boolean
  opensAt: string | null
  closesAt: string | null
}

const initialState: AdminActionState = { error: null }

function toTimeInput(value: string | null): string {
  return value?.slice(0, 5) ?? ''
}

// Closed days persist null times; open days persist both times.
function timeState(isClosed: boolean, value: string | null): string {
  return isClosed ? '' : toTimeInput(value)
}

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

/**
 * Edit state is seeded from the persisted props. The parent gives this component
 * a key derived from the persisted row, so a successful save (which revalidates
 * the route and refreshes props) remounts it with the latest database values.
 * Unsaved edits never change the persisted props, so the instance stays mounted
 * and normal editing/toggling is preserved.
 */
export default function BusinessHoursForm({
  initial,
}: {
  initial: BusinessHoursFormInitial
}) {
  const uid = useId()
  const {
    dayOfWeek,
    isClosed: persistedClosed,
    opensAt: persistedOpensAt,
    closesAt: persistedClosesAt,
  } = initial

  const [state, formAction] = useActionState(saveBusinessHours, initialState)
  const [dirty, setDirty] = useState(false)

  function handleSubmit(formData: FormData) {
    setDirty(false)
    formAction(formData)
  }

  const [isClosed, setIsClosed] = useState(persistedClosed)
  const [opensAt, setOpensAt] = useState(
    timeState(persistedClosed, persistedOpensAt)
  )
  const [closesAt, setClosesAt] = useState(
    timeState(persistedClosed, persistedClosesAt)
  )

  // In-session buffer so unchecking Closed before saving restores the times the
  // admin just cleared. Never persisted and never used to recover old hours.
  const rememberedTimes = useRef<{ opensAt: string; closesAt: string } | null>(
    null
  )

  function handleClosedChange(checked: boolean) {
    if (checked) {
      rememberedTimes.current = { opensAt, closesAt }
      setOpensAt('')
      setClosesAt('')
    } else if (rememberedTimes.current) {
      setOpensAt(rememberedTimes.current.opensAt)
      setClosesAt(rememberedTimes.current.closesAt)
      rememberedTimes.current = null
    }

    setIsClosed(checked)
  }

  return (
    <form
      action={handleSubmit}
      onChange={() => setDirty(true)}
      className="space-y-4"
    >
      <input type="hidden" name="dayOfWeek" value={dayOfWeek} />

      <div className="flex flex-wrap gap-6">
        <div>
          <label className={labelClasses} htmlFor={`${uid}-opens`}>
            Opens
          </label>
          <input
            id={`${uid}-opens`}
            name="opensAt"
            type="time"
            value={opensAt}
            onChange={(event) => setOpensAt(event.target.value)}
            disabled={isClosed}
            required={!isClosed}
            className={inputClasses}
          />
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-closes`}>
            Closes
          </label>
          <input
            id={`${uid}-closes`}
            name="closesAt"
            type="time"
            value={closesAt}
            onChange={(event) => setClosesAt(event.target.value)}
            disabled={isClosed}
            required={!isClosed}
            className={inputClasses}
          />
        </div>
      </div>

      <label className="flex items-center gap-2 text-sm text-foreground">
        <input
          type="checkbox"
          name="isClosed"
          checked={isClosed}
          onChange={(event) => handleClosedChange(event.target.checked)}
          className="focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        />
        Closed
      </label>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <SavedNote saved={state.saved ?? false} dirty={dirty} />

      <SubmitButton label="Save hours" pendingLabel="Saving…" />
    </form>
  )
}
