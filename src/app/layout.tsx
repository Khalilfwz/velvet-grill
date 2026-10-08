import type { Metadata } from 'next'
import { Inter, Playfair_Display } from 'next/font/google'
import './globals.css'

const playfair = Playfair_Display({
  variable: '--font-playfair',
  subsets: ['latin'],
})

const inter = Inter({
  variable: '--font-inter',
  subsets: ['latin'],
})

// Canonical/OG base URL. Never derive this from the Supabase project
// URL — that host serves storage/auth, not this site. Local development
// falls back to localhost; a production deployment (once approved) must
// set NEXT_PUBLIC_SITE_URL.
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: 'Velvet Grill',
    template: '%s | Velvet Grill',
  },
  description:
    'Velvet Grill - Premium dining experience with steak, burgers, drinks, and desserts.',
  openGraph: {
    type: 'website',
    siteName: 'Velvet Grill',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${playfair.variable} ${inter.variable}`}>
      <body>{children}</body>
    </html>
  )
}
