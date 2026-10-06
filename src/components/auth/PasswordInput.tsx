'use client'

import { useState } from 'react'
import { Eye, EyeOff } from 'lucide-react'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const inputClasses = `w-full rounded-lg border border-border bg-surface px-4 py-3 pr-12 text-sm text-foreground ${focusClasses}`

type PasswordInputProps = {
  id: string
  name: string
  label: string
  autoComplete: 'current-password' | 'new-password'
  required?: boolean
  minLength?: number
  defaultValue?: string
  errorId?: string
  hasError?: boolean
  hint?: string
}

export default function PasswordInput({
  id,
  name,
  label,
  autoComplete,
  required = true,
  minLength,
  defaultValue,
  errorId,
  hasError = false,
  hint,
}: PasswordInputProps) {
  const [visible, setVisible] = useState(false)

  return (
    <div>
      <label htmlFor={id} className={labelClasses}>
        {label}
      </label>

      <div className="relative mt-1">
        <input
          id={id}
          name={name}
          type={visible ? 'text' : 'password'}
          autoComplete={autoComplete}
          required={required}
          minLength={minLength}
          defaultValue={defaultValue}
          aria-invalid={hasError ? true : undefined}
          aria-describedby={hasError && errorId ? errorId : undefined}
          className={inputClasses}
        />

        <button
          type="button"
          onClick={() => setVisible((value) => !value)}
          aria-label={visible ? 'Hide password' : 'Show password'}
          aria-pressed={visible}
          className={`absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-2 text-zinc-600 transition-colors hover:text-brand ${focusClasses}`}
        >
          {visible ? (
            <EyeOff size={18} aria-hidden="true" />
          ) : (
            <Eye size={18} aria-hidden="true" />
          )}
        </button>
      </div>

      {hint && <p className="mt-1 text-sm text-zinc-600">{hint}</p>}
    </div>
  )
}
