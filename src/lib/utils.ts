import type {
  DashboardStats,
  ModerationAction,
  ModerationLog,
  Post,
  PostCategory,
  PostStatus,
  PublicPost,
  RejectionReason,
  Report,
} from '../types'

import { supabase } from './supabase'

export const formatDateTime = (iso: string) =>
  new Intl.DateTimeFormat('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(iso))

export const formatDate = (iso: string) =>
  new Intl.DateTimeFormat('en-US', {
    dateStyle: 'medium',
  }).format(new Date(iso))

export const formatRelative = (iso: string) => {
  const d = new Date(iso)
  const diff = Date.now() - d.getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const days = Math.floor(h / 24)
  if (days < 7) return `${days}d ago`
  return formatDate(iso)
}

/** Return a random integer in [min, max], inclusive. */
export const randInt = (min: number, max: number) => Math.floor(Math.random() * (max - min + 1)) + min

/** Return a small rotation in degrees for a sticky note. */
export const randomNoteRotation = () => `${randInt(-7, +5)}deg`

/** Clip a string to the provided max length, adding ellipsis if needed. */
export const truncate = (s: string, max = 160) => {
  if (s.length <= max) return s
  return `${s.slice(0, max - 1).trimEnd()}â€¦`
}

/** Post services: the Freedom Wall uses Supabase views + RPCs (never raw inserts of status). */
export const postsService = {
  /** Fetch published notes, newest first. Uses the public projection. */
  async listPublic(): Promise<PublicPost[]> {
    const { data, error } = await supabase
      .from('posts_public')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data as PublicPost[]) ?? []
  },

  /**
   * Submit a note. Guest notes retain no author identity; authenticated notes retain their author internally. Status is enforced on the DB.
   *
   * IMPORTANT: this must NOT chain `.select()`. Chaining it makes PostgREST send
   * `Prefer: return=representation`, which makes Postgres run `INSERT ... RETURNING *`.
   * That requires the caller to hold SELECT on the table, and migration 002
   * deliberately revokes SELECT on `posts` from `anon` (it would leak `status`,
   * `author_id` and `reviewed_by`). Guests therefore fail with
   * "permission denied for table posts" the moment `.select()` is added.
   */
  async create({
    recipient,
    content,
    category,
    noteColor,
    isAnonymous,
    authorId,
  }: {
    recipient: string
    content: string
    category: Post['category']
    noteColor: Post['note_color']
    isAnonymous: boolean
    authorId: string | null
  }): Promise<void> {
    const trimmedRecipient = recipient.trim()
    const trimmedContent = content.trim()

    const payload: Record<string, unknown> = {
      recipient: trimmedRecipient,
      content: trimmedContent,
      category,
      note_color: noteColor,
      is_anonymous: isAnonymous,
    }
    if (authorId) payload.author_id = authorId

    const { error } = await supabase.from('posts').insert(payload)
    if (error) throw error
  },

  /** Fetch notes owned by the current user (any status). */
  async listMyPosts(): Promise<Post[]> {
    const { data, error } = await supabase
      .from('posts')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data as Post[]) ?? []
  },

  /** Resubmit a rejected note for another review pass. */
  async resubmit(postId: string) {
    const { data, error } = await supabase.rpc('resubmit_post', { p_post_id: postId })
    if (error) throw error
    return data as Post
  },

  /** Update an unpublished note (pending or rejected) â€” owned by the current user. */
  async updateUnpublished(postId: string, changes: Partial<Pick<Post, 'recipient' | 'content' | 'category' | 'note_color' | 'is_anonymous'>>) {
    const { data, error } = await supabase
      .from('posts')
      .update({
        recipient: changes.recipient?.trim(),
        content: changes.content?.trim(),
        category: changes.category,
        note_color: changes.note_color,
        is_anonymous: changes.is_anonymous,
      })
      .eq('id', postId)
      .select('*')
      .single()
    if (error) throw error
    return data as Post
  },

  /** Search published notes by recipient, content or category. */
  async submitReport(postId: string, reason: import('../types').ReportReason, details?: string): Promise<void> {
    const { error } = await supabase.rpc('submit_report', { p_post_id: postId, p_reason: reason, p_details: details?.trim() || null })
    if (error) throw error
  },

  async searchPublic(q: string): Promise<PublicPost[]> {
    const term = q.trim().toLocaleLowerCase()
    const posts = await this.listPublic()
    if (!term) return posts
    return posts.filter((post) => [post.recipient, post.content, post.category].some((value) => value.toLocaleLowerCase().includes(term)))
  },
}

