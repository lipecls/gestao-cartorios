-- =====================================================================
-- Gestão de Cartórios — esquema do banco (Supabase / Postgres)
-- Rode este arquivo inteiro no SQL Editor do Supabase, uma única vez.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tabelas ----------
create table if not exists public.serventias (
  id uuid primary key default gen_random_uuid(),
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.membros (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  papel text not null check (papel in ('admin','assessoria','cartorio')),
  serventia_id uuid references public.serventias(id) on delete cascade,
  rotulo text default '',
  created_at timestamptz not null default now(),
  check (papel <> 'cartorio' or serventia_id is not null)
);

-- Tabelas de dados por serventia: id + serventia + documento JSON
do $$
declare t text;
begin
  foreach t in array array['lancamentos','funcionarios','minutas'] loop
    execute format('create table if not exists public.%I (
      id uuid primary key default gen_random_uuid(),
      serventia_id uuid not null references public.serventias(id) on delete cascade,
      data jsonb not null default ''{}''::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now())', t);
    execute format('create index if not exists %I on public.%I (serventia_id)', t||'_serv_idx', t);
  end loop;
  -- pqta e balancetes usam id composto "<serventia>__<item|competência>"
  foreach t in array array['pqta','balancetes'] loop
    execute format('create table if not exists public.%I (
      id text primary key,
      serventia_id uuid not null references public.serventias(id) on delete cascade,
      data jsonb not null default ''{}''::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now())', t);
    execute format('create index if not exists %I on public.%I (serventia_id)', t||'_serv_idx', t);
  end loop;
end $$;

create table if not exists public.config (
  id text primary key,
  data jsonb not null default '{}'::jsonb
);

-- ---------- Funções de papel (usadas pelas regras) ----------
create or replace function public.meu_papel() returns text
language sql stable security definer set search_path = public as $$
  select papel from public.membros where user_id = auth.uid()
$$;

create or replace function public.minha_serventia() returns uuid
language sql stable security definer set search_path = public as $$
  select serventia_id from public.membros where user_id = auth.uid()
$$;

create or replace function public.is_assessoria() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select papel in ('admin','assessoria') from public.membros where user_id = auth.uid()), false)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select papel = 'admin' from public.membros where user_id = auth.uid()), false)
$$;

-- Vincula um login (já criado em Authentication → Users) a um papel/serventia
create or replace function public.vincular_membro(p_email text, p_papel text, p_serventia uuid, p_rotulo text)
returns public.membros
language plpgsql security definer set search_path = public, auth as $$
declare v_uid uuid; v_row public.membros;
begin
  if not public.is_admin() then raise exception 'apenas administradores'; end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then raise exception 'usuário não encontrado'; end if;
  insert into public.membros (user_id, email, papel, serventia_id, rotulo)
  values (v_uid, lower(p_email), p_papel, case when p_papel = 'cartorio' then p_serventia else null end, coalesce(p_rotulo,''))
  on conflict (user_id) do update set papel = excluded.papel, serventia_id = excluded.serventia_id, rotulo = excluded.rotulo, email = excluded.email
  returning * into v_row;
  return v_row;
end $$;
revoke all on function public.vincular_membro(text,text,uuid,text) from public, anon;
grant execute on function public.vincular_membro(text,text,uuid,text) to authenticated;

-- ---------- Regras de acesso (RLS) ----------
alter table public.serventias enable row level security;
alter table public.membros    enable row level security;
alter table public.config     enable row level security;

drop policy if exists serv_select on public.serventias;
create policy serv_select on public.serventias for select to authenticated
  using (public.is_assessoria() or id = public.minha_serventia());
drop policy if exists serv_write on public.serventias;
create policy serv_write on public.serventias for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists memb_select on public.membros;
create policy memb_select on public.membros for select to authenticated
  using (public.is_assessoria() or user_id = auth.uid());
drop policy if exists memb_write on public.membros;
create policy memb_write on public.membros for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists cfg_select on public.config;
create policy cfg_select on public.config for select to authenticated using (public.meu_papel() is not null);
drop policy if exists cfg_write on public.config;
create policy cfg_write on public.config for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$
declare t text;
begin
  foreach t in array array['lancamentos','funcionarios','minutas','pqta','balancetes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_acesso', t);
    execute format('create policy %I on public.%I for all to authenticated
      using (public.is_assessoria() or serventia_id = public.minha_serventia())
      with check (public.is_assessoria() or serventia_id = public.minha_serventia())', t||'_acesso', t);
  end loop;
end $$;

-- ---------- Tempo real ----------
do $$
declare t text;
begin
  foreach t in array array['serventias','membros','lancamentos','funcionarios','pqta','balancetes','minutas','config'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
alter table public.membros replica identity full;

-- =====================================================================
-- PRIMEIRO ADMINISTRADOR
-- 1) Crie seu login em Authentication → Users → Add user (e-mail + senha).
-- 2) Troque o e-mail abaixo pelo seu e rode só este bloco:
--
-- insert into public.membros (user_id, email, papel)
-- select id, lower(email), 'admin' from auth.users where lower(email) = lower('SEU-EMAIL@exemplo.com')
-- on conflict (user_id) do update set papel = 'admin';
-- =====================================================================
