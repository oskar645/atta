-- ATTA: full SQL baseline (safe idempotent version)
-- Run in Supabase SQL Editor

create extension if not exists pgcrypto;

-- =========================
-- TABLES
-- =========================
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  name text,
  phone text,
  avatar_url text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  uid uuid primary key references auth.users(id) on delete cascade,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_email text,
  owner_name text,
  title text not null default '',
  description text not null default '',
  category text not null default '',
  subcategory text not null default '',
  price bigint not null default 0,
  phone text not null default '',
  phone_hidden boolean not null default false,
  city text not null default '',
  delivery jsonb not null default '{}'::jsonb,
  car jsonb,
  deal_type text,
  real_estate_type text,
  clothes_type text,
  photo_urls text[] not null default '{}',
  status text not null default 'pending',
  rejection_reason text,
  view_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, listing_id)
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id) on delete set null,
  listing_title text not null default '',
  buyer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  last_message text not null default '',
  unread_for_buyer integer not null default 0,
  unread_for_seller integer not null default 0,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (listing_id, buyer_id, seller_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  text text not null default '',
  image_url text,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  reviewer_name text,
  listing_id uuid references public.listings(id) on delete set null,
  rating integer not null check (rating between 1 and 5),
  comment text not null default '',
  reply_text text,
  reply_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id) on delete set null,
  listing_owner_id uuid references auth.users(id) on delete set null,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null default '',
  comment text not null default '',
  status text not null default 'open',
  admin_uid uuid references auth.users(id) on delete set null,
  decision text,
  admin_comment text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references auth.users(id) on delete set null,
  admin_note text
);

create table if not exists public.support_tickets (
  id uuid primary key,
  uid uuid references auth.users(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  name text not null default 'Пользователь',
  subject text not null default 'Обращение в поддержку',
  status text not null default 'open',
  last_message text not null default '',
  unread_for_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  sender text not null check (sender in ('user', 'admin')),
  text text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  scope text not null check (scope in ('global', 'personal')),
  title text not null default '',
  body text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- =========================
-- INDEXES (speed)
-- =========================
create index if not exists idx_listings_status_created on public.listings(status, created_at desc);
create index if not exists idx_listings_owner_created on public.listings(owner_id, created_at desc);
create index if not exists idx_favorites_user on public.favorites(user_id);
create index if not exists idx_chats_buyer_updated on public.chats(buyer_id, updated_at desc);
create index if not exists idx_chats_seller_updated on public.chats(seller_id, updated_at desc);
create index if not exists idx_chat_messages_chat_created on public.chat_messages(chat_id, created_at desc);
create index if not exists idx_reviews_seller_created on public.reviews(seller_id, created_at desc);
create index if not exists idx_reports_status_created on public.reports(status, created_at desc);
create index if not exists idx_support_tickets_updated on public.support_tickets(updated_at desc);
create index if not exists idx_support_messages_ticket_created on public.support_messages(ticket_id, created_at desc);
create index if not exists idx_notifications_user_scope_created on public.user_notifications(user_id, scope, created_at desc);

-- =========================
-- HELPERS
-- =========================
create or replace function public.is_admin(p_uid uuid)
returns boolean
language sql
stable
as $$
  select exists(
    select 1
    from public.admin_users a
    where a.uid = p_uid and coalesce(a.is_admin, false) = true
  );
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_users_touch on public.users;
create trigger trg_users_touch
before update on public.users
for each row execute function public.touch_updated_at();

drop trigger if exists trg_listings_touch on public.listings;
create trigger trg_listings_touch
before update on public.listings
for each row execute function public.touch_updated_at();

drop trigger if exists trg_support_tickets_touch on public.support_tickets;
create trigger trg_support_tickets_touch
before update on public.support_tickets
for each row execute function public.touch_updated_at();

-- auto-create profile after signup (removes "factory labels" flicker)
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, display_name, name, phone, avatar_url, photo_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'display_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', ''),
    coalesce(new.raw_user_meta_data->>'photo_url', '')
  )
  on conflict (id) do update
  set email = excluded.email,
      display_name = case when public.users.display_name is null or public.users.display_name = '' then excluded.display_name else public.users.display_name end,
      name = case when public.users.name is null or public.users.name = '' then excluded.name else public.users.name end,
      phone = case when public.users.phone is null or public.users.phone = '' then excluded.phone else public.users.phone end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- =========================
-- RLS
-- =========================
alter table public.users enable row level security;
alter table public.admin_users enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.chats enable row level security;
alter table public.chat_messages enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
alter table public.user_notifications enable row level security;

