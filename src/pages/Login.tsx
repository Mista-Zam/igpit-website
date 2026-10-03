import { useState } from 'react'
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom'

import { useAuth } from '../context/AuthContext'

const Login = () => {
  const { signIn, signUp, isAuthenticated, isAdmin } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const from = (location.state as { from?: { pathname?: string } } | null)?.from?.pathname
  if (isAuthenticated) return <Navigate to={isAdmin ? '/admin' : from ?? '/wall'} replace />

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    if (!email.trim() || !password) return setError('Email and password are required')
    if (mode === 'signup' && !displayName.trim()) return setError('Please enter a display name.')

    try {
      setSubmitting(true)
      const { error: authError } = mode === 'signup'
        ? await signUp(email.trim(), password, displayName.trim())
        : await signIn(email.trim(), password)
      if (authError) return setError(authError.message)
      if (mode === 'signup') {
        setMode('signin')
        return setError('Account created. Check your email to confirm it, then sign in.')
      }
      navigate(from ?? '/wall', { replace: true })
    } finally {
      setSubmitting(false)
    }
  }

  return <section className="mx-auto flex min-h-[70vh] max-w-md flex-col justify-center px-4 py-10 sm:px-6">
    <div className="space-y-2 text-center">
      <h1 className="font-display text-3xl font-bold sm:text-4xl">{mode === 'signin' ? 'Welcome Back' : 'Join the Wall'}</h1>
      <p className="text-ink-soft">{mode === 'signin' ? 'Sign in to pin a note or check its review status.' : 'Every new account starts as a teacher.'}</p>
    </div>
    <form onSubmit={handleSubmit} className="mt-8 space-y-5 rounded-3xl bg-white/95 p-6 shadow-note ring-1 ring-black/5">
      {error && <div className="rounded-2xl bg-rose-50 px-4 py-2 text-sm font-semibold text-rose-700 ring-1 ring-rose-200">{error}</div>}
      {mode === 'signup' && <div className="space-y-2"><label htmlFor="displayName" className="text-sm font-semibold text-ink">Display name</label><input id="displayName" autoComplete="name" maxLength={60} value={displayName} onChange={(e) => setDisplayName(e.target.value)} className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-brand" /></div>}
      <div className="space-y-2"><label htmlFor="email" className="text-sm font-semibold text-ink">Email</label><input id="email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-brand" /></div>
      <div className="space-y-2"><label htmlFor="password" className="text-sm font-semibold text-ink">Password</label><input id="password" type="password" minLength={6} autoComplete={mode === 'signin' ? 'current-password' : 'new-password'} value={password} onChange={(e) => setPassword(e.target.value)} className="w-full rounded-2xl border border-beige-deep/70 bg-white px-4 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-brand" /></div>
      <button type="submit" disabled={submitting} className="inline-flex w-full justify-center rounded-full bg-brand px-6 py-3 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-dark disabled:opacity-60">{submitting ? 'Please waitâ€¦' : mode === 'signin' ? 'Sign In' : 'Create Teacher Account'}</button>
    </form>
    <p className="mt-6 text-center text-sm text-ink-soft">{mode === 'signin' ? 'New here?' : 'Already have an account?'} <button type="button" onClick={() => { setMode(mode === 'signin' ? 'signup' : 'signin'); setError(null) }} className="font-semibold text-brand underline underline-offset-4">{mode === 'signin' ? 'Create a new Account' : 'Sign in'}</button></p>
    <Link to="/wall" className="mt-3 text-center text-sm font-semibold text-ink-soft underline underline-offset-4">Read the public wall</Link>
  </section>
}

export default Login