/** A report joined with the note it refers to, so moderators can judge it in one row. */
export interface ReportWithPost extends Report {
  post: Pick<Post, 'id' | 'recipient' | 'content' | 'status'> | null
}

/** Moderation service. Every write goes through the SECURITY DEFINER RPCs in 003. */
export const adminService = {
  async stats(): Promise<DashboardStats> {
    const { data, error } = await supabase.rpc('admin_dashboard_stats')
    if (error) throw error
    return data as DashboardStats
  },

  /** List notes for moderation. Admins hold SELECT on `posts` via RLS. */
  async listPosts(opts: {
    status?: PostStatus
    category?: PostCategory
    search?: string
  }): Promise<Post[]> {
    let q = supabase.from('posts').select('*').order('created_at', { ascending: false })

    if (opts.status) q = q.eq('status', opts.status)
    if (opts.category) q = q.eq('category', opts.category)

    const term = opts.search?.trim()
    if (term) {
      // Escape the PostgREST `or` filter metacharacters so user input cannot
      // break out of the filter string.
      const safe = term.replace(/[,()*%]/g, ' ')
      q = q.or(`recipient.ilike.%${safe}%,content.ilike.%${safe}%`)
    }

    const { data, error } = await q
    if (error) throw error
    return (data as Post[]) ?? []
  },

  /** Approve / reject / remove / restore a single note. */
  async moderate(
    postId: string,
    action: ModerationAction,
    reason?: string | null,
    rejectionReason?: RejectionReason | null
  ): Promise<void> {
    const { error } = await supabase.rpc('admin_moderate_post', {
      p_post_id: postId,
      p_action: action,
      p_reason: reason?.trim() || null,
      p_rejection_reason: rejectionReason ?? null,
    })
    if (error) throw error
  },

  /** Pending + resolved reports, with the referenced note attached. */
  async listReports(): Promise<ReportWithPost[]> {
    const { data, error } = await supabase
      .from('reports')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error

    const reports = (data as Report[]) ?? []
    if (reports.length === 0) return []

    const postIds = [...new Set(reports.map((r) => r.post_id))]
    const { data: postData, error: postError } = await supabase
      .from('posts')
      .select('id, recipient, content, status')
      .in('id', postIds)
    if (postError) throw postError

    const byId = new Map(
      ((postData as Pick<Post, 'id' | 'recipient' | 'content' | 'status'>[]) ?? []).map((p) => [
        p.id,
        p,
      ])
    )

    return reports.map((r) => ({ ...r, post: byId.get(r.post_id) ?? null }))
  },

  async deletePost(postId: string): Promise<void> {
    const { error } = await supabase.rpc('admin_delete_post', { p_post_id: postId })
    if (error) throw error
  },

  /** Dismiss a report, keep the note, or remove the note and close the report. */
  async resolveReport(
    reportId: string,
    decision: 'dismiss' | 'keep_published' | 'remove_post',
    reason?: string | null
  ): Promise<void> {
    const { error } = await supabase.rpc('admin_handle_report', {
      p_report_id: reportId,
      p_decision: decision,
      p_reason: reason?.trim() || null,
    })
    if (error) throw error
  },

  async promoteByEmail(email: string): Promise<void> {
    const { error } = await supabase.rpc('admin_promote_user_by_email', { p_email: email.trim() })
    if (error) throw error
  },

  /** Append-only audit trail. */
  async listLogs(): Promise<ModerationLog[]> {
    const { data, error } = await supabase
      .from('moderation_logs')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) throw error
    return (data as ModerationLog[]) ?? []
  },
}