# Teachers' Freedom Wall

A playful, school-inspired bulletin board where teachers leave notes for one another.

## Stack

- React + Vite + TypeScript
- Tailwind CSS
- Supabase (Auth, Postgres + RLS, RPCs)

## Getting started

1. Copy `.env.example` to `.env` and fill `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
2. Install deps: `npm install`
3. Run locally: `npm run dev`

## Database

Migrations live in `supabase/migrations/`. The schema enforces:
- Anyone (guest or signed in) can submit; submissions land in `pending`.
- Public wall reads only from `posts_public` (status=published; no emails/author IDs/moderation data).
- Teachers own their notes; admins act only via SECURITY DEFINER RPCs.
- Reports, moderation actions, and audit logs are enforced by RLS + functions.
- `bootstrap_first_admin(email)` exists for SQL-editor promotion (after normal signup).

Security checks: `supabase/tests/security_checks.sql` (run against a scratch DB as `postgres`).

## Deployment

Built with `npm run build`. For Vercel, use `vercel.json` rewrites for SPA. No Docker required; Supabase is managed.

## Project structure (high level)

- `src/components` — UI: header, hero, wall, admin, modals, layouts
- `src/context` — auth provider
- `src/lib` — supabase client, utils, constants
- `src/pages` — routes (Home, Wall, Leave Note, My Notes, Auth, Admin, About, 404)
- `src/services` — admin/moderation/report services
- `src/types` — TypeScript types

## First admin

1. Sign up normally as a teacher.
2. In Supabase SQL Editor: `select public.bootstrap_first_admin('your@email.com');`
3. To promote others: `select public.admin_set_user_role('target-uuid','admin');`