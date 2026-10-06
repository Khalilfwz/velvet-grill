import Link from 'next/link'
import { requireAdminPage } from '@/lib/admin/guard'
import type { Json } from '@/lib/supabase/database.types'

export const metadata = {
  title: 'Audit',
}

// entity_type values written by the FR-25 audit trigger, one per
// admin-mutable table.
const AUDIT_ENTITY_TYPES = [
  'business_hours',
  'categories',
  'order_item_options',
  'order_items',
  'orders',
  'payments',
  'product_images',
  'product_option_groups',
  'product_options',
  'products',
  'restaurant_settings',
  'restaurant_tables',
  'reviews',
] as const

type AuditEntityType = (typeof AUDIT_ENTITY_TYPES)[number]

function isAuditEntityType(value: string): value is AuditEntityType {
  return (AUDIT_ENTITY_TYPES as readonly string[]).includes(value)
}

const focusClasses =
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand'

function chipClasses(active: boolean): string {
  return `rounded-full border px-3 py-1 font-medium transition-colors ${focusClasses} ${
    active
      ? 'border-brand text-brand'
      : 'border-border text-zinc-600 hover:border-brand hover:text-brand'
  }`
}

function formatDateTime(value: string): string {
  return new Date(value).toLocaleString('id-ID', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function formatMetadata(value: Json | null): string {
  if (value === null) {
    return '—'
  }

  return JSON.stringify(value, null, 2)
}

export default async function AdminAuditPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { supabase } = await requireAdminPage()
  const params = await searchParams
  const entityParam =
    typeof params.entity_type === 'string' ? params.entity_type : ''
  const entityFilter = isAuditEntityType(entityParam) ? entityParam : null

  const auditQuery = supabase
    .from('admin_audit_logs')
    .select(
      'id, created_at, actor_user_id, action, entity_type, entity_id, before_data, after_data, profiles(full_name)'
    )
    .order('created_at', { ascending: false })
    .limit(100)

  const { data: logs, error } = entityFilter
    ? await auditQuery.eq('entity_type', entityFilter)
    : await auditQuery

  if (error) {
    console.error('Failed to load admin audit logs:', error)

    return (
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Audit
        </h1>
        <p className="mt-4 text-red-600">Failed to load audit logs.</p>
      </div>
    )
  }

  const rows = logs ?? []

  return (
    <div className="space-y-10">
      <div>
        <h1 className="font-display text-3xl font-bold text-foreground">
          Audit
        </h1>
        <p className="mt-2 text-sm text-zinc-600">
          Sensitive admin actions recorded by the database, newest first.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Link
          href="/admin/audit"
          className={chipClasses(entityFilter === null)}
        >
          All
        </Link>
        {AUDIT_ENTITY_TYPES.map((entityType) => (
          <Link
            key={entityType}
            href={`/admin/audit?entity_type=${entityType}`}
            className={chipClasses(entityFilter === entityType)}
          >
            {entityType}
          </Link>
        ))}
      </div>

      <section className="space-y-4">
        {rows.length === 0 ? (
          <p className="text-sm text-zinc-600">No audit entries found.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-border text-zinc-600">
                <tr>
                  <th className="px-4 py-3 font-medium">When</th>
                  <th className="px-4 py-3 font-medium">Actor</th>
                  <th className="px-4 py-3 font-medium">Action</th>
                  <th className="px-4 py-3 font-medium">Entity</th>
                  <th className="px-4 py-3 font-medium">Entity id</th>
                  <th className="px-4 py-3 font-medium">Metadata</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((log) => (
                  <tr
                    key={log.id}
                    className="border-b border-border align-top last:border-b-0"
                  >
                    <td className="px-4 py-3 text-zinc-600">
                      {formatDateTime(log.created_at)}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {log.profiles?.full_name ?? log.actor_user_id ?? '—'}
                    </td>
                    <td className="px-4 py-3 font-medium text-foreground">
                      {log.action}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {log.entity_type}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      {log.entity_id ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-zinc-600">
                      <details>
                        <summary
                          className={`cursor-pointer font-medium text-brand ${focusClasses}`}
                        >
                          View
                        </summary>
                        <div className="mt-2 space-y-2">
                          <div>
                            <p className="text-xs font-medium text-zinc-500">
                              Before
                            </p>
                            <pre className="mt-1 max-w-md overflow-x-auto rounded-lg border border-border bg-background p-2 text-xs text-zinc-600">
                              {formatMetadata(log.before_data)}
                            </pre>
                          </div>
                          <div>
                            <p className="text-xs font-medium text-zinc-500">
                              After
                            </p>
                            <pre className="mt-1 max-w-md overflow-x-auto rounded-lg border border-border bg-background p-2 text-xs text-zinc-600">
                              {formatMetadata(log.after_data)}
                            </pre>
                          </div>
                        </div>
                      </details>
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
