import Navbar from '@/components/layout/Navbar'
import StorefrontFooter from '@/components/layout/StorefrontFooter'

export default function StorefrontLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <>
      <Navbar />
      {children}
      <StorefrontFooter />
    </>
  )
}
