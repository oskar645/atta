-- Run in Supabase SQL Editor before using backend phone auth

alter table if exists public.users
  add column if not exists phone_verified boolean not null default false;

create index if not exists idx_users_phone on public.users(phone);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (
    id,
    email,
    display_name,
    name,
    phone,
    phone_verified,
    avatar_url,
    photo_url
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'display_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce((new.raw_user_meta_data->>'phone_verified')::boolean, false),
    coalesce(new.raw_user_meta_data->>'avatar_url', ''),
    coalesce(new.raw_user_meta_data->>'photo_url', '')
  )
  on conflict (id) do update
  set email = excluded.email,
      display_name = case when public.users.display_name is null or public.users.display_name = '' then excluded.display_name else public.users.display_name end,
      name = case when public.users.name is null or public.users.name = '' then excluded.name else public.users.name end,
      phone = case when public.users.phone is null or public.users.phone = '' then excluded.phone else public.users.phone end,
      phone_verified = public.users.phone_verified or excluded.phone_verified;

  return new;
end;
$$;
