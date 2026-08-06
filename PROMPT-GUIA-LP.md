# Prompt para o GUIA-LP — mover a base de NCMs para o Supabase

> Copie o texto abaixo (tudo a partir da linha divisória) e envie no chat responsável
> pelo GUIA-LP. Ele descreve o que foi feito no GUIA-SN para que o LP fique idêntico em
> comportamento e em visual, sem que os dois trabalhos interfiram um no outro.

---

Tire a base de NCMs de dentro do `index.html` do GUIA-LP e passe a servi-la pelo Supabase,
mantendo funcionamento offline via `localStorage`. Isso já foi feito no repositório irmão
GUIA-SN (Simples Nacional) — **siga exatamente a mesma lógica e o mesmo desenho**, para os
dois não divergirem.

**Não presuma que o LP é idêntico ao SN. Inspecione o repositório real antes de decidir
qualquer coisa** — a estrutura de dados, os nomes das variáveis e o volume de registros
podem ser diferentes.

## Projeto e escopo

Use `list_projects` e trabalhe no projeto `FAROL-GUIA-LP`. Não mexa no `FAROL-GUIA-SN`.

Não altere a lógica fiscal, as abas do app, o gate de autenticação nem a barra de usuário
— tudo isso já está pronto e padronizado. O trabalho é só tirar a base do HTML.

## Banco

Duas tabelas, com RLS habilitado e `select` liberado **apenas** para a role
`authenticated` (`using (true)`). Sem policy de escrita: atualizar a base é tarefa do
`service_role`, fora do navegador.

`public.ncm`:

- `ncm text primary key check (ncm ~ '^[0-9]{8}$')`
- `descricao text not null`
- as demais colunas conforme a base do LP realmente tiver (no SN foram `segmento text`,
  `mva numeric(6,2)` e `monofasico text`) — **confira a estrutura real antes**
- índices parciais nas colunas de classificação, `where <coluna> is not null`

`public.ncm_versao`, de linha única:

- `id boolean primary key default true check (id)`
- `versao text not null` — md5 do conteúdo inteiro da base
- `fonte text`, `total integer`, `atualizado_em timestamptz`

Crie um trigger `after insert or update or delete or truncate ... for each statement` em
`public.ncm` que recalcula esse md5 e atualiza `ncm_versao`. Isso é o que garante que a
versão nunca fique atrasada em relação aos dados — e, portanto, que nenhum navegador fique
preso a um cache velho. A função deve ser `security definer` com `set search_path = ''` e
levar `revoke all on function ... from public, anon, authenticated;`, senão o
`get_advisors` acusa que ela é chamável via `/rest/v1/rpc/...`.

Rode `get_advisors` com type `security` no fim e deixe limpo.

## Como carregar os dados

O sandbox provavelmente bloqueia `*.supabase.co`, e passar centenas de KB por chamada de
ferramenta estoura o contexto. O caminho que funcionou no SN:

1. Extraia a base do `index.html` para `supabase/seed/ncm.json`, no mesmo formato compacto
   de origem. **Confira o round-trip** — reconstruir a partir do arquivo tem que devolver
   todos os registros idênticos, campo a campo, antes de seguir.
2. Faça commit e push, para o arquivo ficar acessível em `raw.githubusercontent.com`.
3. No Postgres, `create extension if not exists http with schema extensions;` e use
   `extensions.http_get(...)` para o próprio banco buscar o arquivo, com
   `jsonb_array_elements_text` + `split_part` para inserir.
4. **`drop extension http;` ao terminar.** Ela deixa o banco fazer requisições HTTP de
   saída, o que é superfície para SSRF. Não é opcional.

## Frontend

Mantenha as mesmas estruturas que o app já consome hoje (no SN eram `dbByCode` e
`dbList`) — **mapeie quais são no LP antes de mexer**. Se elas continuarem com a mesma
forma, nada do resto do app precisa mudar.

Substitua o parse do dado embutido por:

- `aplicarBaseNcm(registros)` — preenche as estruturas e marca `baseCarregada = true`
- `atualizarStatusBase(texto)` — com texto, mostra a mensagem crua (sincronizando, erro);
  sem texto, monta o resumo da base carregada

Fluxo da sincronização, dentro do script de acesso:

1. Roda **depois do login**, junto com o carregamento do perfil, dentro do mesmo
   `setTimeout(..., 0)` — o supabase-js trava se um `.from()` for disparado de dentro do
   callback de `onAuthStateChange`.
2. Havendo cache no `localStorage`, aplique-o **imediatamente**, antes de falar com o
   servidor: a ferramenta fica utilizável na hora.
3. Depois leia `ncm_versao`. Versão igual à do cache → não baixe nada. Diferente, ou sem
   cache → baixe paginado e regrave o cache.
4. Sem rede: com cache, segue offline normalmente; sem cache, mostre um aviso pedindo
   conexão.

Três detalhes que deram trabalho no SN e que você vai querer já resolvidos:

1. **`.range()` do supabase-js v2 vira `offset`/`limit` na query string, não header
   `Range`.** Se você mockar a paginação lendo o header `Range` nos testes, o mock devolve
   sempre a primeira página cheia e o laço de download **nunca termina**.
2. **Ponha um teto de páginas no laço.** Se o servidor ignorar a paginação e devolver
   sempre uma página cheia, o laço vira infinito e martela a API. Pare com erro em vez
   disso.
3. **Proteja a busca contra a base ainda não carregada.** Sem isso, quem pesquisar durante
   a sincronização recebe "NCM não encontrado", que é mentira. Mostre "a base ainda está
   sendo carregada".

Corrija também os textos que afirmam que a base é "embutida" e que a ferramenta "funciona
sem internet" — agora ela é baixada uma vez e fica guardada no navegador.

## Testes

Não entregue sem testar. Instale `playwright-core` e `@supabase/supabase-js` num diretório
temporário, sirva o UMD local e mocke as rotas com `page.route()`. Cubra:

- a base não está mais embutida no HTML
- primeira sincronização, conferindo o número de páginas baixadas
- busca funcionando com os dados vindos do servidor
- reload com cache válido **não** rebaixa nada
- versão nova no servidor força ressincronização
- offline **com** cache: continua funcionando
- offline **sem** cache: avisa em vez de falhar em silêncio
- buscar antes da base chegar não responde "não encontrado"

Rode também um teste em **escala real**, servindo o arquivo de seed de verdade em vez de
dados falsos: é ele que revela problemas de paginação e de capacidade do `localStorage`
(no SN, 10.687 registros deram 11 páginas e 1,3 MB de cache).

Compare os erros de console antes e depois das mudanças e me diga o que passou e o que
você **não** conseguiu testar de verdade.

## Entrega

Commits em português, com mensagens descritivas. Atualize o README com o esquema das duas
tabelas novas, como a sincronização e o cache funcionam, e como recarregar a base. Suba
para a branch e **pergunte antes de abrir PR ou mergear**.

Por fim, seja honesto sobre o alcance disso: o gate passa a proteger de verdade a **base
fiscal**, porque sem login o `select` em `public.ncm` é negado pelo RLS. Mas o
`index.html` continua sendo um arquivo estático público, com a lógica de cálculo à vista
no código-fonte; e, uma vez sincronizada, a base fica no `localStorage` daquele navegador
inclusive depois do logout — é o preço de funcionar offline. O login controla quem
**obtém** a base, não o que a pessoa faz com ela depois.
