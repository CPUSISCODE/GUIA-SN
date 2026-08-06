-- Administração do GUIA-SN.
--
-- A condição de admin NÃO fica em public.profiles de propósito: os usuários têm
-- policy de update no próprio perfil, então uma coluna "admin" ali seria
-- auto-atribuível — qualquer um viraria admin. Ela vive numa tabela à parte, sem
-- nenhuma policy de escrita para o cliente; promover e rebaixar só acontece
-- pelas funções security definer da migration 20260806133659.

create table if not exists public.admins (
  id         uuid primary key references auth.users (id) on delete cascade,
  criado_em  timestamptz not null default now(),
  criado_por uuid references auth.users (id) on delete set null
);

comment on table public.admins is 'Quem é administrador do GUIA-SN. Escrita só pelas funções promover_admin/rebaixar_admin.';

alter table public.admins enable row level security;

-- security definer para não disparar RLS de novo ao consultar admins de dentro
-- das policies (evita recursão).
-- NOTA: esta função foi movida para o schema private na migration 20260806133806.
create or replace function public.e_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.id = (select auth.uid()));
$$;

drop policy if exists "Admins veem a lista de admins" on public.admins;
create policy "Admins veem a lista de admins"
  on public.admins
  for select
  to authenticated
  using ( public.e_admin() );

-- Campos de controle de acesso, no perfil.
alter table public.profiles add column if not exists aprovado            boolean not null default false;
alter table public.profiles add column if not exists bloqueado           boolean not null default false;
alter table public.profiles add column if not exists limite_dispositivos integer not null default 2 check (limite_dispositivos between 1 and 20);
alter table public.profiles add column if not exists observacao          text;

comment on column public.profiles.aprovado is 'Liberado pelo admin. Sem isso o usuário entra mas não recebe a base fiscal.';
comment on column public.profiles.bloqueado is 'Bloqueio manual do admin, independente da aprovação.';
comment on column public.profiles.limite_dispositivos is 'Quantos dispositivos distintos o usuário pode registrar.';

-- O usuário pode editar o próprio perfil (nome, empresa), mas não pode se
-- aprovar, se desbloquear nem aumentar o próprio limite de dispositivos.
--
-- auth.uid() nulo significa operação do servidor (migration, service_role, job)
-- e não uma requisição de navegador: requisição anônima não passa pela policy de
-- update de profiles, que exige a role authenticated com auth.uid() = id.
create or replace function public.proteger_campos_de_controle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not public.e_admin() then
    if new.aprovado            is distinct from old.aprovado
    or new.bloqueado           is distinct from old.bloqueado
    or new.limite_dispositivos is distinct from old.limite_dispositivos
    or new.observacao          is distinct from old.observacao then
      raise exception 'Apenas administradores podem alterar aprovação, bloqueio, limite de dispositivos ou observação.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_proteger_controle on public.profiles;
create trigger profiles_proteger_controle
  before update on public.profiles
  for each row
  execute function public.proteger_campos_de_controle();

revoke all on function public.e_admin() from public, anon;
revoke all on function public.proteger_campos_de_controle() from public, anon, authenticated;

-- Primeiro admin: a conta do dono. Fica aprovada e sem bloqueio.
insert into public.admins (id)
select u.id from auth.users u where u.email = 'deltaspriggan@gmail.com'
on conflict (id) do nothing;

update public.profiles p
set aprovado = true, bloqueado = false
from auth.users u
where u.id = p.id and u.email = 'deltaspriggan@gmail.com';
