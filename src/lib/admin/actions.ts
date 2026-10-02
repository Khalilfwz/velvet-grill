'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import type { Database } from '@/lib/supabase/database.types'
import { getAdminContext } from '@/lib/admin/guard'
import {
  categorySchema,
  productSchema,
  productImageSchema,
  optionGroupSchema,
  optionSchema,
  restaurantTableSchema,
  businessHoursSchema,
  restaurantSettingsSchema,
  isUuid,
} from '@/lib/admin/schemas'

export type AdminActionState = {
  error: string | null
}

const GENERIC_ERROR = 'Something went wrong. Please try again.'
const NOT_AUTHORIZED = 'You are not authorized to perform this action.'
const NOT_FOUND = 'That record no longer exists.'
const INVALID_RELATIONSHIP =
  'The selected category, product, or group is not valid.'
const CONFLICT = 'A record with that slug or name already exists.'
const CONFLICT_TABLE = 'A table with that number already exists.'
const INVALID_INPUT = 'Please check the submitted values and try again.'

// Controlled SQLSTATEs raised by the admin_* RPCs plus the table constraints they
// rely on. Anything else collapses to a generic message.
function mapRpcError(
  code: string | undefined,
  conflictMessage: string = CONFLICT
): string {
  switch (code) {
    case '42501':
      return NOT_AUTHORIZED
    case 'P0002':
      return NOT_FOUND
    case '23503':
      return INVALID_RELATIONSHIP
    case '23505':
      return conflictMessage
    case '22023':
    case '23514':
      return INVALID_INPUT
    default:
      return GENERIC_ERROR
  }
}

function str(value: FormDataEntryValue | null): string {
  return typeof value === 'string' ? value : ''
}

type IdParse = { ok: true; id: string | null } | { ok: false }

function parseId(value: FormDataEntryValue | null): IdParse {
  const raw = str(value).trim()

  if (raw === '') {
    return { ok: true, id: null }
  }

  return isUuid(raw) ? { ok: true, id: raw } : { ok: false }
}

function parseRequiredId(value: FormDataEntryValue | null): string | null {
  const raw = str(value).trim()
  return isUuid(raw) ? raw : null
}

function revalidateCatalog(productSlug?: string): void {
  revalidatePath('/menu')

  if (productSlug) {
    revalidatePath(`/menu/${productSlug}`)
  }
}

async function runRpc(
  call: () => PromiseLike<{ error: { code?: string } | null }>,
  conflictMessage: string = CONFLICT
): Promise<string | null> {
  try {
    const { error } = await call()

    return error ? mapRpcError(error.code, conflictMessage) : null
  } catch {
    return GENERIC_ERROR
  }
}

export async function saveCategory(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))

  if (!id.ok) {
    return { error: INVALID_INPUT }
  }

  const parsed = categorySchema.safeParse({
    name: str(formData.get('name')),
    slug: str(formData.get('slug')),
    description: str(formData.get('description')),
    imagePath: str(formData.get('imagePath')),
    sortOrder: str(formData.get('sortOrder')),
    isActive: formData.get('isActive'),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_category', {
      p_id: id.id,
      p_name: parsed.data.name,
      p_slug: parsed.data.slug,
      p_description: parsed.data.description,
      p_image_path: parsed.data.imagePath,
      p_sort_order: parsed.data.sortOrder,
      p_is_active: parsed.data.isActive,
    } as Database['public']['Functions']['admin_save_category']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidateCatalog()
  revalidatePath('/admin/categories')
  revalidatePath('/admin/products')

  return { error: null }
}

export async function saveProduct(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))

  if (!id.ok) {
    return { error: INVALID_INPUT }
  }

  const parsed = productSchema.safeParse({
    name: str(formData.get('name')),
    slug: str(formData.get('slug')),
    description: str(formData.get('description')),
    categoryId: str(formData.get('categoryId')),
    basePrice: str(formData.get('basePrice')),
    stock: str(formData.get('stock')),
    isAvailable: formData.get('isAvailable'),
    isFeatured: formData.get('isFeatured'),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const previousSlug = str(formData.get('previousSlug')).trim()
  let newId: string | null = null

  try {
    const { data, error } = await context.supabase.rpc('admin_save_product', {
      p_id: id.id,
      p_category_id: parsed.data.categoryId,
      p_name: parsed.data.name,
      p_slug: parsed.data.slug,
      p_description: parsed.data.description,
      p_base_price: parsed.data.basePrice,
      p_stock: parsed.data.stock,
      p_is_available: parsed.data.isAvailable,
      p_is_featured: parsed.data.isFeatured,
    } as Database['public']['Functions']['admin_save_product']['Args'])

    if (error) {
      return { error: mapRpcError(error.code) }
    }

    newId = typeof data === 'string' ? data : null
  } catch {
    return { error: GENERIC_ERROR }
  }

  revalidateCatalog(parsed.data.slug)
  revalidatePath('/admin/products')

  if (id.id) {
    revalidatePath(`/admin/products/${id.id}`)
  }

  if (previousSlug && previousSlug !== parsed.data.slug) {
    revalidatePath(`/menu/${previousSlug}`)
  }

  if (!id.id && newId) {
    redirect(`/admin/products/${newId}`)
  }

  return { error: null }
}

export async function saveProductImage(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))
  const productId = parseRequiredId(formData.get('productId'))

  if (!id.ok || !productId) {
    return { error: INVALID_INPUT }
  }

  const parsed = productImageSchema.safeParse({
    storagePath: str(formData.get('storagePath')),
    altText: str(formData.get('altText')),
    sortOrder: str(formData.get('sortOrder')),
    isPrimary: formData.get('isPrimary'),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_product_image', {
      p_id: id.id,
      p_product_id: productId,
      p_storage_path: parsed.data.storagePath,
      p_alt_text: parsed.data.altText,
      p_sort_order: parsed.data.sortOrder,
      p_is_primary: parsed.data.isPrimary,
    } as Database['public']['Functions']['admin_save_product_image']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidateCatalog(str(formData.get('productSlug')).trim() || undefined)
  revalidatePath(`/admin/products/${productId}`)

  return { error: null }
}

