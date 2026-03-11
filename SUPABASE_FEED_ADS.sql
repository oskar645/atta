create table if not exists public.feed_ads (
  id uuid primary key,
  title text not null default '',
  image_url text not null,
  target_url text not null default '',
  placement text not null default 'home',
  duration_days integer not null default 10,
  is_active boolean not null default false,
  activated_at timestamptz null,
  expires_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz null,
  constraint feed_ads_duration_days_check check (duration_days in (1, 2, 5, 10, 15, 20, 30))
);

alter table public.feed_ads enable row level security;

drop policy if exists feed_ads_select_authenticated on public.feed_ads;
create policy feed_ads_select_authenticated
on public.feed_ads
for select
to authenticated
using (true);

drop policy if exists feed_ads_admin_insert on public.feed_ads;
create policy feed_ads_admin_insert
on public.feed_ads
for insert
to authenticated
with check (public.is_admin(auth.uid()));

drop policy if exists feed_ads_admin_update on public.feed_ads;
create policy feed_ads_admin_update
on public.feed_ads
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists feed_ads_admin_delete on public.feed_ads;
create policy feed_ads_admin_delete
on public.feed_ads
for delete
to authenticated
using (public.is_admin(auth.uid()));

insert into storage.buckets (id, name, public)
values ('feed-ads', 'feed-ads', true)
on conflict (id) do nothing;

drop policy if exists "feed_ads_select" on storage.objects;
create policy "feed_ads_select"
on storage.objects
for select
to public
using (bucket_id = 'feed-ads');

drop policy if exists "feed_ads_admin_insert" on storage.objects;
create policy "feed_ads_admin_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'feed-ads'
  and public.is_admin(auth.uid())
);

drop policy if exists "feed_ads_admin_update" on storage.objects;
create policy "feed_ads_admin_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'feed-ads'
  and public.is_admin(auth.uid())
)
with check (
  bucket_id = 'feed-ads'
  and public.is_admin(auth.uid())
);

drop policy if exists "feed_ads_admin_delete" on storage.objects;
create policy "feed_ads_admin_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'feed-ads'
  and public.is_admin(auth.uid())
);
