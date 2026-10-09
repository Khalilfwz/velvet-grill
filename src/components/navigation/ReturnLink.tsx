'use client'

import Link from 'next/link'
import type { ReactNode } from 'react'
import { buildMarkedHref } from '@/lib/navigation/return-targets'
import type { ReturnTargetKey } from '@/lib/navigation/return-targets'
import {
  isPlainLeftClick,
  rememberReturnOrigin,
  rememberScrollOrigin,
} from '@/lib/navigation/return-origin'

type ReturnLinkProps = {
  origin: ReturnTargetKey
  href: string
  className?: string
  children: ReactNode
}

/**
 * List-side navigation link into a detail page. It marks the href with
 * `?from=<origin>` and, on a plain left click, records the origin in the
 * same-tab tracker so the detail page's BackLink can authorize a history-back.
 * Modifier/middle clicks are left untouched, so no stale origin is recorded.
 */
export default function ReturnLink({
  origin,
  href,
  className,
  children,
}: ReturnLinkProps) {
  return (
    <Link
      href={buildMarkedHref(href, origin)}
      className={className}
      onClick={(event) => {
        if (isPlainLeftClick(event)) {
          rememberReturnOrigin(origin)
          rememberScrollOrigin(origin)
        }
      }}
    >
      {children}
    </Link>
  )
}
