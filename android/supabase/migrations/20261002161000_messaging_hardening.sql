-- Authorization hardening applied after messaging_v1.
drop policy if exists conversation_members_insert_member on public.conversation_members;
create policy conversation_members_insert_owner_or_admin on public.conversation_members for insert to authenticated with check (
  exists (select 1 from public.conversations c where c.id = conversation_members.conversation_id and c.created_by = auth.uid())
  or exists (select 1 from public.conversation_members m where m.conversation_id = conversation_members.conversation_id and m.user_id = auth.uid() and m.role in ('OWNER','ADMIN'))
);
drop policy if exists group_members_manage_admin on public.group_members;
create policy group_members_manage_admin on public.group_members for all to authenticated using (
  exists (select 1 from public.conversation_members m where m.conversation_id = group_members.conversation_id and m.user_id = auth.uid() and m.role in ('OWNER','ADMIN'))
) with check (
  exists (select 1 from public.conversation_members m where m.conversation_id = group_members.conversation_id and m.user_id = auth.uid() and m.role in ('OWNER','ADMIN'))
);
insert into storage.buckets(id,name,public) values ('avatars','avatars',false),('chat-media','chat-media',false),('attachments','attachments',false),('voice-messages','voice-messages',false) on conflict(id) do nothing;
