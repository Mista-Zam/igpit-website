-- Seed data for development/testing (fictional teacher names only).
-- Run this in the Supabase SQL Editor AFTER applying migrations 001-003.
-- It does not change RLS or security; posts go to 'pending' by default.

-- Create a few sample submissions (guests). They land in pending.
insert into public.posts (author_id, recipient, content, category, note_color, is_anonymous)
values
  (null, 'Mrs. Thornbull', 'Thank you for always checking on us even when you''re already exhausted.', 'Appreciation', 'yellow', true),
  (null, 'Sir Daniel', 'That one joke during the faculty meeting absolutely saved my Monday.', 'Funny', 'pink', true),
  (null, 'All Teachers', 'Some days we teach. Some days we survive. Both count.', 'Motivation', 'green', true),
  (null, 'Ms. Reyes', 'You made my first semester here feel a lot less scary. Thank you.', 'Appreciation', 'blue', true),
  (null, 'Mrs. Santos', 'Your students may not say it often, but they notice how much effort you put in.', 'Appreciation', 'lavender', true),
  (null, 'Faculty', 'Thank you for covering my duty yesterday. I owe you one.', 'Appreciation', 'orange', true)
on conflict do nothing;

-- Fix the category if 'Gratitude' slipped in; normalize to allowed enum values where needed.
update public.posts
  set category = 'Appreciation'
where recipient = 'Faculty' and content ilike '%covering%';

do $$
begin
  -- No-op if already in valid categories
  null;
end;
$$;