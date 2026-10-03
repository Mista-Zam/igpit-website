/**
 * Domain types for Teachers' Freedom Wall.
 * These mirror the PostgreSQL enums created in supabase/migrations.
 */

export type UserRole = 'teacher' | 'admin'

export type PostStatus = 'pending' | 'published' | 'rejected' | 'removed'

export type PostCategory =
  | 'Classroom'
  | 'Teaching Life'
  | 'Vent'
  | 'Wins'
  | 'Advice'
  | 'Appreciation'
  | 'Funny'
  | 'Motivation'
  | 'Random'

export type NoteColor =
  | 'yellow'
  | 'pink'
  | 'blue'
  | 'green'
  | 'lavender'
  | 'orange'
  | 'purple'

export type ReportReason =
  | 'Offensive content'
  | 'Harassment'
  | 'Spam'
  | 'Personal information'
  | 'Other'

export type ReportStatus = 'pending' | 'reviewed' | 'dismissed' | 'action_taken'

export type ModerationAction =
  | 'approve'
  | 'reject'
  | 'remove'
  | 'restore'
  | 'resolve_report'
  | 'dismiss_report'

export type RejectionReason =
  | 'Inappropriate content'
  | 'Offensive language'
  | 'Harassment'
  | 'Spam'
  | 'Advertising'
  | 'Personal information'
  | 'Duplicate'
  | 'Other'

export interface Profile {
  id: string
  role: UserRole
  display_name: string
  created_at: string
  updated_at: string
}

export interface Post {
  id: string
  author_id: string | null
  recipient: string
  content: string
  category: PostCategory
  note_color: NoteColor
  is_anonymous: boolean
  status: PostStatus
  created_at: string
  updated_at: string
  reviewed_at: string | null
  reviewed_by: string | null
  rejection_reason: RejectionReason | null
}

/** A note as returned by the `posts_public` view: published only, no author id. */
export interface PublicPost {
  id: string
  recipient: string
  content: string
  category: PostCategory
  note_color: NoteColor
  is_anonymous: boolean
  created_at: string
  updated_at: string
  author_display_name: string
  reported_by_me: boolean
}

/** A note owned by the signed-in teacher, including moderation state. */
export interface OwnedPost extends Post {
  author_display_name: string | null
}

export interface Report {
  id: string
  post_id: string
  reporter_id: string | null
  reason: ReportReason
  details: string | null
  status: ReportStatus
  created_at: string
  resolved_at: string | null
  resolved_by: string | null
}

export interface ModerationLog {
  id: string
  post_id: string | null
  moderator_id: string | null
  moderator_display_name: string
  post_recipient: string
  action: ModerationAction
  reason: string | null
  previous_status: PostStatus | null
  new_status: PostStatus | null
  created_at: string
}

export interface DashboardStats {
  pending_count: number
  published_count: number
  rejected_count: number
  removed_count: number
  total_count: number
  report_count: number
  report_total: number
  teacher_count: number
  admin_count: number
  today_count: number
  today_reports: number
  moderation_count: number
  v_today: string
}

/** Filter state for the admin moderation queue. */
export interface PostFilters {
  search: string
  status: PostStatus | 'all'
  category: PostCategory | 'all'
  dateFrom: string | null
  dateTo: string | null
  anonymity: 'all' | 'anonymous' | 'named'
  reported: 'all' | 'reported' | 'unreported'
}

export const emptyPostFilters: PostFilters = {
  search: '',
  status: 'all',
  category: 'all',
  dateFrom: null,
  dateTo: null,
  anonymity: 'all',
  reported: 'all',
}