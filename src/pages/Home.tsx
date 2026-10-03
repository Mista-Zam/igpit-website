import { Link } from 'react-router-dom'

export const Home = () => {
  return (
    <section className="relative mx-auto flex min-h-[70vh] w-full max-w-6xl flex-col items-center justify-center gap-8 px-4 text-center sm:px-6 lg:px-8">
      <h1 className="font-display text-4xl font-bold tracking-tight sm:text-6xl md:text-7xl">
        Dear Teachers, This One's For You.
      </h1>
      <p className="max-w-2xl text-lg text-ink-soft sm:text-xl">
        Leave a note. Share a thought. Make another teacher's day.
      </p>
      <div className="flex flex-wrap justify-center gap-4">
        <Link
          to="/leave-a-note"
          className="inline-flex items-center gap-2 rounded-full bg-brand px-6 py-3 text-sm font-semibold text-white shadow-sm transition hover:bg-brand-dark sm:text-base"
        >
          Leave a Note
        </Link>
        <Link
          to="/wall"
          className="inline-flex items-center gap-2 rounded-full bg-white/95 px-6 py-3 text-sm font-semibold text-ink shadow-sm ring-1 ring-black/5 transition hover:bg-white sm:text-base"
        >
          Read the Wall
        </Link>
      </div>
    </section>
  )
}
