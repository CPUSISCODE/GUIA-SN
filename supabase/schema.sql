-- ============================================================
-- FAROL-GUIA — base fiscal unificada (GUIA-SN + GUIA-LP)
-- ------------------------------------------------------------
-- Projeto Supabase: FAROL-GUIA (dewyncwpubygjdthwixr, sa-east-1)
--
-- Este arquivo é idempotente: pode ser executado novamente em
-- cima de um banco já criado sem perder dados.
--
-- Ordem para recriar o banco do zero:
--   1. schema.sql            (este arquivo)
--   2. seed/dados-fiscais.sql
--   3. seed/ncm.json         (ver README.md — carga dos 10.687 NCMs)
--
-- Fontes dos dados:
--   RICMS/AC (Dec. 008/98 atualizado até o Dec. 11.900 de 06/2026, Anexo I)
--   Tabelas SPED 4.3.10 / 4.3.11 / 4.3.12 (PIS/COFINS monofásico e ST, 2026)
--   Relação de NCMs — 10.687 códigos de mercadorias
--   LC 123/2006 (Simples Nacional) · LC 214/2025 e IT 2025.002 (Reforma Tributária)
--   Lei 9.249/1995 e RIR/2018 (presunção de IRPJ/CSLL no Lucro Presumido)
-- ============================================================

create extension if not exists pg_trgm with schema extensions;

-- ------------------------------------------------------------
-- Tabelas de apoio da base de NCM
-- ------------------------------------------------------------

-- O id preserva a POSIÇÃO original no array empacotado consumido pelo
-- front-end. Não reaproveite ids: o índice gravado em cada NCM aponta
-- para a posição, e trocar o significado de um id remapeia produtos.
create table if not exists public.segmento_st (
  id    smallint primary key,
  nome  text not null unique
);
comment on table public.segmento_st is 'Segmentos de ST do Anexo I do RICMS/AC. O id preserva a posição original do array NCM_DB.segs para compatibilidade do formato empacotado.';

create table if not exists public.grupo_monofasico (
  id    smallint primary key,
  nome  text not null unique
);
comment on table public.grupo_monofasico is 'Grupos de incidência monofásica de PIS/COFINS. O id preserva a posição original do array NCM_DB.monos.';

-- ------------------------------------------------------------
-- NCM — tabela mestra (10.687 códigos)
-- ------------------------------------------------------------
create table if not exists public.ncm (
  codigo               char(8)  primary key,
  descricao            text     not null,
  segmento_st_id       smallint references public.segmento_st(id),
  mva                  numeric(6,2),
  grupo_monofasico_id  smallint references public.grupo_monofasico(id),
  constraint ncm_codigo_8_digitos check (codigo ~ '^[0-9]{8}$'),
  -- No Anexo I do RICMS/AC segmento e MVA andam sempre juntos.
  constraint ncm_st_coerente check ((segmento_st_id is null) = (mva is null)),
  constraint ncm_mva_positiva check (mva is null or mva >= 0)
);
comment on table public.ncm is 'Relação de NCMs de mercadorias com o segmento de ST do Acre (com MVA de referência do segmento) e o grupo monofásico de PIS/COFINS. Base compartilhada por GUIA-SN e GUIA-LP.';
comment on column public.ncm.mva is 'MVA de referência do segmento (mediana das MVAs originais do segmento no Anexo I do RICMS/AC), em %.';

create index if not exists ncm_segmento_st_idx      on public.ncm (segmento_st_id) where segmento_st_id is not null;
create index if not exists ncm_grupo_monofasico_idx on public.ncm (grupo_monofasico_id) where grupo_monofasico_id is not null;
create index if not exists ncm_descricao_trgm_idx   on public.ncm using gin (upper(descricao) extensions.gin_trgm_ops);

-- ------------------------------------------------------------
-- Cesta básica do Acre — Arts. 184-G e 184-H do RICMS/AC
-- ------------------------------------------------------------
create table if not exists public.cesta_basica_ac (
  id                       smallint generated always as identity primary key,
  prefixo                  text    not null unique,
  nome                     text    not null,
  somente_producao_interna boolean not null default false,
  excecao                  text,
  constraint cesta_prefixo_numerico check (prefixo ~ '^[0-9]{2,8}$')
);
comment on table public.cesta_basica_ac is 'Produtos da cesta básica do Acre por prefixo de NCM. Regra de match: prefixo mais específico vence; em empate de comprimento, somente_producao_interna=false vence.';
comment on column public.cesta_basica_ac.somente_producao_interna is 'true = benefício vale apenas para produção interna do Acre; compras de fora seguem a regra normal.';

