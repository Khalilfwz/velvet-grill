import { z } from 'zod'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/
const SAFE_PATH_PATTERN = /^[A-Za-z0-9._/-]+$/

const MAX_SLUG_LENGTH = 80
const MAX_NAME_LENGTH = 120
const MAX_DESCRIPTION_LENGTH = 1000
const MAX_ALT_TEXT_LENGTH = 200
const MAX_PATH_LENGTH = 255
const MAX_SELECTIONS = 1000
const MAX_PRICE = 9_999_999_999.99
const MAX_STOCK = 1_000_000
const MAX_INT = 2_147_483_647

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value)
}

/** Relative-only path safety; mirrors private.is_safe_relative_path(). */
export function isSafeRelativePath(value: string): boolean {
  if (value.length < 1 || value.length > MAX_PATH_LENGTH) {
    return false
  }

  if (value.startsWith('/') || value.endsWith('/')) {
    return false
  }

  if (value.includes('//') || value.includes('://')) {
    return false
  }

  if (value.split('/').some((segment) => segment === '..')) {
    return false
  }

  return SAFE_PATH_PATTERN.test(value)
}

const requiredText = (max: number) => z.string().trim().min(1).max(max)

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => (value === '' ? null : value))

const slug = z.string().trim().max(MAX_SLUG_LENGTH).regex(SLUG_PATTERN)

const sortOrder = z
  .string()
  .trim()
  .transform((value) => (value === '' ? 0 : Number(value)))
  .refine((value) => Number.isInteger(value) && value >= 0 && value <= MAX_INT)

const minSelections = z
  .string()
  .trim()
  .transform((value) => (value === '' ? 0 : Number(value)))
  .refine(
    (value) => Number.isInteger(value) && value >= 0 && value <= MAX_SELECTIONS
  )

const maxSelections = z
  .string()
  .trim()
  .transform((value) => (value === '' ? null : Number(value)))
  .refine(
    (value) =>
      value === null ||
      (Number.isInteger(value) && value >= 1 && value <= MAX_SELECTIONS)
  )

const basePrice = z
  .string()
  .trim()
  .regex(/^\d+(\.\d{1,2})?$/)
  .transform((value) => Number(value))
  .refine((value) => value >= 0 && value <= MAX_PRICE)

const priceDelta = z
  .string()
  .trim()
  .regex(/^-?\d+(\.\d{1,2})?$/)
  .transform((value) => Number(value))
  .refine((value) => value >= -MAX_PRICE && value <= MAX_PRICE)

const stock = z
  .string()
  .trim()
  .regex(/^\d+$/)
  .transform((value) => Number(value))
  .refine((value) => value >= 0 && value <= MAX_STOCK)

const checkbox = z.preprocess(
  (value) => value === 'on' || value === 'true' || value === true,
  z.boolean()
)

export const categorySchema = z.strictObject({
  name: requiredText(MAX_NAME_LENGTH),
  slug,
  description: optionalText(MAX_DESCRIPTION_LENGTH),
  imagePath: optionalText(MAX_PATH_LENGTH).refine(
    (value) => value === null || isSafeRelativePath(value)
  ),
  sortOrder,
  isActive: checkbox,
})

export const productSchema = z.strictObject({
  name: requiredText(MAX_NAME_LENGTH),
  slug,
  description: optionalText(MAX_DESCRIPTION_LENGTH),
  categoryId: z.string().regex(UUID_PATTERN),
  basePrice,
  stock,
  isAvailable: checkbox,
  isFeatured: checkbox,
})

export const productImageSchema = z.strictObject({
  storagePath: z
    .string()
    .trim()
    .max(MAX_PATH_LENGTH)
    .refine((value) => isSafeRelativePath(value)),
  altText: optionalText(MAX_ALT_TEXT_LENGTH),
  sortOrder,
  isPrimary: checkbox,
})

export const optionGroupSchema = z.strictObject({
  name: requiredText(MAX_NAME_LENGTH),
  selectionType: z.enum(['SINGLE', 'MULTIPLE']),
  minSelections,
  maxSelections,
  isRequired: checkbox,
  sortOrder,
  isActive: checkbox,
})

export const optionSchema = z.strictObject({
  name: requiredText(MAX_NAME_LENGTH),
  priceDelta,
  isAvailable: checkbox,
  sortOrder,
})
