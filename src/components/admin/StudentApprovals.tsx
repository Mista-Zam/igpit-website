import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../context/AuthContext'

type Request = { id: string; created_at: string; profiles: { display_name: string }[] }

export const StudentApprovals = () => {
  const { profile } = useAuth()
  const [requests, setRequests] = useState<Request[]>([])
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = async () => {
    if (profile?.role !== 'super_admin') return
    const { data, error: requestError } = await supabase.from('admin_access_requests').select('id, created_at, profiles!admin_access_requests_user_id_fkey(display_name)').eq('status', 'pending').order('created_at')
    if (requestError) setError(requestError.message)
    else setRequests((data ?? []) as Request[])
  }
  useEffect(() => { void load() }, [profile?.role])
  if (profile?.role !== 'super_admin') return null
  const review = async (id: string, approve: boolean) => { setBusy(id); setError(null); const { error: reviewError } = await supabase.rpc('review_admin_access_request', { p_request_id: id, p_approve: approve }); if (reviewError) setError(reviewError.message); await load(); setBusy(null) }
  return <section className="space-y-3 rounded-2xl bg-brand-light/60 p-4 ring-1 ring-brand/15"><div><h2 className="font-display text-xl font-bold">New student accounts</h2><p className="text-sm text-ink-soft">Approve only students you want to help manage the wall.</p></div>{error && <p className="text-sm font-semibold text-rose-700">{error}</p>}{requests.length === 0 ? <p className="text-sm text-ink-soft">No students waiting.</p> : requests.map((request) => <div key={request.id} className="flex items-center justify-between gap-3 rounded-xl bg-white p-3"><span className="font-semibold text-ink">{request.profiles?.[0]?.display_name ?? 'Student'}</span><div className="flex gap-2"><button type="button" disabled={busy === request.id} onClick={() => void review(request.id, true)} className="rounded-full bg-emerald-600 px-3 py-1.5 text-xs font-bold text-white">Approve</button><button type="button" disabled={busy === request.id} onClick={() => void review(request.id, false)} className="rounded-full bg-slate-600 px-3 py-1.5 text-xs font-bold text-white">No</button></div></div>)}</section>
}