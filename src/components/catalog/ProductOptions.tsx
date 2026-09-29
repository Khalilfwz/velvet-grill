'use client'

import { useState } from 'react'
import { formatIDR } from '@/lib/format-currency'
import {
  canSelect,
  clearGroupSelection,
  effectiveMax,
  effectiveMin,
  formatPriceDelta,
  isSelectionComplete,
  optionDeltaTotal,
  selectionHint,
  selectionStatus,
  toggleOption,
} from '@/lib/catalog/product-options'
import type {
  OptionSelections,
  ProductOptionGroup,
} from '@/lib/catalog/product-options'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

type ProductOptionsProps = {
  basePrice: number
  groups: ProductOptionGroup[]
}

export default function ProductOptions({
  basePrice,
  groups,
}: ProductOptionsProps) {
  const [selections, setSelections] = useState<OptionSelections>({})

  const complete = isSelectionComplete(groups, selections)
  const amount = basePrice + optionDeltaTotal(groups, selections)

  return (
    <div className="mt-6 space-y-6">
      {groups.map((group) => {
        const selectedIds = selections[group.id] ?? []
        const max = effectiveMax(group)
        const status = selectionStatus(group, selections)
        const maxReached =
          group.selectionType === 'MULTIPLE' &&
          selectedIds.length > 0 &&
          !canSelect(group, selectedIds)
        const hasOptions = group.options.length > 0
        const note = hasOptions
          ? (status ?? (maxReached ? `Maximum of ${max} selected.` : null))
          : 'No options currently available'
        const allowNone =
          group.selectionType === 'SINGLE' && effectiveMin(group) === 0

        return (
          <fieldset key={group.id}>
            <legend className="font-medium text-foreground">
              {group.name}
              <span className="ml-2 text-sm font-normal text-zinc-600">
                {selectionHint(group)}
              </span>
            </legend>

            {hasOptions && (
              <div className="mt-3 space-y-2">
                {allowNone && (
                  <label className="flex cursor-pointer items-center gap-3 rounded-lg border border-border bg-surface px-4 py-3 text-sm transition-colors hover:border-brand">
                    <input
                      type="radio"
                      name={group.id}
                      checked={selectedIds.length === 0}
                      onChange={() =>
                        setSelections((current) =>
                          clearGroupSelection(group, current)
                        )
                      }
                      className={`h-4 w-4 accent-brand ${focusClasses}`}
                    />
                    <span className="text-foreground">No thanks</span>
                  </label>
                )}

                {group.options.map((option) => {
                  const checked = selectedIds.includes(option.id)
                  const delta = formatPriceDelta(option.priceDelta)
                  const disabled =
                    group.selectionType === 'MULTIPLE' &&
                    !checked &&
                    !canSelect(group, selectedIds)

                  return (
                    <label
                      key={option.id}
                      className={`flex items-center gap-3 rounded-lg border border-border bg-surface px-4 py-3 text-sm transition-colors ${
                        disabled
                          ? 'cursor-not-allowed opacity-60'
                          : 'cursor-pointer hover:border-brand'
                      }`}
                    >
                      <input
                        type={
                          group.selectionType === 'SINGLE' ? 'radio' : 'checkbox'
                        }
                        name={group.id}
                        value={option.id}
                        checked={checked}
                        disabled={disabled}
                        onChange={() =>
                          setSelections((current) =>
                            toggleOption(group, current, option.id)
                          )
                        }
                        className={`h-4 w-4 accent-brand ${focusClasses}`}
                      />
                      <span className="text-foreground">{option.name}</span>
                      <span className="ml-auto shrink-0 text-zinc-600">
                        {delta ?? 'Included'}
                      </span>
                    </label>
                  )
                })}
              </div>
            )}

            {note && <p className="mt-2 text-sm text-zinc-600">{note}</p>}
          </fieldset>
        )
      })}

      {/*
        Preview only. The browser is never authoritative for pricing: nothing is
        submitted here, and any future cart/order write must recompute the price
        and re-validate option membership server-side from the database.
      */}
      <div role="status" className="border-t border-border pt-4">
        <p className="flex flex-wrap items-baseline gap-x-2">
          <span className="text-sm text-zinc-600">
            {complete ? 'Total price' : 'Current price'}
          </span>
          <span className="font-display text-2xl font-medium text-brand">
            {formatIDR(amount)}
          </span>
        </p>

        {!complete && (
          <p className="mt-1 text-sm text-zinc-600">
            Choose the required options to see your total.
          </p>
        )}
      </div>
    </div>
  )
}
