-- Fresh Supabase projects only. Never apply over the legacy schema.
begin;
create schema if not exists private;
revoke all on schema private from public;
create table public.admins (
 singleton boolean primary key default true check(singleton),
 user_id uuid not null unique references auth.users(id) on delete restrict
);
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default 'مستخدم' check(length(name) between 1 and 100),
 city text not null default '', area text not null default '', phone text not null default '',
 avatar_url text not null default '', bio text not null default '' check(length(bio)<=1200),
 social_links jsonb not null default '{}', visibility jsonb not null default '{"showPhone":false,"showSocial":true}',
 verified boolean not null default false, status text not null default 'active' check(status in ('active','blocked','disabled')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.admins where user_id=auth.uid()); $$;
create function public.is_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and status='active'); $$;
create function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,name,city) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'name',''),'مستخدم'),100),left(coalesce(new.raw_user_meta_data->>'city',''),80)); return new;
end; $$;
create trigger marketplace_new_user after insert on auth.users for each row execute function private.new_user();
-- Persistent entitlement is never granted to clients. Deleting listings does not reset it.
create table private.promotion_ledger(user_id uuid primary key, used boolean not null default false, consumed_at timestamptz);
create table public.listings (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check(length(title) between 3 and 180), description text not null check(length(description) between 3 and 5000),
 cat text not null, subcategory text not null default '', city text not null, area text not null default '',
 type text not null default 'sale' check(type in ('sale','wanted','exchange')),
 condition text not null default 'used' check(condition in ('new','used','refurbished')),
 price numeric(16,2) not null default 0 check(price>=0), currency text not null default 'IQD' check(currency in ('IQD','USD')),
 brand text not null default '', model text not null default '', quantity integer not null default 1 check(quantity between 1 and 999999),
 delivery text not null default 'pickup', negotiable boolean not null default false,
 images text[] not null default '{}', video_urls text[] not null default '{}', contact_url text not null default '',
 tags text[] not null default '{}', featured boolean not null default false, pinned boolean not null default false,
 moderation_status text not null default 'published' check(moderation_status in ('draft','published','hidden','pending','rejected')),
 expires_at timestamptz not null default now()+interval '90 days', views bigint not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(cardinality(images)<=8),check(cardinality(video_urls)<=2)
);
create function private.consume_promotion() returns trigger language plpgsql security definer set search_path='' as $$
declare granted boolean;
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.id<>old.id then raise exception 'immutable owner'; end if;
  if not public.is_admin() then
   new.featured:=old.featured; new.pinned:=old.pinned; if coalesce(auth.role(),'')<>'service_role' then new.views:=old.views;end if;
   if old.moderation_status in ('hidden','rejected','pending') then new.moderation_status:=old.moderation_status; end if;
  end if;
 else new.featured:=false;new.pinned:=false;new.views:=0;
 end if;
 if new.moderation_status='published' and (tg_op='INSERT' or old.moderation_status='draft') then
  insert into private.promotion_ledger(user_id) values(new.user_id) on conflict do nothing;
  update private.promotion_ledger set used=true,consumed_at=now() where user_id=new.user_id and used=false returning used into granted;
  if granted then new.featured:=true; end if;
 end if;
 new.updated_at:=now();return new;
end; $$;
create trigger listing_entitlement before insert or update on public.listings for each row execute function private.consume_promotion();
create table public.listing_images(id uuid primary key default gen_random_uuid(), listing_id uuid not null references public.listings(id) on delete cascade, url text not null, position integer not null check(position>=0), unique(listing_id,position));
create table public.listing_videos(id uuid primary key default gen_random_uuid(), listing_id uuid not null references public.listings(id) on delete cascade, url text not null, position integer not null check(position>=0), unique(listing_id,position));
create function private.sync_media() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from public.listing_images where listing_id=new.id;
 insert into public.listing_images(listing_id,url,position) select new.id,u,n-1 from unnest(new.images) with ordinality t(u,n);
 delete from public.listing_videos where listing_id=new.id;
 insert into public.listing_videos(listing_id,url,position) select new.id,u,n-1 from unnest(new.video_urls) with ordinality t(u,n);
 return new;