drop policy if exists users_select_all on public.users;
create policy users_select_all on public.users for select to authenticated using (true);
drop policy if exists users_insert_own on public.users;
create policy users_insert_own on public.users for insert to authenticated with check (auth.uid() = id);
drop policy if exists users_update_own on public.users;
create policy users_update_own on public.users for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists admin_users_select_admin on public.admin_users;
create policy admin_users_select_admin on public.admin_users for select to authenticated using (uid = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists listings_select_visible on public.listings;
create policy listings_select_visible on public.listings for select to authenticated using (status = 'approved' or owner_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists listings_insert_own on public.listings;
create policy listings_insert_own on public.listings for insert to authenticated with check (owner_id = auth.uid());
drop policy if exists listings_update_owner_admin on public.listings;
create policy listings_update_owner_admin on public.listings for update to authenticated using (owner_id = auth.uid() or public.is_admin(auth.uid())) with check (owner_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists listings_delete_owner_admin on public.listings;
create policy listings_delete_owner_admin on public.listings for delete to authenticated using (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists favorites_all_own on public.favorites;
create policy favorites_all_own on public.favorites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists chats_select_member on public.chats;
create policy chats_select_member on public.chats for select to authenticated using (buyer_id = auth.uid() or seller_id = auth.uid());
drop policy if exists chats_insert_member on public.chats;
create policy chats_insert_member on public.chats for insert to authenticated with check (buyer_id = auth.uid() or seller_id = auth.uid());
drop policy if exists chats_update_member on public.chats;
create policy chats_update_member on public.chats for update to authenticated using (buyer_id = auth.uid() or seller_id = auth.uid()) with check (buyer_id = auth.uid() or seller_id = auth.uid());
drop policy if exists chats_delete_member on public.chats;
create policy chats_delete_member on public.chats for delete to authenticated using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists chat_messages_select_member on public.chat_messages;
create policy chat_messages_select_member on public.chat_messages for select to authenticated using (
  exists (select 1 from public.chats c where c.id = chat_messages.chat_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
);
drop policy if exists chat_messages_insert_member on public.chat_messages;
create policy chat_messages_insert_member on public.chat_messages for insert to authenticated with check (
  sender_id = auth.uid()
  and exists (select 1 from public.chats c where c.id = chat_messages.chat_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
);
drop policy if exists chat_messages_delete_member on public.chat_messages;
create policy chat_messages_delete_member on public.chat_messages for delete to authenticated using (
  exists (select 1 from public.chats c where c.id = chat_messages.chat_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
);
drop policy if exists chat_messages_update_member on public.chat_messages;
create policy chat_messages_update_member on public.chat_messages for update to authenticated using (
  exists (select 1 from public.chats c where c.id = chat_messages.chat_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
) with check (
  exists (select 1 from public.chats c where c.id = chat_messages.chat_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
);

drop policy if exists reviews_select_all on public.reviews;
create policy reviews_select_all on public.reviews for select to authenticated using (true);
drop policy if exists reviews_insert_reviewer on public.reviews;
create policy reviews_insert_reviewer on public.reviews for insert to authenticated with check (reviewer_id = auth.uid());
drop policy if exists reviews_update_seller_admin on public.reviews;
create policy reviews_update_seller_admin on public.reviews for update to authenticated using (seller_id = auth.uid() or public.is_admin(auth.uid())) with check (seller_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists reports_insert_reporter on public.reports;
create policy reports_insert_reporter on public.reports for insert to authenticated with check (reporter_id = auth.uid());
drop policy if exists reports_select_owner_admin on public.reports;
create policy reports_select_owner_admin on public.reports for select to authenticated using (reporter_id = auth.uid() or listing_owner_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists reports_update_admin on public.reports;
create policy reports_update_admin on public.reports for update to authenticated using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

drop policy if exists support_tickets_select on public.support_tickets;
create policy support_tickets_select on public.support_tickets for select to authenticated using (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists support_tickets_insert on public.support_tickets;
create policy support_tickets_insert on public.support_tickets for insert to authenticated with check (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists support_tickets_update on public.support_tickets;
create policy support_tickets_update on public.support_tickets for update to authenticated using (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid())) with check (uid = auth.uid() or user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists support_messages_select on public.support_messages;
create policy support_messages_select on public.support_messages for select to authenticated using (
  exists (select 1 from public.support_tickets t where t.id = support_messages.ticket_id and (t.uid = auth.uid() or t.user_id = auth.uid() or public.is_admin(auth.uid())))
);
drop policy if exists support_messages_insert on public.support_messages;
create policy support_messages_insert on public.support_messages for insert to authenticated with check (
  exists (select 1 from public.support_tickets t where t.id = support_messages.ticket_id and (t.uid = auth.uid() or t.user_id = auth.uid() or public.is_admin(auth.uid())))
);

drop policy if exists notifications_select on public.user_notifications;
create policy notifications_select on public.user_notifications for select to authenticated using (scope = 'global' or user_id = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists notifications_insert_admin on public.user_notifications;
create policy notifications_insert_admin on public.user_notifications for insert to authenticated with check (
  public.is_admin(auth.uid())
  and ((scope = 'global' and user_id is null) or (scope = 'personal' and user_id is not null))
);
drop policy if exists notifications_update_own_admin on public.user_notifications;
create policy notifications_update_own_admin on public.user_notifications for update to authenticated using (user_id = auth.uid() or public.is_admin(auth.uid())) with check (user_id = auth.uid() or public.is_admin(auth.uid()));

-- =========================
-- STORAGE (public buckets + policies)
-- =========================
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('listing-photos', 'listing-photos', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('chat_images', 'chat_images', true) on conflict (id) do nothing;

drop policy if exists avatars_public_select on storage.objects;
create policy avatars_public_select on storage.objects for select to public using (bucket_id = 'avatars');
drop policy if exists avatars_write_own on storage.objects;
create policy avatars_write_own on storage.objects for all to authenticated
using (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text)
with check (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists listing_photos_public_select on storage.objects;
create policy listing_photos_public_select on storage.objects for select to public using (bucket_id = 'listing-photos');
drop policy if exists listing_photos_write_auth on storage.objects;
create policy listing_photos_write_auth on storage.objects for all to authenticated
using (bucket_id = 'listing-photos')
with check (bucket_id = 'listing-photos');

drop policy if exists chat_images_auth_select on storage.objects;
create policy chat_images_auth_select on storage.objects for select to authenticated using (bucket_id = 'chat_images');
drop policy if exists chat_images_auth_insert on storage.objects;
create policy chat_images_auth_insert on storage.objects for insert to authenticated with check (bucket_id = 'chat_images');
