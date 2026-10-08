'use client'

import { useActionState, useState } from 'react'
import { placeOrder } from '@/lib/orders/actions'
import type { PlaceOrderState } from '@/lib/orders/actions'
import { formatIDR } from '@/lib/format-currency'
import {
  PAYMENT_METHODS,
  PAYMENT_METHOD_LABELS,
  type PaymentMethod,
} from '@/lib/orders/payment'

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

  // React resets the DOM form once a form action completes, which reverts every
  // uncontrolled control to its default and would discard what the customer
  // typed after a rejected submit. These fields are therefore controlled, so
  // React re-applies their values on the post-action re-render.
  const [pickupAt, setPickupAt] = useState('')
  const [tableId, setTableId] = useState(initialTableId ?? '')
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod | ''>('')
  const [customerName, setCustomerName] = useState(defaultName)
  const [customerPhone, setCustomerPhone] = useState(defaultPhone)
  const [couponCode, setCouponCode] = useState('')
  const [customerNote, setCustomerNote] = useState('')

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

      <fieldset>
        <legend className={labelClasses}>Payment</legend>

        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          {PAYMENT_METHODS.map((value) => (
            <label
              key={value}
              className={`flex cursor-pointer items-center gap-3 rounded-lg border px-4 py-3 text-sm transition-colors ${
                paymentMethod === value
                  ? 'border-brand bg-surface'
                  : 'border-border bg-surface hover:border-brand'
              }`}
            >
              <input
                type="radio"
                name="paymentMethod"
                value={value}
                required
                checked={paymentMethod === value}
                onChange={() => setPaymentMethod(value)}
                // React writes `checked` only when the prop changes, so a
                // browser-native selection or the DOM reset that follows a
                // completed form action could leave the visible radio, and the
                // submitted value, out of step with `paymentMethod`. Re-assert
                // the DOM state on every render.
                ref={(element) => {
                  if (element) {
                    element.checked = paymentMethod === value
                  }
                }}
                className={`h-4 w-4 accent-brand ${focusClasses}`}
              />
              <span className="text-foreground">
                {PAYMENT_METHOD_LABELS[value]}
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
            value={pickupAt}
            onChange={(event) => setPickupAt(event.target.value)}
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
            aria-describedby="tableNote"
            value={tableId}
            onChange={(event) => setTableId(event.target.value)}
            // React writes a controlled select's value only when the prop
            // changes, so the DOM reset that follows a completed form action
            // (which falls back to the first non-disabled option) would leave
            // the visible table disagreeing with `tableId` — and a retry would
            // then submit that wrong value. Re-assert the DOM selection on
            // every render so the select and the React state always agree.
            ref={(element) => {
              if (element) {
                element.value = tableId
              }
            }}
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

          <p id="tableNote" className="mt-1 text-sm text-zinc-600">
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
          value={customerName}
          onChange={(event) => setCustomerName(event.target.value)}
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
          value={customerPhone}
          onChange={(event) => setCustomerPhone(event.target.value)}
          className={fieldClasses}
        />
      </div>

      <div>
        <label htmlFor="couponCode" className={labelClasses}>
          Coupon code{' '}
          <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <input
          id="couponCode"
          name="couponCode"
          type="text"
          autoComplete="off"
          spellCheck={false}
          value={couponCode}
          onChange={(event) => setCouponCode(event.target.value)}
          className={fieldClasses}
        />
        <p className="mt-1 text-sm text-zinc-600">
          Applied when you place the order; any discount appears on your order
          confirmation.
        </p>
      </div>

      <div>
        <label htmlFor="customerNote" className={labelClasses}>
          Order note{' '}
          <span className="font-normal text-zinc-600">(optional)</span>
        </label>
        <textarea
          id="customerNote"
          name="customerNote"
          rows={3}
          maxLength={500}
          value={customerNote}
          onChange={(event) => setCustomerNote(event.target.value)}
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
          Estimates only, before any coupon discount. Final pricing is confirmed
          by the restaurant when your order is placed.
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