end; $$;
create trigger listing_media after insert or update of images,video_urls on public.listings for each row execute function private.sync_media();
create table public.favorites(user_id uuid not null references public.profiles(id) on delete cascade, listing_id uuid not null references public.listings(id) on delete cascade, created_at timestamptz not null default now(), primary key(user_id,listing_id));
create table public.messages(id uuid primary key default gen_random_uuid(), from_user_id uuid not null references public.profiles(id) on delete cascade, to_user_id uuid not null references public.profiles(id) on delete cascade, listing_id uuid references public.listings(id) on delete set null, text text not null check(length(text) between 1 and 2000), read boolean not null default false, created_at timestamptz not null default now(),check(from_user_id<>to_user_id));
create table public.notifications(id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade, type text not null, title text not null, target_id uuid, read boolean not null default false, created_at timestamptz not null default now());
create table public.reports(id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade, listing_id uuid references public.listings(id) on delete set null, target_user_id uuid references public.profiles(id) on delete set null, reason text not null check(length(reason)<=80), note text not null default '' check(length(note)<=500), status text not null default 'new' check(status in ('new','reviewing','resolved','dismissed')), admin_note text not null default '', created_at timestamptz not null default now());
create table public.banners(id uuid primary key default gen_random_uuid(), title text not null check(length(title)<=160), body text not null default '', image_url text not null default '', video_url text not null default '', target_url text not null default '', cta text not null default 'اكتشف الآن', position integer not null default 0, enabled boolean not null default true, starts_at timestamptz not null default now(), ends_at timestamptz, created_at timestamptz not null default now(), check(ends_at is null or ends_at>starts_at));
create table public.site_content(key text primary key, title text not null, body text not null check(length(body)<=20000), kind text not null default 'page', settings jsonb not null default '{}', updated_at timestamptz not null default now());
create table public.user_settings(user_id uuid primary key references public.profiles(id) on delete cascade, preferences jsonb not null default '{}', notifications jsonb not null default '{}', updated_at timestamptz not null default now());
create table public.audit_logs(id bigint generated always as identity primary key, actor_id uuid, action text not null, target text, result text not null default 'success', created_at timestamptz not null default now());
create table private.rate_limits(key text primary key, window_started timestamptz not null, attempts integer not null);
create function public.check_rate(p_key text,p_limit integer,p_seconds integer) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into private.rate_limits as r(key,window_started,attempts) values(p_key,now(),1) on conflict(key) do update set
 attempts=case when r.window_started<now()-make_interval(secs=>p_seconds) then 1 else r.attempts+1 end,
 window_started=case when r.window_started<now()-make_interval(secs=>p_seconds) then now() else r.window_started end returning attempts into n;
 delete from private.rate_limits where window_started<now()-interval '2 days';
 return n<=p_limit;
end; $$;
revoke all on function public.check_rate(text,integer,integer) from public,anon,authenticated;
grant execute on function public.check_rate(text,integer,integer) to service_role;
create function public.record_login() returns void language sql security definer set search_path='' as $$
 insert into public.audit_logs(actor_id,action,target) select auth.uid(),'login',auth.uid()::text where auth.uid() is not null; $$;
create function private.log_change() returns trigger language plpgsql security definer set search_path='' as $$
declare obj jsonb;
begin
 obj:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 insert into public.audit_logs(actor_id,action,target) values(auth.uid(),lower(tg_op)||'_'||tg_table_name,coalesce(obj->>'id',obj->>'key',obj->>'user_id'));
 if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create function private.message_notice() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.notifications(user_id,type,title,target_id) values(new.to_user_id,'message','لديك رسالة جديدة',new.id);return new;end; $$;
create trigger message_notification after insert on public.messages for each row execute function private.message_notice();
-- Protected fields and grants: no self-service admin, verification or account status changes.
revoke all on all tables in schema public from anon,authenticated;
grant select on public.admins to authenticated;
grant select on public.profiles to authenticated;
grant update(name,city,area,phone,avatar_url,bio,social_links,visibility,updated_at) on public.profiles to authenticated;
-- Profile phone is populated from verified Auth by a server RPC, not an arbitrary client patch.
revoke update(phone) on public.profiles from authenticated;
create function public.sync_auth_phone() returns void language sql security definer set search_path='' as $$
 update public.profiles set phone=coalesce((select phone from auth.users where id=auth.uid() and phone_confirmed_at is not null),'') where id=auth.uid(); $$;
