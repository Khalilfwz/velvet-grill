'use client'

import { useFormStatus } from 'react-dom'

type SubmitButtonProps = {
  label: string
  pendingLabel?: string
  variant?: 'default' | 'danger'
  size?: 'default' | 'compact'
  className?: string
}

const baseClasses =
  'inline-flex items-center justify-center rounded-lg text-sm font-medium text-white transition-colors disabled:cursor-not-allowed disabled:opacity-60 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const VARIANT_CLASSES = {
  default: 'bg-brand hover:bg-brand-light',
  danger: 'bg-red-700 hover:bg-red-800',
} as const

const SIZE_CLASSES = {
  default: 'px-4 py-2',
  compact: 'px-3 py-1.5 text-xs',
} as const

export default function SubmitButton({
  label,
  pendingLabel,
  variant = 'default',
  size = 'default',
  className = '',
}: SubmitButtonProps) {
  const { pending } = useFormStatus()

  return (
    <button
      type="submit"
      disabled={pending}
      className={`${baseClasses} ${VARIANT_CLASSES[variant]} ${SIZE_CLASSES[size]} ${className}`}
    >
      {pending ? (pendingLabel ?? label) : label}
    </button>
  )
}
