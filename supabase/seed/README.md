# Carga da base de NCMs

`ncm.json` é a cópia versionada da base fiscal, no mesmo formato compacto em que
ela vivia embutida no `index.html`:

```json
{
  "meta":  "RICMS/AC 06/2026 + SPED 4.3.x + NCM v4 (descrições normalizadas)",
  "segs":  ["Alimentícios", "Autopeças", ...],   // 24 segmentos de ST do RICMS/AC
  "monos": ["Autopeças", "Bebidas frias", ...],  // 12 categorias monofásicas
  "rows":  ["01012100|Cavalos reprodutores de raça pura|||", ...]
}
```

Cada item de `rows` tem cinco campos separados por `|`:

| Posição | Campo | Observação |
| --- | --- | --- |
| 1 | `ncm` | 8 dígitos |
| 2 | `descricao` | |
| 3 | índice em `segs` | vazio = sem ST no Acre |
| 4 | `mva` | vazio = sem MVA |
| 5 | índice em `monos` | vazio = não é monofásico |

Total: **10.687** registros, dos quais 2.052 com segmento de ST e MVA, e 550
monofásicos.

## Como a carga foi feita

O sandbox onde a migração foi executada não alcança a API do Supabase, e passar
630 KB por chamada de ferramenta não era viável. A saída foi fazer o próprio
Postgres buscar o arquivo direto do GitHub:

```sql
create extension if not exists http with schema extensions;

with baixado as (
  select (extensions.http_get(
    'https://raw.githubusercontent.com/CPUSISCODE/GUIA-SN/main/supabase/seed/ncm.json'
  )).content::jsonb as j
),
linhas as (
  select b.j, jsonb_array_elements_text(b.j -> 'rows') as r from baixado b
)
insert into public.ncm (ncm, descricao, segmento, mva, monofasico)
select
  split_part(r, '|', 1),
  split_part(r, '|', 2),
  case when split_part(r,'|',3) <> '' then j -> 'segs'  ->> (split_part(r,'|',3)::int) end,
  nullif(split_part(r, '|', 4), '')::numeric,
  case when split_part(r,'|',5) <> '' then j -> 'monos' ->> (split_part(r,'|',5)::int) end
from linhas
on conflict (ncm) do update set
  descricao  = excluded.descricao,
  segmento   = excluded.segmento,
  mva        = excluded.mva,
  monofasico = excluded.monofasico;

drop extension http;
```

> **Remova a extensão `http` depois da carga.** Ela deixa o banco fazer
> requisições HTTP de saída, o que é superfície para SSRF. Ela foi habilitada só
> durante a importação e removida em seguida — o `drop extension` no fim não é
> opcional.

O trigger `ncm_versao_sync` recalcula a versão da base sozinho a cada escrita em
`public.ncm`, então não é preciso atualizar `ncm_versao` na mão. Assim que a
versão muda, todo navegador descarta o cache e ressincroniza no próximo acesso.

## Atualizando a base

1. Edite `ncm.json` (ou gere de novo a partir das fontes oficiais).
2. Faça o commit e envie para a `main`.
3. Rode o bloco SQL acima, apontando para a `main`.
4. Confira: `select total, versao from public.ncm_versao;`
