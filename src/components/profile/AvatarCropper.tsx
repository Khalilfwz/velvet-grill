'use client'

import {
  useEffect,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent,
} from 'react'
import {
  AVATAR_MAX_BYTES,
  isAllowedAvatarMimeType,
  type AvatarMimeType,
} from '@/lib/profile/avatar'

// The crop viewport is a fixed square in CSS pixels; the output canvas is a
// larger square so the stored avatar stays sharp. Drawing is a straight linear
// scale of the viewport, so the uploaded file matches the preview exactly.
const VIEWPORT = 256
const OUTPUT = 512
const MIN_ZOOM = 1
const MAX_ZOOM = 3
const ARROW_STEP = 12
const ARROW_STEP_FAST = 36
const JPEG_QUALITY = 0.9

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const primaryButtonClasses = `rounded-full bg-brand px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`

const secondaryButtonClasses = `rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`

const labelClasses = 'block text-sm font-medium text-foreground'

type Crop = { zoom: number; x: number; y: number }

type Offset = { x: number; y: number }

type Size = { width: number; height: number }

type AvatarCropperProps = {
  file: File
  isUploading: boolean
  onCancel: () => void
  onConfirm: (file: File) => void
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value))
}

// Cover scale guarantees the image always fills the square viewport, so its
// drawn size is never smaller than VIEWPORT in either axis.
function scaledSize(image: HTMLImageElement, zoom: number): Size {
  const cover = Math.max(
    VIEWPORT / image.naturalWidth,
    VIEWPORT / image.naturalHeight
  )
  const scale = cover * zoom

  return {
    width: image.naturalWidth * scale,
    height: image.naturalHeight * scale,
  }
}

function clampOffset(x: number, y: number, size: Size): Offset {
  return {
    x: clamp(x, VIEWPORT - size.width, 0),
    y: clamp(y, VIEWPORT - size.height, 0),
  }
}

function centeredCrop(image: HTMLImageElement, zoom: number): Crop {
  const size = scaledSize(image, zoom)
  const offset = clampOffset(
    (VIEWPORT - size.width) / 2,
    (VIEWPORT - size.height) / 2,
    size
  )

  return { zoom, ...offset }
}

// Preserve the source format so the preview's transparency and colour are not
// silently flattened; JPEG is the fallback and gets a white matte instead.
function outputMimeType(sourceType: string): AvatarMimeType {
  if (sourceType === 'image/png') return 'image/png'
  if (sourceType === 'image/webp') return 'image/webp'
  return 'image/jpeg'
}

function filenameFor(type: AvatarMimeType): string {
  if (type === 'image/png') return 'avatar.png'
  if (type === 'image/webp') return 'avatar.webp'
  return 'avatar.jpg'
}

