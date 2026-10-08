import type { MetadataRoute } from 'next'

// Robots directives are crawler etiquette, not security controls —
// authorization on protected routes remains enforced server-side
// (RLS plus server-side auth guards) regardless of what crawlers do.
//
// Same base URL as the root metadataBase in layout.tsx. Never derive
// it from the Supabase project URL.
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: '*',
      allow: '/',
      disallow: [
        '/admin',
        '/cart',
        '/checkout',
        '/orders',
        '/profile',
        '/wishlist',
        '/notifications',
        '/login',
        '/register',
        '/auth',
      ],
    },
    sitemap: `${siteUrl}/sitemap.xml`,
  }
}
