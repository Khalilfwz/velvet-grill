'use client'

import { useEffect } from 'react'
import {
  clearScrollOrigin,
  peekScrollOrigin,
} from '@/lib/navigation/return-origin'

// Upper bound for waiting until the menu layout is tall enough to hold the
// saved offset (images loading, fonts swapping). Not a fixed delay: the loop
// exits as soon as the position is reachable, the user takes control, or the
// deadline passes.
const RESTORE_DEADLINE_MS = 2000

// Any of these means the user is scrolling on their own — restoration must
// never fight them for the scroll position.
const CANCEL_EVENTS = ['wheel', 'touchstart', 'keydown', 'pointerdown'] as const

/**
 * Restores the menu's previous scroll position after a same-tab return from a
 * product page. The offset is captured by ReturnLink at click time in the
 * in-memory origin tracker, so it exists only for this tab's current
 * navigation lifecycle: a fresh load, refresh, direct URL, or new tab has an
 * empty tracker and never restores anything.
 */
export default function MenuScrollRestoration() {
  useEffect(() => {
    const slot = peekScrollOrigin()

    if (slot === null || slot.origin !== 'menu' || slot.y <= 0) {
      return
    }

    let rafId = 0
    let cancelled = false
    const startedAt = performance.now()

    const stop = () => {
      cancelled = true

      for (const event of CANCEL_EVENTS) {
        window.removeEventListener(event, cancel)
      }

      cancelAnimationFrame(rafId)
      clearScrollOrigin(slot)
    }

    const cancel = () => {
      stop()
    }

    const tick = () => {
      if (cancelled) {
        return
      }

      const maxScroll =
        document.documentElement.scrollHeight - window.innerHeight

      if (maxScroll >= slot.y - 1) {
        window.scrollTo({ top: slot.y, behavior: 'instant' })
        stop()
        return
      }

      if (performance.now() - startedAt >= RESTORE_DEADLINE_MS) {
        stop()
        return
      }

      rafId = requestAnimationFrame(tick)
    }

    for (const event of CANCEL_EVENTS) {
      window.addEventListener(event, cancel, { passive: true })
    }

    rafId = requestAnimationFrame(tick)

    return () => {
      for (const event of CANCEL_EVENTS) {
        window.removeEventListener(event, cancel)
      }

      cancelAnimationFrame(rafId)
      // The slot is intentionally not cleared here: React StrictMode remounts
      // effects in development, and a newer slot recorded by a ReturnLink
      // click just before unmount must survive. clearScrollOrigin's identity
      // guard consumes the slot exactly once, on apply, cancel, or deadline.
    }
  }, [])

  return null
}
