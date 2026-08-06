-- Dispositivos por usuário e histórico de acessos.
--
-- Sobre a "região": o navegador não sabe a localização de forma confiável e não
-- há servidor próprio aqui para ler o IP. O que dá para captar sem mentir é o
-- fuso horário do navegador (America/Rio_Branco, America/Sao_Paulo…), que serve
-- de aproximação regional. É informado pelo cliente e, portanto, falsificável —
-- vale como visibilidade operacional, não como prova.

create table if not exists public.dispositivos (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  impressao       text not null,          -- id estável gerado no navegador
  tipo            text not null default 'desconhecido'
                    check (tipo in ('celular','tablet','computador','desconhecido')),
  navegador       text,
  sistema         text,
  fuso            text,                   -- ex.: America/Rio_Branco
  user_agent      text,
  primeiro_acesso timestamptz not null default now(),
  ultimo_acesso   timestamptz not null default now(),
  acessos         integer not null default 1,
  unique (user_id, impressao)
);

comment on table public.dispositivos is 'Dispositivos distintos por usuário. O limite vem de profiles.limite_dispositivos e é aplicado por trigger.';
comment on column public.dispositivos.fuso is 'Fuso do navegador, usado como aproximação de região. Informado pelo cliente.';

create index if not exists dispositivos_user_idx on public.dispositivos (user_id);

create table if not exists public.acessos (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  dispositivo_id uuid references public.dispositivos (id) on delete set null,
  quando         timestamptz not null default now(),
  tipo           text,
  fuso           text
);

comment on table public.acessos is 'Um registro por entrada na ferramenta.';

create index if not exists acessos_user_idx   on public.acessos (user_id, quando desc);
create index if not exists acessos_quando_idx on public.acessos (quando desc);

alter table public.dispositivos enable row level security;
alter table public.acessos      enable row level security;

-- Limite de dispositivos, aplicado no banco: o cliente não consegue contornar
-- registrando um aparelho a mais.
-- NOTA: corrigida na migration 20260806134132 para não barrar reconexão de um
-- aparelho já conhecido.
create or replace function public.checar_limite_dispositivos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limite integer;
  v_atual  integer;
begin
  select p.limite_dispositivos into v_limite
  from public.profiles p where p.id = new.user_id;

  if v_limite is null then v_limite := 2; end if;

  select count(*) into v_atual
  from public.dispositivos d where d.user_id = new.user_id;

  if v_atual >= v_limite then
    raise exception 'Limite de % dispositivo(s) atingido para este usuário.', v_limite
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists dispositivos_limite on public.dispositivos;
create trigger dispositivos_limite
  before insert on public.dispositivos
  for each row
  execute function public.checar_limite_dispositivos();

revoke all on function public.checar_limite_dispositivos() from public, anon, authenticated;

-- Policies: o usuário enxerga e registra os próprios dispositivos e acessos;
-- o admin enxerga tudo e pode remover dispositivos para liberar espaço.

drop policy if exists "Usuário vê os próprios dispositivos" on public.dispositivos;
create policy "Usuário vê os próprios dispositivos"
  on public.dispositivos for select to authenticated
  using ( (select auth.uid()) = user_id or public.e_admin() );

drop policy if exists "Usuário registra o próprio dispositivo" on public.dispositivos;
create policy "Usuário registra o próprio dispositivo"
  on public.dispositivos for insert to authenticated
  with check ( (select auth.uid()) = user_id );

drop policy if exists "Usuário atualiza o próprio dispositivo" on public.dispositivos;
create policy "Usuário atualiza o próprio dispositivo"
  on public.dispositivos for update to authenticated
  using ( (select auth.uid()) = user_id )
  with check ( (select auth.uid()) = user_id );

drop policy if exists "Admin remove dispositivos" on public.dispositivos;
create policy "Admin remove dispositivos"
  on public.dispositivos for delete to authenticated
  using ( public.e_admin() );

drop policy if exists "Usuário vê os próprios acessos" on public.acessos;
create policy "Usuário vê os próprios acessos"
  on public.acessos for select to authenticated
  using ( (select auth.uid()) = user_id or public.e_admin() );

drop policy if exists "Usuário registra o próprio acesso" on public.acessos;
create policy "Usuário registra o próprio acesso"
  on public.acessos for insert to authenticated
  with check ( (select auth.uid()) = user_id );
