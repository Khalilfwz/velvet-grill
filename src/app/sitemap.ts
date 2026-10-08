import type { MetadataRoute } from 'next'

// Public, indexable pages only — kept consistent with robots.ts:
// every entry is robots-allowed, and protected/auth routes
// (including /login and /register) are excluded.
//
// Static list on purpose: builds never depend on a running database.
// Same base URL as the root metadataBase in layout.tsx. Never derive
// it from the Supabase project URL.
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: siteUrl,
      lastModified: new Date(),
      changeFrequency: 'weekly',
      priority: 1,
    },
    {
      url: `${siteUrl}/menu`,
      lastModified: new Date(),
      changeFrequency: 'weekly',
      priority: 0.8,
    },
    {
      url: `${siteUrl}/about`,
      lastModified: new Date(),
      changeFrequency: 'monthly',
      priority: 0.5,
    },
  ]
}
