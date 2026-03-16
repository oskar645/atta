alter table public.feed_ads
  add column if not exists impression_count bigint not null default 0,
  add column if not exists click_count bigint not null default 0;

create or replace function public.track_feed_ad_event(
  p_ad_id uuid,
  p_event text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_event = 'impression' then
    update public.feed_ads
    set impression_count = coalesce(impression_count, 0) + 1,
        updated_at = timezone('utc', now())
    where id = p_ad_id
      and is_active = true
      and (expires_at is null or expires_at > timezone('utc', now()));
  elsif p_event = 'click' then
    update public.feed_ads
    set click_count = coalesce(click_count, 0) + 1,
        updated_at = timezone('utc', now())
    where id = p_ad_id
      and is_active = true
      and (expires_at is null or expires_at > timezone('utc', now()));
  end if;
end;
$$;

grant execute on function public.track_feed_ad_event(uuid, text) to authenticated;
