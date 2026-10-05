-- Run on a disposable database after the platform and web migrations; see scripts/test-web-migrations.py.
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
insert into public.web_push_subscriptions(id,user_id,endpoint_hash,endpoint,p256dh,auth,reminder_minute) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','first','https://push.example/1','test','test',0),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','second','https://push.example/2','test','test',0);
insert into public.linked_accounts(id,user_id,provider,display_name) values
('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','11111111-1111-4111-8111-111111111111','bakalari','Fixture school');
insert into public.mark_fingerprints(id,user_id,linked_account_id,provider,subject_id,fingerprint,source) values
('ffffffff-ffff-4fff-8fff-ffffffffffff','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','bakalari','math','fixture','provider_id');
insert into public.new_mark_events(id,user_id,linked_account_id,fingerprint_id,provider,subject_id,mark_text,notification_body) values
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','ffffffff-ffff-4fff-8fff-ffffffffffff','bakalari','math','1','Fixture');
do $$ begin
  if (select count(*) from public.web_push_jobs where kind='mark') <> 1 then raise exception 'mark trigger isolation'; end if;
  if exists(select 1 from public.web_push_jobs where subscription_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then raise exception 'other account notified'; end if;
end $$;
insert into public.planner_items(owner_id,item_id,item,revision) values
('11111111-1111-4111-8111-111111111111','dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-dddddddddddd','title','Due','dueDate',now(),'isCompleted',false),1),
('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-ddddddddddde',
 jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-ddddddddddde','title','Lesson only','lesson',jsonb_build_object('start',now()),'isCompleted',false),2);
set local role service_role;
select public.enqueue_web_planner_reminders();
select public.enqueue_web_planner_reminders();
do $$ declare claimed integer; begin
  if (select count(*) from public.web_push_jobs where kind='planner') <> 2 then raise exception 'planner reminder missing lesson or not idempotent'; end if;
  select count(*) into claimed from public.claim_web_push_jobs(50);
  if claimed <> 3 then raise exception 'claim count'; end if;
  if exists(select 1 from public.claim_web_push_jobs(50)) then raise exception 'unexpired jobs reclaimed'; end if;
end $$;
reset role;
set local role authenticated;
do $$ begin
  begin perform public.enqueue_web_planner_reminders(); raise exception 'public enqueue allowed'; exception when insufficient_privilege then null; end;
  begin perform public.claim_web_push_jobs(); raise exception 'public claim allowed'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.web_push_subscriptions; raise exception 'push secrets exposed'; exception when insufficient_privilege then null; end;
end $$;
rollback;
