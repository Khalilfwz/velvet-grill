'use client'

import { useState } from 'react'
import { formatIDR } from '@/lib/format-currency'
import AddToCartForm from '@/components/cart/AddToCartForm'
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
  productId?: string
  isAuthenticated?: boolean
}

export default function ProductOptions({
  basePrice,
  groups,
  productId,
  isAuthenticated = false,
}: ProductOptionsProps) {
  const [selections, setSelections] = useState<OptionSelections>({})

  const complete = isSelectionComplete(groups, selections)
  const amount = basePrice + optionDeltaTotal(groups, selections)
  const selectedOptionIds = Object.values(selections).flat()

  return (
    <div className="mt-6 space-y-8">
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
            <legend className="text-xs font-semibold uppercase tracking-[0.2em] text-foreground">
              {group.name}
              <span className="ml-2 text-xs font-normal normal-case tracking-normal text-zinc-600">
                {selectionHint(group)}
              </span>
            </legend>

            {hasOptions && (
              <div className="mt-4 space-y-2">
                {allowNone && (
                  <label
                    className={`flex cursor-pointer items-center gap-3 rounded-lg border px-4 py-3 text-sm transition-colors ${
                      selectedIds.length === 0
                        ? 'border-brand bg-brand/5'
                        : 'border-transparent hover:border-border hover:bg-surface'
                    }`}
                  >
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
                    <span
                      className={
                        selectedIds.length === 0
                          ? 'font-medium text-brand'
                          : 'text-foreground'
                      }
                    >
                      No thanks
                    </span>
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
                      className={`flex items-center gap-3 rounded-lg border px-4 py-3 text-sm transition-colors ${
                        disabled
                          ? 'cursor-not-allowed border-transparent opacity-60'
                          : checked
                            ? 'cursor-pointer border-brand bg-brand/5'
                            : 'cursor-pointer border-transparent hover:border-border hover:bg-surface'
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
                      <span
                        className={
                          checked ? 'font-medium text-brand' : 'text-foreground'
                        }
                      >
                        {option.name}
                      </span>
                      <span className="ml-auto shrink-0 text-zinc-600 tabular-nums">
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
        Display estimate only. The client is never authoritative: the submitted
        ids are re-validated against the database by the cart Server Action,
        which recomputes option membership and availability server-side.
      */}
      <div className="rounded-xl border border-border bg-surface p-6">
        <div role="status">
          <p className="flex flex-wrap items-baseline gap-x-3">
            <span className="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-600">
              {complete ? 'Total price' : 'Current price'}
            </span>
            <span className="font-display text-3xl font-medium text-brand tabular-nums">
              {formatIDR(amount)}
            </span>
          </p>

          {!complete && (
            <p className="mt-1 text-sm text-zinc-600">
              Choose the required options to see your total.
            </p>
          )}
        </div>

        {productId && (
          <div className="mt-6">
            <AddToCartForm
              productId={productId}
              optionIds={selectedOptionIds}
              complete={complete}
              isAuthenticated={isAuthenticated}
            />
          </div>
        )}
      </div>
    </div>
  )
}
