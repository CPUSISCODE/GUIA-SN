# Prompt para o GUIA-LP — painel de administração

> Copie tudo a partir da linha divisória e envie no chat responsável pelo GUIA-LP.
> Este prompt pressupõe que o prompt anterior (mover a base de NCMs para o Supabase) já
> foi executado lá.

---

Implemente no GUIA-LP o painel de administração que já existe no GUIA-SN. **Siga a mesma
lógica e o mesmo desenho visual**, para os dois não divergirem.

**Não presuma que o LP é idêntico ao SN. Inspecione o repositório real antes de decidir
qualquer coisa.** Use `list_projects` e trabalhe no projeto `FAROL-GUIA-LP` — não toque no
`FAROL-GUIA-SN`.

Não altere a lógica fiscal, o gate de autenticação nem a barra de usuário. O trabalho é
acrescentar administração.

## Banco

### Tabela `public.admins`

`id uuid primary key references auth.users(id) on delete cascade`, `criado_em`,
`criado_por`.

**Ponto crítico: não coloque a flag de admin em `profiles`.** Os usuários têm policy de
`update` no próprio perfil, então uma coluna `admin` ali seria auto-atribuível e qualquer
um viraria admin sozinho. A tabela `admins` não pode ter nenhuma policy de escrita para o
cliente — entrar e sair dela só acontece pelas funções abaixo.

### Campos de controle em `public.profiles`

`aprovado boolean not null default false`, `bloqueado boolean not null default false`,
`limite_dispositivos integer not null default 2 check (between 1 and 20)` e
`observacao text`.

Proteja os quatro com um trigger `before update` que recusa a alteração quando quem
está atualizando não é admin. **Atenção:** libere quando `(select auth.uid()) is null` —
isso significa operação do servidor (migration, `service_role`), não requisição de
navegador. Sem essa ressalva, a própria migration que aprova o primeiro admin é barrada
pelo trigger que ela acabou de criar (aconteceu comigo).

### `public.dispositivos` e `public.acessos`

`dispositivos`: `impressao text` (id aleatório guardado no navegador — não é
fingerprinting), `tipo` (celular/tablet/computador/desconhecido), `navegador`, `sistema`,
`fuso`, `user_agent`, `primeiro_acesso`, `ultimo_acesso`, com `unique (user_id, impressao)`.

`acessos`: um registro por entrada, com `dispositivo_id`, `quando`, `tipo` e `fuso`.

**O limite de dispositivos tem de ser aplicado por trigger no banco**, não no navegador —
checagem em JS é contornada pelo devtools em cinco segundos.

**Armadilha do Postgres:** o `BEFORE INSERT` dispara *antes* de o `ON CONFLICT` ser
avaliado. Se o trigger só contar dispositivos, um upsert de aparelho **já registrado**
bate no limite e barra o usuário no computador de sempre. O trigger precisa retornar cedo
quando a `impressao` já existir para aquele usuário.

### Travar a base pela aprovação

Crie `usuario_liberado()` (`aprovado and not bloqueado`) e troque a policy de `select` da
tabela de NCMs para usá-la. **É isto que faz "permitir acessos" virar barreira de verdade**
em vez de aviso na tela: sem aprovação o RLS nega a base e não há o que a ferramenta
consulte.

### Funções do painel

- `listar_usuarios()` — a planilha. Junta `auth.users` (e-mail, `last_sign_in_at`,
  `email_confirmed_at`) com o perfil e os totais de dispositivos e acessos.
- `promover_admin(p_email text)` — torna alguém admin pelo e-mail; já deixa aprovado e
  desbloqueado, senão o novo admin fica sem acesso à base.
- `rebaixar_admin(p_id uuid)` — **recuse remover o último admin**, senão o sistema fica
  sem ninguém que possa administrar.

As três são `security definer`, precisam ser chamáveis por `authenticated` (é assim que o
painel funciona) e devem checar admin na primeira linha, levantando erro com
`errcode = '42501'`.

### O advisor e o schema `private`

Os auxiliares usados **dentro das policies** (`e_admin`, `usuario_liberado`) não podem
ficar em `public`: lá eles ganham rota em `/rest/v1/rpc/...` e o `get_advisors` acusa.
Mova-os para um schema `private` (que o PostgREST não expõe), com
`grant usage on schema private to authenticated` e `grant execute` nas funções — a role
precisa do EXECUTE porque as policies são avaliadas com os privilégios de quem consulta.

