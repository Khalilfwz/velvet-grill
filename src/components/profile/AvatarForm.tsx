'use client'

import Image from 'next/image'
import {
  startTransition,
  useRef,
  useState,
  useActionState,
  type ChangeEvent,
} from 'react'
import {
  uploadAvatar,
  removeAvatar,
  type AvatarActionState,
} from '@/lib/profile/avatar-actions'
import AvatarCropper from '@/components/profile/AvatarCropper'
import { isAllowedAvatarMimeType } from '@/lib/profile/avatar'

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

const labelClasses = 'block text-sm font-medium text-foreground'

const secondaryButtonClasses = `rounded-full border border-border px-5 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand disabled:cursor-not-allowed disabled:opacity-60 ${focusClasses}`

const initialState: AvatarActionState = { error: null, success: false }

type AvatarFormProps = {
  avatarUrl: string | null
}

export default function AvatarForm({ avatarUrl }: AvatarFormProps) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [localError, setLocalError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  // The upload action wraps the server action so a confirmed upload can drop
  // the crop and let the freshly revalidated avatar become the visible
  // preview. Resetting here, rather than in an effect, keeps the state change
  // on the action that caused it.
  const [uploadState, uploadAction, isUploading] = useActionState(
    async (previousState: AvatarActionState, formData: FormData) => {
      const result = await uploadAvatar(previousState, formData)

      if (result.success) {
        setSelectedFile(null)
        setLocalError(null)
      }

      return result
    },
    initialState
  )
  const [removeState, removeAction, isRemoving] = useActionState(
    removeAvatar,
    initialState
  )

  const error = localError ?? uploadState.error ?? removeState.error
  const success = uploadState.success || removeState.success

  function handleFileChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0] ?? null

    if (!file) {
      setSelectedFile(null)
      return
    }

    // The accept attribute is a hint; the browser can still supply any file.
    // SVG and other types are rejected here before any preview is attempted,
    // and the server re-validates the uploaded blob regardless.
    if (!isAllowedAvatarMimeType(file.type)) {
      setLocalError('Choose a JPEG, PNG, or WebP image.')
      setSelectedFile(null)
      event.target.value = ''
      return
    }

    setLocalError(null)
    setSelectedFile(file)
  }

  function handleCancelCrop() {
    setSelectedFile(null)
    setLocalError(null)
    if (inputRef.current) {
      inputRef.current.value = ''
    }
  }

  function handleConfirmCrop(file: File) {
    const formData = new FormData()
    formData.set('avatar', file)

    // The dispatch runs outside a form action, so it must be wrapped in a
    // transition for the pending state (isUploading) to update correctly.
    startTransition(() => {
      uploadAction(formData)
    })
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start gap-4">
        <span className="block h-16 w-16 shrink-0 overflow-hidden rounded-full border border-border bg-background">
          {avatarUrl ? (
            <Image
              src={avatarUrl}
              alt="Your profile photo"
              width={64}
              height={64}
              className="h-full w-full object-cover"
            />
          ) : (
            <span className="flex h-full w-full items-center justify-center text-xs text-zinc-500">
              No photo
            </span>
          )}
        </span>

        <div className="min-w-[16rem] flex-1 space-y-2">
          <span className={labelClasses}>Profile photo</span>

          {selectedFile ? (
            <AvatarCropper
              file={selectedFile}
              isUploading={isUploading}
              onCancel={handleCancelCrop}
              onConfirm={handleConfirmCrop}
            />
          ) : (
            <>
              <div className="flex items-center gap-3">
                <input
                  ref={inputRef}
                  id="avatar"
                  name="avatar"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  onChange={handleFileChange}
                  className="peer sr-only"
                />
                <label
                  htmlFor="avatar"
                  className={`cursor-pointer rounded-full border border-border px-4 py-2 text-sm font-medium text-foreground transition-colors hover:border-brand hover:text-brand peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-brand ${focusClasses}`}
                >
                  {avatarUrl ? 'Choose a new photo' : 'Choose photo'}
                </label>
              </div>
              <p className="text-sm text-zinc-600">JPEG, PNG, or WebP. Max 2 MB.</p>
            </>
          )}
        </div>
      </div>

      {avatarUrl && !selectedFile && (
        <form action={removeAction}>
          <button
            type="submit"
            disabled={isRemoving}
            className={secondaryButtonClasses}
          >
            {isRemoving ? 'Removing…' : 'Remove photo'}
          </button>
        </form>
      )}

      {error && (
        <p role="alert" className="text-sm text-red-600">
          {error}
        </p>
      )}

      {success && !error && !selectedFile && (
        <p role="status" className="text-sm font-medium text-brand">
          Photo updated.
        </p>
      )}
    </div>
  )
}
