insert into storage.buckets (id, name, public)
values ('chat_images', 'chat_images', true)
on conflict (id) do nothing;

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

drop policy if exists "chat_images_update_auth" on storage.objects;
create policy "chat_images_update_auth"
on storage.objects
for update
to authenticated
using (bucket_id = 'chat_images')
with check (bucket_id = 'chat_images');

drop policy if exists "chat_images_delete_auth" on storage.objects;
create policy "chat_images_delete_auth"
on storage.objects
for delete
to authenticated
using (bucket_id = 'chat_images');
