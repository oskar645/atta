begin;

-- Keep only real admin accounts. Everything else is treated as test data.
-- Storage files are not deleted here because Supabase blocks direct DELETE
-- from storage.objects in SQL. Remove files separately in Storage UI/API.

delete from public.user_notifications;
delete from public.support_messages;
delete from public.support_tickets;
delete from public.chat_messages;
delete from public.chats;
delete from public.favorites;
delete from public.reviews;
delete from public.reports;
delete from public.feed_ads;
delete from public.listings;

delete from public.admin_users
where coalesce(is_admin, false) = false;

with admin_ids as (
  select uid
  from public.admin_users
  where coalesce(is_admin, false) = true
)
delete from auth.users
where id not in (select uid from admin_ids);

commit;
