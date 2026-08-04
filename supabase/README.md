# Base fiscal no Supabase — FAROL-GUIA

Os dois guias — [GUIA-SN](https://github.com/CPUSISCODE/GUIA-SN) (Simples Nacional) e
[GUIA-LP](https://github.com/CPUSISCODE/GUIA-LP) (Lucro Presumido) — usam **um único banco de
dados**. A base de NCM, as MVAs de ST do Acre, a cesta básica, as regras da Reforma Tributária
e as alíquotas de entrada são exatamente as mesmas nos dois. O que muda entre eles é só o
**motor de cálculo do regime**, que continua dentro de cada `index.html`.

| | GUIA-SN | GUIA-LP |
|---|---|---|
| Base de NCM, ST/MVA, monofásico | Supabase (comum) | Supabase (comum) |
| Cesta básica AC, Reforma Tributária, UFs | Supabase (comum) | Supabase (comum) |
| Motor de cálculo | Anexo I, DAS, CSOSN | Presunção IRPJ/CSLL, PIS/COFINS, CST |

## Projeto

- **Nome:** FAROL-GUIA
- **Ref:** `dewyncwpubygjdthwixr` · região `sa-east-1`
- **URL:** `https://dewyncwpubygjdthwixr.supabase.co`

A chave usada no front-end é a **publicável (anon)**, e está em `farol-supabase.js`. Isso é o uso
previsto pelo Supabase: as políticas de RLS deste projeto só concedem `SELECT`, então a chave não
permite alterar nada. **Não** coloque a `service_role` em nenhum arquivo do repositório.

## Conteúdo

| Tabela | Registros | O que guarda |
|---|---:|---|
| `ncm` | 10.687 | Código, descrição, segmento de ST, MVA e grupo monofásico |
| `segmento_st` | 24 | Segmentos de ST do Anexo I do RICMS/AC |
| `grupo_monofasico` | 12 | Grupos de PIS/COFINS monofásico (SPED 4.3.x) |
| `cesta_basica_ac` | 41 | Prefixos da cesta básica (Arts. 184-G/184-H) |
| `rt_regra` / `rt_regra_prefixo` | 9 / 72 | CST IBS/CBS e cClassTrib por faixa de NCM |
| `uf` / `grupo_origem` | 28 / 6 | Alíquota interestadual e % de antecipação |
| `parametro_fiscal` | 4 | ICMS interno AC (19%), cesta (17%), CBS/IBS de teste |
| `sn_anexo_i_faixa` | 6 | Faixas do Anexo I do Simples Nacional |
| `lp_regime_pis_cofins` / `lp_parametro` | 2 / 8 | PIS/COFINS, presunção de IRPJ e CSLL |

Dos 10.687 NCMs, **2.052** têm segmento de ST no Acre e **550** são monofásicos de PIS/COFINS.

## Como o front-end consome

Não há biblioteca nem build: `farol-supabase.js` fala direto com a API REST via `fetch`.

| Função (RPC) | Uso |
|---|---|
| `ncm_versao()` | Total + hash MD5 da base. Consulta barata, feita a cada carregamento |
| `ncm_bundle()` | Base de NCM completa, no formato empacotado que o `index.html` já usava |
| `fiscal_bundle()` | Cesta básica, Reforma Tributária, UFs, alíquotas, faixas e parâmetros |

Sequência a cada abertura da página:

1. A base **embutida no HTML** é montada primeiro — a ferramenta abre e funciona sem internet,
   como antes.
2. Se houver cópia local (`localStorage`) de uma sincronização anterior, ela entra em uso na hora.
3. `ncm_versao()` compara o hash. Se bater com a cópia local, nada é baixado.
4. Se não bater, `ncm_bundle()` + `fiscal_bundle()` são baixados e guardados.

**A base do Supabase só substitui a embutida depois de passar por validação completa**
(`validarNcm` em `farol-supabase.js`): formato de cada linha, código de 8 dígitos, índices de
segmento e monofásico dentro do intervalo, MVA numérica, coerência entre segmento de ST e MVA, e
conferência do total recebido contra o total declarado pelo banco. Qualquer reprovação mantém a
base embutida — sincronizar nunca deixa a ferramenta em estado pior do que estava.

O indicador no canto inferior direito mostra a origem da base em uso; clicar nele força uma nova
sincronização.

## Recriar o banco do zero

```sql
-- 1. estrutura, RLS e funções
\i schema.sql
-- 2. dados de referência
\i seed/dados-fiscais.sql
```

Para os 10.687 NCMs, use `seed/ncm.json` (mesmo formato devolvido por `ncm_bundle()`):

```sql
-- Desempacota o JSON exatamente como o front-end faz.
with linha as (
  select r as texto from jsonb_array_elements_text(:'payload'::jsonb -> 'rows') as r
), campo as (
  select split_part(texto,'|',1) as codigo,
         split_part(texto,'|',2) as descricao,
         nullif(split_part(texto,'|',3),'') as seg,
         nullif(split_part(texto,'|',4),'') as mva,
         nullif(split_part(texto,'|',5),'') as mono
  from linha
)
insert into public.ncm (codigo, descricao, segmento_st_id, mva, grupo_monofasico_id)
select codigo, descricao, seg::smallint, mva::numeric, mono::smallint from campo
on conflict (codigo) do update set
  descricao           = excluded.descricao,
  segmento_st_id      = excluded.segmento_st_id,
  mva                 = excluded.mva,
  grupo_monofasico_id = excluded.grupo_monofasico_id;
```

Conferência depois da carga — deve devolver `10687 / 2052 / 550`:

```sql
select count(*) as total,
       count(segmento_st_id) as com_st,
       count(grupo_monofasico_id) as com_monofasico
from public.ncm;
```

## Alterar a base

Alterou um NCM, uma MVA ou uma alíquota no Supabase? Não precisa mexer em nada nos repositórios:
o hash de `ncm_versao()` muda sozinho e as duas ferramentas baixam a versão nova na próxima
abertura. A base embutida no HTML continua lá como rede de segurança para uso offline.

Cuidado com os ids de `segmento_st` e `grupo_monofasico`: eles representam a **posição** no array
empacotado. Apagar um id no meio da lista remapeia produtos — para aposentar um segmento, prefira
deixar a linha existir e parar de referenciá-la.
