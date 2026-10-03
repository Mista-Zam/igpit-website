import { useCallback, useEffect, useMemo, useState } from 'react'

import { Loading } from '../ui/Loading'
import { StickyNote } from './StickyNote'
import { postsService } from '../../lib/utils'
import type { PublicPost } from '../../types'
import { ALL_CATEGORY, POST_CATEGORIES } from '../../lib/constants'

export const Wall = () => {
  const [posts, setPosts] = useState<PublicPost[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState<string>(ALL_CATEGORY)

  const fetchPosts = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      setPosts(search.trim() ? await postsService.searchPublic(search) : await postsService.listPublic())
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'The wall could not be loaded.')
    } finally { setLoading(false) }
  }, [search])

  useEffect(() => { void fetchPosts() }, [fetchPosts])
  const filtered = useMemo(() => category === ALL_CATEGORY ? posts : posts.filter((post) => post.category === category), [posts, category])

  return <section className="relative mx-auto w-full max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
    <div className="mb-8 space-y-4 text-center"><h1 className="font-display text-3xl font-bold tracking-tight sm:text-5xl">What's On The Teachers' Board?</h1><p className="text-lg text-ink-soft">Pin a thought. Pass it on.</p></div>
    <div className="mb-8 flex flex-wrap items-center justify-center gap-3">
      <div className="flex items-center gap-2 rounded-full bg-white/90 px-4 py-2 shadow-sm ring-1 ring-black/5"><input type="search" value={search} onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void fetchPosts() }} placeholder="Search notes, teachers, or topics..." className="w-48 bg-transparent text-sm font-medium text-ink placeholder:text-ink-faint focus:outline-none sm:w-64" /><button type="button" onClick={() => void fetchPosts()} className="rounded-full bg-brand px-3 py-1 text-xs font-semibold text-white shadow-sm hover:bg-brand-dark">Search</button></div>
      <select value={category} onChange={(e) => setCategory(e.target.value)} aria-label="Filter notes by category" className="rounded-full bg-white/90 px-4 py-2 text-sm font-semibold text-ink shadow-sm ring-1 ring-black/5 focus:outline-none focus:ring-2 focus:ring-brand"><option value={ALL_CATEGORY}>All categories</option>{POST_CATEGORIES.map((item) => <option key={item} value={item}>{item}</option>)}</select>
    </div>
    {loading && <Loading label="Pinning notes to the board…" />}
    {error && <div className="mx-auto max-w-md rounded-2xl bg-white/95 px-4 py-3 text-center text-sm font-semibold text-rose-700 ring-1 ring-rose-200">{error}</div>}
    {!loading && !error && filtered.length === 0 && <div className="mx-auto max-w-md space-y-2 rounded-3xl bg-white/95 px-6 py-8 text-center shadow-note ring-1 ring-black/5"><h2 className="font-display text-xl font-bold">No notes yet.</h2><p className="text-sm text-ink-soft">Be the first teacher to pin something to the wall.</p></div>}
    {!loading && !error && filtered.length > 0 && <div className="flex flex-wrap items-start justify-center gap-8">{filtered.map((post, index) => <StickyNote key={post.id} post={post} index={index} className="animate-note-in" />)}</div>}
  </section>
}