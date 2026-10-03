import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

import { postsService } from '../lib/utils'
import { CONTENT_MAX, NOTE_COLORS, POST_CATEGORIES, RECIPIENT_MAX, RECIPIENT_PRESETS } from '../lib/constants'
import type { NoteColor, PostCategory } from '../types'
import { useAuth } from '../context/AuthContext'

const LeaveNote = () => {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [recipient, setRecipient] = useState('')
  const [content, setContent] = useState('')
  const [category, setCategory] = useState<PostCategory>('Appreciation')
  const [noteColor, setNoteColor] = useState<NoteColor>('yellow')
  const [isAnonymous, setIsAnonymous] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handlePreset = (p: string) => setRecipient(p)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    const r = recipient.trim()
    const c = content.trim()
    if (!r) { setError('Recipient is required'); return }
    if (!c) { setError('Message is required'); return }
    if (r.length > RECIPIENT_MAX) { setError(`Recipient must be under ${RECIPIENT_MAX} characters`); return }
    if (c.length > CONTENT_MAX) { setError(`Message must be under ${CONTENT_MAX} characters`); return }

    try {
      setSubmitting(true)
      await postsService.create({
        recipient: r,
        content: c,
        category,
        noteColor,
        isAnonymous,
        authorId: user?.id ?? null,
      })
      setRecipient('')
      setContent('')
      navigate('/wall', { state: { notice: 'Your note was submitted and is awaiting moderation.' } })
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to submit note')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="mx-auto max-w-2xl space-y-6 px-4 py-10 sm:px-6 lg:px-8">
      <div>
        <h1 className="font-display text-3xl font-bold sm:text-4xl">Write a Note</h1>
        <p className="text-ink-soft">Your note will be reviewed before it appears on the wall.</p>
      </div>
      <form onSubmit={handleSubmit} className="space-y-6 rounded-3xl bg-white/95 p-6 shadow-note ring-1 ring-black/5">
        {error && (
          <div className="rounded-2xl bg-rose-50 px-4 py-2 text-sm font-semibold text-rose-700 ring-1 ring-rose-200">
            {error}
          </div>
        )}

        <div className="space-y-2">
          <label className="text-sm font-semibold text-ink">TO</label>
          <input
            value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
            placeholder="e.g. Mrs. Thornbull or All Teachers"
            maxLength={RECIPIENT_MAX}
            className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-2 text-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-brand"
          />
          <div className="flex flex-wrap gap-2">
            {RECIPIENT_PRESETS.map((p) => (
              <button key={p} type="button" onClick={() => handlePreset(p)}
                className="rounded-full bg-white/90 px-3 py-1 text-xs font-semibold ring-1 ring-black/5 hover:bg-white">
                {p}
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-2">
          <label className="text-sm font-semibold text-ink">Message</label>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="Write something worth passing on..."
            maxLength={CONTENT_MAX}
            rows={6}
            className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-3 text-base shadow-sm focus:outline-none focus:ring-2 focus:ring-brand"
          />
          <div className="text-right text-xs text-ink-faint">{content.length}/{CONTENT_MAX}</div>
        </div>

        <div className="grid gap-6 sm:grid-cols-2">
          <div className="space-y-2">
            <label className="text-sm font-semibold text-ink">Category</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value as PostCategory)}
              className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-brand"
            >
              {POST_CATEGORIES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <label className="text-sm font-semibold text-ink">Note Color</label>
            <div className="flex flex-wrap gap-2">
              {NOTE_COLORS.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setNoteColor(c)}
                  className={`h-8 w-8 rounded-full ring-2 transition ${noteColor === c ? 'ring-ink' : 'ring-transparent'} shadow-sm`}
                  style={{ backgroundColor: c === 'yellow' ? '#FFE566' : c === 'pink' ? '#FF8FB3' : c === 'blue' ? '#70CFFF' : c === 'green' ? '#7BE0B2' : c === 'lavender' ? '#B89CFF' : c === 'orange' ? '#FFAA68' : '#D09CFF' }}
                  aria-label={c}
                />
              ))}
            </div>
          </div>
        </div>

        <label className="flex items-center gap-3">
          <input type="checkbox" checked={isAnonymous} onChange={(e) => setIsAnonymous(e.target.checked)} />
          <span className="text-sm font-medium text-ink">Post anonymously</span>
        </label>

        <div className="flex gap-3">
          <button
            type="submit"
            disabled={submitting}
            className="inline-flex items-center gap-2 rounded-full bg-brand px-6 py-3 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-dark disabled:opacity-60"
          >
            {submitting ? 'Pinningâ€¦' : 'Pin My Note'}
          </button>
          <button type="button" onClick={() => navigate('/wall')} className="inline-flex items-center gap-2 rounded-full bg-white/95 px-6 py-3 text-sm font-semibold ring-1 ring-black/5 hover:bg-white">
            Cancel
          </button>
        </div>
      </form>
    </section>
  )
}

export default LeaveNote
