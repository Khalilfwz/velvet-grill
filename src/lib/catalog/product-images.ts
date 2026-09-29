import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

export const PRODUCT_IMAGES_BUCKET = 'product-images'

export type ProductImageRow = Pick<
  Database['public']['Tables']['product_images']['Row'],
  'id' | 'storage_path' | 'alt_text' | 'sort_order' | 'is_primary' | 'created_at'
>

export function orderProductImages(
  images: ProductImageRow[]
): ProductImageRow[] {
  return [...images].sort((a, b) => {
    if (a.is_primary !== b.is_primary) {
      return a.is_primary ? -1 : 1
    }

    if (a.sort_order !== b.sort_order) {
      return a.sort_order - b.sort_order
    }

    const byCreatedAt = a.created_at.localeCompare(b.created_at)

    if (byCreatedAt !== 0) {
      return byCreatedAt
    }

    return a.id.localeCompare(b.id)
  })
}

export function selectPrimaryImage(
  images: ProductImageRow[]
): ProductImageRow | null {
  return orderProductImages(images)[0] ?? null
}

export function getProductImageUrl(
  supabase: SupabaseClient<Database>,
  storagePath: string
): string {
  return supabase.storage
    .from(PRODUCT_IMAGES_BUCKET)
    .getPublicUrl(storagePath).data.publicUrl
}
