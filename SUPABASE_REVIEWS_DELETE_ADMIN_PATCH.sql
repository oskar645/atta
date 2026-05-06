-- ATTA: allow admin to delete reviews
-- Run in Supabase SQL Editor

alter table if exists public.reviews enable row level security;

drop policy if exists "reviews_delete_admin_only" on public.reviews;
create policy "reviews_delete_admin_only"
on public.reviews
for delete
to authenticated
using (public.is_admin(auth.uid()));

