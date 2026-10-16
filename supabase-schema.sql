-- Schema for offline-first assembly data synchronization.
-- Run this script in Supabase SQL Editor before enabling production sync.

create table if not exists public.assembly_memberships (
  assembly_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'proclamateur' check (role in ('owner', 'coordinateur', 'secretaire', 'proclamateur', 'assistant', 'ancien', 'responsable_predication')),
  proclamateur_id text,
  created_at timestamptz not null default now(),
  primary key (assembly_id, user_id)
);

alter table public.assembly_memberships add column if not exists proclamateur_id text;

alter table public.assembly_memberships drop constraint if exists assembly_memberships_role_check;
alter table public.assembly_memberships drop constraint if exists assemblymemberships_role_check;
update public.assembly_memberships set role = 'coordinateur' where role = 'admin';
update public.assembly_memberships set role = 'proclamateur' where role = 'member';
alter table public.assembly_memberships add constraint assemblymemberships_role_check
  check (role in ('owner', 'coordinateur', 'secretaire', 'proclamateur', 'assistant', 'ancien', 'responsable_predication'));

create table if not exists public.app_sync_records (
  assembly_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  database_name text not null,
  store_name text not null,
  record_id text not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (assembly_id, database_name, store_name, record_id)
);

create table if not exists public.assembly_page_permissions (
  assembly_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  page_key text not null,
  created_at timestamptz not null default now(),
  primary key (assembly_id, user_id, page_key)
);

create table if not exists public.assembly_access_requests (
  assembly_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (assembly_id, user_id)
);

create table if not exists public.assembly_inbox_messages (
  id bigint generated always as identity primary key,
  assembly_id text not null,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('rapport_personnel', 'rapport_groupe', 'rapport_recu', 'rappel_rapport', 'suivi_pastoral')),
  title text not null,
  body text not null,
  reference_month text,
  dedupe_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  read_at timestamptz,
  unique (assembly_id, recipient_user_id, dedupe_key)
);

create table if not exists public.assembly_whatsapp_consents (
  assembly_id text not null,
  proclamateur_id text not null,
  consented boolean not null default false,
  consented_phone text,
  consented_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (assembly_id, proclamateur_id)
);

alter table public.assembly_whatsapp_consents
  add column if not exists consented_phone text;

create table if not exists public.assembly_whatsapp_deliveries (
  assembly_id text not null,
  proclamateur_id text not null,
  report_month text not null check (report_month ~ '^[0-9]{4}-[0-9]{2}$'),
  reminder_kind text not null default 'secretary'
    check (reminder_kind in ('before-month-end', 'after-month-5', 'after-month-10', 'secretary', 'secretary-follow-up', 'manager')),
  status text not null check (status in ('queued', 'sent', 'failed')),
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (assembly_id, proclamateur_id, report_month)
);

create table if not exists public.assembly_report_reminder_actions (
  assembly_id text not null,
  report_month text not null check (report_month ~ '^[0-9]{4}-[0-9]{2}$'),
  group_key text not null,
  triggered_by uuid not null references auth.users(id) on delete cascade,
  triggered_at timestamptz not null default now(),
  primary key (assembly_id, report_month, group_key)
);

create table if not exists public.assembly_report_manual_reminders (
  assembly_id text not null,
  proclamateur_id text not null,
  report_month text not null check (report_month ~ '^[0-9]{4}-[0-9]{2}$'),
  sent_by uuid not null references auth.users(id) on delete cascade,
  sent_at timestamptz not null default now(),
  primary key (assembly_id, proclamateur_id, report_month)
);

alter table public.assembly_whatsapp_deliveries
  add column if not exists reminder_kind text not null default 'secretary';
alter table public.assembly_whatsapp_deliveries
  drop constraint if exists assembly_whatsapp_deliveries_pkey;
alter table public.assembly_whatsapp_deliveries
  add constraint assembly_whatsapp_deliveries_pkey
  primary key (assembly_id, proclamateur_id, report_month, reminder_kind);
alter table public.assembly_whatsapp_deliveries
  drop constraint if exists assembly_whatsapp_deliveries_reminder_kind_check;
alter table public.assembly_whatsapp_deliveries
  add constraint assembly_whatsapp_deliveries_reminder_kind_check
  check (reminder_kind in ('before-month-end', 'after-month-5', 'after-month-10', 'secretary', 'secretary-follow-up', 'manager'));

alter table public.assembly_inbox_messages
  drop constraint if exists assembly_inbox_messages_category_check;
alter table public.assembly_inbox_messages
  add constraint assembly_inbox_messages_category_check
  check (category in ('rapport_personnel', 'rapport_groupe', 'rapport_recu', 'rappel_rapport', 'suivi_pastoral'));

alter table public.assembly_memberships enable row level security;
alter table public.app_sync_records enable row level security;
alter table public.assembly_page_permissions enable row level security;
alter table public.assembly_access_requests enable row level security;
alter table public.assembly_inbox_messages enable row level security;
alter table public.assembly_whatsapp_consents enable row level security;
alter table public.assembly_whatsapp_deliveries enable row level security;
alter table public.assembly_report_reminder_actions enable row level security;
alter table public.assembly_report_manual_reminders enable row level security;

drop policy if exists "members can read their assembly memberships" on public.assembly_memberships;
drop policy if exists "members can read assembly records" on public.app_sync_records;
drop policy if exists "members can insert assembly records" on public.app_sync_records;
drop policy if exists "members can update assembly records" on public.app_sync_records;
drop policy if exists "members can read their page permissions" on public.assembly_page_permissions;

create policy "members can read their assembly memberships"
  on public.assembly_memberships for select
  using (user_id = auth.uid());

create policy "members can read assembly records"
  on public.app_sync_records for select
  using (exists (
    select 1 from public.assembly_memberships membership
    where membership.assembly_id = app_sync_records.assembly_id
      and membership.user_id = auth.uid()
  ));

create policy "members can insert assembly records"
  on public.app_sync_records for insert
  with check (exists (
    select 1 from public.assembly_memberships membership
    where membership.assembly_id = app_sync_records.assembly_id
      and membership.user_id = auth.uid()
  ));

create policy "members can update assembly records"
  on public.app_sync_records for update
  using (exists (
    select 1 from public.assembly_memberships membership
    where membership.assembly_id = app_sync_records.assembly_id
      and membership.user_id = auth.uid()
  ));

create policy "members can read their page permissions"
  on public.assembly_page_permissions for select
  using (user_id = auth.uid());

drop policy if exists "users can read their access requests" on public.assembly_access_requests;
create policy "users can read their access requests"
  on public.assembly_access_requests for select
  using (user_id = auth.uid());

drop policy if exists "users can read their inbox messages" on public.assembly_inbox_messages;
create policy "users can read their inbox messages"
  on public.assembly_inbox_messages for select
  using (
    recipient_user_id = auth.uid()
    and exists (
      select 1 from public.assembly_memberships membership
      where membership.assembly_id = assembly_inbox_messages.assembly_id
        and membership.user_id = auth.uid()
    )
    and (category <> 'rappel_rapport' or read_at is null)
  );

grant select on public.assembly_inbox_messages to authenticated;

drop policy if exists "members can read their own WhatsApp consent" on public.assembly_whatsapp_consents;
create policy "members can read their own WhatsApp consent"
  on public.assembly_whatsapp_consents for select
  using (
    exists (
      select 1 from public.assembly_memberships membership
      where membership.assembly_id = assembly_whatsapp_consents.assembly_id
        and membership.user_id = auth.uid()
        and membership.proclamateur_id = assembly_whatsapp_consents.proclamateur_id
    )
  );

revoke all on public.assembly_whatsapp_consents from anon, authenticated;
grant select on public.assembly_whatsapp_consents to authenticated;
revoke all on public.assembly_whatsapp_deliveries from anon, authenticated;
grant all on public.assembly_whatsapp_consents, public.assembly_whatsapp_deliveries to service_role;
revoke all on public.assembly_report_reminder_actions from anon, authenticated;
grant all on public.assembly_report_reminder_actions to service_role;
revoke all on public.assembly_report_manual_reminders from anon, authenticated;
grant all on public.assembly_report_manual_reminders to service_role;

create index if not exists app_sync_records_assembly_idx
  on public.app_sync_records (assembly_id, updated_at);

create index if not exists assembly_inbox_recipient_idx
  on public.assembly_inbox_messages (assembly_id, recipient_user_id, created_at desc);

-- Required for immediate cross-device updates through Supabase Realtime.
do $$
begin
  alter publication supabase_realtime add table public.app_sync_records;
exception
  when duplicate_object then null;
end;
$$;

create or replace function public.can_access_sync_store(target_assembly_id text, target_store_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.assembly_memberships membership
    where membership.assembly_id = target_assembly_id
      and membership.user_id = auth.uid()
      and membership.role in ('owner', 'coordinateur', 'secretaire')
  )
  or exists (
    select 1
    from public.assembly_page_permissions permission
    where permission.assembly_id = target_assembly_id
      and permission.user_id = auth.uid()
      and split_part(permission.page_key, ':', 1) = case target_store_name
        when 'proclamateurs' then 'proclamateurs'
        when 'detailPredication' then 'rapports'
        when 'pionniersAuxiliaire' then 'souscription'
        when 'permanentCandidatures' then 'souscription'
        when 'attendance' then 'assistance'
        when 'visites' then 'programmation'
        when 'epreuves' then 'programmation'
        when 'formations' then 'programmation'
        when 'groupLeaders' then 'programmation'
        when 'tasks' then 'taches'
        when 'pioneerEncouragementReport' then 'pdf'
        else ''
      end
  )
  or (
    target_store_name = 'groupLeaders'
    and exists (
      select 1 from public.assembly_page_permissions permission
      where permission.assembly_id = target_assembly_id
        and permission.user_id = auth.uid()
        and split_part(permission.page_key, ':', 1) in ('rapports', 'programmation')
    )
  );
