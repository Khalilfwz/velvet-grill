import { formatIDR } from '@/lib/format-currency'
import type { Database } from '@/lib/supabase/database.types'

type SelectionType = Database['public']['Enums']['option_selection_type']

// Server-side source shapes: narrowed projections of the generated DB rows.
export type OptionGroupSource = Pick<
  Database['public']['Tables']['product_option_groups']['Row'],
  | 'id'
  | 'name'
  | 'selection_type'
  | 'min_selections'
  | 'max_selections'
  | 'is_required'
  | 'sort_order'
  | 'is_active'
>

export type OptionSource = Pick<
  Database['public']['Tables']['product_options']['Row'],
  'id' | 'group_id' | 'name' | 'price_delta' | 'is_available' | 'sort_order'
>

// Minimal client DTO: the only option data that crosses into the browser.
export type ProductOption = {
  id: string
  name: string
  priceDelta: number
}

export type ProductOptionGroup = {
  id: string
  name: string
  selectionType: SelectionType
  minSelections: number
  maxSelections: number | null
  isRequired: boolean
  options: ProductOption[]
}

/** groupId -> selected optionIds */
export type OptionSelections = Record<string, string[]>

type Orderable = { sort_order: number; name: string; id: string }

function byCatalogOrder<T extends Orderable>(a: T, b: T): number {
  if (a.sort_order !== b.sort_order) {
    return a.sort_order - b.sort_order
  }

  const byName = a.name.localeCompare(b.name)

  if (byName !== 0) {
    return byName
  }

  return a.id.localeCompare(b.id)
}

function orderBy<T extends Orderable>(rows: T[]): T[] {
  return [...rows].sort(byCatalogOrder)
}

/**
 * Maps DB rows to the client DTO, dropping inactive groups and unavailable
 * options. RLS already restricts both, so this is defense in depth.
 *
 * An active group whose options are all unavailable is kept with an empty
 * option list: it still represents the group's requirement, and the UI renders
 * an empty state for it rather than silently hiding it.
 */
export function buildProductOptionGroups(
  groups: OptionGroupSource[],
  options: OptionSource[]
): ProductOptionGroup[] {
  const availableOptions = options.filter((option) => option.is_available)

  return orderBy(groups.filter((group) => group.is_active)).map((group) => ({
    id: group.id,
    name: group.name,
    selectionType: group.selection_type,
    minSelections: group.min_selections,
    maxSelections: group.max_selections,
    isRequired: group.is_required,
    options: orderBy(
      availableOptions.filter((option) => option.group_id === group.id)
    ).map((option) => ({
      id: option.id,
      name: option.name,
      priceDelta: option.price_delta,
    })),
  }))
}

/** A validity requirement: the minimum a selection must reach to be complete. */
export function effectiveMin(group: ProductOptionGroup): number {
  return Math.max(group.minSelections, group.isRequired ? 1 : 0)
}

/** An interaction limit: the most that may be selected at once. */
export function effectiveMax(group: ProductOptionGroup): number | null {
  return group.selectionType === 'SINGLE' ? 1 : group.maxSelections
}

export function canSelect(
  group: ProductOptionGroup,
  selectedIds: string[]
): boolean {
  const max = effectiveMax(group)

  return max === null || selectedIds.length < max
}

export function isGroupSatisfied(
  group: ProductOptionGroup,
  selectedIds: string[]
): boolean {
  const max = effectiveMax(group)

  return (
    selectedIds.length >= effectiveMin(group) &&
    (max === null || selectedIds.length <= max)
  )
}

export function isSelectionComplete(
  groups: ProductOptionGroup[],
  selections: OptionSelections
): boolean {
  return groups.every((group) =>
    isGroupSatisfied(group, selections[group.id] ?? [])
  )
}

/**
 * Adds, replaces, or removes a selection.
 *
 * `effectiveMax` is an interaction limit and is enforced on additions only.
 * Removal is never blocked: `effectiveMin` is a validity requirement, not a
 * deselection lock, so a chosen option can always be swapped out (the group
 * simply reports itself unsatisfied in the meantime).
 */
export function toggleOption(
  group: ProductOptionGroup,
  selections: OptionSelections,
  optionId: string
): OptionSelections {
  const selected = selections[group.id] ?? []

  if (group.selectionType === 'SINGLE') {
    if (selected[0] === optionId) {
      return effectiveMin(group) === 0
        ? { ...selections, [group.id]: [] }
        : selections
    }

    return { ...selections, [group.id]: [optionId] }
  }

  if (selected.includes(optionId)) {
    return {
      ...selections,
      [group.id]: selected.filter((id) => id !== optionId),
    }
  }

  if (!canSelect(group, selected)) {
    return selections
  }

  return { ...selections, [group.id]: [...selected, optionId] }
}

/** Clears a group. Ignored when the group needs a selection to stay valid. */
export function clearGroupSelection(
  group: ProductOptionGroup,
  selections: OptionSelections
): OptionSelections {
  if (effectiveMin(group) > 0) {
    return selections
  }

  return { ...selections, [group.id]: [] }
}

export function optionDeltaTotal(
  groups: ProductOptionGroup[],
  selections: OptionSelections
): number {
  return groups.reduce((total, group) => {
    const selected = selections[group.id] ?? []

    return (
      total +
      group.options.reduce(
        (groupTotal, option) =>
          selected.includes(option.id)
            ? groupTotal + option.priceDelta
            : groupTotal,
        0
      )
    )
  }, 0)
}

export function selectionHint(group: ProductOptionGroup): string {
  const min = effectiveMin(group)
  const max = effectiveMax(group)

  if (group.selectionType === 'SINGLE') {
    return min > 0 ? 'Choose 1' : 'Optional'
  }

  if (min === 0) {
    return max === null
      ? 'Optional — choose any'
      : `Optional — choose up to ${max}`
  }

  if (max === null) {
    return `Choose at least ${min}`
  }

  return min === max ? `Choose ${min}` : `Choose ${min} or ${max}`
}

/** The unmet requirement, or null when the group is satisfied. */
export function selectionStatus(
  group: ProductOptionGroup,
  selections: OptionSelections
): string | null {
  const selected = selections[group.id] ?? []

  return selected.length < effectiveMin(group) ? selectionHint(group) : null
}

/** Display string for an option's price delta; null when it costs nothing. */
export function formatPriceDelta(delta: number): string | null {
  if (delta === 0) {
    return null
  }

  const formatted = formatIDR(Math.abs(delta))

  return delta > 0 ? `+${formatted}` : `−${formatted}`
}
