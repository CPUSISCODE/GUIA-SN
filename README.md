# GUIA-SN — Consulta NCM · Simples Nacional (Acre)

Ferramenta fiscal de página única (`index.html`), sem build e sem dependências além de
CDN. Consulta NCM, importação de XML de NF-e, auditoria de cadastro e cálculo de custo
operacional, com as regras do RICMS/AC para empresas do Simples Nacional.

O acesso é controlado por **cadastro e login via Supabase**. Enquanto não houver sessão,
uma tela de acesso cobre toda a página; a ferramenta só aparece depois da autenticação.

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
index.html                       a ferramenta inteira + o controle de acesso
README.md                        este arquivo
supabase/
  migrations/
    20260805133803_criar_tabela_profiles_com_rls_e_triggers.sql
  templates/
    confirmacao-cadastro.html    e-mail de confirmação (colar no painel)
```