-- ------------------------------------------------------------
-- Reforma Tributária — CST IBS/CBS + cClassTrib
-- ------------------------------------------------------------
-- ordem importa: quando duas regras têm prefixos do MESMO comprimento
-- que servem para o mesmo NCM, vence a de menor ordem.
create table if not exists public.rt_regra (
  id          smallint primary key,
  ordem       smallint not null,
  cst         text     not null,
  cclasstrib  text     not null,
  rotulo      text     not null,
  ressalva    text
);
comment on table public.rt_regra is 'Classificação tributária IBS/CBS (IT 2025.002 / LC 214/2025) por faixa de NCM, para venda a consumidor final.';

create table if not exists public.rt_regra_prefixo (
  regra_id  smallint not null references public.rt_regra(id) on delete cascade,
  prefixo   text     not null,
  primary key (regra_id, prefixo),
  constraint rt_prefixo_numerico check (prefixo ~ '^[0-9]{2,8}$')
);
comment on table public.rt_regra_prefixo is 'Prefixos de NCM de cada regra da Reforma Tributária. Match: prefixo mais longo vence.';

-- ------------------------------------------------------------
-- Origem da mercadoria e alíquotas de entrada
-- ------------------------------------------------------------
create table if not exists public.grupo_origem (
  grupo                text primary key,
  aliq_interestadual   numeric(5,2) not null,
  pct_antecipacao      numeric(5,2) not null
);
comment on table public.grupo_origem is 'Alíquota interestadual e % de antecipação parcial por grupo de origem, tendo o Acre como destino.';

create table if not exists public.uf (
  sigla  text primary key,
  nome   text not null,
  grupo  text not null references public.grupo_origem(grupo),
  constraint uf_sigla_valida check (sigla ~ '^[A-Z]{2,3}$')
);
comment on table public.uf is 'UFs de origem do fornecedor (inclui EXT para mercadoria importada).';

-- ------------------------------------------------------------
-- Parâmetros por regime
-- ------------------------------------------------------------
create table if not exists public.parametro_fiscal (
  chave      text primary key,
  valor      numeric(10,4) not null,
  descricao  text not null
);
comment on table public.parametro_fiscal is 'Alíquotas e constantes gerais usadas pelos dois módulos (SN e LP).';

create table if not exists public.sn_anexo_i_faixa (
  numero           smallint primary key,
  teto             numeric(14,2) not null,
  aliq_nominal     numeric(5,2)  not null,
  parcela_deduzir  numeric(12,2) not null,
  pct_cofins       numeric(5,2)  not null,
  pct_pis          numeric(5,2)  not null,
  pct_icms         numeric(5,2),
  constraint sn_faixa_numero check (numero between 1 and 6)
);
comment on table public.sn_anexo_i_faixa is 'Faixas do Anexo I (Comércio) do Simples Nacional. pct_icms NULL na 6ª faixa = ICMS recolhido fora do DAS.';

create table if not exists public.lp_regime_pis_cofins (
  regime  text primary key,
  pis     numeric(5,2) not null,
  cofins  numeric(5,2) not null,
  rotulo  text not null
);
comment on table public.lp_regime_pis_cofins is 'Alíquotas de PIS/COFINS do Lucro Presumido por regime de apuração.';

create table if not exists public.lp_parametro (
  chave      text primary key,
  valor      numeric(12,4) not null,
  descricao  text not null
);
comment on table public.lp_parametro is 'Constantes do motor de Lucro Presumido (presunção IRPJ/CSLL, adicional trimestral).';

-- ------------------------------------------------------------
-- RLS — base pública de consulta, somente leitura
-- ------------------------------------------------------------
-- A chave publicável usada no front-end só consegue SELECT. Nenhuma
-- política de INSERT/UPDATE/DELETE é criada: alterações na base passam
-- pelo painel do Supabase ou por uma migração.
do $$
declare t text;
begin
  foreach t in array array[
    'segmento_st','grupo_monofasico','ncm','cesta_basica_ac','rt_regra','rt_regra_prefixo',
    'grupo_origem','uf','parametro_fiscal','sn_anexo_i_faixa','lp_regime_pis_cofins','lp_parametro'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = t and policyname = 'leitura_publica_' || t
    ) then
      execute format(
        'create policy %I on public.%I for select to anon, authenticated using (true)',
        'leitura_publica_' || t, t);
    end if;
  end loop;
end $$;

-- ============================================================
-- Bundles de leitura consumidos por GUIA-SN e GUIA-LP
-- ------------------------------------------------------------
-- Devolvem exatamente o mesmo formato das constantes embutidas no
-- front-end, para substituição direta e sem conversão no cliente.
-- ============================================================

