create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (follower_id, seller_id),
  constraint user_follows_not_self check (follower_id <> seller_id)
);

create index if not exists idx_user_follows_seller_created
  on public.user_follows (seller_id, created_at desc);

create index if not exists idx_user_follows_follower_created
  on public.user_follows (follower_id, created_at desc);

grant usage on schema public to authenticated;
grant select, insert, delete on public.user_follows to authenticated;
grant select, insert, delete on public.user_follows to service_role;

alter table public.user_follows enable row level security;

drop policy if exists "user_follows_select_auth" on public.user_follows;
create policy "user_follows_select_auth"
on public.user_follows
for select
to authenticated
using (true);

drop policy if exists "user_follows_insert_own" on public.user_follows;
create policy "user_follows_insert_own"
on public.user_follows
for insert
to authenticated
with check (auth.uid() = follower_id and follower_id <> seller_id);

drop policy if exists "user_follows_delete_own" on public.user_follows;
create policy "user_follows_delete_own"
on public.user_follows
for delete
to authenticated
using (auth.uid() = follower_id);

create or replace function public.notify_followers_about_listing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  seller_name text;
begin
  if new.owner_id is null then
    return new;
  end if;

  select coalesce(nullif(u.display_name, ''), nullif(u.name, ''), nullif(u.email, ''), 'Продавец')
    into seller_name
  from public.users u
  where u.id = new.owner_id;

  insert into public.user_notifications (user_id, scope, title, body, is_read)
  select
    f.follower_id,
    'personal',
    'Новое объявление',
    seller_name || ' разместил новое объявление: ' || coalesce(new.title, 'Без названия'),
    false
  from public.user_follows f
  where f.seller_id = new.owner_id;

  return new;
end;
$$;

drop trigger if exists trg_notify_followers_about_listing on public.listings;
create trigger trg_notify_followers_about_listing
after insert on public.listings
for each row
execute function public.notify_followers_about_listing();
