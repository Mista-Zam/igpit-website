import { useCallback, useEffect, useMemo, useState } from 'react'

import {
  adminService,
  formatRelative,
  type ReportWithPost,
} from '../lib/utils'
import {
  NOTE_COLOR_HEX,
  REJECTION_REASONS,
  REPORT_STATUS_META,
  STATUS_META,
} from '../lib/constants'
import { useAuth } from '../context/AuthContext'
import type {
  DashboardStats,
  ModerationLog,
  Post,
  PostStatus,
  RejectionReason,
} from '../types'

type Tab = PostStatus | 'reports' | 'logs'

const TABS: { key: Tab; label: string }[] = [
  { key: 'pending', label: 'Pending' },
  { key: 'published', label: 'Published' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'removed', label: 'Removed' },
  { key: 'reports', label: 'Reports' },
  { key: 'logs', label: 'Logs' },
]

const StatCard = ({ label, value }: { label: string; value: number | undefined }) => (
  <div className="rounded-2xl bg-white/95 px-4 py-3 shadow-note ring-1 ring-black/5">
    <div className="text-2xl font-bold text-ink">{value ?? 'â€“'}</div>
    <div className="text-xs font-semibold uppercase tracking-wide text-ink-soft">{label}</div>
  </div>
)

const NoteCard = ({
  post,
  busy,
  onApprove,
  onReject,
  onRemove,
  onRestore,
}: {
  post: Post
  busy: boolean
  onApprove: (p: Post) => void
  onReject: (p: Post, reason: RejectionReason) => void
  onRemove: (p: Post) => void
  onRestore: (p: Post) => void
}) => {
  const [reason, setReason] = useState<RejectionReason>('Inappropriate content')

  return (
    <article className="space-y-3 rounded-2xl bg-white/95 p-4 shadow-note ring-1 ring-black/5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-ink-soft">
          To {post.recipient}
        </div>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-bold ${STATUS_META[post.status].className}`}
        >
          {STATUS_META[post.status].label}
        </span>
      </div>

      <div
        className="rounded-xl p-3 text-sm text-ink"
        style={{ backgroundColor: NOTE_COLOR_HEX[post.note_color] }}
      >
        {post.content}
      </div>

      <div className="flex flex-wrap items-center gap-2 text-xs font-medium text-ink-faint">
        <span>{post.is_anonymous ? 'Anonymous' : 'Named'}</span>
        <span>Â·</span>
        <span>{formatRelative(post.created_at)}</span>
      </div>

      {post.rejection_reason && (
        <div className="text-xs font-semibold text-rose-600">
          Rejected: {post.rejection_reason}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 border-t border-black/5 pt-3">
        {(post.status === 'pending' || post.status === 'rejected') && (
          <>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as RejectionReason)}
              disabled={busy}
              className="rounded-full border border-beige-deep/70 bg-white px-2 py-1 text-xs font-semibold focus:outline-none focus:ring-2 focus:ring-brand"
            >
              {REJECTION_REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
            <button
              type="button"
              disabled={busy}
              onClick={() => onApprove(post)}
              className="rounded-full bg-emerald-600 px-3 py-1 text-xs font-bold text-white transition hover:bg-emerald-700 disabled:opacity-50"
            >
              Approve
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => onReject(post, reason)}
              className="rounded-full bg-amber-500 px-3 py-1 text-xs font-bold text-white transition hover:bg-amber-600 disabled:opacity-50"
            >
              Reject
            </button>
          </>
        )}

        {post.status === 'published' && (
          <button
            type="button"
            disabled={busy}
            onClick={() => onRemove(post)}
            className="rounded-full bg-rose-600 px-3 py-1 text-xs font-bold text-white transition hover:bg-rose-700 disabled:opacity-50"
          >
            Remove
          </button>
        )}

        {post.status === 'removed' && (
          <button
            type="button"
            disabled={busy}
            onClick={() => onRestore(post)}
            className="rounded-full bg-slate-700 px-3 py-1 text-xs font-bold text-white transition hover:bg-slate-800 disabled:opacity-50"
          >
            Restore
          </button>
        )}
      </div>
    </article>
  )
}

const Admin = () => {
  const { profile, signOut } = useAuth()
  const [tab, setTab] = useState<Tab>('pending')
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [posts, setPosts] = useState<Post[]>([])
  const [reports, setReports] = useState<ReportWithPost[]>([])
  const [logs, setLogs] = useState<ModerationLog[]>([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [flash, setFlash] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [s, p, r, l] = await Promise.all([
        adminService.stats(),
        adminService.listPosts({ status: tab as PostStatus }),
        adminService.listReports(),
        adminService.listLogs(),
      ])
      setStats(s)
      setPosts(p)
      setReports(r)
      setLogs(l)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load moderation data')
    } finally {
      setLoading(false)
    }
  }, [tab])

  useEffect(() => {
    void load()
  }, [load])

  const pendingReports = useMemo(() => reports.filter((r) => r.status === 'pending'), [reports])

  const run = async (
    postId: string,
    label: string,
    fn: () => Promise<void>
  ) => {
    setBusyId(postId)
    setError(null)
    setFlash(null)
    try {
      await fn()
      setFlash(label)
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed')
    } finally {
      setBusyId(null)
    }
  }

  const onApprove = (p: Post) =>
    run(p.id, 'Note published.', () => adminService.moderate(p.id, 'approve'))

  const onReject = (p: Post, reason: RejectionReason) =>
    run(p.id, 'Note rejected.', () =>
      adminService.moderate(p.id, 'reject', reason, reason)
    )

  const onRemove = (p: Post) =>
    run(p.id, 'Note removed.', () =>
      adminService.moderate(p.id, 'remove', 'Removed from the wall')
    )

  const onRestore = (p: Post) =>
    run(p.id, 'Note restored.', () => adminService.moderate(p.id, 'restore'))

  const onResolveReport = (r: ReportWithPost, decision: 'dismiss' | 'keep_published' | 'remove_post') =>
    run(r.id, 'Report resolved.', () => adminService.resolveReport(r.id, decision))

  const showPosts = tab !== 'reports' && tab !== 'logs'

  return (
    <section className="mx-auto max-w-5xl space-y-6 px-4 py-10 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="font-display text-3xl font-bold sm:text-4xl">Admin Dashboard</h1>
          <p className="text-ink-soft">
            Signed in as {profile?.display_name ?? 'admin'} Â· {profile?.role}
          </p>
        </div>
        <button
          type="button"
          onClick={() => void signOut()}
          className="rounded-full bg-white/95 px-4 py-2 text-sm font-semibold ring-1 ring-black/5 hover:bg-white"
        >
          Sign Out
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Pending" value={stats?.pending_count} />
        <StatCard label="Published" value={stats?.published_count} />
        <StatCard label="Open Reports" value={pendingReports.length} />
        <StatCard label="Teachers" value={stats?.teacher_count} />
      </div>

      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`rounded-full px-4 py-1.5 text-xs font-bold uppercase tracking-wide transition ${
              tab === t.key
                ? 'bg-brand text-white shadow-sm'
                : 'bg-white/90 text-ink-soft ring-1 ring-black/5 hover:bg-white'
            }`}
          >
            {t.label}
            {t.key === 'reports' && pendingReports.length > 0 && (
              <span className="ml-1.5 rounded-full bg-rose-600 px-1.5 text-white">
                {pendingReports.length}
              </span>
            )}
          </button>
        ))}
      </div>

      {error && (
        <div className="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-700 ring-1 ring-rose-200">
          {error}
        </div>
      )}
      {flash && (
        <div className="rounded-2xl bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-700 ring-1 ring-emerald-200">
          {flash}
        </div>
      )}

      {loading && (
        <div className="py-10 text-center text-sm font-semibold text-ink-soft">Loadingâ€¦</div>
      )}

      {!loading && showPosts && (
        <div className="space-y-3">
          {posts.length === 0 && (
            <p className="py-10 text-center text-sm text-ink-soft">Nothing here.</p>
          )}
          {posts.map((p) => (
            <NoteCard
              key={p.id}
              post={p}
              busy={busyId === p.id}
              onApprove={onApprove}
              onReject={onReject}
              onRemove={onRemove}
              onRestore={onRestore}
            />
          ))}
        </div>
      )}

      {!loading && tab === 'reports' && (
        <div className="space-y-3">
          {reports.length === 0 && (
            <p className="py-10 text-center text-sm text-ink-soft">No reports.</p>
          )}
          {reports.map((r) => (
            <article
              key={r.id}
              className="space-y-3 rounded-2xl bg-white/95 p-4 shadow-note ring-1 ring-black/5"
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="text-sm font-bold text-ink">{r.reason}</div>
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-bold ${REPORT_STATUS_META[r.status].className}`}
                >
                  {REPORT_STATUS_META[r.status].label}
                </span>
              </div>

              {r.details && <p className="text-sm text-ink-soft">â€œ{r.details}â€</p>}

              {r.post ? (
                <div className="rounded-xl bg-cream p-3 text-sm text-ink">
                  <div className="text-xs font-semibold uppercase text-ink-soft">
                    To {r.post.recipient} Â· {r.post.status}
                  </div>
                  <p className="mt-1">{r.post.content}</p>
                </div>
              ) : (
                <p className="text-sm text-ink-faint">The reported note no longer exists.</p>
              )}

              <div className="text-xs text-ink-faint">{formatRelative(r.created_at)}</div>

              {r.status === 'pending' && (
                <div className="flex flex-wrap gap-2 border-t border-black/5 pt-3">
                  <button
                    type="button"
                    disabled={busyId === r.id}
                    onClick={() => onResolveReport(r, 'dismiss')}
                    className="rounded-full bg-slate-600 px-3 py-1 text-xs font-bold text-white hover:bg-slate-700 disabled:opacity-50"
                  >
                    Dismiss
                  </button>
                  <button
                    type="button"
                    disabled={busyId === r.id}
                    onClick={() => onResolveReport(r, 'keep_published')}
                    className="rounded-full bg-emerald-600 px-3 py-1 text-xs font-bold text-white hover:bg-emerald-700 disabled:opacity-50"
                  >
                    Keep Note
                  </button>
                  <button
                    type="button"
                    disabled={busyId === r.id}
                    onClick={() => onResolveReport(r, 'remove_post')}
                    className="rounded-full bg-rose-600 px-3 py-1 text-xs font-bold text-white hover:bg-rose-700 disabled:opacity-50"
                  >
                    Remove Note
                  </button>
                </div>
              )}
            </article>
          ))}
        </div>
      )}

      {!loading && tab === 'logs' && (
        <div className="overflow-x-auto rounded-2xl bg-white/95 shadow-note ring-1 ring-black/5">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-black/5 text-xs uppercase tracking-wide text-ink-soft">
              <tr>
                <th className="px-4 py-3">When</th>
                <th className="px-4 py-3">Moderator</th>
                <th className="px-4 py-3">Action</th>
                <th className="px-4 py-3">Note</th>
                <th className="px-4 py-3">Reason</th>
              </tr>
            </thead>
            <tbody>
              {logs.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-10 text-center text-ink-soft">
                    No moderation activity yet.
                  </td>
                </tr>
              )}
              {logs.map((l) => (
                <tr key={l.id} className="border-b border-black/5 last:border-0">
                  <td className="whitespace-nowrap px-4 py-3 text-ink-soft">
                    {formatRelative(l.created_at)}
                  </td>
                  <td className="px-4 py-3 font-semibold">{l.moderator_display_name}</td>
                  <td className="px-4 py-3">{l.action}</td>
                  <td className="px-4 py-3">{l.post_recipient}</td>
                  <td className="px-4 py-3 text-ink-soft">{l.reason ?? 'â€“'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}

export default Admin