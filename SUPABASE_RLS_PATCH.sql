-- ATTA incremental RLS/permissions patch
-- Run in Supabase SQL Editor

create extension if not exists pgcrypto;

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

-- ---------------------------
-- users
-- ---------------------------
alter table if exists public.users enable row level security;

drop policy if exists "users_select_all" on public.users;
create policy "users_select_all"
on public.users
for select
to authenticated
using (true);

drop policy if exists "users_insert_own" on public.users;
create policy "users_insert_own"
on public.users
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "users_update_own" on public.users;
create policy "users_update_own"
on public.users
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- ---------------------------
-- listings
-- ---------------------------
alter table if exists public.listings enable row level security;

drop policy if exists "listings_select_visible" on public.listings;
create policy "listings_select_visible"
on public.listings
for select
to authenticated
using (
  status = 'approved'
  or owner_id = auth.uid()
  or public.is_admin(auth.uid())
);

drop policy if exists "listings_insert_own" on public.listings;
create policy "listings_insert_own"
on public.listings
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "listings_update_owner_or_admin" on public.listings;
create policy "listings_update_owner_or_admin"
on public.listings
for update
to authenticated
using (owner_id = auth.uid() or public.is_admin(auth.uid()))
with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "listings_delete_owner_or_admin" on public.listings;
create policy "listings_delete_owner_or_admin"
on public.listings
for delete
to authenticated
using (owner_id = auth.uid() or public.is_admin(auth.uid()));

-- ---------------------------
-- chats / chat_messages
-- ---------------------------
alter table if exists public.chats enable row level security;
alter table if exists public.chat_messages enable row level security;

drop policy if exists "chats_member_select" on public.chats;
create policy "chats_member_select"
on public.chats
for select
to authenticated
using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "chats_member_insert" on public.chats;
create policy "chats_member_insert"
on public.chats
for insert
to authenticated
with check (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "chats_member_update" on public.chats;
create policy "chats_member_update"
on public.chats
for update
to authenticated
using (buyer_id = auth.uid() or seller_id = auth.uid())
with check (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "chats_member_delete" on public.chats;
create policy "chats_member_delete"
on public.chats
for delete
to authenticated
using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "chat_messages_member_select" on public.chat_messages;
create policy "chat_messages_member_select"
on public.chat_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_messages.chat_id
      and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())
  )
);

drop policy if exists "chat_messages_member_insert" on public.chat_messages;
create policy "chat_messages_member_insert"
on public.chat_messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.chats c
    where c.id = chat_messages.chat_id
      and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())
  )
);

drop policy if exists "chat_messages_member_delete" on public.chat_messages;
create policy "chat_messages_member_delete"
on public.chat_messages
for delete
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_messages.chat_id
      and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())
  )
);

-- ---------------------------
-- reviews
-- ---------------------------
alter table if exists public.reviews enable row level security;

drop policy if exists "reviews_select_all" on public.reviews;
create policy "reviews_select_all"
on public.reviews
for select
to authenticated
using (true);

drop policy if exists "reviews_insert_reviewer" on public.reviews;
create policy "reviews_insert_reviewer"
on public.reviews
for insert
to authenticated
with check (reviewer_id = auth.uid());

drop policy if exists "reviews_update_seller_or_admin" on public.reviews;
create policy "reviews_update_seller_or_admin"
on public.reviews
for update
to authenticated
using (seller_id = auth.uid() or public.is_admin(auth.uid()))
with check (seller_id = auth.uid() or public.is_admin(auth.uid()));

-- ---------------------------
-- reports
-- ---------------------------
alter table if exists public.reports enable row level security;

drop policy if exists "reports_insert_reporter" on public.reports;
create policy "reports_insert_reporter"
on public.reports
for insert
to authenticated
with check (reporter_id = auth.uid());

drop policy if exists "reports_select_owner_admin" on public.reports;
create policy "reports_select_owner_admin"
on public.reports
for select
to authenticated
using (
  reporter_id = auth.uid()
  or listing_owner_id = auth.uid()
  or public.is_admin(auth.uid())
);

drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_admin_update"
on public.reports
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

-- ---------------------------
-- support_tickets / support_messages
-- ---------------------------
alter table if exists public.support_tickets enable row level security;
alter table if exists public.support_messages enable row level security;