create function public.public_profiles(p_ids uuid[]) returns table(id uuid,name text,city text,area text,phone text,avatar_url text,bio text,social_links jsonb,verified boolean,created_at timestamptz) language sql stable security definer set search_path='' as $$
 select p.id,p.name,p.city,p.area,case when p.visibility->>'showPhone'='true' then p.phone else '' end,p.avatar_url,p.bio,
 case when p.visibility->>'showSocial'='false' then '{}'::jsonb else p.social_links end,p.verified,p.created_at from public.profiles p where p.status='active' and p.id=any(p_ids) limit 60; $$;
grant execute on function public.public_profiles(uuid[]) to anon,authenticated;
grant select on public.listings,public.listing_images,public.listing_videos,public.banners,public.site_content to anon,authenticated;
grant insert(user_id,title,description,cat,subcategory,city,area,type,condition,price,currency,brand,model,quantity,delivery,negotiable,images,video_urls,contact_url,tags,moderation_status) on public.listings to authenticated;
grant update(title,description,cat,subcategory,city,area,type,condition,price,currency,brand,model,quantity,delivery,negotiable,images,video_urls,contact_url,tags,moderation_status) on public.listings to authenticated;
grant delete on public.listings to authenticated;
grant select,insert,delete on public.favorites to authenticated;
grant select,insert on public.messages to authenticated; grant update(read) on public.messages to authenticated;
grant select on public.notifications to authenticated; grant update(read) on public.notifications to authenticated;
grant select on public.reports to authenticated;grant insert(user_id,listing_id,target_user_id,reason,note) on public.reports to authenticated;
grant select,insert,update,delete on public.user_settings to authenticated;
grant select on public.audit_logs to authenticated;
-- Admin mutations are RPCs; protected columns remain inaccessible in the Data API.
create function public.admin_profile(p_id uuid,p_status text,p_verified boolean default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'admin_required';end if;
 if p_id=auth.uid() then raise exception 'cannot_disable_admin';end if;
 update public.profiles set status=p_status,verified=coalesce(p_verified,verified) where id=p_id;
end; $$;
create function public.admin_listing(p_id uuid,p_status text default null,p_featured boolean default null,p_pinned boolean default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'admin_required';end if;
 update public.listings set moderation_status=coalesce(p_status,moderation_status),featured=coalesce(p_featured,featured),pinned=coalesce(p_pinned,pinned) where id=p_id;
end; $$;
create function public.admin_report(p_id uuid,p_status text,p_note text) returns void language plpgsql security definer set search_path='' as $$
begin if not public.is_admin() then raise exception 'admin_required';end if;
 update public.reports set status=p_status,admin_note=left(p_note,2000) where id=p_id;end; $$;
grant insert,update,delete on public.banners,public.site_content to authenticated;
do $$ declare t text;begin
 foreach t in array array['admins','profiles','listings','listing_images','listing_videos','favorites','messages','notifications','reports','banners','site_content','user_settings','audit_logs'] loop
 execute format('alter table public.%I enable row level security',t);
 end loop;
 foreach t in array array['admins','profiles','listings','reports','banners','site_content'] loop
 execute format('create trigger audit_change after insert or update or delete on public.%I for each row execute function private.log_change()',t);
 end loop;
end $$;
create policy admin_read on public.admins for select to authenticated using(public.is_admin());
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_edit on public.profiles for update to authenticated using(id=auth.uid() and public.is_active()) with check(id=auth.uid());
create policy listing_read on public.listings for select using((moderation_status='published' and expires_at>now() and exists(select 1 from public.public_profiles(array[user_id]))) or user_id=auth.uid() or public.is_admin());
create policy listing_add on public.listings for insert to authenticated with check(user_id=auth.uid() and public.is_active() and moderation_status in ('published','draft'));
create policy listing_edit on public.listings for update to authenticated using((user_id=auth.uid() and public.is_active()) or public.is_admin()) with check((user_id=auth.uid() and public.is_active()) or public.is_admin());
create policy listing_delete on public.listings for delete to authenticated using((user_id=auth.uid() and public.is_active()) or public.is_admin());
create policy image_read on public.listing_images for select using(exists(select 1 from public.listings l where l.id=listing_id));
create policy video_read on public.listing_videos for select using(exists(select 1 from public.listings l where l.id=listing_id));
create policy favorite_read on public.favorites for select to authenticated using(user_id=auth.uid() and public.is_active());
create policy favorite_add on public.favorites for insert to authenticated with check(user_id=auth.uid() and public.is_active());
create policy favorite_delete on public.favorites for delete to authenticated using(user_id=auth.uid() and public.is_active());
create policy message_read on public.messages for select to authenticated using(public.is_active() and (from_user_id=auth.uid() or to_user_id=auth.uid()));
create policy message_add on public.messages for insert to authenticated with check(from_user_id=auth.uid() and public.is_active() and not read and exists(select 1 from public.public_profiles(array[to_user_id])));
create policy message_mark on public.messages for update to authenticated using(to_user_id=auth.uid() and public.is_active()) with check(to_user_id=auth.uid());
create policy notice_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notice_mark on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy report_read on public.reports for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy report_add on public.reports for insert to authenticated with check(user_id=auth.uid() and public.is_active() and (listing_id is not null or target_user_id is not null));
create policy banner_read on public.banners for select using(public.is_admin() or (enabled and starts_at<=now() and (ends_at is null or ends_at>now())));
create policy banner_admin on public.banners for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy content_read on public.site_content for select using(true);
create policy content_admin on public.site_content for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy setting_owner on public.user_settings for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and public.is_active());
create policy audit_admin on public.audit_logs for select to authenticated using(public.is_admin());
-- Storage: private, user-folder ownership. Browser uploads are not granted; backend validates magic bytes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('marketplace-media','marketplace-media',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/webm']);
create policy media_read on storage.objects for select to authenticated using(bucket_id='marketplace-media' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
-- No authenticated insert/update/delete storage policies. Only validated server uploads use service role.
create index listings_feed on public.listings(moderation_status,created_at desc);
create index listings_seller on public.listings(user_id,created_at desc);
create index listings_filter on public.listings(cat,city,price);
create index messages_inbox on public.messages(to_user_id,read,created_at desc);
create index messages_outbox on public.messages(from_user_id,created_at desc);
create index notifications_inbox on public.notifications(user_id,read,created_at desc);
create index reports_queue on public.reports(status,created_at desc);
create index audit_recent on public.audit_logs(created_at desc);
create index listings_search on public.listings using gin(to_tsvector('simple',title||' '||description));
create table public.media_objects(path text primary key,owner_id uuid not null references public.profiles(id) on delete cascade,mime text not null,bytes integer not null check(bytes>0),created_at timestamptz not null default now());
alter table public.media_objects enable row level security;
revoke all on public.media_objects from anon,authenticated;
-- Harden functions: private trigger helpers are not callable through the Data API.
revoke all on all functions in schema private from public,anon,authenticated;
revoke all on function public.record_login(),public.sync_auth_phone(),public.admin_profile(uuid,text,boolean),public.admin_listing(uuid,text,boolean,boolean),public.admin_report(uuid,text,text) from public,anon;
grant execute on function public.record_login(),public.sync_auth_phone(),public.admin_profile(uuid,text,boolean),public.admin_listing(uuid,text,boolean,boolean),public.admin_report(uuid,text,text) to authenticated;
-- Defense in depth for direct authenticated REST writes.
create function private.valid_https(u text) returns boolean language sql immutable set search_path='' as $$
 select u='' or (u ~ '^https://[A-Za-z0-9.-]+(:443)?(/[^[:space:]<>]*)?$' and u !~* '^https://(localhost|127\.|10\.|192\.168\.|169\.254\.)'); $$;
create function private.validate_listing_media() returns trigger language plpgsql security definer set search_path='' as $$
declare f text;
begin
 if not private.valid_https(new.contact_url) then raise exception 'invalid contact url';end if;
 foreach f in array new.images loop
  if not exists(select 1 from public.media_objects m where m.path=f and m.mime like 'image/%' and (m.owner_id=new.user_id or public.is_admin())) then raise exception 'media_not_owned';end if;
 end loop;
 foreach f in array new.video_urls loop
  if f ~ '^https://(www\.)?(youtube\.com|youtu\.be|vimeo\.com)/' and private.valid_https(f) then continue;end if;
  if not exists(select 1 from public.media_objects m where m.path=f and m.mime like 'video/%' and (m.owner_id=new.user_id or public.is_admin())) then raise exception 'media_not_owned';end if;
 end loop;
 return new;
end; $$;
create trigger listing_validate before insert or update on public.listings for each row execute function private.validate_listing_media();
create function private.validate_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare u text;
begin
 if new.avatar_url<>'' and not exists(select 1 from public.media_objects m where m.path=new.avatar_url and m.owner_id=new.id and m.mime like 'image/%') then raise exception 'invalid_avatar';end if;
 if jsonb_typeof(new.social_links)<>'object' or length(new.social_links::text)>4000 then raise exception 'invalid_socials';end if;
 for u in select value from jsonb_each_text(new.social_links) loop
  if not private.valid_https(u) then raise exception 'invalid_social_url';end if;
 end loop;
 return new;
end; $$;
create trigger profile_validate before update on public.profiles for each row execute function private.validate_profile();
revoke all on all functions in schema private from public,anon,authenticated;
create table public.reviews(id uuid primary key default gen_random_uuid(),author_id uuid not null references public.profiles(id) on delete cascade,target_id uuid not null references public.profiles(id) on delete cascade,rating integer not null check(rating between 1 and 5),text text not null check(length(text)<=1000),created_at timestamptz not null default now(),unique(author_id,target_id),check(author_id<>target_id));
alter table public.reviews enable row level security;
revoke all on public.reviews from anon,authenticated;
grant select on public.reviews to anon,authenticated;
grant insert(author_id,target_id,rating,text) on public.reviews to authenticated;
create policy review_read on public.reviews for select using(true);
create policy review_add on public.reviews for insert to authenticated with check(author_id=auth.uid() and public.is_active());
create function public.record_view(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin update public.listings set views=views+1 where id=p_id and moderation_status='published' and expires_at>now();end; $$;
revoke all on function public.record_view(uuid) from public,anon,authenticated;
grant execute on function public.record_view(uuid) to service_role;
create function public.admin_stats() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if not public.is_admin() then raise exception 'admin_required';end if;
return jsonb_build_object('users',(select count(*) from public.profiles),'listings',(select count(*) from public.listings),'reports',(select count(*) from public.reports),'active',(select count(*) from public.listings where moderation_status='published' and expires_at>now()),'hidden',(select count(*) from public.listings where moderation_status='hidden'),'featured',(select count(*) from public.listings where featured),'messages',(select count(*) from public.messages),'views',(select coalesce(sum(views),0) from public.listings));end; $$;
revoke all on function public.admin_stats() from public,anon;
grant execute on function public.admin_stats() to authenticated;
create table private.recovery_tickets(hash text primary key,user_id uuid not null,expires_at timestamptz not null);
create function public.issue_recovery(p_hash text,p_user uuid) returns void language sql security definer set search_path='' as $$ insert into private.recovery_tickets values(p_hash,p_user,now()+interval '10 minutes'); $$;
create function public.consume_recovery(p_hash text,p_user uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;begin delete from private.recovery_tickets where hash=p_hash and user_id=p_user and expires_at>now();get diagnostics n=row_count;return n=1;end; $$;
revoke all on function public.issue_recovery(text,uuid),public.consume_recovery(text,uuid) from public,anon,authenticated;
grant execute on function public.issue_recovery(text,uuid),public.consume_recovery(text,uuid) to service_role;
grant all on all tables in schema public to service_role;
grant usage,select on all sequences in schema public to service_role;
commit;
