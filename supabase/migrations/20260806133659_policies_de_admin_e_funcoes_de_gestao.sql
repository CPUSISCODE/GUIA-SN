-- Visibilidade do admin sobre os perfis (policies são somadas com OR, então
-- estas convivem com as que restringem cada usuário ao próprio perfil).
--
-- NOTA: as referências a public.e_admin()/public.usuario_liberado() foram
-- trocadas por private.* na migration 20260806133806.

drop policy if exists "Admin vê todos os perfis" on public.profiles;
create policy "Admin vê todos os perfis"
  on public.profiles for select to authenticated
  using ( public.e_admin() );

drop policy if exists "Admin atualiza qualquer perfil" on public.profiles;
create policy "Admin atualiza qualquer perfil"
  on public.profiles for update to authenticated
  using ( public.e_admin() )
  with check ( public.e_admin() );

-- A base fiscal passa a exigir aprovação. É aqui que "permitir acessos" vira
-- barreira de verdade: sem aprovação o select em public.ncm é negado pelo RLS,
-- e não há o que a ferramenta consulte.
create or replace function public.usuario_liberado()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.aprovado and not p.bloqueado
  );
$$;

revoke all on function public.usuario_liberado() from public, anon;

drop policy if exists "Usuários autenticados podem ler a base de NCMs" on public.ncm;
create policy "Usuários aprovados podem ler a base de NCMs"
  on public.ncm for select to authenticated
  using ( public.usuario_liberado() );

-- Planilha do painel: junta auth.users (e-mail, último login, confirmação) com
-- o perfil e os totais de dispositivos e acessos. security definer porque o
-- cliente não enxerga auth.users; a checagem de admin está dentro.
create or replace function public.listar_usuarios()
returns table (
  id                  uuid,
  email               text,
  nome                text,
  empresa             text,
  aprovado            boolean,
  bloqueado           boolean,
  limite_dispositivos integer,
  admin               boolean,
  email_confirmado    boolean,
  assinou_em          timestamptz,
  ultimo_login        timestamptz,
  dispositivos        integer,
  total_acessos       bigint,
  ultimo_acesso       timestamptz,
  observacao          text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;

  return query
  select u.id,
         u.email::text,
         p.nome,
         p.empresa,
         coalesce(p.aprovado, false),
         coalesce(p.bloqueado, false),
         coalesce(p.limite_dispositivos, 2),
         (a.id is not null),
         (u.email_confirmed_at is not null),
         u.created_at,
         u.last_sign_in_at,
         coalesce(d.n, 0)::integer,
         coalesce(ac.n, 0),
         ac.ultimo,
         p.observacao
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.admins   a on a.id = u.id
  left join (select user_id, count(*) n from public.dispositivos group by 1) d  on d.user_id  = u.id
  left join (select user_id, count(*) n, max(quando) ultimo from public.acessos group by 1) ac on ac.user_id = u.id
  order by u.created_at desc;
end;
$$;

-- Promover outro usuário a admin, pelo e-mail.
create or replace function public.promover_admin(p_email text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;

  select u.id into v_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'Não existe usuário com o e-mail %.', p_email using errcode = 'P0002';
  end if;

  insert into public.admins (id, criado_por) values (v_id, (select auth.uid()))
  on conflict (id) do nothing;

  -- Admin sempre entra aprovado e desbloqueado, senão fica sem acesso à base.
  update public.profiles set aprovado = true, bloqueado = false where id = v_id;

  return v_id;
end;
$$;

-- Rebaixar um admin, com trava para não sobrar nenhum.
create or replace function public.rebaixar_admin(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total integer;
begin
  if not public.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;

  select count(*) into v_total from public.admins;
  if v_total <= 1 then
    raise exception 'Não é possível remover o último administrador.' using errcode = 'P0001';
  end if;

  delete from public.admins where id = p_id;
end;
$$;

revoke all on function public.listar_usuarios()    from public, anon;
revoke all on function public.promover_admin(text) from public, anon;
revoke all on function public.rebaixar_admin(uuid) from public, anon;
