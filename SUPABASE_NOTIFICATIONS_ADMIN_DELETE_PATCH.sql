-- Fix admin notification deletion under RLS.
-- Run this in Supabase SQL Editor.

create or replace function public.is_admin(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.admin_users a
    where a.uid = p_uid and coalesce(a.is_admin, false) = true
  );
$$;

grant execute on function public.is_admin(uuid) to authenticated;

grant select, insert, update, delete
on public.user_notifications
to authenticated;

drop policy if exists notifications_delete_admin on public.user_notifications;
drop policy if exists "notifications_delete_admin_only" on public.user_notifications;

create policy notifications_delete_admin
on public.user_notifications
for delete
to authenticated
using (public.is_admin(auth.uid()));