export async function deleteProductImage(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const imageId = parseRequiredId(formData.get('id'))
  const productId = parseRequiredId(formData.get('productId'))

  if (!imageId || !productId) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_delete_product_image', {
      p_id: imageId,
      p_product_id: productId,
    } as Database['public']['Functions']['admin_delete_product_image']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidateCatalog(str(formData.get('productSlug')).trim() || undefined)
  revalidatePath(`/admin/products/${productId}`)

  return { error: null }
}

export async function saveOptionGroup(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))
  const productId = parseRequiredId(formData.get('productId'))

  if (!id.ok || !productId) {
    return { error: INVALID_INPUT }
  }

  const parsed = optionGroupSchema.safeParse({
    name: str(formData.get('name')),
    selectionType: str(formData.get('selectionType')),
    minSelections: str(formData.get('minSelections')),
    maxSelections: str(formData.get('maxSelections')),
    isRequired: formData.get('isRequired'),
    sortOrder: str(formData.get('sortOrder')),
    isActive: formData.get('isActive'),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_option_group', {
      p_id: id.id,
      p_product_id: productId,
      p_name: parsed.data.name,
      p_selection_type: parsed.data.selectionType,
      p_min_selections: parsed.data.minSelections,
      p_max_selections: parsed.data.maxSelections,
      p_is_required: parsed.data.isRequired,
      p_sort_order: parsed.data.sortOrder,
      p_is_active: parsed.data.isActive,
    } as Database['public']['Functions']['admin_save_option_group']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidateCatalog(str(formData.get('productSlug')).trim() || undefined)
  revalidatePath(`/admin/products/${productId}`)

  return { error: null }
}

export async function saveOption(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))
  const productId = parseRequiredId(formData.get('productId'))
  const groupId = parseRequiredId(formData.get('groupId'))

  if (!id.ok || !productId || !groupId) {
    return { error: INVALID_INPUT }
  }

  const parsed = optionSchema.safeParse({
    name: str(formData.get('name')),
    priceDelta: str(formData.get('priceDelta')),
    isAvailable: formData.get('isAvailable'),
    sortOrder: str(formData.get('sortOrder')),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_option', {
      p_id: id.id,
      p_group_id: groupId,
      p_product_id: productId,
      p_name: parsed.data.name,
      p_price_delta: parsed.data.priceDelta,
      p_is_available: parsed.data.isAvailable,
      p_sort_order: parsed.data.sortOrder,
    } as Database['public']['Functions']['admin_save_option']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidateCatalog(str(formData.get('productSlug')).trim() || undefined)
  revalidatePath(`/admin/products/${productId}`)

  return { error: null }
}

export async function saveRestaurantTable(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const id = parseId(formData.get('id'))

  if (!id.ok) {
    return { error: INVALID_INPUT }
  }

  const parsed = restaurantTableSchema.safeParse({
    tableNumber: str(formData.get('tableNumber')),
    capacity: str(formData.get('capacity')),
    isActive: formData.get('isActive'),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(
    () =>
      context.supabase.rpc('admin_save_restaurant_table', {
        p_id: id.id,
        p_table_number: parsed.data.tableNumber,
        p_capacity: parsed.data.capacity,
        p_is_active: parsed.data.isActive,
      } as Database['public']['Functions']['admin_save_restaurant_table']['Args']),
    CONFLICT_TABLE
  )

  if (error) {
    return { error }
  }

  revalidatePath('/admin/tables')
  revalidatePath('/checkout')

  return { error: null }
}

export async function saveBusinessHours(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const parsed = businessHoursSchema.safeParse({
    dayOfWeek: str(formData.get('dayOfWeek')),
    isClosed: formData.get('isClosed'),
    opensAt: str(formData.get('opensAt')),
    closesAt: str(formData.get('closesAt')),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_business_hours', {
      p_day_of_week: parsed.data.dayOfWeek,
      p_is_closed: parsed.data.isClosed,
      p_opens_at: parsed.data.opensAt,
      p_closes_at: parsed.data.closesAt,
    } as Database['public']['Functions']['admin_save_business_hours']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidatePath('/admin/hours')

  return { error: null }
}

export async function saveRestaurantSettings(
  _previousState: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  const context = await getAdminContext()

  if (!context) {
    return { error: NOT_AUTHORIZED }
  }

  const parsed = restaurantSettingsSchema.safeParse({
    restaurantName: str(formData.get('restaurantName')),
    address: str(formData.get('address')),
    phone: str(formData.get('phone')),
    timezone: str(formData.get('timezone')),
  })

  if (!parsed.success) {
    return { error: INVALID_INPUT }
  }

  const error = await runRpc(() =>
    context.supabase.rpc('admin_save_restaurant_settings', {
      p_restaurant_name: parsed.data.restaurantName,
      p_address: parsed.data.address,
      p_phone: parsed.data.phone,
      p_timezone: parsed.data.timezone,
    } as Database['public']['Functions']['admin_save_restaurant_settings']['Args'])
  )

  if (error) {
    return { error }
  }

  revalidatePath('/admin/settings')

  return { error: null }
}
