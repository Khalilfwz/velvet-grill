'use client'

import { useFormStatus } from 'react-dom'

type SubmitButtonProps = {
  label: string
  pendingLabel?: string
  className?: string
}

const baseClasses =
  'inline-flex items-center justify-center rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default function SubmitButton({
  label,
  pendingLabel,
  className = '',
}: SubmitButtonProps) {
  const { pending } = useFormStatus()

  return (
    <button type="submit" disabled={pending} className={`${baseClasses} ${className}`}>
      {pending ? (pendingLabel ?? label) : label}
    </button>
  )
}
