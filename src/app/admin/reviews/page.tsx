import { requireAdminPage } from '@/lib/admin/guard'
import ReviewModerationForm from '@/components/admin/ReviewModerationForm'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import FilterChips from '@/components/admin/FilterChips'
import StatusBadge from '@/components/admin/StatusBadge'
import { Star } from 'lucide-react'
import type { Database } from '@/lib/supabase/database.types'

export const metadata = {
  title: 'Reviews',
}

type ReviewStatus = Database['public']['Enums']['review_status']

const REVIEW_STATUSES: ReviewStatus[] = ['PUBLISHED', 'HIDDEN']

const REVIEW_STATUS_LABELS: Record<ReviewStatus, string> = {
  PUBLISHED: 'Published',
  HIDDEN: 'Hidden',
}

function isReviewStatus(value: string): value is ReviewStatus {
  return (REVIEW_STATUSES as string[]).includes(value)
}

function RatingStars({ rating }: { rating: number }) {
  return (
    <span
      role="img"
      aria-label={`Rated ${rating} out of 5`}
      className="inline-flex items-center gap-0.5"
    >
      {[1, 2, 3, 4, 5].map((value) => (
        <Star
          key={value}
          size={14}
          aria-hidden="true"
          className={value <= rating ? 'fill-current text-brand' : 'text-border'}
        />
      ))}
    </span>
  )
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
        <AdminPageHeading
          title="Reviews"
          description="Hide or republish customer reviews."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load reviews.
        </p>
      </div>
    )
  }

  const rows = reviews ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Reviews"
        description="Hide or republish customer reviews."
      />

      <FilterChips
        ariaLabel="Filter reviews by status"
        activeValue={statusFilter ?? 'ALL'}
        items={[
          { value: 'ALL', label: 'All', href: '/admin/reviews' },
          ...REVIEW_STATUSES.map((status) => ({
            value: status,
            label: REVIEW_STATUS_LABELS[status],
            href: `/admin/reviews?status=${status}`,
          })),
        ]}
      />

      <section>
        {rows.length === 0 ? (
          <EmptyState
            message={statusFilter ? 'No reviews with this status.' : 'No reviews found.'}
          />
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <div
              role="region"
              aria-label="Reviews"
              tabIndex={0}
              className="overflow-x-auto focus-visible:outline-2 -outline-offset-2 focus-visible:outline-brand"
            >
              <table className="w-full min-w-[760px] text-left text-sm">
                <caption className="sr-only">
                  Customer reviews with moderation status and hide or publish
                  actions.
                </caption>
                <thead className="border-b border-border text-zinc-600">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-medium">Product</th>
                    <th scope="col" className="px-4 py-3 font-medium">Author</th>
                    <th scope="col" className="px-4 py-3 font-medium">Rating</th>
                    <th scope="col" className="px-4 py-3 font-medium">Review</th>
                    <th scope="col" className="px-4 py-3 font-medium">Status</th>
                    <th scope="col" className="px-4 py-3 font-medium">Created</th>
                    <th scope="col" className="px-4 py-3 font-medium">Moderate</th>
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
                      <td className="px-4 py-3">
                        <RatingStars rating={review.rating} />
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        {review.title && (
                          <span className="block font-medium text-foreground">
                            {review.title}
                          </span>
                        )}
                        {review.content && review.content.length > 120 ? (
                          <details>
                            <summary className="cursor-pointer underline decoration-border underline-offset-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand">
                              {excerpt(review.content)}
                            </summary>
                            <p className="mt-2 whitespace-pre-wrap">
                              {review.content}
                            </p>
                          </details>
                        ) : (
                          excerpt(review.content)
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <StatusBadge
                          label={REVIEW_STATUS_LABELS[review.status]}
                          tone={review.status === 'PUBLISHED' ? 'brand' : 'muted'}
                        />
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        {formatDateTime(review.created_at)}
                      </td>
                      <td className="px-4 py-3">
                        <ReviewModerationForm
                          reviewId={review.id}
                          reviewTitle={review.title}
                          status={review.status}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}