$$;

revoke all on function public.can_access_sync_store(text, text) from public;
grant execute on function public.can_access_sync_store(text, text) to authenticated;

create or replace function public.can_access_report_sync_record(
  target_assembly_id text,
  target_record_id text,
  target_payload jsonb,
  operation text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_role text;
  caller_proclamateur_id text;
  caller_group text;
  target_proclamateur_id text;
  target_group text;
  caller_manages_group boolean := false;
begin
  select membership.role, membership.proclamateur_id
  into caller_role, caller_proclamateur_id
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();

  if caller_role in ('owner', 'coordinateur', 'secretaire', 'responsable_predication') then
    return true;
  end if;
  if caller_proclamateur_id is null then return false; end if;

  target_proclamateur_id := coalesce(
    nullif(target_payload->>'proclamateurId', ''),
    substring(target_record_id from '^[^_]+_(.*)$'),
    ''
  );
  if target_proclamateur_id = '' then return false; end if;

  if target_proclamateur_id = caller_proclamateur_id then
    return operation in ('read', 'insert');
  end if;

  select nullif(trim(person.payload->>'groupe'), '')
  into caller_group
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = caller_proclamateur_id
    and person.deleted_at is null
  limit 1;
  if caller_group is null then return false; end if;

  select nullif(trim(person.payload->>'groupe'), '')
  into target_group
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = target_proclamateur_id
    and person.deleted_at is null
  limit 1;
  target_group := coalesce(nullif(trim(target_payload->>'groupe'), ''), target_group);
  if target_group is null or lower(target_group) <> lower(caller_group) then return false; end if;

  select exists (
    select 1 from public.app_sync_records leaders
    where leaders.assembly_id = target_assembly_id
      and leaders.database_name = 'ProclamateursDB'
      and leaders.store_name = 'groupLeaders'
      and leaders.deleted_at is null
      and lower(trim(leaders.payload->>'group')) = lower(caller_group)
      and caller_proclamateur_id in (leaders.payload->>'leaderId', leaders.payload->>'adjointId')
  ) into caller_manages_group;

  if operation = 'read' then
    return caller_manages_group or caller_role in ('ancien', 'assistant');
  end if;
  return caller_manages_group and operation in ('insert', 'update');
end;
$$;

revoke all on function public.can_access_report_sync_record(text, text, jsonb, text) from public;
grant execute on function public.can_access_report_sync_record(text, text, jsonb, text) to authenticated;

drop policy if exists "members can read assembly records" on public.app_sync_records;
drop policy if exists "members can insert assembly records" on public.app_sync_records;
drop policy if exists "members can update assembly records" on public.app_sync_records;
drop policy if exists "members can read permitted assembly records" on public.app_sync_records;
drop policy if exists "members can insert permitted assembly records" on public.app_sync_records;
drop policy if exists "members can update permitted assembly records" on public.app_sync_records;

create policy "members can read permitted assembly records"
  on public.app_sync_records for select
  using (
    public.can_access_sync_store(assembly_id, store_name)
    and (
      store_name <> 'detailPredication'
      or public.can_access_report_sync_record(assembly_id, record_id, payload, 'read')
    )
  );

create policy "members can insert permitted assembly records"
  on public.app_sync_records for insert
  with check (
    user_id = auth.uid()
    and public.can_access_sync_store(assembly_id, store_name)
    and (
      store_name <> 'detailPredication'
      or public.can_access_report_sync_record(assembly_id, record_id, payload, 'insert')
    )
  );

create policy "members can update permitted assembly records"
  on public.app_sync_records for update
  using (
    public.can_access_sync_store(assembly_id, store_name)
    and (
      store_name <> 'detailPredication'
      or public.can_access_report_sync_record(assembly_id, record_id, payload, 'update')
    )
  )
  with check (
    public.can_access_sync_store(assembly_id, store_name)
    and (
      store_name <> 'detailPredication'
      or public.can_access_report_sync_record(assembly_id, record_id, payload, 'update')
    )
  );

create or replace function public.write_assembly_inbox_message(
  target_assembly_id text,
  target_user_id uuid,
  target_category text,
  target_title text,
  target_body text,
  target_month text,
  target_dedupe_key text,
  target_metadata jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.assembly_inbox_messages (
    assembly_id, recipient_user_id, category, title, body,
    reference_month, dedupe_key, metadata, created_at, updated_at, read_at
  )
  values (
    target_assembly_id, target_user_id, target_category, target_title, target_body,
    target_month, target_dedupe_key, coalesce(target_metadata, '{}'::jsonb), now(), now(), null
  )
  on conflict (assembly_id, recipient_user_id, dedupe_key) do update
    set category = excluded.category,
        title = excluded.title,
        body = excluded.body,
        reference_month = excluded.reference_month,
        metadata = excluded.metadata,
        updated_at = now(),
        read_at = null;
$$;

revoke all on function public.write_assembly_inbox_message(text, uuid, text, text, text, text, text, jsonb) from public;

create or replace function public.refresh_assembly_group_report_message(
  target_assembly_id text,
  target_month text,
  target_group text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  total_members integer;
  submitted_members integer;
  pending_members jsonb;
  manager record;
  group_key text;
  message_body text;
begin
  group_key := lower(trim(coalesce(target_group, '')));
  if group_key = '' or target_month !~ '^[0-9]{4}-[0-9]{2}$' then return; end if;

  select count(*)::integer
  into total_members
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.deleted_at is null
    and lower(trim(coalesce(person.payload->>'groupe', ''))) = group_key;

  select count(distinct coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')))::integer
  into submitted_members
  from public.app_sync_records report
  join public.app_sync_records person
    on person.assembly_id = report.assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$'))
    and person.deleted_at is null
  where report.assembly_id = target_assembly_id
    and report.database_name = 'ProclamateursDB'
    and report.store_name = 'detailPredication'
    and report.deleted_at is null
    and report.payload->>'month' = target_month
    and lower(trim(coalesce(person.payload->>'groupe', report.payload->>'groupe', ''))) = group_key;

  select coalesce(
    jsonb_agg(jsonb_build_object('name', pending.member_name) order by lower(pending.member_name), pending.member_name),
    '[]'::jsonb
  )
  into pending_members
  from (
    select coalesce(
      nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
      person.record_id
    ) as member_name
    from public.app_sync_records person
    where person.assembly_id = target_assembly_id
      and person.database_name = 'ProclamateursDB'
      and person.store_name = 'proclamateurs'
      and person.deleted_at is null
      and lower(trim(coalesce(person.payload->>'groupe', ''))) = group_key
      and not exists (
        select 1
        from public.app_sync_records report
        where report.assembly_id = target_assembly_id
          and report.database_name = 'ProclamateursDB'
          and report.store_name = 'detailPredication'
          and report.deleted_at is null
          and report.payload->>'month' = target_month
          and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
      )
  ) pending;

  message_body := format(
    '%s, nous espérons que vous vous portez bien, ainsi que votre famille. Bilan du groupe %s pour %s : %s proclamateur(s) sur %s ont remis leur rapport.%s Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
    public.assembly_report_greeting(),
    target_group,
    public.assembly_report_month_label(target_month),
    coalesce(submitted_members, 0),
    coalesce(total_members, 0),
    case
      when coalesce(total_members, 0) - coalesce(submitted_members, 0) <= 0
        then E'\nTous les rapports ont été remis.'
      else E'\nRapports encore attendus (' ||
        (coalesce(total_members, 0) - coalesce(submitted_members, 0))::text ||
        E'). Consultez la liste ci-dessous pour identifier les proclamateurs concernés.' ||
        E'\nMerci d’entrer avec tact en contact avec eux et de les encourager à transmettre leur rapport, de préférence par l’intermédiaire du responsable ou de son adjoint.'
    end
  );

  if total_members = 0 then return; end if;

  if coalesce(submitted_members, 0) >= total_members then
    update public.assembly_inbox_messages message
    set read_at = now(), updated_at = now()
    where message.assembly_id = target_assembly_id
      and message.category = 'rappel_rapport'
      and message.reference_month = target_month
      and message.dedupe_key = 'manager-report-reminder:' || target_month || ':' || group_key;
  else
    update public.assembly_inbox_messages message
    set body = format(
          '%s, nous espérons que vous vous portez bien, ainsi que votre famille. Rappel : %s rapport(s) du groupe %s pour %s sont encore attendus. Consultez la liste ci-dessous et encouragez courtoisement les proclamateurs concernés à transmettre leur rapport, de préférence au responsable ou à son adjoint. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
          public.assembly_report_greeting(),
          greatest(total_members - coalesce(submitted_members, 0), 0),
          target_group,
          public.assembly_report_month_label(target_month)
        ),
        metadata = message.metadata || jsonb_build_object(
          'attendus', greatest(total_members - coalesce(submitted_members, 0), 0),
          'pendingMembers', coalesce(pending_members, '[]'::jsonb)
        ),
        updated_at = now(),
        read_at = null
    where message.assembly_id = target_assembly_id
      and message.category = 'rappel_rapport'
      and message.reference_month = target_month
      and message.dedupe_key = 'manager-report-reminder:' || target_month || ':' || group_key;
  end if;

  for manager in
    select distinct membership.user_id
    from public.app_sync_records leaders
    join public.assembly_memberships membership
      on membership.assembly_id = target_assembly_id
      and membership.proclamateur_id in (
        nullif(leaders.payload->>'leaderId', ''),
        nullif(leaders.payload->>'adjointId', '')
      )
    where leaders.assembly_id = target_assembly_id
      and leaders.database_name = 'ProclamateursDB'
      and leaders.store_name = 'groupLeaders'
      and leaders.deleted_at is null
      and lower(trim(coalesce(leaders.payload->>'group', ''))) = group_key
  loop
    perform public.write_assembly_inbox_message(
      target_assembly_id,
      manager.user_id,
      'rapport_groupe',
      format('Rapports du groupe %s — %s', target_group, public.assembly_report_month_label(target_month)),
      message_body,
      target_month,
      'group-report:' || target_month || ':' || group_key,
      jsonb_build_object(
        'groupe', target_group,
        'total', total_members,
        'remis', coalesce(submitted_members, 0),
        'attendus', greatest(total_members - coalesce(submitted_members, 0), 0),
        'pendingMembers', coalesce(pending_members, '[]'::jsonb)
      )
    );
  end loop;
end;
$$;

revoke all on function public.refresh_assembly_group_report_message(text, text, text) from public;

create or replace function public.assembly_report_greeting()
returns text
language sql
stable
set search_path = public
as $$
  select case
    when extract(hour from (now() at time zone 'Africa/Kinshasa')) >= 18
      or extract(hour from (now() at time zone 'Africa/Kinshasa')) < 5
      then 'Bonsoir'
    else 'Bonjour'
  end;
$$;

revoke all on function public.assembly_report_greeting() from public, anon, authenticated;

create or replace function public.assembly_report_month_label(target_month text)
returns text
language sql
immutable
set search_path = public
as $$
  select
    case substring(target_month from 6 for 2)
      when '01' then 'janvier'
      when '02' then 'février'
      when '03' then 'mars'
      when '04' then 'avril'
      when '05' then 'mai'
      when '06' then 'juin'
      when '07' then 'juillet'
      when '08' then 'août'
      when '09' then 'septembre'
      when '10' then 'octobre'
      when '11' then 'novembre'
      when '12' then 'décembre'
      else target_month
    end || ' ' || substring(target_month from 1 for 4);
$$;

revoke all on function public.assembly_report_month_label(text) from public, anon, authenticated;

create or replace function public.assembly_report_reminder_text(
  target_assembly_id text,
  target_proclamateur_id text,
  target_month text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  person_payload jsonb;
  group_payload jsonb;
  leader_payload jsonb;
  adjoint_payload jsonb;
  secretary_phones text;
  secretary_contact text;
  member_name text;
  salutation text;
  leader_name text;
  adjoint_name text;
  leader_phone text;
  adjoint_phone text;
  reminder_wording text;
begin
  select person.payload
  into person_payload
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = target_proclamateur_id
    and person.deleted_at is null
  limit 1;

  member_name := coalesce(
    nullif(trim(concat_ws(' ', person_payload->>'nom', person_payload->>'postnom', person_payload->>'prenom')), ''),
    target_proclamateur_id
  );
  salutation := case upper(trim(coalesce(person_payload->>'sexe', '')))
    when 'F' then 'Très chère Sr'
    when 'FEMME' then 'Très chère Sr'
    when 'FÉMININ' then 'Très chère Sr'
    when 'M' then 'Très cher Fr'
    when 'HOMME' then 'Très cher Fr'
    when 'MASCULIN' then 'Très cher Fr'
    else 'Bonjour'
  end;

  select leaders.payload
  into group_payload
  from public.app_sync_records leaders
  where leaders.assembly_id = target_assembly_id
    and leaders.database_name = 'ProclamateursDB'
    and leaders.store_name = 'groupLeaders'
    and leaders.deleted_at is null
    and lower(trim(coalesce(leaders.payload->>'group', ''))) =
        lower(trim(coalesce(person_payload->>'groupe', '')))
  order by leaders.updated_at desc
  limit 1;

  select member.payload
  into leader_payload
  from public.app_sync_records member
  where member.assembly_id = target_assembly_id
    and member.database_name = 'ProclamateursDB'
    and member.store_name = 'proclamateurs'
    and member.record_id = nullif(group_payload->>'leaderId', '')
    and member.deleted_at is null
  limit 1;

  select member.payload
  into adjoint_payload
  from public.app_sync_records member
  where member.assembly_id = target_assembly_id
    and member.database_name = 'ProclamateursDB'
    and member.store_name = 'proclamateurs'
    and member.record_id = nullif(group_payload->>'adjointId', '')
    and member.deleted_at is null
  limit 1;

  leader_name := coalesce(
    nullif(trim(concat_ws(' ', leader_payload->>'nom', leader_payload->>'postnom', leader_payload->>'prenom')), ''),
    nullif(trim(group_payload->>'leaderName'), ''),
    'du groupe'
  );
  adjoint_name := coalesce(
    nullif(trim(concat_ws(' ', adjoint_payload->>'nom', adjoint_payload->>'postnom', adjoint_payload->>'prenom')), ''),
    nullif(trim(group_payload->>'adjointName'), ''),
    'du groupe'
  );
  leader_phone := nullif(trim(leader_payload->>'telephone'), '');
  adjoint_phone := nullif(trim(adjoint_payload->>'telephone'), '');

  select string_agg(distinct nullif(trim(person.payload->>'telephone'), ''), ' / ')
  into secretary_phones
  from public.assembly_memberships secretary
  left join public.app_sync_records person
    on person.assembly_id = secretary.assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = secretary.proclamateur_id
    and person.deleted_at is null
  where secretary.assembly_id = target_assembly_id
    and secretary.role = 'secretaire';

  secretary_contact := case
    when secretary_phones is null then 'le secrétariat (numéro non renseigné)'
    when position(' / ' in secretary_phones) > 0 then 'le secrétariat aux numéros ' || secretary_phones
    else 'le secrétariat au numéro ' || secretary_phones
  end;

  reminder_wording := case
    when mod(hashtext(target_proclamateur_id || target_month), 2) = 0 then
      format('Votre rapport d’activité de prédication pour %s n’a pas encore été reçu. Merci de le transmettre dès que possible', public.assembly_report_month_label(target_month))
    else
      format('Nous n’avons pas encore reçu votre rapport d’activité de prédication pour %s. Nous vous prions de bien vouloir le transmettre dès que possible', public.assembly_report_month_label(target_month))
  end;

  return format(
    '%s%s %s, nous espérons que vous vous portez bien, ainsi que votre famille. %s à votre responsable %s%s ou à son adjoint %s%s. Il est préférable de passer par le responsable ou son adjoint. À défaut, vous pouvez le remettre %s. Merci aussi pour les rapports des mois précédents déjà transmis. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
    public.assembly_report_greeting(),
    case when salutation = 'Bonjour' then '' else ', ' || salutation end,
    member_name,
    reminder_wording,
    leader_name,
    case when leader_phone is null then '' else ' — ' || leader_phone end,
    adjoint_name,
    case when adjoint_phone is null then '' else ' — ' || adjoint_phone end,
    secretary_contact
  );
end;
$$;

revoke all on function public.assembly_report_reminder_text(text, text, text) from public, anon, authenticated;

create or replace function public.get_assembly_secretary_contact(target_assembly_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  secretary_phones text;
begin
  select membership.role
  into caller_role
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();

  if caller_role is null then
    raise exception 'Votre compte n’est pas associé à cette assemblée';
  end if;
  if caller_role not in ('owner', 'coordinateur', 'secretaire', 'responsable_predication') then
    raise exception 'Accès secrétariat requis';
  end if;

  select string_agg(distinct nullif(trim(person.payload->>'telephone'), ''), ' / ')
  into secretary_phones
  from public.assembly_memberships secretary
  join public.app_sync_records person
    on person.assembly_id = secretary.assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = secretary.proclamateur_id
    and person.deleted_at is null
  where secretary.assembly_id = target_assembly_id
    and secretary.role = 'secretaire';

  return secretary_phones;
end;
$$;

revoke all on function public.get_assembly_secretary_contact(text) from public, anon;
grant execute on function public.get_assembly_secretary_contact(text) to authenticated;

create or replace function public.get_assembly_report_reminder_status(
  target_assembly_id text,
  target_month text,
  target_group text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  reminder_rows jsonb;
begin
  select membership.role
  into caller_role
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();

  if caller_role is null then
    raise exception 'Votre compte n’est pas associé à cette assemblée';
  end if;
  if caller_role not in ('owner', 'coordinateur', 'secretaire', 'responsable_predication') then
    raise exception 'Accès secrétariat requis';
  end if;
  if target_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'Le mois du rapport est invalide';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'proclamateurId', person.record_id,
      'memberName', coalesce(
        nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
        person.record_id
      ),
      'group', nullif(trim(person.payload->>'groupe'), ''),
      'reminderSent',
        exists (
          select 1
          from public.assembly_report_manual_reminders manual
          where manual.assembly_id = target_assembly_id
            and manual.proclamateur_id = person.record_id
            and manual.report_month = target_month
        )
        or exists (
          select 1
          from public.assembly_whatsapp_deliveries delivery
          where delivery.assembly_id = target_assembly_id
            and delivery.proclamateur_id = person.record_id
            and delivery.report_month = target_month
            and delivery.status = 'sent'
        )
        or exists (
          select 1
          from public.assembly_inbox_messages message
          where message.assembly_id = target_assembly_id
            and message.category = 'rappel_rapport'
            and message.reference_month = target_month
            and message.metadata->>'proclamateurId' = person.record_id
        )
    )
    order by lower(coalesce(
      nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
      person.record_id
    ))
  ), '[]'::jsonb)
  into reminder_rows
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.deleted_at is null
    and (nullif(trim(target_group), '') is null
      or lower(trim(coalesce(person.payload->>'groupe', ''))) = lower(trim(target_group)))
    and not exists (
      select 1
      from public.app_sync_records report
      where report.assembly_id = target_assembly_id
        and report.database_name = 'ProclamateursDB'
        and report.store_name = 'detailPredication'
        and report.deleted_at is null
        and report.payload->>'month' = target_month
        and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
    );

  return reminder_rows;
end;
$$;

revoke all on function public.get_assembly_report_reminder_status(text, text, text) from public, anon;
grant execute on function public.get_assembly_report_reminder_status(text, text, text) to authenticated;

create or replace function public.record_manual_assembly_report_reminder(
  target_assembly_id text,
  target_month text,
  target_proclamateur_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
begin
  select membership.role
  into caller_role
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();

  if caller_role is null then
    raise exception 'Votre compte n’est pas associé à cette assemblée';
  end if;
  if caller_role not in ('owner', 'coordinateur', 'secretaire', 'responsable_predication') then
    raise exception 'Accès secrétariat requis';
  end if;
  if target_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'Le mois du rapport est invalide';
  end if;
  if not exists (
    select 1
    from public.app_sync_records person
    where person.assembly_id = target_assembly_id
      and person.database_name = 'ProclamateursDB'
      and person.store_name = 'proclamateurs'
      and person.record_id = target_proclamateur_id
      and person.deleted_at is null
      and not exists (
        select 1
        from public.app_sync_records report
        where report.assembly_id = target_assembly_id
          and report.database_name = 'ProclamateursDB'
          and report.store_name = 'detailPredication'
          and report.deleted_at is null
          and report.payload->>'month' = target_month
          and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = target_proclamateur_id
      )
  ) then
    raise exception 'Ce proclamateur n’est pas en attente de rapport pour le mois choisi';
  end if;

  insert into public.assembly_report_manual_reminders (
    assembly_id, proclamateur_id, report_month, sent_by, sent_at
  )
  values (target_assembly_id, target_proclamateur_id, target_month, auth.uid(), now())
  on conflict (assembly_id, proclamateur_id, report_month) do update
    set sent_by = excluded.sent_by,
        sent_at = excluded.sent_at;

  return jsonb_build_object('recorded', true);
end;
$$;

revoke all on function public.record_manual_assembly_report_reminder(text, text, text) from public, anon;
grant execute on function public.record_manual_assembly_report_reminder(text, text, text) to authenticated;

create or replace function public.get_my_assembly_report_groups(target_assembly_id text, target_month text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  caller_proclamateur_id text;
  result jsonb;
begin
  if target_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'Le mois du rapport est invalide';
  end if;
  select membership.role, membership.proclamateur_id
  into caller_role, caller_proclamateur_id
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();
  if caller_role is null then
    raise exception 'Votre compte n’est pas associé à cette assemblée';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'group', groups.group_name,
    'total', groups.total_members,
    'submitted', groups.submitted_members,
    'pending', greatest(groups.total_members - groups.submitted_members, 0),
    'triggeredAt', groups.triggered_at
  ) order by groups.group_name), '[]'::jsonb)
  into result
  from (
    select
      leaders.payload->>'group' as group_name,
      count(distinct person.record_id)::integer as total_members,
      count(distinct report_person.record_id)::integer as submitted_members,
      action.triggered_at
    from public.app_sync_records leaders
    join public.app_sync_records person
      on person.assembly_id = leaders.assembly_id
      and person.database_name = 'ProclamateursDB'
      and person.store_name = 'proclamateurs'
      and person.deleted_at is null
      and lower(trim(coalesce(person.payload->>'groupe', ''))) =
          lower(trim(coalesce(leaders.payload->>'group', '')))
    left join lateral (
      select coalesce(
        nullif(report.payload->>'proclamateurId', ''),
        substring(report.record_id from '^[^_]+_(.*)$')
      ) as proclamateur_id
      from public.app_sync_records report
      where report.assembly_id = leaders.assembly_id
        and report.database_name = 'ProclamateursDB'
        and report.store_name = 'detailPredication'
        and report.deleted_at is null
        and report.payload->>'month' = target_month
        and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
      limit 1
    ) report_match on true
    left join public.app_sync_records report_person
      on report_person.assembly_id = leaders.assembly_id
      and report_person.database_name = 'ProclamateursDB'
      and report_person.store_name = 'proclamateurs'
      and report_person.record_id = report_match.proclamateur_id
      and report_person.deleted_at is null
    left join public.assembly_report_reminder_actions action
      on action.assembly_id = leaders.assembly_id
      and action.report_month = target_month
      and action.group_key = lower(trim(coalesce(leaders.payload->>'group', '')))
    where leaders.assembly_id = target_assembly_id
      and leaders.database_name = 'ProclamateursDB'
      and leaders.store_name = 'groupLeaders'
      and leaders.deleted_at is null
      and (
        caller_role in ('owner', 'coordinateur', 'secretaire', 'responsable_predication')
        or caller_proclamateur_id in (
          nullif(leaders.payload->>'leaderId', ''),
          nullif(leaders.payload->>'adjointId', '')
        )
      )
    group by leaders.payload->>'group', action.triggered_at
  ) groups;
  return result;
end;
$$;

revoke all on function public.get_my_assembly_report_groups(text, text) from public;
grant execute on function public.get_my_assembly_report_groups(text, text) to authenticated;

drop function if exists public.send_assembly_report_reminders(text, text);

create or replace function public.send_assembly_report_reminders(
  target_assembly_id text,
  target_month text,
  target_group text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  caller_proclamateur_id text;
  caller_user_id uuid := auth.uid();
  caller_is_group_manager boolean := false;
  member_row record;
  group_row record;
  manager_row record;
  proclamation_count integer := 0;
  manager_count integer := 0;
begin
  select role, proclamateur_id
  into caller_role, caller_proclamateur_id
  from public.assembly_memberships
  where assembly_id = target_assembly_id and user_id = auth.uid();
  if caller_role is null then
    raise exception 'Votre compte n’est pas associé à cette assemblée';
  end if;
  if target_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'Le mois du rapport est invalide';
  end if;

  if caller_role not in ('owner', 'coordinateur', 'secretaire', 'responsable_predication') then
    if nullif(trim(target_group), '') is null
      or extract(day from (now() at time zone 'Africa/Kinshasa')::date) < 3
      or not exists (
        select 1
        from public.app_sync_records leaders
        where leaders.assembly_id = target_assembly_id
          and leaders.database_name = 'ProclamateursDB'
          and leaders.store_name = 'groupLeaders'
          and leaders.deleted_at is null
          and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(target_group))
          and caller_proclamateur_id in (
            nullif(leaders.payload->>'leaderId', ''),
            nullif(leaders.payload->>'adjointId', '')
          )
      ) then
      raise exception 'Seul le responsable ou son adjoint peut rappeler les membres de son groupe à partir du 3';
    end if;
    caller_is_group_manager := true;
  elsif extract(day from (now() at time zone 'Africa/Kinshasa')::date) < 5 then
    raise exception 'Le secrétariat peut envoyer les rappels à partir du 5 du mois';
  end if;

  if caller_is_group_manager then
    insert into public.assembly_report_reminder_actions (
      assembly_id, report_month, group_key, triggered_by, triggered_at
    )
    values (
      target_assembly_id,
      target_month,
      lower(trim(target_group)),
      caller_user_id,
      now()
    )
    on conflict (assembly_id, report_month, group_key) do update
      set triggered_by = excluded.triggered_by,
          triggered_at = excluded.triggered_at;
  end if;

  for member_row in
    select
      person.record_id as proclamateur_id,
      membership.user_id,
      coalesce(
        nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
        person.record_id
      ) as member_name,
      nullif(trim(person.payload->>'groupe'), '') as group_name
    from public.app_sync_records person
    join public.assembly_memberships membership
      on membership.assembly_id = target_assembly_id
      and membership.proclamateur_id = person.record_id
    where person.assembly_id = target_assembly_id
      and person.database_name = 'ProclamateursDB'
      and person.store_name = 'proclamateurs'
      and person.deleted_at is null
      and (caller_is_group_manager or nullif(trim(target_group), '') is null
        or lower(trim(coalesce(person.payload->>'groupe', ''))) = lower(trim(target_group)))
      and not exists (
        select 1
        from public.app_sync_records report
        where report.assembly_id = target_assembly_id
          and report.database_name = 'ProclamateursDB'
          and report.store_name = 'detailPredication'
          and report.deleted_at is null
          and report.payload->>'month' = target_month
          and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
      )
  loop
    perform public.write_assembly_inbox_message(
      target_assembly_id,
      member_row.user_id,
      'rappel_rapport',
      format('Rappel : rapport de %s attendu', public.assembly_report_month_label(target_month)),
      case when caller_is_group_manager then
        'Votre responsable ou son adjoint vous rappelle courtoisement de transmettre votre rapport. ' ||
        public.assembly_report_reminder_text(target_assembly_id, member_row.proclamateur_id, target_month)
      else
        'Le secrétariat vous rappelle courtoisement de transmettre votre rapport. ' ||
        public.assembly_report_reminder_text(target_assembly_id, member_row.proclamateur_id, target_month)
      end,
      target_month,
      'report-reminder:' || target_month || ':manual:' || member_row.proclamateur_id,
      jsonb_build_object('proclamateurId', member_row.proclamateur_id, 'groupe', member_row.group_name)
    );
    proclamation_count := proclamation_count + 1;
  end loop;

  for group_row in
    select distinct leaders.payload->>'group' as group_name
    from public.app_sync_records leaders
    where leaders.assembly_id = target_assembly_id
      and leaders.database_name = 'ProclamateursDB'
      and leaders.store_name = 'groupLeaders'
      and leaders.deleted_at is null
      and (caller_is_group_manager or nullif(trim(target_group), '') is null
        or lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(target_group)))
      and exists (
        select 1
        from public.app_sync_records person
        where person.assembly_id = target_assembly_id
          and person.database_name = 'ProclamateursDB'
          and person.store_name = 'proclamateurs'
          and person.deleted_at is null
          and lower(trim(coalesce(person.payload->>'groupe', ''))) = lower(trim(leaders.payload->>'group'))
          and not exists (
            select 1
            from public.app_sync_records report
            where report.assembly_id = target_assembly_id
              and report.database_name = 'ProclamateursDB'
              and report.store_name = 'detailPredication'
              and report.deleted_at is null
              and report.payload->>'month' = target_month
              and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
          )
      )
  loop
    perform public.refresh_assembly_group_report_message(target_assembly_id, target_month, group_row.group_name);
    for manager_row in
      select distinct membership.user_id
      from public.app_sync_records leaders
      join public.assembly_memberships membership
        on membership.assembly_id = target_assembly_id
        and membership.proclamateur_id in (
          nullif(leaders.payload->>'leaderId', ''),
          nullif(leaders.payload->>'adjointId', '')
        )
      where leaders.assembly_id = target_assembly_id
        and leaders.database_name = 'ProclamateursDB'
        and leaders.store_name = 'groupLeaders'
        and leaders.deleted_at is null
        and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(group_row.group_name))
    loop
      perform public.write_assembly_inbox_message(
        target_assembly_id,
        manager_row.user_id,
        'rappel_rapport',
        format('Rappel pour votre groupe — %s', group_row.group_name),
        format('%s, nous espérons que vous vous portez bien, ainsi que votre famille. Des rapports de prédication pour %s (%s) sont encore attendus. Consultez le bilan de votre groupe dans la boîte de messagerie. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.', public.assembly_report_greeting(), group_row.group_name, public.assembly_report_month_label(target_month)),
        target_month,
        'manager-report-reminder:' || target_month || ':' || lower(trim(group_row.group_name)),
        jsonb_build_object('groupe', group_row.group_name)
      );
      manager_count := manager_count + 1;
    end loop;
  end loop;

  return jsonb_build_object('proclamateurs', proclamation_count, 'responsables', manager_count);
end;
$$;

revoke all on function public.send_assembly_report_reminders(text, text, text) from public;
grant execute on function public.send_assembly_report_reminders(text, text, text) to authenticated;

create or replace function public.handle_assembly_report_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  report_month text;
  person_id text;
  person_payload jsonb;
  group_name text;
  member_name text;
  member_user_id uuid;
  courses_count integer;
  manager record;
  report_recipient record;
begin
  if new.database_name <> 'ProclamateursDB'
    or new.store_name <> 'detailPredication' then
    return new;
  end if;

  report_month := coalesce(new.payload->>'month', substring(new.record_id from '^([0-9]{4}-[0-9]{2})_'));
  person_id := coalesce(nullif(new.payload->>'proclamateurId', ''), substring(new.record_id from '^[^_]+_(.*)$'));
  if report_month !~ '^[0-9]{4}-[0-9]{2}$' or coalesce(person_id, '') = '' then return new; end if;

  select person.payload
  into person_payload
  from public.app_sync_records person
  where person.assembly_id = new.assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = person_id
    and person.deleted_at is null
  limit 1;

  group_name := coalesce(nullif(trim(new.payload->>'groupe'), ''), nullif(trim(person_payload->>'groupe'), ''));
  if new.deleted_at is not null then
    update public.assembly_inbox_messages message
    set read_at = now(), updated_at = now()
    where message.assembly_id = new.assembly_id
      and message.reference_month = report_month
      and message.dedupe_key in (
        'report-reminder:' || report_month || ':before-month-end:' || person_id,
        'report-reminder:' || report_month || ':after-month:' || person_id,
        'report-reminder:' || report_month || ':after-month-5:' || person_id,
        'report-reminder:' || report_month || ':after-month-10:' || person_id,
        'report-reminder:' || report_month || ':manual:' || person_id
      );
    delete from public.assembly_inbox_messages message
    where message.assembly_id = new.assembly_id
      and message.reference_month = report_month
      and message.dedupe_key = 'report-response:' || report_month || ':' || person_id;
    if group_name is not null then
      perform public.refresh_assembly_group_report_message(new.assembly_id, report_month, group_name);
    end if;
    return new;
  end if;

  member_name := coalesce(
    nullif(trim(new.payload->>'nom'), ''),
    nullif(trim(concat_ws(' ', person_payload->>'nom', person_payload->>'postnom', person_payload->>'prenom')), ''),
    person_id
  );

  select membership.user_id
  into member_user_id
  from public.assembly_memberships membership
  where membership.assembly_id = new.assembly_id
    and membership.proclamateur_id = person_id
  limit 1;

  if member_user_id is not null then
    perform public.write_assembly_inbox_message(
      new.assembly_id,
      member_user_id,
      'rapport_personnel',
      format('Votre rapport de prédication — %s', public.assembly_report_month_label(report_month)),
      format(
        'Votre rapport de %s est enregistré.%s Cours / études bibliques : %s. Heures : %s.',
        public.assembly_report_month_label(report_month),
        case when coalesce(new.payload->>'aprecher', 'no') = 'yes' then ' Vous avez participé à la prédication.' else '' end,
        coalesce(new.payload->>'coursBiblique', '0'),
        coalesce(new.payload->>'heures', '0')
      ),
      report_month,
      'personal-report:' || report_month || ':' || person_id,
      jsonb_build_object(
        'proclamateurId', person_id,
        'coursBiblique', coalesce(new.payload->>'coursBiblique', '0'),
        'heures', coalesce(new.payload->>'heures', '0'),
        'etudesBibliques', coalesce(new.payload->>'etudesBibliques', '0')
      )
    );
  end if;

  update public.assembly_inbox_messages message
  set read_at = now(), updated_at = now()
  where message.assembly_id = new.assembly_id
    and message.reference_month = report_month
    and message.category = 'rappel_rapport'
    and message.dedupe_key in (
      'report-reminder:' || report_month || ':before-month-end:' || person_id,
      'report-reminder:' || report_month || ':after-month:' || person_id,
      'report-reminder:' || report_month || ':after-month-5:' || person_id,
      'report-reminder:' || report_month || ':after-month-10:' || person_id,
      'report-reminder:' || report_month || ':manual:' || person_id
    );

  for report_recipient in
    select distinct membership.user_id
    from public.assembly_memberships membership
    where membership.assembly_id = new.assembly_id
      and (
        membership.role = 'secretaire'
        or membership.proclamateur_id in (
          select nullif(leaders.payload->>'leaderId', '')
          from public.app_sync_records leaders
          where leaders.assembly_id = new.assembly_id
            and leaders.database_name = 'ProclamateursDB'
            and leaders.store_name = 'groupLeaders'
            and leaders.deleted_at is null
            and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(coalesce(group_name, '')))
          union
          select nullif(leaders.payload->>'adjointId', '')
          from public.app_sync_records leaders
          where leaders.assembly_id = new.assembly_id
            and leaders.database_name = 'ProclamateursDB'
            and leaders.store_name = 'groupLeaders'
            and leaders.deleted_at is null
            and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(coalesce(group_name, '')))
        )
      )
  loop
    perform public.write_assembly_inbox_message(
      new.assembly_id,
      report_recipient.user_id,
      'rapport_recu',
      format('Rapport reçu — %s', member_name),
      format(
        'Rapport de prédication de %s reçu pour %s.%sGroupe : %s. Participation : %s. Cours / études bibliques : %s. Heures : %s.',
        member_name,
        public.assembly_report_month_label(report_month),
        E'\n',
        coalesce(group_name, 'Non renseigné'),
        case when coalesce(new.payload->>'aprecher', 'no') = 'yes' then 'a prêché' else 'n’a pas prêché' end,
        coalesce(new.payload->>'coursBiblique', '0'),
        coalesce(new.payload->>'heures', '0')
      ),
      report_month,
      'report-response:' || report_month || ':' || person_id,
      jsonb_build_object(
        'proclamateurId', person_id,
        'groupe', group_name,
        'heures', coalesce(new.payload->>'heures', '0'),
        'coursBiblique', coalesce(new.payload->>'coursBiblique', '0'),
        'etudesBibliques', coalesce(new.payload->>'etudesBibliques', '0')
      )
    );
  end loop;

  if group_name is not null then
    perform public.refresh_assembly_group_report_message(new.assembly_id, report_month, group_name);
  end if;

  courses_count := case
    when coalesce(new.payload->>'coursBiblique', '') ~ '^[0-9]+$'
      then (new.payload->>'coursBiblique')::integer
    else 0
  end;

  if group_name is not null and courses_count = 0 then
    for manager in
      select distinct membership.user_id
      from public.app_sync_records leaders
      join public.assembly_memberships membership
        on membership.assembly_id = new.assembly_id
        and membership.proclamateur_id in (
          nullif(leaders.payload->>'leaderId', ''),
          nullif(leaders.payload->>'adjointId', '')
        )
      where leaders.assembly_id = new.assembly_id
        and leaders.database_name = 'ProclamateursDB'
        and leaders.store_name = 'groupLeaders'
        and leaders.deleted_at is null
        and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(group_name))
    loop
      perform public.write_assembly_inbox_message(
        new.assembly_id,
        manager.user_id,
        'suivi_pastoral',
        format('Accompagnement pastoral à prévoir — %s', member_name),
        format(
          '%s a indiqué 0 cours biblique(s) dans son rapport de %s. Le responsable et son adjoint sont invités à lui rendre une visite pastorale et à l’aider à commencer un cours biblique.',
          member_name,
          public.assembly_report_month_label(report_month)
        ),
        report_month,
        'pastoral-follow-up:' || report_month || ':' || person_id,
        jsonb_build_object('proclamateurId', person_id, 'groupe', group_name, 'resolved', false)
      );
    end loop;
  elsif group_name is not null then
    update public.assembly_inbox_messages message
    set title = format('Suivi biblique actualisé — %s', member_name),
        body = format('%s a indiqué %s cours biblique(s) dans son rapport de %s. Le suivi pastoral lié à ce rapport est actualisé.', member_name, courses_count, public.assembly_report_month_label(report_month)),
        metadata = message.metadata || jsonb_build_object('resolved', true),
        read_at = coalesce(message.read_at, now()),
        updated_at = now()
    where message.assembly_id = new.assembly_id
      and message.category = 'suivi_pastoral'
      and message.reference_month = report_month
      and message.dedupe_key = 'pastoral-follow-up:' || report_month || ':' || person_id;
  end if;

  return new;