-- Base de NCM empacotada como "codigo|descricao|idx_seg|mva|idx_mono".
-- Os arrays segs/monos são montados por POSIÇÃO (generate_series), de modo
-- que o índice gravado em cada linha continue apontando para o nome certo
-- mesmo que algum id seja removido no futuro.
create or replace function public.ncm_bundle()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'segs', (
      select coalesce(jsonb_agg(s.nome order by g.i), '[]'::jsonb)
      from generate_series(0, coalesce((select max(id) from public.segmento_st), -1)) g(i)
      left join public.segmento_st s on s.id = g.i
    ),
    'monos', (
      select coalesce(jsonb_agg(m.nome order by g.i), '[]'::jsonb)
      from generate_series(0, coalesce((select max(id) from public.grupo_monofasico), -1)) g(i)
      left join public.grupo_monofasico m on m.id = g.i
    ),
    'rows', (
      select coalesce(jsonb_agg(
        trim(n.codigo) || '|' || n.descricao || '|' ||
        coalesce(n.segmento_st_id::text, '') || '|' ||
        coalesce(trim_scale(n.mva)::text, '') || '|' ||
        coalesce(n.grupo_monofasico_id::text, '')
        order by n.codigo), '[]'::jsonb)
      from public.ncm n
    ),
    'total',  (select count(*) from public.ncm),
    'com_st', (select count(*) from public.ncm where segmento_st_id is not null),
    'com_monofasico', (select count(*) from public.ncm where grupo_monofasico_id is not null),
    'meta', 'Supabase FAROL-GUIA · base unificada · RICMS/AC 06/2026 + SPED 4.3.x + NCM v4'
  );
$$;
comment on function public.ncm_bundle() is 'Base de NCM completa no formato empacotado usado pelo front-end (NCM_DB).';

-- Assinatura barata da base: o cliente confere antes de baixar tudo de novo.
create or replace function public.ncm_versao()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'total', count(*),
    'hash',  md5(string_agg(
               trim(codigo) || '|' || descricao || '|' ||
               coalesce(segmento_st_id::text,'') || '|' ||
               coalesce(trim_scale(mva)::text,'') || '|' ||
               coalesce(grupo_monofasico_id::text,''), E'\n' order by codigo))
  )
  from public.ncm;
$$;
comment on function public.ncm_versao() is 'Total de NCMs e hash MD5 da base empacotada — usado para validar o cache local do cliente.';

-- Demais parâmetros fiscais, nos mesmos formatos das constantes do front-end.
create or replace function public.fiscal_bundle()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'cesta', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'pref', prefixo, 'nome', nome,
               'interna', somente_producao_interna, 'exc', excecao)
             order by length(prefixo) desc, somente_producao_interna, prefixo), '[]'::jsonb)
      from public.cesta_basica_ac
    ),
    'rt', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'pref', p.prefixos, 'cst', r.cst, 'ct', r.cclasstrib,
               'label', r.rotulo, 'caveat', r.ressalva)
             order by r.ordem), '[]'::jsonb)
      from public.rt_regra r
      join lateral (
        select coalesce(jsonb_agg(rp.prefixo order by rp.prefixo), '[]'::jsonb) as prefixos
        from public.rt_regra_prefixo rp where rp.regra_id = r.id
      ) p on true
    ),
    'regions', (
      select coalesce(jsonb_object_agg(sigla, jsonb_build_object('name', nome, 'group', grupo)), '{}'::jsonb)
      from public.uf
    ),
    'grupos', (
      select coalesce(jsonb_object_agg(grupo, jsonb_build_object(
               'inter', trim_scale(aliq_interestadual), 'antecip', trim_scale(pct_antecipacao))), '{}'::jsonb)
      from public.grupo_origem
    ),
    'params', (
      select coalesce(jsonb_object_agg(chave, trim_scale(valor)), '{}'::jsonb)
      from public.parametro_fiscal
    ),
    'faixasSN', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'max', trim_scale(teto), 'aliq', trim_scale(aliq_nominal),
               'pd', trim_scale(parcela_deduzir), 'cofins', trim_scale(pct_cofins),
               'pis', trim_scale(pct_pis), 'icms', trim_scale(pct_icms))
             order by numero), '[]'::jsonb)
      from public.sn_anexo_i_faixa
    ),
    'lpRates', (
      select coalesce(jsonb_object_agg(regime, jsonb_build_object(
               'pis', trim_scale(pis), 'cofins', trim_scale(cofins), 'rotulo', rotulo)), '{}'::jsonb)
      from public.lp_regime_pis_cofins
    ),
    'lpParams', (
      select coalesce(jsonb_object_agg(chave, trim_scale(valor)), '{}'::jsonb)
      from public.lp_parametro
    )
  );
$$;
comment on function public.fiscal_bundle() is 'Cesta básica AC, regras da Reforma Tributária, UFs, alíquotas, faixas do Simples e parâmetros do Lucro Presumido.';

revoke all on function public.ncm_bundle()    from public;
revoke all on function public.ncm_versao()    from public;
revoke all on function public.fiscal_bundle() from public;
grant execute on function public.ncm_bundle()    to anon, authenticated;
grant execute on function public.ncm_versao()    to anon, authenticated;
grant execute on function public.fiscal_bundle() to anon, authenticated;
