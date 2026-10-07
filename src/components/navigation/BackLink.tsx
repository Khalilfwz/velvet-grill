'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { resolveReturnTarget } from '@/lib/navigation/return-targets'
import type {
  ReturnRouteKey,
  SearchParamValue,
} from '@/lib/navigation/return-targets'
import {
  clearReturnOrigin,
  isPlainLeftClick,
  isReturnOriginCurrent,
} from '@/lib/navigation/return-origin'

type BackLinkProps = {
  route: ReturnRouteKey
  from: SearchParamValue
  className?: string
}

/**
 * Detail-page "Back" control. Its label and fallback href come from the central
 * resolver — which only accepts a marker that is a known target AND allowed for
 * this route — so the component itself performs no marker validation.
 *
 * A plain left click uses history-back only when the resolver produced an
 * origin AND the same-tab tracker matches it; otherwise it is an ordinary link.
 */
export default function BackLink({ route, from, className }: BackLinkProps) {
  const router = useRouter()
  const { origin, href, label } = resolveReturnTarget(route, from)

  return (
    <Link
      href={href}
      className={className}
      onClick={(event) => {
        // `origin` is non-null only for a known, route-allowed marker, so the
        // remaining condition is the same-tab tracker match.
        if (!isPlainLeftClick(event) || origin === null) {
          return
        }

        if (!isReturnOriginCurrent(origin)) {
          return
        }

        event.preventDefault()
        clearReturnOrigin()
        router.back()
      }}
    >
      {label}
    </Link>
  )
}