end;
$$;

revoke all on function public.handle_assembly_report_sync() from public;
drop trigger if exists assembly_report_sync_notifications on public.app_sync_records;
create trigger assembly_report_sync_notifications
  after insert or update on public.app_sync_records
  for each row execute function public.handle_assembly_report_sync();

create or replace function public.mark_assembly_inbox_message_read(
  target_assembly_id text,
  target_message_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.assembly_inbox_messages
  set read_at = coalesce(read_at, now())
  where assembly_id = target_assembly_id
    and id = target_message_id
    and recipient_user_id = auth.uid();
  return found;
end;
$$;

revoke all on function public.mark_assembly_inbox_message_read(text, bigint) from public;
grant execute on function public.mark_assembly_inbox_message_read(text, bigint) to authenticated;

create or replace function public.get_my_assembly_whatsapp_consent(target_assembly_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  member_id text;
  member_phone text;
  has_phone boolean;
  is_consented boolean;
begin
  select membership.proclamateur_id
  into member_id
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();
  if member_id is null then
    return jsonb_build_object('available', false, 'hasPhone', false, 'consented', false);
  end if;

  select nullif(trim(person.payload->>'telephone'), '')
  into member_phone
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = member_id
    and person.deleted_at is null
  limit 1;

  has_phone := member_phone is not null;
  select coalesce(consent.consented and consent.consented_phone = member_phone, false)
  into is_consented
  from public.assembly_whatsapp_consents consent
  where consent.assembly_id = target_assembly_id
    and consent.proclamateur_id = member_id;

  return jsonb_build_object(
    'available', true,
    'hasPhone', coalesce(has_phone, false),
    'consented', coalesce(is_consented, false)
  );
end;
$$;

revoke all on function public.get_my_assembly_whatsapp_consent(text) from public;
grant execute on function public.get_my_assembly_whatsapp_consent(text) to authenticated;

create or replace function public.set_my_assembly_whatsapp_consent(
  target_assembly_id text,
  target_consented boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  member_id text;
  member_phone text;
  has_phone boolean;
begin
  select membership.proclamateur_id
  into member_id
  from public.assembly_memberships membership
  where membership.assembly_id = target_assembly_id
    and membership.user_id = auth.uid();
  if member_id is null then
    raise exception 'Associez d’abord ce compte à votre fiche de proclamateur';
  end if;

  select nullif(trim(person.payload->>'telephone'), '')
  into member_phone
  from public.app_sync_records person
  where person.assembly_id = target_assembly_id
    and person.database_name = 'ProclamateursDB'
    and person.store_name = 'proclamateurs'
    and person.record_id = member_id
    and person.deleted_at is null
  limit 1;
  has_phone := member_phone is not null;
  if target_consented and not coalesce(has_phone, false) then
    raise exception 'Ajoutez d’abord un numéro de téléphone à votre fiche';
  end if;

  insert into public.assembly_whatsapp_consents (
    assembly_id, proclamateur_id, consented, consented_phone, consented_at, revoked_at, updated_at
  )
  values (
    target_assembly_id,
    member_id,
    target_consented,
    case when target_consented then member_phone else null end,
    case when target_consented then now() else null end,
    case when target_consented then null else now() end,
    now()
  )
  on conflict (assembly_id, proclamateur_id) do update
    set consented = excluded.consented,
        consented_phone = case
          when excluded.consented then excluded.consented_phone
          else assembly_whatsapp_consents.consented_phone
        end,
        consented_at = case
          when excluded.consented then now()
          else assembly_whatsapp_consents.consented_at
        end,
        revoked_at = case when excluded.consented then null else now() end,
        updated_at = now();
  return jsonb_build_object('consented', target_consented);
end;
$$;

revoke all on function public.set_my_assembly_whatsapp_consent(text, boolean) from public;
grant execute on function public.set_my_assembly_whatsapp_consent(text, boolean) to authenticated;

drop function if exists public.claim_assembly_whatsapp_delivery(text, text, text);

create or replace function public.claim_assembly_whatsapp_delivery(
  target_assembly_id text,
  target_proclamateur_id text,
  target_month text,
  target_reminder_kind text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed_id text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role requis';
  end if;
  if target_reminder_kind not in ('before-month-end', 'after-month-5', 'after-month-10', 'secretary', 'secretary-follow-up', 'manager') then
    raise exception 'Type de rappel WhatsApp invalide';
  end if;

  insert into public.assembly_whatsapp_deliveries (
    assembly_id, proclamateur_id, report_month, reminder_kind, status, created_at, updated_at
  )
  values (target_assembly_id, target_proclamateur_id, target_month, target_reminder_kind, 'queued', now(), now())
  on conflict (assembly_id, proclamateur_id, report_month, reminder_kind) do update
    set status = 'queued', error_message = null, updated_at = now()
    where assembly_whatsapp_deliveries.status = 'failed'
  returning proclamateur_id into claimed_id;

  return claimed_id is not null;
end;
$$;

revoke all on function public.claim_assembly_whatsapp_delivery(text, text, text, text) from public;
grant execute on function public.claim_assembly_whatsapp_delivery(text, text, text, text) to service_role;

drop function if exists public.finish_assembly_whatsapp_delivery(text, text, text, text, text, text);
create or replace function public.finish_assembly_whatsapp_delivery(
  target_assembly_id text,
  target_proclamateur_id text,
  target_month text,
  target_reminder_kind text,
  target_status text,
  target_provider_message_id text default null,
  target_error_message text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role requis';
  end if;
  if target_reminder_kind not in ('before-month-end', 'after-month-5', 'after-month-10', 'secretary', 'secretary-follow-up', 'manager') then
    raise exception 'Type de rappel WhatsApp invalide';
  end if;
  if target_status not in ('sent', 'failed') then
    raise exception 'État de livraison invalide';
  end if;

  update public.assembly_whatsapp_deliveries
  set status = target_status,
      provider_message_id = target_provider_message_id,
      error_message = left(target_error_message, 500),
      updated_at = now()
  where assembly_id = target_assembly_id
    and proclamateur_id = target_proclamateur_id
    and report_month = target_month
    and reminder_kind = target_reminder_kind;
end;
$$;

revoke all on function public.finish_assembly_whatsapp_delivery(text, text, text, text, text, text, text) from public;
grant execute on function public.finish_assembly_whatsapp_delivery(text, text, text, text, text, text, text) to service_role;

drop function if exists public.manage_assembly_user(text, text, text[]);

create or replace function public.manage_assembly_user(
  target_email text,
  target_role text,
  target_pages text[],
  target_proclamateur_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  target_user_id uuid;
begin
  select role into caller_role
  from public.assembly_memberships
  where assembly_id = '55954' and user_id = auth.uid();

  if caller_role not in ('owner', 'coordinateur', 'secretaire') then
    raise exception 'Accès administrateur requis';
  end if;

  if target_role not in ('coordinateur', 'secretaire', 'proclamateur', 'assistant', 'ancien', 'responsable_predication') then
    raise exception 'Rôle invalide';
  end if;

  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(target_email));

  if target_user_id is null then
    raise exception 'Utilisateur introuvable. Il doit d’abord créer son compte.';
  end if;

  insert into public.assembly_memberships (assembly_id, user_id, role, proclamateur_id)
  values ('55954', target_user_id, target_role, nullif(trim(target_proclamateur_id), ''))
  on conflict (assembly_id, user_id) do update
    set role = excluded.role, proclamateur_id = excluded.proclamateur_id;

  delete from public.assembly_page_permissions
  where assembly_id = '55954' and user_id = target_user_id;

  insert into public.assembly_page_permissions (assembly_id, user_id, page_key)
  select '55954', target_user_id, page_key
  from unnest(coalesce(target_pages, array[]::text[])) as page_key;

  update public.assembly_access_requests
  set status = 'approved', updated_at = now()
  where assembly_id = '55954' and user_id = target_user_id;

  return jsonb_build_object('user_id', target_user_id, 'role', target_role, 'pages', target_pages);
end;
$$;

revoke all on function public.manage_assembly_user(text, text, text[], text) from public;
grant execute on function public.manage_assembly_user(text, text, text[], text) to authenticated;

create or replace function public.request_assembly_access(target_assembly_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.assembly_access_requests (assembly_id, user_id, status, updated_at)
  values (target_assembly_id, auth.uid(), 'pending', now())
  on conflict (assembly_id, user_id) do update set status = 'pending', updated_at = now();
  return jsonb_build_object('status', 'pending');
end;
$$;

revoke all on function public.request_assembly_access(text) from public;
grant execute on function public.request_assembly_access(text) to authenticated;

create or replace function public.list_assembly_access(target_assembly_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  result jsonb;
begin
  select role into caller_role from public.assembly_memberships
  where assembly_id = target_assembly_id and user_id = auth.uid();
  if caller_role not in ('owner', 'coordinateur', 'secretaire') then
    raise exception 'Accès administrateur requis';
  end if;
  select jsonb_build_object(
    'requests', coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', request.user_id, 'email', lower(coalesce(account.email, '')),
      'name', trim(coalesce(account.raw_user_meta_data->>'prenom', '') || ' ' || coalesce(account.raw_user_meta_data->>'nom', '')),
      'status', request.status, 'created_at', request.created_at
    ) order by request.created_at desc)
    from public.assembly_access_requests request join auth.users account on account.id = request.user_id
    where request.assembly_id = target_assembly_id and request.status = 'pending'), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', membership.user_id, 'email', lower(coalesce(account.email, '')),
      'name', trim(coalesce(account.raw_user_meta_data->>'prenom', '') || ' ' || coalesce(account.raw_user_meta_data->>'nom', '')),
      'role', membership.role,
      'proclamateur_id', membership.proclamateur_id,
      'pages', coalesce((select jsonb_agg(permission.page_key order by permission.page_key) from public.assembly_page_permissions permission where permission.assembly_id = target_assembly_id and permission.user_id = membership.user_id), '[]'::jsonb)
    ) order by account.email)
    from public.assembly_memberships membership join auth.users account on account.id = membership.user_id
    where membership.assembly_id = target_assembly_id), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_assembly_access(text) from public;
grant execute on function public.list_assembly_access(text) to authenticated;

create or replace function public.revoke_assembly_user(target_assembly_id text, target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare caller_role text;
begin
  select role into caller_role from public.assembly_memberships where assembly_id = target_assembly_id and user_id = auth.uid();
  if caller_role not in ('owner', 'coordinateur', 'secretaire') then raise exception 'Accès administrateur requis'; end if;
  if target_user_id = auth.uid() then raise exception 'Vous ne pouvez pas retirer votre propre accès'; end if;
  delete from public.assembly_page_permissions where assembly_id = target_assembly_id and user_id = target_user_id;
  delete from public.assembly_memberships where assembly_id = target_assembly_id and user_id = target_user_id;
  update public.assembly_access_requests set status = 'rejected', updated_at = now() where assembly_id = target_assembly_id and user_id = target_user_id;
  return jsonb_build_object('revoked', true);
end;
$$;

revoke all on function public.revoke_assembly_user(text, uuid) from public;
grant execute on function public.revoke_assembly_user(text, uuid) to authenticated;

create or replace function public.refresh_assembly_report_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  local_today date := (now() at time zone 'Africa/Kinshasa')::date;
  report_month text;
  reminder_kind text;
  assembly_row record;
  member_row record;
  group_row record;
  pastoral_row record;
  manager_row record;
begin
  if extract(day from local_today) = 3 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'manager-summary';
  elsif extract(day from local_today) = 4 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'manager-follow-up';
  elsif extract(day from local_today) = 5 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'after-month-5';
  elsif extract(day from local_today) = 10 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'after-month-10';
  elsif local_today = (date_trunc('month', local_today::timestamp) + interval '1 month')::date - 3 then
    report_month := to_char(local_today, 'YYYY-MM');
    reminder_kind := 'before-month-end';
  else
    return;
  end if;

  for assembly_row in
    select distinct membership.assembly_id
    from public.assembly_memberships membership
  loop
    for member_row in
      select
        membership.user_id,
        person.record_id as proclamateur_id,
        coalesce(
          nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
          person.record_id
        ) as member_name,
        person.payload->>'sexe' as sex
      from public.app_sync_records person
      join public.assembly_memberships membership
        on membership.assembly_id = assembly_row.assembly_id
        and membership.proclamateur_id = person.record_id
      where person.assembly_id = assembly_row.assembly_id
        and person.database_name = 'ProclamateursDB'
        and person.store_name = 'proclamateurs'
        and person.deleted_at is null
        and reminder_kind in ('before-month-end', 'after-month-5', 'after-month-10')
        and (
          reminder_kind = 'before-month-end'
          or not exists (
          select 1
          from public.app_sync_records report
          where report.assembly_id = assembly_row.assembly_id
            and report.database_name = 'ProclamateursDB'
            and report.store_name = 'detailPredication'
            and report.deleted_at is null
            and report.payload->>'month' = report_month
            and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
          )
        )
    loop
      perform public.write_assembly_inbox_message(
        assembly_row.assembly_id,
        member_row.user_id,
        'rappel_rapport',
        case reminder_kind
          when 'before-month-end' then format('Préparez votre rapport de %s', public.assembly_report_month_label(report_month))
          when 'after-month-5' then format('Rappel du 5 : rapport de %s attendu', public.assembly_report_month_label(report_month))
          when 'after-month-10' then format('Dernier rappel automatique : rapport de %s attendu', public.assembly_report_month_label(report_month))
          else format('Rappel : rapport de %s attendu', public.assembly_report_month_label(report_month))
        end,
        case reminder_kind
          when 'before-month-end' then format(
            '%s%s %s, nous espérons que vous vous portez bien, ainsi que votre famille. La fin du mois approche. Pensez à préparer votre rapport d’activité de prédication de %s. Vous pourrez le transmettre dès que le mois sera terminé, de préférence à votre responsable ou à son adjoint. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
            public.assembly_report_greeting(),
            case upper(trim(coalesce(member_row.sex, '')))
              when 'F' then ', Très chère Sr'
              when 'FEMME' then ', Très chère Sr'
              when 'FÉMININ' then ', Très chère Sr'
              when 'M' then ', Très cher Fr'
              when 'HOMME' then ', Très cher Fr'
              when 'MASCULIN' then ', Très cher Fr'
              else ''
            end,
            member_row.member_name,
            public.assembly_report_month_label(report_month)
          )
          when 'after-month-5' then
            public.assembly_report_reminder_text(
              assembly_row.assembly_id,
              member_row.proclamateur_id,
              report_month
            )
          else
            public.assembly_report_reminder_text(
              assembly_row.assembly_id,
              member_row.proclamateur_id,
              report_month
            )
        end,
        report_month,
        'report-reminder:' || report_month || ':' || reminder_kind || ':' || member_row.proclamateur_id,
        jsonb_build_object('proclamateurId', member_row.proclamateur_id, 'reminderKind', reminder_kind)
      );
    end loop;

    if reminder_kind in ('manager-summary', 'manager-follow-up') then
      for group_row in
      select distinct leaders.payload->>'group' as group_name
      from public.app_sync_records leaders
      where leaders.assembly_id = assembly_row.assembly_id
        and leaders.database_name = 'ProclamateursDB'
        and leaders.store_name = 'groupLeaders'
        and leaders.deleted_at is null
        and nullif(trim(leaders.payload->>'group'), '') is not null
    loop
      if reminder_kind = 'manager-summary' then
        perform public.refresh_assembly_group_report_message(
          assembly_row.assembly_id,
          report_month,
          group_row.group_name
        );
      elsif not exists (
        select 1
        from public.assembly_report_reminder_actions action
        where action.assembly_id = assembly_row.assembly_id
          and action.report_month = report_month
          and action.group_key = lower(trim(group_row.group_name))
      ) and exists (
        select 1
        from public.app_sync_records person
        where person.assembly_id = assembly_row.assembly_id
          and person.database_name = 'ProclamateursDB'
          and person.store_name = 'proclamateurs'
          and person.deleted_at is null
          and lower(trim(coalesce(person.payload->>'groupe', ''))) = lower(trim(group_row.group_name))
          and not exists (
            select 1
            from public.app_sync_records report
            where report.assembly_id = assembly_row.assembly_id
              and report.database_name = 'ProclamateursDB'
              and report.store_name = 'detailPredication'
              and report.deleted_at is null
              and report.payload->>'month' = report_month
              and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
          )
      ) then
        for manager_row in
          select distinct membership.user_id
          from public.app_sync_records leaders
          join public.assembly_memberships membership
            on membership.assembly_id = assembly_row.assembly_id
            and membership.proclamateur_id in (
              nullif(leaders.payload->>'leaderId', ''),
              nullif(leaders.payload->>'adjointId', '')
            )
          where leaders.assembly_id = assembly_row.assembly_id
            and leaders.database_name = 'ProclamateursDB'
            and leaders.store_name = 'groupLeaders'
            and leaders.deleted_at is null
            and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(group_row.group_name))
        loop
          perform public.write_assembly_inbox_message(
            assembly_row.assembly_id,
            manager_row.user_id,
            'rappel_rapport',
            format('Rappel aux responsables — groupe %s', group_row.group_name),
            format(
              '%s, nous espérons que vous vous portez bien, ainsi que votre famille. Le bilan du %s indiquait des rapports encore attendus dans votre groupe (%s). Consultez la liste ci-dessous et, si ce n’est pas déjà fait, merci de contacter courtoisement les proclamateurs concernés et de leur rappeler de transmettre leur rapport. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
              public.assembly_report_greeting(),
              public.assembly_report_month_label(report_month),
              group_row.group_name
            ),
            report_month,
            'manager-follow-up:' || report_month || ':' || lower(trim(group_row.group_name)),
            jsonb_build_object(
              'groupe', group_row.group_name,
              'reminderKind', reminder_kind,
              'pendingMembers', (
                select coalesce(
                  jsonb_agg(jsonb_build_object('name', pending.member_name) order by lower(pending.member_name), pending.member_name),
                  '[]'::jsonb
                )
                from (
                  select coalesce(
                    nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
                    person.record_id
                  ) as member_name
                  from public.app_sync_records person
                  where person.assembly_id = assembly_row.assembly_id
                    and person.database_name = 'ProclamateursDB'
                    and person.store_name = 'proclamateurs'
                    and person.deleted_at is null
                    and lower(trim(coalesce(person.payload->>'groupe', ''))) = lower(trim(group_row.group_name))
                    and not exists (
                      select 1
                      from public.app_sync_records report
                      where report.assembly_id = assembly_row.assembly_id
                        and report.database_name = 'ProclamateursDB'
                        and report.store_name = 'detailPredication'
                        and report.deleted_at is null
                        and report.payload->>'month' = report_month
                        and coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) = person.record_id
                    )
                ) pending
              )
            )
          );
        end loop;
      end if;
      end loop;
    end if;

    if reminder_kind = 'after-month-5' then
      for pastoral_row in
        select
          coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$')) as proclamateur_id,
          coalesce(
            nullif(trim(report.payload->>'nom'), ''),
            nullif(trim(concat_ws(' ', person.payload->>'nom', person.payload->>'postnom', person.payload->>'prenom')), ''),
            person.record_id
          ) as member_name,
          coalesce(nullif(trim(report.payload->>'groupe'), ''), person.payload->>'groupe') as group_name
        from public.app_sync_records report
        join public.app_sync_records person
          on person.assembly_id = report.assembly_id
          and person.database_name = 'ProclamateursDB'
          and person.store_name = 'proclamateurs'
          and person.record_id = coalesce(nullif(report.payload->>'proclamateurId', ''), substring(report.record_id from '^[^_]+_(.*)$'))
          and person.deleted_at is null
        where report.assembly_id = assembly_row.assembly_id
          and report.database_name = 'ProclamateursDB'
          and report.store_name = 'detailPredication'
          and report.deleted_at is null
          and report.payload->>'month' = report_month
          and coalesce(report.payload->>'coursBiblique', '0') = '0'
      loop
        for manager_row in
          select distinct membership.user_id
          from public.app_sync_records leaders
          join public.assembly_memberships membership
            on membership.assembly_id = assembly_row.assembly_id
            and membership.proclamateur_id in (
              nullif(leaders.payload->>'leaderId', ''),
              nullif(leaders.payload->>'adjointId', '')
            )
          where leaders.assembly_id = assembly_row.assembly_id
            and leaders.database_name = 'ProclamateursDB'
            and leaders.store_name = 'groupLeaders'
            and leaders.deleted_at is null
            and lower(trim(coalesce(leaders.payload->>'group', ''))) = lower(trim(coalesce(pastoral_row.group_name, '')))
        loop
          perform public.write_assembly_inbox_message(
            assembly_row.assembly_id,
            manager_row.user_id,
            'suivi_pastoral',
            format('Rappel de visite pastorale — %s', pastoral_row.member_name),
            format(
              '%s, nous espérons que vous vous portez bien, ainsi que votre famille. %s a déclaré 0 cours biblique(s) pour %s. Le responsable et son adjoint sont invités à organiser une visite pastorale pour l’aider à commencer un cours biblique. Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège.',
              public.assembly_report_greeting(),
              pastoral_row.member_name,
              public.assembly_report_month_label(report_month)
            ),
            report_month,
            'pastoral-follow-up:' || report_month || ':' || pastoral_row.proclamateur_id,
            jsonb_build_object('proclamateurId', pastoral_row.proclamateur_id, 'groupe', pastoral_row.group_name, 'resolved', false)
          );
        end loop;
      end loop;
    end if;
  end loop;
end;
$$;

revoke all on function public.refresh_assembly_report_reminders() from public;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Runs daily at 08:00 in Kinshasa (07:00 UTC); reminders are sent on days 3, 4, 5, 10 and two days before month-end.
do $$
declare
  existing_job record;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'assembly-report-reminders'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
  perform cron.schedule(
    'assembly-report-reminders',
    '0 7 * * *',
    'select public.refresh_assembly_report_reminders();'
  );
end;
$$;

create or replace function public.enqueue_assembly_whatsapp_report_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  local_today date := (now() at time zone 'Africa/Kinshasa')::date;
  report_month text;
  reminder_kind text;
  supabase_url text;
  service_role_key text;
  pg_net_schema text;
  assembly_row record;
begin
  if extract(day from local_today) = 5 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'after-month-5';
  elsif extract(day from local_today) = 10 then
    report_month := to_char(local_today - interval '1 month', 'YYYY-MM');
    reminder_kind := 'after-month-10';
  elsif local_today = (date_trunc('month', local_today::timestamp) + interval '1 month')::date - 3 then
    report_month := to_char(local_today, 'YYYY-MM');
    reminder_kind := 'before-month-end';
  else
    return;
  end if;

  select secret.decrypted_secret into supabase_url
  from vault.decrypted_secrets secret
  where secret.name = 'assembly_supabase_url'
  limit 1;
  select secret.decrypted_secret into service_role_key
  from vault.decrypted_secrets secret
  where secret.name = 'assembly_supabase_service_role_key'
  limit 1;
  if coalesce(trim(supabase_url), '') = '' or coalesce(trim(service_role_key), '') = '' then
    raise exception 'Ajoutez assembly_supabase_url et assembly_supabase_service_role_key dans Supabase Vault pour activer les envois WhatsApp planifiés';
  end if;

  select namespace.nspname
  into pg_net_schema
  from pg_extension ext
  join pg_namespace namespace on namespace.oid = ext.extnamespace
  where ext.extname = 'pg_net';
  if pg_net_schema is null then
    raise exception 'L’extension pg_net doit être activée pour les rappels WhatsApp planifiés';
  end if;

  for assembly_row in
    select distinct membership.assembly_id
    from public.assembly_memberships membership
  loop
    execute format(
      'select %I.http_post(url := $1, headers := $2, body := $3)',
      pg_net_schema
    )
    using
      rtrim(supabase_url, '/') || '/functions/v1/send-whatsapp-report-reminders',
      jsonb_build_object(
        'Authorization', 'Bearer ' || service_role_key,
        'Content-Type', 'application/json'
      ),
      jsonb_build_object(
        'assemblyId', assembly_row.assembly_id,
        'month', report_month,
        'reminderKind', reminder_kind
      );
  end loop;
end;
$$;

revoke all on function public.enqueue_assembly_whatsapp_report_reminders() from public, anon, authenticated;

do $$
declare
  existing_job record;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'assembly-report-whatsapp-reminders'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
  perform cron.schedule(
    'assembly-report-whatsapp-reminders',
    '0 7 * * *',
    'select public.enqueue_assembly_whatsapp_report_reminders();'
  );
end;
$$;

do $$ 
begin
  alter publication supabase_realtime add table public.assembly_inbox_messages;
exception
  when duplicate_object then null;
end;
$$;

notify pgrst, 'reload schema';
