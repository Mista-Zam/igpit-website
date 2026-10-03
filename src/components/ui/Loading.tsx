export const Loading = ({ label = 'Loading…' }: { label?: string }) => {
  return (
    <div className="flex min-h-[40vh] items-center justify-center">
      <div className="inline-flex items-center gap-3 rounded-2xl bg-white/90 px-5 py-3 shadow-note ring-1 ring-black/5 backdrop-blur-sm">
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-brand/40 border-t-brand" />
        <span className="text-sm font-semibold text-ink-soft">{label}</span>
      </div>
    </div>
  )
}