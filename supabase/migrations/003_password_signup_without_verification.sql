-- Password signup without email/SMS confirmation: keep the phone supplied at signup.
-- Enable the corresponding "Confirm email" and "Confirm phone" switches in Supabase Auth.
create or replace function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,name,city,phone)
 values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'name',''),'مستخدم'),100),left(coalesce(new.raw_user_meta_data->>'city',''),80),left(coalesce(new.phone,''),32));
 return new;
end; $$;

create or replace function public.sync_auth_phone() returns void language sql security definer set search_path='' as $$
 update public.profiles set phone=coalesce((select phone from auth.users where id=auth.uid()),'') where id=auth.uid(); $$;
