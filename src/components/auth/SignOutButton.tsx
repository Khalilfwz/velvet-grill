'use client'

import { useFormStatus } from 'react-dom'

export default function SignOutButton({ className }: { className: string }) {
  const { pending } = useFormStatus()

  return (
    <button
      type="submit"
      disabled={pending}
      className={`${className} disabled:cursor-not-allowed disabled:opacity-60`}
    >
      Sign out
    </button>
  )
}
