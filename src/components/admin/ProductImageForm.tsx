'use client'

import {
  useActionState,
  useState,
  useId,
  type FormEvent,
} from 'react'
import {
  saveProductImage,
  deleteProductImage,
  type AdminActionState,
} from '@/lib/admin/actions'
import { productImagePublicUrl } from '@/lib/catalog/product-images'
import StatusBadge from './StatusBadge'
import SubmitButton from './SubmitButton'
import AdminImagePreview from './AdminImagePreview'
import { adminInputClasses, adminLabelClasses } from './form-styles'

const pathLabelClasses = 'block text-xs font-medium text-zinc-500'

const pathInputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 font-mono text-xs text-zinc-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

export type ProductImageInitial = {
  id: string
  storagePath: string
  altText: string | null
  sortOrder: number
  isPrimary: boolean
}

const initialState: AdminActionState = { error: null }

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''

export default function ProductImageForm({
  productId,
  productSlug,
  initial,
  position,
}: {
  productId: string
  productSlug: string
  initial?: ProductImageInitial
  position?: number
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveProductImage, initialState)
  const [deleteState, deleteAction] = useActionState(
    deleteProductImage,
    initialState
  )
  const [pathDraft, setPathDraft] = useState(initial?.storagePath ?? '')

  const trimmedPath = pathDraft.trim()
  const previewSrc = trimmedPath
    ? productImagePublicUrl(trimmedPath, SUPABASE_URL)
    : null

  function confirmDelete(event: FormEvent<HTMLFormElement>) {
    if (!window.confirm('Delete this image? This cannot be undone.')) {
      event.preventDefault()
    }
  }

  return (
    <div className="space-y-4">
      {position !== undefined && (
        <div className="flex flex-wrap items-center gap-2">
          <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">
            Image {position}
          </p>
          {initial?.isPrimary && <StatusBadge tone="brand" label="Primary" />}
        </div>
      )}

      <form
        action={formAction}
        className="grid gap-4 sm:grid-cols-[200px_1fr]"
      >
        <input type="hidden" name="productId" value={productId} />
        <input type="hidden" name="productSlug" value={productSlug} />
        {initial && <input type="hidden" name="id" value={initial.id} />}

        <AdminImagePreview
          src={previewSrc}
          alt={initial?.altText || `${productSlug} image preview`}
          emptyHint={
            initial ? 'Preview unavailable' : 'Enter a storage path to preview'
          }
        />

        <div className="space-y-3">
          <div>
            <label className={adminLabelClasses} htmlFor={`${uid}-alt-text`}>
              Alt text
            </label>
            <input
              id={`${uid}-alt-text`}
              name="altText"
              defaultValue={initial?.altText ?? ''}
              maxLength={200}
              className={adminInputClasses}
            />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <label
                className={adminLabelClasses}
                htmlFor={`${uid}-sort-order`}
              >
                Sort order
              </label>
              <input
                id={`${uid}-sort-order`}
                name="sortOrder"
                type="number"
                min={0}
                defaultValue={initial?.sortOrder ?? 0}
                className={adminInputClasses}
              />
            </div>

            <label className="mt-1 flex items-center gap-2 text-sm text-foreground">
              <input
                type="checkbox"
                name="isPrimary"
                defaultChecked={initial?.isPrimary ?? false}
              />
              Primary image
            </label>
          </div>

          <div>
            <label
              className={pathLabelClasses}
              htmlFor={`${uid}-storage-path`}
            >
              Storage path
            </label>
            <input
              id={`${uid}-storage-path`}
              name="storagePath"
              defaultValue={initial?.storagePath ?? ''}
              onChange={(event) => setPathDraft(event.target.value)}
              required
              maxLength={255}
              placeholder="products/wagyu-ribeye-steak/main.webp"
              className={pathInputClasses}
            />
          </div>

          {state.error && (
            <p role="alert" className="text-sm text-red-600">
              {state.error}
            </p>
          )}

          <div>
            <SubmitButton
              label={initial ? 'Save image' : 'Add image'}
              pendingLabel="Saving…"
            />
          </div>
        </div>
      </form>

      {initial && (
        <div className="flex justify-end border-t border-border pt-3">
          <form action={deleteAction} onSubmit={confirmDelete}>
            <input type="hidden" name="id" value={initial.id} />
            <input type="hidden" name="productId" value={productId} />
            <input type="hidden" name="productSlug" value={productSlug} />

            {deleteState.error && (
              <p role="alert" className="mb-2 text-sm text-red-600">
                {deleteState.error}
              </p>
            )}

            <SubmitButton
              label="Delete image"
              pendingLabel="Deleting…"
              variant="danger"
            />
          </form>
        </div>
      )}
    </div>
  )
}
