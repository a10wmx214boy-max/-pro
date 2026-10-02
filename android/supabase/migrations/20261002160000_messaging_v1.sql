-- Messaging v1 migration. Existing marketplace tables are preserved.
create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists username text,
  add column if not exists display_name text,
  add column if not exists last_seen_at timestamptz,
  add column if not exists last_seen_visibility text not null default 'everyone',
  add column if not exists read_receipts boolean not null default true;

update public.profiles
set display_name = coalesce(nullif(display_name, ''), name, 'مستخدم')
where display_name is null or display_name = '';

create unique index if not exists profiles_username_lower_uidx
  on public.profiles (lower(username)) where username is not null;
create index if not exists profiles_username_search_idx
  on public.profiles using gin (to_tsvector('simple', coalesce(username,'') || ' ' || coalesce(display_name, name, '')));

alter table public.profiles
  drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format check (username is null or username ~ '^[a-zA-Z0-9_]{3,32}$');
alter table public.profiles
  drop constraint if exists profiles_last_seen_visibility;
alter table public.profiles
  add constraint profiles_last_seen_visibility check (last_seen_visibility in ('everyone','contacts','nobody'));

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('DIRECT','GROUP')),
  title text,
  avatar_url text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'MEMBER' check (role in ('OWNER','ADMIN','MEMBER')),
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text,
  message_type text not null default 'TEXT' check (message_type in ('TEXT','IMAGE','FILE','AUDIO','SYSTEM')),
  reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_edited boolean not null default false,
  constraint chat_messages_content_length check (content is null or char_length(content) between 1 and 10000)
);

create table if not exists public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0 and byte_size <= 52428800),
  created_at timestamptz not null default now()
);

create table if not exists public.message_receipts (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

create table if not exists public.conversation_user_settings (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_muted boolean not null default false,
  is_pinned boolean not null default false,
  primary key (conversation_id, user_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.group_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'MEMBER' check (role in ('OWNER','ADMIN','MEMBER')),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_members_user_idx on public.conversation_members(user_id, conversation_id);
create index if not exists chat_messages_conversation_created_idx on public.chat_messages(conversation_id, created_at desc);
create index if not exists chat_messages_sender_idx on public.chat_messages(sender_id, created_at desc);
create index if not exists message_attachments_message_idx on public.message_attachments(message_id);

create or replace function public.is_conversation_member(target_conversation uuid, target_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.conversation_members where conversation_id = target_conversation and user_id = target_user) $$;

create or replace function public.is_blocked_between(other_user uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.blocks where (blocker_id = auth.uid() and blocked_id = other_user) or (blocker_id = other_user and blocked_id = auth.uid())) $$;

create or replace function public.touch_profile_presence()
returns trigger language plpgsql security definer set search_path = public
as $$ begin update public.profiles set last_seen_at = now(), updated_at = now() where id = auth.uid(); return new; end $$;

create or replace function public.prevent_direct_duplicate()
returns trigger language plpgsql security definer set search_path = public
as $$ declare duplicate_id uuid; begin if new.kind = 'DIRECT' then select cm1.conversation_id into duplicate_id from public.conversation_members cm1 join public.conversation_members cm2 on cm2.conversation_id=cm1.conversation_id where cm1.user_id=auth.uid() and cm2.user_id <> auth.uid() and cm2.user_id in (select user_id from public.conversation_members where conversation_id=new.id) limit 1; end if; return new; end $$;

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.message_receipts enable row level security;
alter table public.conversation_user_settings enable row level security;
alter table public.blocks enable row level security;
alter table public.group_members enable row level security;

create policy conversations_select_member on public.conversations for select to authenticated using (public.is_conversation_member(id));
create policy conversations_insert_authenticated on public.conversations for insert to authenticated with check (created_by = auth.uid());
create policy conversations_update_member on public.conversations for update to authenticated using (public.is_conversation_member(id)) with check (public.is_conversation_member(id));
create policy conversation_members_select_member on public.conversation_members for select to authenticated using (public.is_conversation_member(conversation_id));
create policy conversation_members_insert_member on public.conversation_members for insert to authenticated with check (public.is_conversation_member(conversation_id) or user_id = auth.uid());
create policy conversation_members_update_owner on public.conversation_members for update to authenticated using (exists(select 1 from public.conversation_members m where m.conversation_id=conversation_id and m.user_id=auth.uid() and m.role in ('OWNER','ADMIN')));
create policy conversation_members_delete_owner on public.conversation_members for delete to authenticated using (user_id=auth.uid() or exists(select 1 from public.conversation_members m where m.conversation_id=conversation_id and m.user_id=auth.uid() and m.role in ('OWNER','ADMIN')));

create policy chat_messages_select_member on public.chat_messages for select to authenticated using (public.is_conversation_member(conversation_id));
create policy chat_messages_insert_member on public.chat_messages for insert to authenticated with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id) and not public.is_blocked_between((select user_id from public.conversation_members where conversation_id = chat_messages.conversation_id and user_id <> auth.uid() limit 1)));
create policy chat_messages_update_sender on public.chat_messages for update to authenticated using (sender_id = auth.uid()) with check (sender_id = auth.uid());
create policy chat_messages_delete_sender on public.chat_messages for delete to authenticated using (sender_id = auth.uid());
create policy attachments_select_member on public.message_attachments for select to authenticated using (exists(select 1 from public.chat_messages m where m.id=message_id and public.is_conversation_member(m.conversation_id)));
create policy attachments_insert_sender on public.message_attachments for insert to authenticated with check (exists(select 1 from public.chat_messages m where m.id=message_id and m.sender_id=auth.uid()));
create policy receipts_select_member on public.message_receipts for select to authenticated using (exists(select 1 from public.chat_messages m where m.id=message_id and public.is_conversation_member(m.conversation_id)));
create policy receipts_upsert_recipient on public.message_receipts for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy settings_owner on public.conversation_user_settings for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy blocks_owner on public.blocks for all to authenticated using (blocker_id=auth.uid()) with check (blocker_id=auth.uid() and blocked_id <> auth.uid());
create policy group_members_select_member on public.group_members for select to authenticated using (public.is_conversation_member(conversation_id));
create policy group_members_manage_admin on public.group_members for all to authenticated using (exists(select 1 from public.conversation_members m where m.conversation_id=conversation_id and m.user_id=auth.uid() and m.role in ('OWNER','ADMIN'))) with check (exists(select 1 from public.conversation_members m where m.conversation_id=conversation_id and m.user_id=auth.uid() and m.role in ('OWNER','ADMIN')));

create policy profiles_search_authenticated on public.profiles for select to authenticated using (true);
create policy profiles_update_self on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

insert into storage.buckets (id, name, public) values
  ('avatars','avatars',false), ('chat-media','chat-media',false), ('attachments','attachments',false), ('voice-messages','voice-messages',false)
on conflict (id) do nothing;

create policy storage_read_chat_member on storage.objects for select to authenticated using (bucket_id in ('chat-media','attachments','voice-messages') and public.is_conversation_member(split_part(name,'/',1)::uuid));
create policy storage_insert_user_media on storage.objects for insert to authenticated with check (bucket_id in ('avatars','chat-media','attachments','voice-messages') and (owner_id = auth.uid() or (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text)));
create policy storage_update_user_media on storage.objects for update to authenticated using (owner_id = auth.uid());
create policy storage_delete_user_media on storage.objects for delete to authenticated using (owner_id = auth.uid());

alter table public.chat_messages replica identity full;
alter publication supabase_realtime add table public.chat_messages;
alter publication supabase_realtime add table public.conversation_members;
alter publication supabase_realtime add table public.conversations;
