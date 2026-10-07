'use client'

import { useActionState, useId } from 'react'
import {
  saveProductImage,
  deleteProductImage,
  type AdminActionState,
} from '@/lib/admin/actions'
import SubmitButton from './SubmitButton'

const inputClasses =
  'mt-1 w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'
const labelClasses = 'block text-sm font-medium text-foreground'

export type ProductImageInitial = {
  id: string
  storagePath: string
  altText: string | null
  sortOrder: number
  isPrimary: boolean
}

const initialState: AdminActionState = { error: null }

export default function ProductImageForm({
  productId,
  productSlug,
  initial,
}: {
  productId: string
  productSlug: string
  initial?: ProductImageInitial
}) {
  const uid = useId()
  const [state, formAction] = useActionState(saveProductImage, initialState)
  const [deleteState, deleteAction] = useActionState(
    deleteProductImage,
    initialState
  )

  return (
    <div className="space-y-3">
      <form action={formAction} className="space-y-3">
        <input type="hidden" name="productId" value={productId} />
        <input type="hidden" name="productSlug" value={productSlug} />
        {initial && <input type="hidden" name="id" value={initial.id} />}

        <div>
          <label className={labelClasses} htmlFor={`${uid}-storage-path`}>
            Storage path
          </label>
          <input
            id={`${uid}-storage-path`}
            name="storagePath"
            defaultValue={initial?.storagePath ?? ''}
            required
            maxLength={255}
            placeholder="products/wagyu-ribeye-steak/main.webp"
            className={inputClasses}
          />
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-alt-text`}>
            Alt text
          </label>
          <input
            id={`${uid}-alt-text`}
            name="altText"
            defaultValue={initial?.altText ?? ''}
            maxLength={200}
            className={inputClasses}
          />
        </div>

        <div>
          <label className={labelClasses} htmlFor={`${uid}-sort-order`}>
            Sort order
          </label>
          <input
            id={`${uid}-sort-order`}
            name="sortOrder"
            type="number"
            min={0}
            defaultValue={initial?.sortOrder ?? 0}
            className={inputClasses}
          />
        </div>

        <label className="flex items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            name="isPrimary"
            defaultChecked={initial?.isPrimary ?? false}
          />
          Primary
        </label>

        {state.error && (
          <p role="alert" className="text-sm text-red-600">
            {state.error}
          </p>
        )}

        <SubmitButton
          label={initial ? 'Save image' : 'Add image'}
          pendingLabel="Saving…"
        />
      </form>

      {initial && (
        <form action={deleteAction}>
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
            className="bg-red-700 hover:bg-red-800"
          />
        </form>
      )}
    </div>
  )
}
