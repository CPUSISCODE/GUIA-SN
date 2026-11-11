# GUIA-SN — Consulta NCM · Simples Nacional (Acre)

Ferramenta fiscal de página única (`index.html`), sem build e sem dependências além de
CDN. Consulta NCM, importação de XML de NF-e, auditoria de cadastro e cálculo de custo
operacional, com as regras do RICMS/AC para empresas do Simples Nacional.

O acesso é controlado por **cadastro e login via Supabase**. Enquanto não houver sessão,
uma tela de acesso cobre toda a página; a ferramenta só aparece depois da autenticação.

A **base fiscal não fica mais embutida no HTML**: os 10.687 NCMs vivem na tabela
`public.ncm`, protegida por RLS, e são baixados no primeiro acesso autenticado. A partir
daí ficam guardados no `localStorage` do navegador, e a ferramenta **volta a funcionar
sem internet** — a rede só é usada de novo quando a versão publicada da base muda.

---

## Sumário

- [Como rodar](#como-rodar)
- [Projeto Supabase](#projeto-supabase)
- [Esquema do banco](#esquema-do-banco)
- [Configuração obrigatória no painel](#configuração-obrigatória-no-painel)
  - [1. URL Configuration](#1-url-configuration-obrigatório)
  - [2. Confirmação de e-mail: manter ou desligar](#2-confirmação-de-e-mail-manter-ou-desligar)
  - [3. Template do e-mail de confirmação](#3-template-do-e-mail-de-confirmação)
- [Como funciona o front-end](#como-funciona-o-front-end)
- [Estrutura do repositório](#estrutura-do-repositório)

---

## Como rodar

Não há build. Abra o `index.html` em qualquer servidor estático (GitHub Pages, Netlify,
Vercel, `python3 -m http.server`, etc.).

> **Importante:** abrir o arquivo por `file://` não funciona para o login — o Supabase
> exige uma origem HTTP(S) válida para os redirecionamentos de e-mail. Use um servidor,
> mesmo que local.

---

## Projeto Supabase

| Item | Valor |
| --- | --- |
| Projeto | `FAROL-GUIA-SN` |
| Referência (`project_id`) | `axfyuiidgauhshmmywmp` |
| Região | `sa-east-1` |
| URL da API | `https://axfyuiidgauhshmmywmp.supabase.co` |

A **URL** e a **chave publicável** (`sb_publishable_...`) ficam embutidas no `index.html`.
Isso é esperado: a chave publicável é feita para ser exposta no navegador. Quem protege os
dados é o **RLS** da tabela `profiles`.

> A chave `service_role` **nunca** deve aparecer no HTML nem em qualquer arquivo do
> repositório — ela ignora o RLS por completo.

---

## Esquema do banco

Migration: [`supabase/migrations/20260805133803_criar_tabela_profiles_com_rls_e_triggers.sql`](supabase/migrations/20260805133803_criar_tabela_profiles_com_rls_e_triggers.sql)

### Tabela `public.profiles`

| Coluna | Tipo | Observações |
| --- | --- | --- |
| `id` | `uuid` | PK, referencia `auth.users(id)` **on delete cascade** |
| `nome` | `text` | Vem do cadastro |
| `empresa` | `text` | Opcional |
| `created_at` | `timestamptz` | `not null default now()` |
| `updated_at` | `timestamptz` | `not null default now()`, mantido por trigger |

Apagar o usuário em `auth.users` apaga o perfil junto (cascade).

### Row Level Security

RLS **habilitado**. Três policies, todas restritas à role `authenticated` e à condição
`(select auth.uid()) = id` — ou seja, cada usuário só enxerga e altera o próprio perfil:

| Policy | Comando |
| --- | --- |
| `Usuários podem ver o próprio perfil` | `select` |
| `Usuários podem criar o próprio perfil` | `insert` |
| `Usuários podem atualizar o próprio perfil` | `update` |

Não há policy de `delete`: o perfil sai junto com a conta, pelo cascade.

> `(select auth.uid())` em vez de `auth.uid()` puro faz o Postgres avaliar a função uma
> única vez por consulta (initplan), em vez de uma vez por linha.

### Tabela `public.ncm`

A base fiscal. Migration:
[`20260806130125_criar_tabela_ncm_e_versao.sql`](supabase/migrations/20260806130125_criar_tabela_ncm_e_versao.sql)

| Coluna | Tipo | Observações |
| --- | --- | --- |
| `ncm` | `text` | PK, 8 dígitos (`check (ncm ~ '^[0-9]{8}$')`) |
| `descricao` | `text` | `not null` |
| `segmento` | `text` | Segmento de ST do RICMS/AC. `null` = sem ST |
| `mva` | `numeric(6,2)` | MVA de referência do segmento |
| `monofasico` | `text` | Categoria monofásica de PIS/COFINS. `null` = não é |

10.687 registros, dos quais 2.052 com segmento e MVA, e 550 monofásicos. Índices parciais
em `segmento` e `monofasico`.

RLS habilitado, com uma única policy de `select` para a role `authenticated`, condicionada
a `private.usuario_liberado()` — ou seja, **estar autenticado não basta: a conta precisa
estar aprovada e não bloqueada**. Sem isso o RLS devolve lista vazia e a ferramenta não tem
o que consultar. Ver [Administração](#administração).

Não há policy de escrita — atualizar a base é tarefa do `service_role`, fora do navegador.
Ver [`supabase/seed/README.md`](supabase/seed/README.md).

### Tabela `public.ncm_versao`

Linha única (`id boolean primary key default true check (id)`) com a versão corrente da
base: `versao` (md5 do conteúdo), `fonte`, `total` e `atualizado_em`. Também com `select`
liberado apenas para `authenticated`.

É essa versão que decide se o cache do navegador ainda vale. O trigger
`ncm_versao_sync` recalcula o md5 a cada escrita em `public.ncm`, então é impossível a
base mudar e a versão ficar para trás — e, portanto, impossível um navegador ficar preso
a um cache velho.

### Como a sincronização funciona

1. O usuário entra. Só então a base é buscada (a policy exige `authenticated`).
2. Se já existe cache no `localStorage` (chave `guia-sn-base-ncm`), ele é aplicado **na
   hora** — a ferramenta fica utilizável antes mesmo de falar com o servidor.
3. Em seguida a página lê `ncm_versao`. Versão igual à do cache → nada é baixado.
   Versão diferente (ou sem cache) → a base é baixada paginada, de 1.000 em 1.000, e
   regravada no cache.
4. Sem rede: havendo cache, a ferramenta segue funcionando offline. Sem cache, aparece
   um aviso pedindo conexão — e a busca informa que a base está carregando em vez de
   responder "NCM não encontrado".

O cache ocupa cerca de 1,3 MB, bem dentro do limite dos navegadores. Se a gravação
falhar (cota estourada, storage bloqueado), a ferramenta funciona igual naquela sessão e
apenas ressincroniza no acesso seguinte.

### Administração

Migrations `20260806133536`, `20260806133610`, `20260806133659`, `20260806133806` e
`20260806134132`.

#### `public.admins`

Uma linha por administrador (`id`, `criado_em`, `criado_por`).

**A condição de admin não fica em `profiles` de propósito.** Os usuários têm policy de
`update` no próprio perfil, então uma coluna `admin` ali seria auto-atribuível — qualquer
um viraria admin sozinho. A tabela `admins` não tem nenhuma policy de escrita para o
cliente: entrar e sair dela só acontece pelas funções `promover_admin` e `rebaixar_admin`.

#### Campos de controle em `public.profiles`

| Coluna | Padrão | Para que serve |
| --- | --- | --- |
| `aprovado` | `false` | Sem isso o usuário entra, mas **não recebe a base fiscal** |
| `bloqueado` | `false` | Bloqueio manual, independente da aprovação |
| `limite_dispositivos` | `2` | Quantos aparelhos distintos ele pode registrar (1 a 20) |
| `observacao` | `null` | Anotação livre do admin |

Esses quatro campos são protegidos pelo trigger `profiles_proteger_controle`: se quem
está atualizando não for admin, a alteração é recusada. O usuário continua podendo editar
o próprio nome e empresa normalmente.

#### `public.dispositivos` e `public.acessos`

`dispositivos` guarda um registro por aparelho (`impressao`, `tipo`, `navegador`,
`sistema`, `fuso`, `primeiro_acesso`, `ultimo_acesso`), com `unique (user_id, impressao)`.
`acessos` guarda um registro por entrada na ferramenta.

A `impressao` é um identificador aleatório gerado e guardado **naquele navegador** — não é
fingerprinting, e some se o usuário limpar os dados do site.

**O limite de dispositivos é aplicado no banco**, pelo trigger `dispositivos_limite`, e
não no navegador: não há como contornar registrando um aparelho a mais pelo devtools. O
trigger ignora aparelhos já conhecidos, senão reconectar do computador de sempre seria
barrado (o `BEFORE INSERT` dispara antes de o Postgres avaliar o `ON CONFLICT`).

#### Sobre a "região"

O navegador não sabe a localização de forma confiável, e não há servidor próprio aqui para
ler o IP. O que dá para captar sem inventar é o **fuso horário do navegador**
(`America/Rio_Branco`, `America/Sao_Paulo`…), que serve de aproximação regional. Como vem
do cliente, é falsificável: vale como visibilidade operacional, **não como prova**.

Região por IP de verdade exigiria uma Edge Function lendo o endereço de origem — não está
implementado. Vale lembrar que guardar IP e localização de usuário identificado é dado
pessoal sob a **LGPD** e precisa estar declarado para o usuário.

#### Funções expostas ao painel

| Função | O que faz |
| --- | --- |
| `listar_usuarios()` | A planilha do painel. Junta `auth.users` (e-mail, último login, confirmação) com o perfil e os totais de dispositivos e acessos |
| `promover_admin(p_email)` | Torna alguém admin pelo e-mail. Já deixa a conta aprovada e desbloqueada |
| `rebaixar_admin(p_id)` | Remove um admin. **Recusa remover o último**, para não deixar o sistema sem ninguém |

As três são `security definer` e **precisam** ser chamáveis pela role `authenticated` —
é assim que o painel funciona. Cada uma checa `private.e_admin()` na primeira linha e
levanta erro se quem chamou não for admin. O advisor de segurança sinaliza essas três
funções; é intencional, e a autorização está dentro delas.

Já os auxiliares `private.e_admin()` e `private.usuario_liberado()`, usados dentro das
policies, ficam no schema **`private`**, que o PostgREST não expõe — assim não viram rota
em `/rest/v1/rpc/...`.

#### O que o painel faz

Aba **Administração**, visível apenas para admins:

- Planilha com todos os usuários, ordenável por qualquer coluna, com busca por nome,
  e-mail ou empresa, filtros por situação e exportação em CSV.
- Cartões de resumo: total, aprovados, aguardando, bloqueados e administradores.
- Ao clicar num usuário: quando assinou, se confirmou o e-mail, último login, último
  acesso, total de acessos, dispositivos usados sobre o limite, a lista de aparelhos (com
  tipo, navegador, sistema e região aproximada) e os últimos 20 acessos.
- Ações: aprovar/revogar, bloquear/desbloquear, mudar o limite de dispositivos, remover um
  aparelho para liberar vaga, e **tornar outro usuário administrador**.
- Aba **API**, documentando os endpoints REST já disponíveis.

Quem não está aprovado vê uma tela explicando que a conta aguarda liberação, em vez de uma
ferramenta vazia sem motivo aparente.

### Funções e triggers

| Objeto | O que faz |
| --- | --- |
| `public.handle_new_user()` | `security definer`, `set search_path = ''`. Lê `raw_user_meta_data ->> 'nome'` e `->> 'empresa'` e insere a linha em `profiles`. Strings vazias viram `null`. |
| `on_auth_user_created` | Trigger `after insert on auth.users` que dispara a função acima. |
| `public.handle_updated_at()` | `security definer`, `set search_path = ''`. Atualiza `updated_at = now()`. |
| `set_profiles_updated_at` | Trigger `before update on public.profiles`. |

**Permissões das funções.** As duas funções existem só para servir os triggers. Sem
revogar o `execute`, elas ficam expostas como RPC em `/rest/v1/rpc/...` — o que o
`get_advisors` acusa. Por isso a migration termina com:

```sql
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_updated_at() from public, anon, authenticated;
```

Depois disso o advisor de segurança fica limpo (nenhum lint).

---

## Configuração obrigatória no painel

Estes três passos **não** são aplicados pela migration — precisam ser feitos no painel do
Supabase.

### 1. URL Configuration (obrigatório)

**Authentication → URL Configuration**

Sem isso, todo link enviado por e-mail (confirmação de cadastro e redefinição de senha)
aponta para `http://localhost:3000` e **quebra**.

- **Site URL** — o endereço onde a página está publicada. Ex.:
  `https://cpusiscode.github.io/GUIA-SN/`
- **Redirect URLs** — adicione todas as origens de onde a ferramenta é aberta, uma por
  linha. Ex.:

  ```
  https://cpusiscode.github.io/GUIA-SN/**
  http://localhost:8000/**
  ```

O front-end envia `emailRedirectTo` e `redirectTo` como
`window.location.origin + window.location.pathname`. Esse endereço **precisa** casar com
alguma entrada de Redirect URLs, senão o Supabase devolve o usuário para a Site URL e o
link parece "não funcionar".

### 2. Confirmação de e-mail: manter ou desligar

**Authentication → Sign In / Providers → Email → "Confirm email"**

O front-end trata os **dois** cenários; a escolha é sua:

| | **Ligada** (padrão) | **Desligada** |
| --- | --- | --- |
| O que acontece | `signUp` devolve `session: null`. A tela avisa que o link foi enviado e volta para a aba **Entrar**. O usuário só entra depois de clicar no link. | `signUp` já devolve uma sessão e o usuário entra direto na ferramenta. |
| A favor | Confirma que o e-mail existe e é da pessoa; evita cadastro em massa com endereços falsos. | Cadastro sem atrito; ninguém trava por e-mail no spam. |
| Contra | Depende de entrega de e-mail. O SMTP padrão do Supabase é limitado (poucos e-mails por hora) e serve só para testes. | Qualquer um cria conta com e-mail inventado. |

**Recomendação:** manter **ligada** e, se o volume de cadastros crescer, configurar um
SMTP próprio em **Project Settings → Authentication → SMTP Settings**. O limite do
remetente padrão do Supabase costuma ser o primeiro problema em produção.

Se optar por desligar, o `Confirm email` fica em *off* e o template abaixo deixa de ser
usado.

### 3. Template do e-mail de confirmação

O arquivo [`supabase/templates/confirmacao-cadastro.html`](supabase/templates/confirmacao-cadastro.html)
tem o e-mail em português, no visual da ferramenta. Ele **não pode ser aplicado por API** —
precisa ser colado no painel:

1. Abra **Authentication → Emails** (aba **Templates**).
2. Selecione **Confirm signup**.
3. Em **Subject heading**, use algo como:
   `Confirme seu acesso ao GUIA-SN`
4. Clique em **Source** / `</>` para editar o HTML cru (não o editor visual).
5. Apague o conteúdo e cole o arquivo inteiro.
6. **Save**.

O template usa `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .Email }}` e
`{{ .Data.nome }}` — `{{ .Data }}` expõe o `raw_user_meta_data`, que é exatamente o que o
front-end manda em `options.data` do `signUp`.

> Se o cadastro for feito sem o campo nome preenchido, `{{ .Data.nome }}` renderiza vazio.
> O formulário exige nome, então na prática isso não acontece.

---

## Como funciona o front-end

Tudo vive no `index.html`, em dois blocos no fim do arquivo: o `<script>` do
supabase-js e o `<script>` do controle de acesso.

**Biblioteca.** Build UMD do jsDelivr com versão fixada:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.1/dist/umd/supabase.js"></script>
```

Versão fixada de propósito — `@2` solto puxaria qualquer minor futura sem aviso. O arquivo
é HTML puro, então nada de `import`/módulos: o UMD expõe `window.supabase.createClient`.

**Estrutura.** Todo o conteúdo original está dentro de `<div id="appRoot">`, que começa
com `hidden`. O `<div id="authGate">` é a tela de acesso, irmã do `appRoot`. Quem alterna
os dois é o `onAuthStateChange`.

**Sessão.** O cliente é criado com `persistSession`, `autoRefreshToken` e
`detectSessionInUrl`, e usa `storageKey: 'guia-sn-auth'` no `localStorage`.

### Dois detalhes que exigem atenção

1. **`INITIAL_SESSION`.** A sessão salva é restaurada pelo evento `INITIAL_SESSION` do
   `onAuthStateChange`, não por uma chamada avulsa a `getSession()`. Enquanto esse evento
   não chega, a tela mostra "Verificando acesso…" — é isso que evita o piscar da
   ferramenta antes de saber se há sessão.

2. **Nunca chamar `.from()` dentro do callback.** O supabase-js serializa as operações de
   auth; disparar uma consulta ao banco de dentro do callback de `onAuthStateChange`
   trava o cliente. A busca do perfil é adiada com `setTimeout(..., 0)`:

   ```js
   sb.auth.onAuthStateChange(function(evento, sessao){
     aplicarSessao(sessao);                                   // só mexe no DOM
     if(sessao && sessao.user){
       setTimeout(function(){ carregarPerfil(sessao.user); }, 0);
     }
   });
   ```

### O que a tela de acesso faz

- Abas **Entrar** e **Criar conta**.
- Cadastro com nome, empresa (opcional), e-mail e senha de 8+ caracteres com confirmação.
  Nome e empresa vão em `options.data` do `signUp`, de onde o trigger do banco os lê.
- Os dois fluxos de cadastro (com e sem confirmação de e-mail), descritos acima.
- Detecção de e-mail já cadastrado — com "Confirm email" ligado o Supabase responde
  sucesso, mas com `identities: []`; a tela traduz isso para uma mensagem clara.
- Redefinição de senha por `resetPasswordForEmail`.
- Barra no topo com nome/empresa/e-mail e botão **Sair**.
- **Mensagens de erro em português.** O Supabase responde em inglês
  (`Invalid login credentials`, `Email not confirmed`, `User already registered`, rate
  limits, etc.); há uma tabela de tradução por expressão regular no script.

O visual reaproveita as variáveis CSS `:root` já existentes (`--ink`, `--paper`, `--gold`,
`--mono`, `--serif`…), então a tela de login não destoa do resto da ferramenta.

---

## Estrutura do repositório

```
index.html                       a ferramenta + o controle de acesso + a base + o painel admin
README.md                        este arquivo
supabase/
  migrations/
    20260805133803_criar_tabela_profiles_com_rls_e_triggers.sql
    20260806130125_criar_tabela_ncm_e_versao.sql
    20260806130354_versionar_base_ncm_automaticamente.sql
    20260806133536_criar_admins_e_campos_de_controle.sql
    20260806133610_criar_dispositivos_e_acessos.sql
    20260806133659_policies_de_admin_e_funcoes_de_gestao.sql
    20260806133806_mover_helpers_de_rls_para_schema_privado.sql
    20260806134132_corrigir_limite_para_dispositivo_ja_conhecido.sql
  seed/
    ncm.json                     cópia versionada dos 10.687 NCMs
    README.md                    formato do arquivo e como recarregar a base
  templates/
    confirmacao-cadastro.html    e-mail de confirmação (colar no painel)
```

## Um aviso sobre o alcance do controle de acesso

O gate protege a **base fiscal**: sem login, `public.ncm` não é legível, então a
ferramenta não tem o que consultar. Isso é real, e vem do RLS.

O que ele não protege é o **código da página** — `index.html` continua sendo um arquivo
estático público, com a lógica de cálculo à vista de quem abrir o código-fonte. E, uma
vez sincronizada, a base fica guardada no `localStorage` daquele navegador, inclusive
depois do logout: é o preço de funcionar offline. Quem já entrou uma vez leva a base
consigo.

Em outras palavras: o login controla **quem consegue obter a base**, não o que a pessoa
faz com ela depois de obtida.

## Histórico de XMLs


Ao importar uma NF-e válida de até 5 MB, o XML original é guardado automaticamente
na conta autenticada. A seção **XMLs guardados** permite buscar por arquivo,
fornecedor, número ou chave da nota, reabrir os cálculos e baixar o arquivo original.
O histórico tem páginas de 20 registros e funciona entre aparelhos com a mesma conta.
**Limpar** apenas fecha o cálculo atual; não apaga o arquivo guardado.

A migration `supabase/migrations/20261111135429_guardar_xml_documentos_sn.sql` cria
`public.xml_documentos`, com os bytes originais em base64 e os metadados na mesma
linha. Assim não há upload órfão se a gravação falhar. Cada conta só pode inserir e
ler os próprios XMLs, e precisa continuar aprovada e não bloqueada. Nem o painel
admin ganha acesso aos XMLs de outras contas. Não há URLs públicas de download.
Chave de NF-e e SHA-256 impedem duplicados por usuário, sem sobrescrever originais.

O histórico requer rede e a migration aplicada no **FAROL-GUIA-SN**. Falhas de
gravação são exibidas explicitamente; o cálculo continua disponível quando a base
fiscal estiver carregada, e o usuário pode selecionar o arquivo novamente para
tentar guardar. XMLs importados antes desta atualização precisam ser reenviados,
pois o aplicativo antigo não conservava os arquivos. Alterações de preço e margem
feitas no cálculo não alteram o XML original guardado.
