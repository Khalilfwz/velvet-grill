import { requireAdminPage } from '@/lib/admin/guard'
import AdminPageHeading from '@/components/admin/AdminPageHeading'
import EmptyState from '@/components/admin/EmptyState'
import FilterChips from '@/components/admin/FilterChips'
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

// Display-only humanizing of the stored tokens; filter/query values stay raw.
function entityLabel(entityType: string): string {
  return entityType
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
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
        <AdminPageHeading
          title="Audit"
          description="Sensitive admin actions recorded by the database, newest first."
        />
        <p role="alert" className="mt-4 text-sm text-red-600">
          Failed to load audit logs.
        </p>
      </div>
    )
  }

  const rows = logs ?? []

  return (
    <div className="space-y-8">
      <AdminPageHeading
        title="Audit"
        description="Sensitive admin actions recorded by the database, newest first."
      />

      <FilterChips
        ariaLabel="Filter audit logs by entity type"
        activeValue={entityFilter ?? 'ALL'}
        items={[
          { value: 'ALL', label: 'All', href: '/admin/audit' },
          ...AUDIT_ENTITY_TYPES.map((entityType) => ({
            value: entityType,
            label: entityLabel(entityType),
            href: `/admin/audit?entity_type=${entityType}`,
          })),
        ]}
      />

      <section>
        {rows.length === 0 ? (
          <EmptyState
            message={
              entityFilter
                ? 'No audit entries for this entity type.'
                : 'No audit entries found.'
            }
          />
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface">
            <div
              role="region"
              aria-label="Audit log"
              tabIndex={0}
              className="overflow-x-auto focus-visible:outline-2 -outline-offset-2 focus-visible:outline-brand"
            >
              <table className="w-full min-w-[860px] text-left text-sm">
                <caption className="sr-only">
                  Audit log entries, newest first; metadata expands per row.
                </caption>
                <thead className="border-b border-border text-zinc-600">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-medium">When</th>
                    <th scope="col" className="px-4 py-3 font-medium">Actor</th>
                    <th scope="col" className="px-4 py-3 font-medium">Action</th>
                    <th scope="col" className="px-4 py-3 font-medium">Entity</th>
                    <th scope="col" className="px-4 py-3 font-medium">Entity id</th>
                    <th scope="col" className="px-4 py-3 font-medium">Metadata</th>
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
                        {entityLabel(log.entity_type)}
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        {log.entity_id ? (
                          <span
                            title={log.entity_id}
                            className="block max-w-[16ch] truncate font-mono text-xs"
                          >
                            {log.entity_id}
                          </span>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="px-4 py-3 text-zinc-600">
                        <details>
                          <summary
                            aria-label={`View change for ${log.action} ${entityLabel(log.entity_type)}`}
                            className="cursor-pointer font-medium text-brand focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
                          >
                            View
                          </summary>
                          <div className="mt-2 grid gap-3 sm:grid-cols-2">
                            <div>
                              <p className="text-xs font-medium text-zinc-500">
                                Before
                              </p>
                              <pre className="mt-1 overflow-x-auto rounded-lg border border-border bg-background p-2 text-xs text-zinc-600">
                                {formatMetadata(log.before_data)}
                              </pre>
                            </div>
                            <div>
                              <p className="text-xs font-medium text-zinc-500">
                                After
                              </p>
                              <pre className="mt-1 overflow-x-auto rounded-lg border border-border bg-background p-2 text-xs text-zinc-600">
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
          </div>
        )}
      </section>
    </div>
  )
}
