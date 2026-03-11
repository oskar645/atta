alter table if exists public.chat_messages
  add column if not exists delivered_at timestamptz,
  add column if not exists read_at timestamptz;

alter table if exists public.chat_messages enable row level security;

drop policy if exists chat_messages_update_member on public.chat_messages;
create policy chat_messages_update_member
on public.chat_messages
for update
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_messages.chat_id
      and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.chats c
    where c.id = chat_messages.chat_id
      and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())
  )
);
