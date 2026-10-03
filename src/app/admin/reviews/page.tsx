import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import ReviewModerationForm from '@/components/admin/ReviewModerationForm'
import type { Database } from '@/lib/supabase/database.types'

export const metadata = {
  title: 'Reviews',
}

type ReviewStatus = Database['public']['Enums']['review_status']

const REVIEW_STATUSES: ReviewStatus[] = ['PUBLISHED', 'HIDDEN']

function isReviewStatus(value: string): value is ReviewStatus {
  return (REVIEW_STATUSES as string[]).includes(value)
}

function excerpt(value: string | null): string {
  if (!value) {
    return '—'
  }

  return value.length > 120 ? `${value.slice(0, 120)}…` : value
}

function formatDateTime(value: string): string {
  return new Date(value).toLocaleString('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

export default async function AdminReviewsPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { supabase } = await requireAdminPage()
  const params = await searchParams
  const statusParam = typeof params.status === 'string' ? params.status : ''
  const statusFilter = isReviewStatus(statusParam) ? statusParam : null

  const reviewsQuery = supabase
    .from('reviews')
    .select(
      'id, rating, title, content, status, created_at, products(name), profiles(full_name)'
    )
    .order('created_at', { ascending: false })
    .limit(100)

  const { data: reviews, error } = statusFilter
    ? await reviewsQuery.eq('status', statusFilter)
    : await reviewsQuery

  if (error) {
    console.error('Failed to load admin reviews:', error)

    return (
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Reviews
        </h1>
        <p className="mt-4 text-red-600">Failed to load reviews.</p>
      </div>
    )
  }

  const rows = reviews ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Reviews
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Hide or republish customer reviews.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Link
          href="/admin/reviews"
          className={`rounded-full border px-3 py-1 font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand ${
            statusFilter
              ? 'border-border text-zinc-600 hover:border-brand hover:text-brand'
              : 'border-brand text-brand'
          }`}
        >
          All
        </Link>
        {REVIEW_STATUSES.map((status) => (
          <Link
            key={status}
            href={`/admin/reviews?status=${status}`}
            className={`rounded-full border px-3 py-1 font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand ${
              statusFilter === status
                ? 'border-brand text-brand'
                : 'border-border text-zinc-600 hover:border-brand hover:text-brand'
            }`}
          >
            {status}
          </Link>
        ))}
      </div>

      <section className="space-y-4">
        {rows.length === 0 ? (
          <p className="text-sm text-zinc-600">No reviews found.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Product</th>
                  <th className="px-4 py-3 font-medium">Author</th>
                  <th className="px-4 py-3 font-medium">Rating</th>
                  <th className="px-4 py-3 font-medium">Review</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Created</th>
                  <th className="px-4 py-3 font-medium">Moderate</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((review) => (
                  <tr
                    key={review.id}
                    className="border-b border-border align-top last:border-b-0"
                  >
                    <td className="px-4 py-3 text-zinc-600">
                      {review.products?.name ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {review.profiles?.full_name ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">{review.rating}</td>
                    <td className="px-4 py-3 text-zinc-600">
                      {review.title && (
                        <span className="block font-medium text-foreground">
                          {review.title}
                        </span>
                      )}
                      {excerpt(review.content)}
                    </td>
                    <td className="px-4 py-3">
                      {review.status === 'PUBLISHED' ? (
                        <span className="text-emerald-700">Published</span>
                      ) : (
                        <span className="text-zinc-500">Hidden</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {formatDateTime(review.created_at)}
                    </td>
                    <td className="px-4 py-3">
                      <ReviewModerationForm
                        reviewId={review.id}
                        status={review.status}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}
