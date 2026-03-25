-- ATTA presence/online status
-- Run in Supabase SQL Editor

create table if not exists public.user_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_online boolean not null default false,
  last_seen timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_presence_online_last_seen
  on public.user_presence (is_online, last_seen desc);

create or replace function public.touch_presence_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_presence_touch on public.user_presence;
create trigger trg_user_presence_touch
before update on public.user_presence
for each row execute function public.touch_presence_updated_at();

alter table public.user_presence enable row level security;

drop policy if exists user_presence_select_auth on public.user_presence;
create policy user_presence_select_auth
on public.user_presence
for select
to authenticated
using (true);

drop policy if exists user_presence_insert_own on public.user_presence;
create policy user_presence_insert_own
on public.user_presence
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists user_presence_update_own on public.user_presence;
create policy user_presence_update_own
on public.user_presence
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
