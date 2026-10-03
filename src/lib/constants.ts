import type {
  ModerationAction,
  NoteColor,
  PostCategory,
  PostStatus,
  ReportReason,
  ReportStatus,
  RejectionReason,
  UserRole,
} from '../types'

export const APP_NAME = "DCSHS Teachers' Dedication Wall"
export const TAGLINE = 'A dedication wall for teachers, by students.'

export const POST_CATEGORIES: PostCategory[] = [
  'Classroom',
  'Teaching Life',
  'Vent',
  'Wins',
  'Advice',
  'Appreciation',
  'Funny',
  'Motivation',
  'Random',
]

export const ALL_CATEGORY = 'All' as const

export const NOTE_COLORS: NoteColor[] = [
  'yellow',
  'pink',
  'blue',
  'green',
  'lavender',
  'orange',
  'purple',
]

/** Note swatch colours, shared by Tailwind classes and inline styles. */
export const NOTE_COLOR_HEX: Record<NoteColor, string> = {
  yellow: '#FFE566',
  pink: '#FF8FB3',
  blue: '#70CFFF',
  green: '#7BE0B2',
  lavender: '#B89CFF',
  orange: '#FFAA68',
  purple: '#D09CFF',
}

export const NOTE_COLOR_LABELS: Record<NoteColor, string> = {
  yellow: 'Buttercup',
  pink: 'Blush',
  blue: 'Sky',
  green: 'Mint',
  lavender: 'Lilac',
  orange: 'Peach',
  purple: 'Grape',
}

/** Recipient presets for the composer. */
export const RECIPIENT_PRESETS = [
  'All Teachers',
  'Faculty',
  'Whoever Needs It Today',
] as const

export const RECIPIENT_MAX = 60
export const CONTENT_MAX = 1200

export const REPORT_REASONS: ReportReason[] = [
  'Offensive content',
  'Harassment',
  'Spam',
  'Personal information',
  'Other',
]

export const REJECTION_REASONS: RejectionReason[] = [
  'Inappropriate content',
  'Offensive language',
  'Harassment',
  'Spam',
  'Advertising',
  'Personal information',
  'Duplicate',
  'Other',
]

export const POST_STATUSES: PostStatus[] = ['pending', 'published', 'rejected', 'removed']

export const REPORT_STATUSES: ReportStatus[] = ['pending', 'reviewed', 'dismissed', 'action_taken']

export const MODERATION_ACTIONS: ModerationAction[] = [
  'approve',
  'reject',
  'remove',
  'restore',
  'resolve_report',
  'dismiss_report',
]

export const USER_ROLES: UserRole[] = ['teacher', 'admin']

/** Human labels + tones for status badges. */
export const STATUS_META: Record<PostStatus, { label: string; className: string }> = {
  pending: {
    label: 'Pending review',
    className: 'bg-amber-100 text-amber-900 ring-amber-300',
  },
  published: {
    label: 'Published',
    className: 'bg-emerald-100 text-emerald-900 ring-emerald-300',
  },
  rejected: {
    label: 'Rejected',
    className: 'bg-rose-100 text-rose-900 ring-rose-300',
  },
  removed: {
    label: 'Removed',
    className: 'bg-slate-200 text-slate-800 ring-slate-400',
  },
}

export const REPORT_STATUS_META: Record<ReportStatus, { label: string; className: string }> = {
  pending: { label: 'Needs review', className: 'bg-amber-100 text-amber-900 ring-amber-300' },
  reviewed: { label: 'Reviewed, kept', className: 'bg-sky-100 text-sky-900 ring-sky-300' },
  dismissed: { label: 'Dismissed', className: 'bg-slate-200 text-slate-800 ring-slate-400' },
  action_taken: { label: 'Action taken', className: 'bg-emerald-100 text-emerald-900 ring-emerald-300' },
}

export const ACTION_META: Record<ModerationAction, { label: string; className: string }> = {
  approve: { label: 'Approved', className: 'bg-emerald-100 text-emerald-900 ring-emerald-300' },
  reject: { label: 'Rejected', className: 'bg-rose-100 text-rose-900 ring-rose-300' },
  remove: { label: 'Removed', className: 'bg-slate-200 text-slate-800 ring-slate-400' },
  restore: { label: 'Restored', className: 'bg-sky-100 text-sky-900 ring-sky-300' },
  resolve_report: { label: 'Report resolved', className: 'bg-indigo-100 text-indigo-900 ring-indigo-300' },
  dismiss_report: { label: 'Report dismissed', className: 'bg-slate-200 text-slate-800 ring-slate-400' },
}