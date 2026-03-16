create or replace function public.increment_listing_view(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.listings
  set view_count = coalesce(view_count, 0) + 1
  where id = p_listing_id
    and status = 'approved';
end;
$$;

grant execute on function public.increment_listing_view(uuid) to anon, authenticated, service_role;
