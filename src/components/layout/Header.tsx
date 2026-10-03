import { Link, NavLink } from 'react-router-dom'

import { APP_NAME, TAGLINE } from '../../lib/constants'

const navLink = (isActive: boolean) =>
  `inline-flex items-center gap-2 px-3 py-2 rounded-full text-sm font-semibold transition ${
    isActive
      ? 'bg-brand text-white shadow-sm'
      : 'text-ink-soft hover:bg-white/80 hover:text-ink'
  }`

export const Header = () => {
  return (
    <header className="sticky top-0 z-40 border-b border-beige-deep/60 bg-cream/90 backdrop-blur supports-[backdrop-filter]:bg-cream/80">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
        <Link to="/" className="flex flex-col gap-0.5">
          <span className="font-display text-xl font-bold tracking-tight sm:text-2xl">
            {APP_NAME}
          </span>
          <span className="hidden text-xs font-medium text-ink-soft sm:block">{TAGLINE}</span>
        </Link>

        <nav className="hidden items-center gap-2 md:flex">
          <NavLink to="/" className={({ isActive }) => navLink(isActive)} end>
            Home
          </NavLink>
          <NavLink to="/wall" className={({ isActive }) => navLink(isActive)}>
            Dedication Wall
          </NavLink>
          <NavLink to="/leave-a-note" className={({ isActive }) => navLink(isActive)}>
            Leave a Note
          </NavLink>
          <NavLink to="/about" className={({ isActive }) => navLink(isActive)}>
            About
          </NavLink>
        </nav>

        <div className="flex items-center gap-2">
          <Link
            to="/leave-a-note"
            className="inline-flex items-center gap-2 rounded-full bg-brand px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-dark"
          >
            Leave a Note
          </Link>
        </div>
      </div>
    </header>
  )
}