Não tente eliminar os avisos das três funções do painel: elas **precisam** ser chamáveis,
e a autorização está dentro delas. Documente isso em vez de silenciar.

Rode `get_advisors` com type `security` no fim.

### Promova o admin inicial

Insira em `admins` o usuário que o dono indicar, e deixe o perfil dele aprovado.

## Frontend

Aba **Administração** ao lado das existentes, com `hidden` por padrão e revelada só quando
a consulta a `admins` devolver linha (a policy já garante que só admin recebe algo).

Reaproveite as variáveis CSS `:root` que já existem. No SN as classes ficaram `.adm-*`,
com pílulas de situação (`.pill.ok/.pend/.no/.adm`) e a tabela em `.adm-tabela` com
cabeçalho `sticky` e `overflow-x:auto` no contêiner.

Conteúdo:

- Cartões de resumo: total, aprovados, aguardando, bloqueados, administradores.
- Planilha ordenável por qualquer coluna (clique alterna a direção), busca por nome/e-mail/
  empresa, filtro por situação e exportação em CSV (com BOM, separador `;`).
- Ao clicar num usuário: quando assinou, se confirmou o e-mail, último login, último
  acesso, total de acessos, dispositivos sobre o limite, lista de aparelhos e últimos
  acessos.
- Ações: aprovar/revogar, bloquear/desbloquear, alterar limite, remover aparelho e
  **tornar outro usuário administrador**.
- Aba **API** documentando os endpoints REST que o PostgREST já expõe.

Quem não estiver aprovado deve ver uma tela explicando a situação, no lugar da ferramenta,
em vez de uma página vazia sem motivo aparente. Trate também o caso de bloqueio e o de
limite de dispositivos atingido, com textos diferentes.

Registre o dispositivo e o acesso no login: **tente o `update` primeiro** e só insira se
nada for atualizado — é o insert que passa pelo limite no banco. Faça isso dentro do mesmo
`setTimeout(..., 0)` já usado para o perfil.

Dois detalhes que custaram tempo no SN:

1. **A mensagem de confirmação some.** Se você escrever a mensagem de sucesso e em seguida
   recarregar a lista, o recarregamento reconstrói o HTML do detalhe e leva o elemento da
   mensagem junto. Escreva a mensagem **depois** que o recarregamento resolver.
2. **Limpe o estado de admin no logout** — esconda a aba, zere a seleção e limpe o
   detalhe. Senão o próximo usuário a entrar naquele navegador vê resquícios do anterior.

## Testes

Não entregue sem testar. Playwright com as rotas mockadas, cobrindo:

- aba escondida para quem não é admin, visível para admin;
- planilha carregando, resumo correto, filtros, busca e ordenação;
- detalhe do usuário com dispositivos e acessos;
- aprovar, bloquear, alterar limite (inclusive valor fora da faixa) e promover a admin;
- conta não aprovada, conta bloqueada e limite de dispositivos atingido;
- exportação CSV e aba API.

Teste também a **autorização no próprio banco**, com SQL, simulando um usuário comum via
`set local role authenticated` e `set local request.jwt.claims`. É o teste que importa:
prove que um usuário comum não consegue listar usuários, não se promove a admin, não se
auto-aprova, não aumenta o próprio limite, não lê a base sem aprovação, não enxerga perfis
alheios e não registra dispositivo para outra pessoa — mas continua editando o próprio
nome. Apague os usuários de teste depois.

## Entrega

Commits em português, descritivos. README documentando as tabelas, o motivo de a flag de
admin ficar fora de `profiles`, o schema `private`, e o que o painel faz. Suba para a
branch e **pergunte antes de abrir PR ou mergear**.

Seja honesto sobre dois limites, como fiz no SN:

- **A "região" não vem do IP.** Sem servidor próprio, o que dá para captar é o fuso do
  navegador (`Intl.DateTimeFormat().resolvedOptions().timeZone`), que é aproximação
  regional e vem do cliente — falsificável. Serve de visibilidade operacional, não de
  prova. Região por IP exigiria uma Edge Function.
- **Guardar IP, localização e dispositivo de usuário identificado é dado pessoal sob a
  LGPD** e precisa estar declarado para o usuário.
