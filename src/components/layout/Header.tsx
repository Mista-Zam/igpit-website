import { useState } from 'react'
import { Link, NavLink } from 'react-router-dom'
import { APP_NAME, TAGLINE } from '../../lib/constants'
import { useAuth } from '../../context/AuthContext'

const navLink = (isActive: boolean) => `inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold transition ${isActive ? 'bg-brand text-white shadow-sm' : 'text-ink-soft hover:bg-white/80 hover:text-ink'}`

export const Header = () => {
  const [open, setOpen] = useState(false)
  const { isAdmin } = useAuth()
  const close = () => setOpen(false)
  return <header className="sticky top-0 z-40 border-b border-beige-deep/60 bg-cream/90 backdrop-blur supports-[backdrop-filter]:bg-cream/80">
    <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
      <Link to="/" onClick={close} className="flex flex-col gap-0.5"><span className="flex items-center gap-2 font-display text-xl font-bold tracking-tight sm:text-2xl">{APP_NAME}{isAdmin && <span className="rounded-full bg-brand px-2 py-0.5 font-sans text-[10px] font-bold uppercase tracking-wide text-white">Admin</span>}</span><span className="hidden text-xs font-medium text-ink-soft sm:block">{TAGLINE}</span></Link>
      <nav className="hidden items-center gap-2 md:flex"><NavLink to="/" className={({ isActive }) => navLink(isActive)} end>Home</NavLink><NavLink to="/wall" className={({ isActive }) => navLink(isActive)}>Freedom Wall</NavLink><NavLink to="/leave-a-note" className={({ isActive }) => navLink(isActive)}>Leave a Note</NavLink><NavLink to="/about" className={({ isActive }) => navLink(isActive)}>About</NavLink>{isAdmin && <NavLink to="/admin" className={({ isActive }) => navLink(isActive)}>Dashboard</NavLink>}</nav>
      <div className="flex items-center gap-2"><Link to="/leave-a-note" className="hidden rounded-full bg-brand px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-dark sm:inline-flex">Leave a Note</Link><button type="button" onClick={() => setOpen((value) => !value)} className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-white text-ink shadow-sm ring-1 ring-black/5 md:hidden" aria-label={open ? 'Close navigation menu' : 'Open navigation menu'} aria-expanded={open}>{open ? <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="m6 6 12 12M18 6 6 18" /></svg> : <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M4 7h16M4 12h16M4 17h16" /></svg>}</button></div>
    </div>
    {open && <nav className="border-t border-beige-deep/60 bg-paper px-4 py-3 shadow-note md:hidden" aria-label="Mobile navigation"><div className="mx-auto grid max-w-7xl gap-1"><NavLink onClick={close} to="/" className={({ isActive }) => navLink(isActive)} end>Home</NavLink><NavLink onClick={close} to="/wall" className={({ isActive }) => navLink(isActive)}>Freedom Wall</NavLink><NavLink onClick={close} to="/leave-a-note" className={({ isActive }) => navLink(isActive)}>Leave a Note</NavLink><NavLink onClick={close} to="/about" className={({ isActive }) => navLink(isActive)}>About</NavLink>{isAdmin ? <NavLink onClick={close} to="/admin" className={({ isActive }) => navLink(isActive)}>Dashboard</NavLink> : <NavLink onClick={close} to="/auth/login" className={({ isActive }) => navLink(isActive)}>Admin sign in</NavLink>}</div></nav>}
  </header>
}