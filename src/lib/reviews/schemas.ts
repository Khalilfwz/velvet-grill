import { z } from 'zod'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const MAX_TITLE_LENGTH = 120
const MAX_CONTENT_LENGTH = 2000

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => (value === '' ? null : value))

export const reviewSubmissionSchema = z.strictObject({
  orderItemId: z.string().trim().regex(UUID_PATTERN),
  rating: z
    .string()
    .trim()
    .regex(/^[1-5]$/)
    .transform((value) => Number(value)),
  title: optionalText(MAX_TITLE_LENGTH),
  content: optionalText(MAX_CONTENT_LENGTH),
})
