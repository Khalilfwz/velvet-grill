import Image from 'next/image'

function isUnoptimized(src: string): boolean {
  if (/\.svg$/i.test(src)) {
    return true
  }

  try {
    const { hostname } = new URL(src)

    return ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(hostname)
  } catch {
    return false
  }
}

type ProductImageProps = {
  src: string | null
  alt: string
  sizes: string
  preload?: boolean
  className?: string
}

export default function ProductImage({
  src,
  alt,
  sizes,
  preload = false,
  className = '',
}: ProductImageProps) {
  return (
    <div className={`relative overflow-hidden bg-border/40 ${className}`}>
      {src && (
        <Image
          src={src}
          alt={alt}
          fill
          sizes={sizes}
          preload={preload}
          unoptimized={isUnoptimized(src)}
          className="object-cover"
        />
      )}
    </div>
  )
}
