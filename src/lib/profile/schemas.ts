import { z } from 'zod'

// Deliberately local to the profile module: profile validation must not depend
// on admin schema helpers. Only the fields a customer may self-edit are defined.
const MAX_FULL_NAME_LENGTH = 120
const MAX_PHONE_LENGTH = 32
const MAX_EMAIL_LENGTH = 254

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

const optionalProfileText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => (value === '' ? null : value))

export const profileUpdateSchema = z.strictObject({
  fullName: optionalProfileText(MAX_FULL_NAME_LENGTH),
  phone: optionalProfileText(MAX_PHONE_LENGTH),
})

export const emailChangeSchema = z.strictObject({
  email: z.string().trim().max(MAX_EMAIL_LENGTH).regex(EMAIL_PATTERN),
})

export type ProfileUpdateInput = z.infer<typeof profileUpdateSchema>
export type EmailChangeInput = z.infer<typeof emailChangeSchema>
