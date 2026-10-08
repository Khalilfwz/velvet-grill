import Navbar from '@/components/layout/Navbar'
import StorefrontFooter from '@/components/layout/StorefrontFooter'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export default function StorefrontLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <>
      <a
        href="#main-content"
        className={`sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-lg focus:border focus:border-border focus:bg-surface focus:px-4 focus:py-2 focus:text-sm focus:font-medium focus:text-foreground focus:shadow-sm ${focusClasses}`}
      >
        Skip to content
      </a>

      <Navbar />
      <div id="main-content" tabIndex={-1} className="outline-none">
        {children}
      </div>
      <StorefrontFooter />
    </>
  )
}
