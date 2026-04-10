-- Fix saved search permissions under RLS.
-- Run this in Supabase SQL Editor if saving a search fails with code 42501.

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

create table if not exists public.saved_searches (
  id uuid primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null default '',
  query_key text not null,
  category text not null default 'Все',
  search text not null default '',
  subcategory text not null default 'Все',
  location text not null default '',
  prefer_location_first boolean not null default false,
  radius_km integer null,
  auto_brand text not null default '',
  auto_model text not null default '',
  auto_condition text not null default '',
  auto_mileage_to integer null,
  only_uncrashed boolean not null default false,
  alerts_enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique(user_id, query_key)
);

alter table public.saved_searches enable row level security;

grant select, insert, update, delete
on public.saved_searches
to authenticated;

drop policy if exists "saved_searches_select_own" on public.saved_searches;
drop policy if exists "saved_searches_select_own_or_admin" on public.saved_searches;
create policy "saved_searches_select_own_or_admin"
on public.saved_searches
for select
to authenticated
using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists "saved_searches_insert_own" on public.saved_searches;
create policy "saved_searches_insert_own"
on public.saved_searches
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "saved_searches_update_own" on public.saved_searches;
create policy "saved_searches_update_own"
on public.saved_searches
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "saved_searches_delete_own" on public.saved_searches;
create policy "saved_searches_delete_own"
on public.saved_searches
for delete
to authenticated
using (auth.uid() = user_id);

create index if not exists saved_searches_user_idx
on public.saved_searches(user_id, updated_at desc);