export default function AvatarCropper({
  file,
  isUploading,
  onCancel,
  onConfirm,
}: AvatarCropperProps) {
  const [image, setImage] = useState<HTMLImageElement | null>(null)
  const [crop, setCrop] = useState<Crop>({ zoom: MIN_ZOOM, x: 0, y: 0 })
  const [error, setError] = useState<string | null>(null)
  const [isPreparing, setIsPreparing] = useState(false)
  const dragRef = useRef<{
    pointerId: number
    startX: number
    startY: number
    originX: number
    originY: number
  } | null>(null)

  useEffect(() => {
    const url = URL.createObjectURL(file)
    const loaded = new Image()
    let cancelled = false

    loaded.onload = () => {
      if (cancelled) return
      setImage(loaded)
      setCrop(centeredCrop(loaded, MIN_ZOOM))
    }

    loaded.onerror = () => {
      if (cancelled) return
      setError('We could not read that image. Choose a different photo.')
    }

    loaded.src = url

    return () => {
      cancelled = true
      loaded.onload = null
      loaded.onerror = null
      URL.revokeObjectURL(url)
    }
  }, [file])

  const size = image
    ? scaledSize(image, crop.zoom)
    : { width: 0, height: 0 }
  const busy = isUploading || isPreparing

  function applyOffset(next: Offset) {
    setCrop((previous) => ({ ...previous, ...next }))
  }

  function handleZoom(next: number) {
    if (!image) return

    const zoom = clamp(next, MIN_ZOOM, MAX_ZOOM)

    setCrop((previous) => {
      // Anchor the viewport centre so zooming does not jump the subject.
      const previousSize = scaledSize(image, previous.zoom)
      const centerX = (VIEWPORT / 2 - previous.x) / previousSize.width
      const centerY = (VIEWPORT / 2 - previous.y) / previousSize.height
      const nextSize = scaledSize(image, zoom)
      const offset = clampOffset(
        VIEWPORT / 2 - centerX * nextSize.width,
        VIEWPORT / 2 - centerY * nextSize.height,
        nextSize
      )

      return { zoom, ...offset }
    })
  }

  function nudge(dx: number, dy: number) {
    if (!image) return

    setCrop((previous) => {
      const currentSize = scaledSize(image, previous.zoom)
      const offset = clampOffset(
        previous.x + dx,
        previous.y + dy,
        currentSize
      )

      return { ...previous, ...offset }
    })
  }

  function handlePointerDown(event: PointerEvent<HTMLDivElement>) {
    if (!image || event.button !== 0) return

    event.currentTarget.setPointerCapture(event.pointerId)
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      originX: crop.x,
      originY: crop.y,
    }
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId || !image) return

    const currentSize = scaledSize(image, crop.zoom)
    applyOffset(
      clampOffset(
        drag.originX + (event.clientX - drag.startX),
        drag.originY + (event.clientY - drag.startY),
        currentSize
      )
    )
  }

  function handlePointerUp(event: PointerEvent<HTMLDivElement>) {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return

    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }

    dragRef.current = null
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.shiftKey ? ARROW_STEP_FAST : ARROW_STEP

    if (event.key === 'ArrowLeft') nudge(-step, 0)
    else if (event.key === 'ArrowRight') nudge(step, 0)
    else if (event.key === 'ArrowUp') nudge(0, -step)
    else if (event.key === 'ArrowDown') nudge(0, step)
    else return

    event.preventDefault()
  }

  async function handleUpload() {
    if (!image) return

    setIsPreparing(true)
    setError(null)

    try {
      const requestedType = outputMimeType(file.type)
      const canvas = document.createElement('canvas')
      canvas.width = OUTPUT
      canvas.height = OUTPUT

      const context = canvas.getContext('2d')
      if (!context) {
        setError('We could not prepare that image. Try another photo.')
        return
      }

      const factor = OUTPUT / VIEWPORT
      const currentSize = scaledSize(image, crop.zoom)

      context.imageSmoothingEnabled = true
      context.imageSmoothingQuality = 'high'

      if (requestedType === 'image/jpeg') {
        context.fillStyle = '#ffffff'
        context.fillRect(0, 0, OUTPUT, OUTPUT)
      }

      context.drawImage(
        image,
        crop.x * factor,
        crop.y * factor,
        currentSize.width * factor,
        currentSize.height * factor
      )

      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, requestedType, JPEG_QUALITY)
      )

      if (!blob) {
        setError('We could not prepare that image. Try another photo.')
        return
      }

      if (blob.size > AVATAR_MAX_BYTES) {
        setError('That photo is too large. Try a different image.')
        return
      }

      // Trust the encoder's actual type when it reports an allowed one, so a
      // browser that cannot encode WebP does not mislabel a PNG payload.
      const producedType = isAllowedAvatarMimeType(blob.type)
        ? blob.type
        : requestedType

      onConfirm(
        new File([blob], filenameFor(producedType), { type: producedType })
      )
    } finally {
      setIsPreparing(false)
    }
  }

  return (
    <div className="space-y-3">
      <div
        role="group"
        aria-label="Crop your photo"
        aria-describedby="avatar-crop-hint"
        tabIndex={0}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
        onKeyDown={handleKeyDown}
        className={`relative cursor-grab touch-none overflow-hidden rounded-xl border border-border bg-background active:cursor-grabbing ${focusClasses}`}
        style={{ width: VIEWPORT, height: VIEWPORT }}
      >
        {image && (
          // eslint-disable-next-line @next/next/no-img-element -- local object URL preview; next/image cannot optimize blob sources
          <img
            src={image.src}
            alt=""
            aria-hidden="true"
            draggable={false}
            className="pointer-events-none absolute max-w-none select-none"
            style={{
              left: crop.x,
              top: crop.y,
              width: size.width,
              height: size.height,
            }}
          />
        )}
      </div>

      <p id="avatar-crop-hint" className="text-sm text-zinc-600">
        Drag the photo to reposition it, or focus the frame and use the arrow
        keys. Use the slider to zoom.
      </p>

      <div>
        <label htmlFor="avatar-zoom" className={labelClasses}>
          Zoom
        </label>
        <input
          id="avatar-zoom"
          type="range"
          min={MIN_ZOOM}
          max={MAX_ZOOM}
          step={0.01}
          value={crop.zoom}
          disabled={!image || busy}
          onChange={(event) => handleZoom(Number(event.target.value))}
          className={`mt-1 w-full accent-brand ${focusClasses}`}
        />
      </div>

      {error && (
        <p role="alert" className="text-sm text-red-600">
          {error}
        </p>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={handleUpload}
          disabled={!image || busy}
          className={primaryButtonClasses}
        >
          {busy ? 'Preparing…' : 'Upload photo'}
        </button>

        <button
          type="button"
          onClick={onCancel}
          disabled={busy}
          className={secondaryButtonClasses}
        >
          Cancel
        </button>

        <button
          type="button"
          onClick={() => image && setCrop(centeredCrop(image, MIN_ZOOM))}
          disabled={!image || busy}
          className={`rounded-full px-3 py-2 text-sm font-medium text-brand transition-colors hover:text-brand-light disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`}
        >
          Reset
        </button>
      </div>
    </div>
  )
}
