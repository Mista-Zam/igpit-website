import type { AuthError, Session, User } from '@supabase/supabase-js'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'

import { supabase } from '../lib/supabase'
import type { Profile } from '../types'

export interface AuthContextValue {
  user: User | null
  profile: Profile | null
  session: Session | null
  loading: boolean
  isAdmin: boolean
  isAuthenticated: boolean
  signUp: (
    email: string,
    password: string,
    displayName: string
  ) => Promise<{ error: AuthError | null }>
  signIn: (email: string, password: string) => Promise<{ error: AuthError | null }>
  signOut: () => Promise<{ error: AuthError | null }>
  resetPassword: (email: string) => Promise<{ error: AuthError | null }>
  updateDisplayName: (displayName: string) => Promise<{ error: AuthError | null }>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  // Fetch profile for the current user. Returns null if the profile has not been
  // created yet (edge case) and is never exposed in a way that leaks emails.
  const fetchProfile = async (uid: string | null) => {
    if (!uid) {
      setProfile(null)
      return
    }

    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', uid)
      .single()

    if (error) {
      // The row may not exist yet in an extremely rare case - ignore silently.
      // The profile is created by the database trigger on auth.users insert.
      setProfile(null)
      return
    }

    setProfile((data as Profile) ?? null)
  }

  // Bootstrap: recover session on first load, subscribe to auth changes.
  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)
      setUser(newSession?.user ?? null)
      fetchProfile(newSession?.user?.id ?? null).finally(() => {
        setLoading(false)
      })
    })

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setUser(data.session?.user ?? null)
      fetchProfile(data.session?.user?.id ?? null).finally(() => setLoading(false))
    })

    return () => subscription.unsubscribe()
  }, [])

  // Re-fetch profile when the user changes.
  useEffect(() => {
    fetchProfile(user?.id ?? null)
  }, [user?.id])

  const signUp = async (email: string, password: string, displayName: string) => {
    const trimmed = displayName.trim()
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          display_name: trimmed.length >= 1 ? trimmed : email.split('@')[0],
        },
      },
    })
    return { error }
  }

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error }
  }

  const signOut = async () => {
    const { error } = await supabase.auth.signOut()
    return { error }
  }

  const resetPassword = async (email: string) => {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/auth/reset-password`,
    })
    return { error }
  }

  const updateDisplayName = async (displayName: string) => {
    const trimmed = displayName.trim()
    if (!user) return { error: null }
    const { error } = await supabase
      .from('profiles')
      .update({ display_name: trimmed })
      .eq('id', user.id)
    if (!error) await fetchProfile(user.id)
    return { error: (error as unknown as AuthError | null) }
  }

  const isAuthenticated = !!user
  const isAdmin = profile?.role === 'admin' || profile?.role === 'super_admin'

  const value = useMemo(
    () => ({
      user,
      profile,
      session,
      loading,
      isAdmin,
      isAuthenticated,
      signUp,
      signIn,
      signOut,
      resetPassword,
      updateDisplayName,
    }),
    [user, profile, session, loading, isAdmin, isAuthenticated]
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export const useAuth = () => {
  const ctx = useContext(AuthContext)
  if (!ctx) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return ctx
}