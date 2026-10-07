'use client'

import Image from 'next/image'
import { useState } from 'react'
import { isUnoptimizedProductImage } from '@/components/catalog/ProductImage'

export default function AdminImagePreview({
  src,
  alt,
  emptyHint = 'No preview',
  className = '',
}: {
  src: string | null
  alt: string
  emptyHint?: string
  className?: string
}) {
  // Track the src that failed rather than a boolean, so a new src is retried
  // without an effect: failed is true only while the current src has failed.
  const [failedSrc, setFailedSrc] = useState<string | null>(null)
  const failed = src !== null && failedSrc === src

  return (
    <div
      className={`relative aspect-[4/3] w-full overflow-hidden rounded-lg border border-border bg-border/40 ${className}`}
    >
      {src && !failed ? (
        <Image
          src={src}
          alt={alt}
          fill
          sizes="(min-width: 640px) 200px, 50vw"
          unoptimized={isUnoptimizedProductImage(src)}
          className="object-cover"
          onError={() => setFailedSrc(src)}
        />
      ) : (
        <div className="flex h-full items-center justify-center p-3 text-center">
          <p className="text-xs leading-relaxed text-zinc-500">
            {failed ? 'Preview unavailable — no image at this path' : emptyHint}
          </p>
        </div>
      )}
    </div>
  )
}
