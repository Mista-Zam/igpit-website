import { Navigate, Outlet, useLocation } from 'react-router-dom'

import { useAuth } from '../../context/AuthContext'

export const ProtectedRoute = () => {
  const { isAuthenticated, loading } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <div className="inline-flex items-center gap-3 rounded-2xl bg-white/90 px-5 py-3 shadow-note ring-1 ring-black/5 backdrop-blur-sm">
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-brand/40 border-t-brand" />
          <span className="text-sm font-semibold text-ink-soft">Checking your sessionâ€¦</span>
        </div>
      </div>
    )
  }

  if (!isAuthenticated) {
    return <Navigate to="/admin/login" replace state={{ from: location }} />
  }

  return <Outlet />
}

export const AdminRoute = () => {
  const { isAuthenticated, isAdmin, loading } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <div className="inline-flex items-center gap-3 rounded-2xl bg-white/90 px-5 py-3 shadow-note ring-1 ring-black/5 backdrop-blur-sm">
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-brand/40 border-t-brand" />
          <span className="text-sm font-semibold text-ink-soft">Checking permissionsâ€¦</span>
        </div>
      </div>
    )
  }

  if (!isAuthenticated) {
    return <Navigate to="/admin/login" replace state={{ from: location }} />
  }

  if (!isAdmin) {
    return <Navigate to="/wall" replace />
  }

  return <Outlet />
}