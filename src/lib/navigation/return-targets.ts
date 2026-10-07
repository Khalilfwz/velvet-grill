// Return-target registry and route-origin policy for history-based "back"
// navigation. This module is pure and server-safe: it holds no state and may be
// imported by server components (to compute labels/hrefs) and by the client
// components that decide whether a history-back is safe.
//
// A `?from=` query value is navigation metadata only. It is never trusted as
// text, URL, or authorization: it can only select an entry from the fixed
// registry below, and only when that entry is allowed for the current detail
// route.

export type SearchParamValue = string | string[] | undefined

export const RETURN_TARGETS = {
  menu: { href: '/menu', label: 'Back to menu' },
  wishlist: { href: '/wishlist', label: 'Back to wishlist' },
  cart: { href: '/cart', label: 'Back to cart' },
  orders: { href: '/orders', label: 'Back to My Orders' },
  notifications: { href: '/notifications', label: 'Back to notifications' },
  'admin-products': { href: '/admin/products', label: 'Back to products' },
} as const

export type ReturnTargetKey = keyof typeof RETURN_TARGETS

// The canonical fallback and the only origins allowed for each detail route.
export const RETURN_ROUTES = {
  'menu-product': { fallback: 'menu', allowed: ['menu', 'wishlist', 'cart'] },
  'order-detail': { fallback: 'orders', allowed: ['orders', 'notifications'] },
  'admin-product': { fallback: 'admin-products', allowed: ['admin-products'] },
} as const satisfies Record<
  string,
  { fallback: ReturnTargetKey; allowed: readonly ReturnTargetKey[] }
>

export type ReturnRouteKey = keyof typeof RETURN_ROUTES

export function isReturnTargetKey(value: unknown): value is ReturnTargetKey {
  return typeof value === 'string' && value in RETURN_TARGETS
}

/**
 * True only when `from` is a single string that is BOTH a known
 * `RETURN_TARGETS` key and listed in the route's allowed origins. Repeated
 * (array) or absent values are never allowed.
 */
export function isAllowedReturnOrigin(
  route: ReturnRouteKey,
  from: SearchParamValue
): from is ReturnTargetKey {
  if (!isReturnTargetKey(from)) {
    return false
  }

  const allowed = RETURN_ROUTES[route].allowed as readonly ReturnTargetKey[]

  return allowed.includes(from)
}

export type ResolvedReturnTarget = {
  origin: ReturnTargetKey | null
  href: string
  label: string
}

/**
 * The single source of truth for a detail page's back control. `origin` is the
 * marker only when it is known AND allowed for the route; every other value
 * (unknown, empty, repeated, wrong type, route-disallowed) yields `origin: null`
 * and the route's canonical fallback. The returned `href`/`label` always come
 * from `RETURN_TARGETS`, never from the query string.
 */
export function resolveReturnTarget(
  route: ReturnRouteKey,
  from: SearchParamValue
): ResolvedReturnTarget {
  const origin = isAllowedReturnOrigin(route, from) ? from : null
  const target = RETURN_TARGETS[origin ?? RETURN_ROUTES[route].fallback]

  return { origin, href: target.href, label: target.label }
}

/** Marks a list-to-detail href with its navigation-only origin parameter. */
export function buildMarkedHref(href: string, origin: ReturnTargetKey): string {
  const separator = href.includes('?') ? '&' : '?'

  return `${href}${separator}from=${origin}`
}
