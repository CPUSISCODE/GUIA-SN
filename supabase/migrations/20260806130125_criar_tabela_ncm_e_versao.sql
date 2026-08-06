-- Base fiscal do GUIA-SN, que antes vivia embutida no index.html.
-- Sai do HTML e passa a ser servida pelo Supabase, sob RLS: só usuário
-- autenticado consegue ler.

create table if not exists public.ncm (
  ncm         text primary key check (ncm ~ '^[0-9]{8}$'),
  descricao   text not null,
  segmento    text,            -- segmento de ST do RICMS/AC (null = sem ST)
  mva         numeric(6,2),    -- MVA de referência do segmento
  monofasico  text             -- categoria monofásica de PIS/COFINS (null = não é)
);

comment on table public.ncm is 'Base de NCMs do GUIA-SN: descrição, segmento de ST no Acre com MVA de referência e categoria monofásica de PIS/COFINS.';

create index if not exists ncm_segmento_idx   on public.ncm (segmento) where segmento is not null;
create index if not exists ncm_monofasico_idx on public.ncm (monofasico) where monofasico is not null;

-- Linha única com a versão da base. O navegador guarda a base no localStorage
-- e usa esta versão para saber se o cache ainda vale.
create table if not exists public.ncm_versao (
  id            boolean primary key default true check (id),
  versao        text not null,
  fonte         text,
  total         integer not null default 0,
  atualizado_em timestamptz not null default now()
);

comment on table public.ncm_versao is 'Versão corrente da base de NCMs. O cliente compara com a cópia em localStorage para decidir se ressincroniza.';

alter table public.ncm         enable row level security;
alter table public.ncm_versao  enable row level security;

-- Somente leitura, e somente para quem está autenticado. Escrita fica a cargo
-- do service_role (fora do navegador).

drop policy if exists "Usuários autenticados podem ler a base de NCMs" on public.ncm;
create policy "Usuários autenticados podem ler a base de NCMs"
  on public.ncm
  for select
  to authenticated
  using ( true );

drop policy if exists "Usuários autenticados podem ler a versão da base" on public.ncm_versao;
create policy "Usuários autenticados podem ler a versão da base"
  on public.ncm_versao
  for select
  to authenticated
  using ( true );
