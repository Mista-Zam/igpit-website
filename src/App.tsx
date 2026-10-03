import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { AuthProvider } from './context/AuthContext'
import { Layout } from './components/layout/Layout'
import { ProtectedRoute, AdminRoute } from './components/routes/ProtectedRoute'
import { Home } from './pages/Home'
import Wall from './pages/Wall'
import LeaveNote from './pages/LeaveNote'
import About from './pages/About'
import Admin from './pages/Admin'
import Login from './pages/Login'
import NotFound from './pages/NotFound'
function App() { return <AuthProvider><BrowserRouter><Routes><Route element={<Layout />}><Route index element={<Home />} /><Route path="wall" element={<Wall />} /><Route path="about" element={<About />} /><Route path="leave-a-note" element={<LeaveNote />} /><Route element={<ProtectedRoute />}><Route path="my-notes" element={<Wall />} /></Route><Route path="login" element={<Login />} /><Route path="auth/login" element={<Login />} /><Route element={<AdminRoute />}><Route path="admin" element={<Admin />} /><Route path="admin/*" element={<Admin />} /></Route><Route path="*" element={<NotFound />} /></Route></Routes></BrowserRouter></AuthProvider> }
export default App