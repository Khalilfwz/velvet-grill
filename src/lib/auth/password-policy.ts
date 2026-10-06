// Mirrors auth.email.minimum_password_length / password_requirements in
// supabase/config.toml. The active local policy is length-only (no character
// class requirements), so feedback here must not assert classes or strength.
export const PASSWORD_MIN_LENGTH = 6

export const PASSWORD_MIN_LENGTH_HINT = `At least ${PASSWORD_MIN_LENGTH} characters.`
