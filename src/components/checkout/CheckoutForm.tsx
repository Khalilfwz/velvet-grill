'use client'

import { useActionState, useState } from 'react'
import { placeOrder } from '@/lib/orders/actions'
import type { PlaceOrderState } from '@/lib/orders/actions'
import { formatIDR } from '@/lib/format-currency'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const fieldClasses = `mt-1 w-full rounded-lg border border-border bg-surface px-4 py-2 text-sm text-foreground ${focusClasses}`

const initialState: PlaceOrderState = { error: null }

export type CheckoutTable = {
  id: string
  tableNumber: string
}

type CheckoutFormProps = {
  tables: CheckoutTable[]
  defaultName: string
  defaultPhone: string
  initialTableId: string | null
  estimate: number | null
  hasUnavailableLine: boolean
  idempotencyKey: string
}

export default function CheckoutForm({
  tables,
  defaultName,
  defaultPhone,
  initialTableId,
  estimate,
  hasUnavailableLine,
  idempotencyKey,
}: CheckoutFormProps) {
  const [state, formAction, isPending] = useActionState(
    placeOrder,
    initialState
  )
  const [fulfillmentType, setFulfillmentType] = useState<'PICKUP' | 'DINE_IN'>(
    initialTableId ? 'DINE_IN' : 'PICKUP'
  )

  return (
    <form action={formAction} className="space-y-6">
      {/* Identifier only, generated once per rendered form so retries reuse it. */}
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />

      <fieldset>
        <legend className={labelClasses}>Fulfillment</legend>

        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          {(['PICKUP', 'DINE_IN'] as const).map((value) => (
            <label
              key={value}
              className={`flex cursor-pointer items-center gap-3 rounded-lg border px-4 py-3 text-sm transition-colors ${
                fulfillmentType === value
                  ? 'border-brand bg-surface'
                  : 'border-border bg-surface hover:border-brand'
              }`}
            >
              <input
                type="radio"
                name="fulfillmentType"
                value={value}
                checked={fulfillmentType === value}
                onChange={() => setFulfillmentType(value)}
                // React only writes `checked` when the prop changes, so a
                // browser-native selection (form/bfcache restore, hydration)
                // could leave the visible radio, and the value the browser
                // submits, out of step with `fulfillmentType` and the field
                // area below. Re-assert the DOM state on every render so the
                // radio, the visible field and the submitted value always
                // agree with the React state.
                ref={(element) => {
                  if (element) {
                    element.checked = fulfillmentType === value
                  }
                }}
                className={`h-4 w-4 accent-brand ${focusClasses}`}
              />
              <span className="text-foreground">
                {value === 'PICKUP' ? 'Pickup' : 'Dine-in'}
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      {fulfillmentType === 'PICKUP' ? (
        <div>
          <label htmlFor="pickupAt" className={labelClasses}>
            Pickup time
          </label>
          <input
            id="pickupAt"
            name="pickupAt"
            type="datetime-local"
            required
            className={fieldClasses}
          />
        </div>
      ) : (
        <div>
          <label htmlFor="tableId" className={labelClasses}>
            Table
          </label>
          <select
            id="tableId"
            name="tableId"
            required
            defaultValue={initialTableId ?? ''}
            className={fieldClasses}
          >
            <option value="" disabled>
              Select your table
            </option>

            {tables.map((table) => (
              <option key={table.id} value={table.id}>
                {table.tableNumber}
              </option>
            ))}
          </select>

          <p className="mt-1 text-sm text-zinc-600">
            Use the table shown on your table card.
          </p>
        </div>
      )}

      <div>
        <label htmlFor="customerName" className={labelClasses}>
          Name
        </label>
        <input
          id="customerName"
          name="customerName"
          type="text"
          required
          maxLength={120}
          defaultValue={defaultName}
          className={fieldClasses}
        />
      </div>

      <div>
        <label htmlFor="customerPhone" className={labelClasses}>
          Phone <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <input
          id="customerPhone"
          name="customerPhone"
          type="tel"
          maxLength={32}
          defaultValue={defaultPhone}
          className={fieldClasses}
        />
      </div>

      <div>
        <label htmlFor="customerNote" className={labelClasses}>
          Note <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <textarea
          id="customerNote"
          name="customerNote"
          rows={3}
          maxLength={500}
          className={fieldClasses}
        />
      </div>

      <div role="status" className="border-t border-border pt-4">
        {hasUnavailableLine || estimate === null ? (
          <p className="text-sm text-zinc-600">
            Some items in your cart are unavailable. Review your cart before
            placing the order.
          </p>
        ) : (
          <p className="flex items-baseline justify-between">
            <span className="text-sm text-zinc-600">Estimated total</span>
            <span className="font-display text-2xl font-medium text-brand">
              {formatIDR(estimate)}
            </span>
          </p>
        )}

        <p className="mt-2 text-sm text-zinc-600">
          Estimates only. Final pricing is confirmed by the restaurant when your
          order is placed.
        </p>
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending || hasUnavailableLine}
        className={`w-full rounded-full bg-brand px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
      >
        {isPending ? 'Placing order…' : 'Place order'}
      </button>
    </form>
  )
}
