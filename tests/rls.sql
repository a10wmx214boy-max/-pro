-- Run with psql on DISPOSABLE Supabase DB after both migrations.
-- psql "$TEST_DATABASE_URL" -v a="AUTH_USER_A_UUID" -v b="AUTH_USER_B_UUID" -f tests/rls.sql
-- Use two new verified accounts created through Auth first; rollback leaves no application data.
begin;
select set_config('test.a', :'a', true),set_config('test.b', :'b',true);
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.a'),'role','authenticated')::text,true);
do $$ declare first_id uuid;f boolean;begin
 insert into public.listings(user_id,title,description,cat,city) values(auth.uid(),'اختبار أول','تفاصيل الاختبار الأول','other','بغداد') returning id,featured into first_id,f;
 if not f then raise exception 'FAIL: fresh A first listing not featured';end if;
 insert into public.listings(user_id,title,description,cat,city) values(auth.uid(),'اختبار ثان','تفاصيل الاختبار الثاني','other','بغداد') returning featured into f;
 if f then raise exception 'FAIL: promotion reused';end if;
 delete from public.listings where id=first_id;
 insert into public.listings(user_id,title,description,cat,city) values(auth.uid(),'اختبار ثالث','تفاصيل الاختبار الثالث','other','بغداد') returning featured into f;
 if f then raise exception 'FAIL: deleting restored promotion';end if;
 begin
  insert into public.listings(user_id,title,description,cat,city) values(current_setting('test.b')::uuid,'انتحال مالك','اختبار منع انتحال المالك','other','بغداد');
  raise exception 'FAIL: owner spoof allowed';
 exception when insufficient_privilege then null;end;
 begin update public.profiles set verified=true where id=auth.uid();raise exception 'FAIL verified write';exception when insufficient_privilege then null;end;
 begin insert into public.admins(user_id) values(auth.uid());raise exception 'FAIL admin self grant';exception when insufficient_privilege then null;end;
 insert into public.messages(from_user_id,to_user_id,text) values(auth.uid(),current_setting('test.b')::uuid,'اختبار خصوصية');
 raise notice 'A promotion, protected fields and ownership insert checks passed';
end $$;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.b'),'role','authenticated')::text,true);
do $$ declare n integer;begin
 update public.listings set title='تعديل ممنوع' where user_id=current_setting('test.a')::uuid;
 get diagnostics n=row_count;if n<>0 then raise exception 'FAIL B modified A';end if;
 delete from public.listings where user_id=current_setting('test.a')::uuid;
 get diagnostics n=row_count;if n<>0 then raise exception 'FAIL B deleted A';end if;
 raise notice 'B update/delete ownership passed';
end $$;
set local role anon;
do $$ begin if exists(select 1 from public.messages) then raise exception 'FAIL anonymous messages';end if;exception when insufficient_privilege then raise notice 'Anon messages blocked';end $$;
rollback;
