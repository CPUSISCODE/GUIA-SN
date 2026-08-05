-- Tabela de perfis de usuário do GUIA-SN.
-- Cada linha corresponde a um usuário de auth.users e é criada automaticamente
-- pelo trigger on_auth_user_created no momento do cadastro.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text,
  empresa text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil do usuário do GUIA-SN, espelhando auth.users com dados de cadastro (nome e empresa).';

alter table public.profiles enable row level security;

-- Policies: cada usuário autenticado só enxerga e altera o próprio perfil.
-- (select auth.uid()) é avaliado uma única vez por consulta (initplan), evitando
-- reavaliação por linha.

drop policy if exists "Usuários podem ver o próprio perfil" on public.profiles;
create policy "Usuários podem ver o próprio perfil"
  on public.profiles
  for select
  to authenticated
  using ( (select auth.uid()) = id );

drop policy if exists "Usuários podem criar o próprio perfil" on public.profiles;
create policy "Usuários podem criar o próprio perfil"
  on public.profiles
  for insert
  to authenticated
  with check ( (select auth.uid()) = id );

drop policy if exists "Usuários podem atualizar o próprio perfil" on public.profiles;
create policy "Usuários podem atualizar o próprio perfil"
  on public.profiles
  for update
  to authenticated
  using ( (select auth.uid()) = id )
  with check ( (select auth.uid()) = id );

-- Função que mantém updated_at sempre em dia.
create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
  before update on public.profiles
  for each row
  execute function public.handle_updated_at();

-- Cria o perfil automaticamente quando um usuário se cadastra, aproveitando
-- os campos enviados em options.data do signUp (raw_user_meta_data).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nome, empresa)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'nome'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'empresa'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- As funções acima só devem ser executadas pelos triggers. Sem o revoke elas
-- ficam expostas como RPC em /rest/v1/rpc/...
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_updated_at() from public, anon, authenticated;