drop policy if exists "support_tickets_select_owner_admin" on public.support_tickets;
create policy "support_tickets_select_owner_admin"
on public.support_tickets
for select
to authenticated
using (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "support_tickets_insert_owner_admin" on public.support_tickets;
create policy "support_tickets_insert_owner_admin"
on public.support_tickets
for insert
to authenticated
with check (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "support_tickets_update_owner_admin" on public.support_tickets;
create policy "support_tickets_update_owner_admin"
on public.support_tickets
for update
to authenticated
using (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()))
with check (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "support_messages_select_owner_admin" on public.support_messages;
create policy "support_messages_select_owner_admin"
on public.support_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.support_tickets t
    where t.id = support_messages.ticket_id
      and (t.uid = auth.uid() or t.user_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop policy if exists "support_messages_insert_owner_admin" on public.support_messages;
create policy "support_messages_insert_owner_admin"
on public.support_messages
for insert
to authenticated
with check (
  exists (
    select 1
    from public.support_tickets t
    where t.id = support_messages.ticket_id
      and (t.uid = auth.uid() or t.user_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

-- ---------------------------
-- notifications
-- ---------------------------
create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null references auth.users(id) on delete cascade,
  scope text not null default 'personal',
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.user_notifications
  alter column user_id drop not null;

alter table public.user_notifications enable row level security;

grant select, insert, update, delete
on public.user_notifications
to authenticated;

drop policy if exists "notifications_select" on public.user_notifications;
create policy "notifications_select"
on public.user_notifications
for select
to authenticated
using (
  scope = 'global'
  or user_id = auth.uid()
  or public.is_admin(auth.uid())
);

drop policy if exists "notifications_insert_admin_only" on public.user_notifications;
create policy "notifications_insert_admin_only"
on public.user_notifications
for insert
to authenticated
with check (
  public.is_admin(auth.uid())
  and (
    (scope = 'global' and user_id is null)
    or
    (scope = 'personal' and user_id is not null)
  )
);

drop policy if exists "notifications_update_own_or_admin" on public.user_notifications;
create policy "notifications_update_own_or_admin"
on public.user_notifications
for update
to authenticated
using (user_id = auth.uid() or public.is_admin(auth.uid()))
with check (user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "notifications_delete_admin_only" on public.user_notifications;
create policy "notifications_delete_admin_only"
on public.user_notifications
for delete
to authenticated
using (public.is_admin(auth.uid()));

create index if not exists idx_user_notifications_user_scope
  on public.user_notifications(user_id, scope, created_at desc);

-- ---------------------------
-- saved searches
-- ---------------------------
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

-- ---------------------------
-- storage buckets + policies
-- ---------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('listing-photos', 'listing-photos', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat_images', 'chat_images', true)
on conflict (id) do nothing;

drop policy if exists "avatars_select" on storage.objects;
create policy "avatars_select"
on storage.objects
for select
to public
using (bucket_id = 'avatars');

drop policy if exists "avatars_write_own" on storage.objects;
create policy "avatars_write_own"
on storage.objects
for all
to authenticated
using (
  bucket_id = 'avatars'
  and split_part(name, '/', 1) = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "listing_photos_select" on storage.objects;
create policy "listing_photos_select"
on storage.objects
for select
to public
using (bucket_id = 'listing-photos');

drop policy if exists "listing_photos_insert_auth" on storage.objects;
create policy "listing_photos_insert_auth"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'listing-photos');

drop policy if exists "listing_photos_update_auth" on storage.objects;
create policy "listing_photos_update_auth"
on storage.objects
for update
to authenticated
using (bucket_id = 'listing-photos')
with check (bucket_id = 'listing-photos');

drop policy if exists "listing_photos_delete_auth" on storage.objects;
create policy "listing_photos_delete_auth"
on storage.objects
for delete
to authenticated
using (bucket_id = 'listing-photos');

drop policy if exists "chat_images_select_auth" on storage.objects;
create policy "chat_images_select_auth"
on storage.objects
for select
to authenticated
using (bucket_id = 'chat_images');

drop policy if exists "chat_images_insert_auth" on storage.objects;
create policy "chat_images_insert_auth"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'chat_images');

drop policy if exists "chat_images_delete_auth" on storage.objects;
create policy "chat_images_delete_auth"
on storage.objects
for delete
to authenticated
using (bucket_id = 'chat_images');
