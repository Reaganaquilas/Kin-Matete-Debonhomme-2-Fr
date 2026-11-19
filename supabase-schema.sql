-- Schema for offline-first assembly data synchronization.
-- Run this script in Supabase SQL Editor before enabling production sync.

create table if not exists public.assembly_memberships (
  assembly_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'proclamateur' check (role in ('owner', 'coordinateur', 'secretaire', 'proclamateur', 'assistant', 'ancien', 'responsable_predication')),
  created_at timestamptz not null default now(),
  primary key (assembly_id, user_id)
);

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

alter table public.assembly_memberships enable row level security;
alter table public.app_sync_records enable row level security;
alter table public.assembly_page_permissions enable row level security;
alter table public.assembly_access_requests enable row level security;

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

create index if not exists app_sync_records_assembly_idx
  on public.app_sync_records (assembly_id, updated_at);

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
  );
$$;

revoke all on function public.can_access_sync_store(text, text) from public;
grant execute on function public.can_access_sync_store(text, text) to authenticated;

drop policy if exists "members can read assembly records" on public.app_sync_records;
drop policy if exists "members can insert assembly records" on public.app_sync_records;
drop policy if exists "members can update assembly records" on public.app_sync_records;
drop policy if exists "members can read permitted assembly records" on public.app_sync_records;
drop policy if exists "members can insert permitted assembly records" on public.app_sync_records;
drop policy if exists "members can update permitted assembly records" on public.app_sync_records;

create policy "members can read permitted assembly records"
  on public.app_sync_records for select
  using (public.can_access_sync_store(assembly_id, store_name));

create policy "members can insert permitted assembly records"
  on public.app_sync_records for insert
  with check (
    user_id = auth.uid()
    and public.can_access_sync_store(assembly_id, store_name)
  );

create policy "members can update permitted assembly records"
  on public.app_sync_records for update
  using (public.can_access_sync_store(assembly_id, store_name))
  with check (public.can_access_sync_store(assembly_id, store_name));

create or replace function public.manage_assembly_user(
  target_email text,
  target_role text,
  target_pages text[]
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

  insert into public.assembly_memberships (assembly_id, user_id, role)
  values ('55954', target_user_id, target_role)
  on conflict (assembly_id, user_id) do update set role = excluded.role;

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

revoke all on function public.manage_assembly_user(text, text, text[]) from public;
grant execute on function public.manage_assembly_user(text, text, text[]) to authenticated;

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
