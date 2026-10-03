import { Link, Outlet } from 'react-router-dom'

import { Header } from './Header'

export const Layout = () => {
  return (
    <div className="flex min-h-dvh flex-col bg-cream">
      <Header />
      <main className="relative flex-1">
        <div className="pointer-events-none absolute inset-0 -z-10 cork-texture opacity-40" />
        <div className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-48 bg-gradient-to-b from-beige/60 to-transparent" />
        <Outlet />
      </main>
      <Link to="/leave-a-note" className="fixed bottom-16 right-4 z-40 inline-flex items-center gap-2 rounded-full bg-brand px-4 py-3 text-sm font-bold text-white shadow-note-lift transition hover:bg-brand-dark md:hidden" aria-label="Add a note"><span className="text-lg leading-none">+</span> Add a Note</Link>
      <footer className="border-t border-beige-deep/60 bg-paper/80 py-6">
        <div className="mx-auto max-w-7xl px-4 text-center text-sm text-ink-faint sm:px-6 lg:px-8">
          Ãƒâ€šÃ‚Â© {new Date().getFullYear()} Teachers' Freedom Wall ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Notes from one teacher to another.
        </div>
      </footer>
    </div>
  )
}