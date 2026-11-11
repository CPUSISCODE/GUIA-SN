-- XML original e metadados gravados em uma única transação, privados por usuário.
-- Base64 preserva os bytes originais, inclusive declaração de encoding e BOM.
create table public.xml_documentos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  documento_id text not null check (documento_id ~ '^([0-9]{44}|[a-f0-9]{64})$'),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  nome_arquivo text not null check (length(nome_arquivo) between 1 and 255),
  fornecedor text not null default '' check (length(fornecedor) <= 500),
  numero_nota text not null default '' check (length(numero_nota) <= 30),
  chave_nfe text check (chave_nfe ~ '^[0-9]{44}$'),
  valor_total numeric(18,2) not null default 0 check (valor_total >= 0),
  tamanho_bytes integer not null check (tamanho_bytes between 1 and 5242880),
  xml_base64 text not null check (length(xml_base64) <= 6990508),
  created_at timestamptz not null default now(),
  unique(user_id, documento_id),
  unique(user_id, sha256),
  check (octet_length(decode(xml_base64, 'base64')) = tamanho_bytes)
);
create index sn_xml_documentos_user_created_idx on public.xml_documentos(user_id, created_at desc, id);
alter table public.xml_documentos enable row level security;
revoke all on public.xml_documentos from anon, authenticated;
grant select, insert on public.xml_documentos to authenticated;
create policy sn_xml_documentos_select_own on public.xml_documentos
  for select to authenticated
  using ((select auth.uid()) = user_id and (select private.usuario_liberado()));
create policy sn_xml_documentos_insert_own on public.xml_documentos
  for insert to authenticated
  with check ((select auth.uid()) = user_id and (select private.usuario_liberado()));
comment on table public.xml_documentos is 'Arquivo privado de NF-e do GUIA-SN. Originais imutáveis, sem acesso anônimo ou entre contas.';
