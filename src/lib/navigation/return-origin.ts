'use client'

// Per-tab, in-memory record of the list a user most recently navigated from
// into a detail page. It lives only in the client bundle and is reset by every
// hard load (new tab, refresh, typed URL), which is what makes history-back
// authorization safe: a copied or bookmarked deep link can never have a
// matching record. This is a single navigation-origin marker, not a store, and
// it is deliberately client-only so a server render can never share it.

import {
  isReturnTargetKey,
  type ReturnTargetKey,
} from '@/lib/navigation/return-targets'

let lastOrigin: ReturnTargetKey | null = null

export function rememberReturnOrigin(origin: ReturnTargetKey): void {
  lastOrigin = origin
}

export function isReturnOriginCurrent(from: unknown): boolean {
  return isReturnTargetKey(from) && lastOrigin === from
}

export function clearReturnOrigin(): void {
  lastOrigin = null
}

type ClickLike = {
  defaultPrevented: boolean
  button: number
  metaKey: boolean
  ctrlKey: boolean
  shiftKey: boolean
  altKey: boolean
}

/**
 * Only a plain primary click should be converted into a history-back or origin
 * record; modifier/middle clicks keep their normal "open in new tab" behaviour.
 */
export function isPlainLeftClick(event: ClickLike): boolean {
  return (
    !event.defaultPrevented &&
    event.button === 0 &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.shiftKey &&
    !event.altKey
  )
}
