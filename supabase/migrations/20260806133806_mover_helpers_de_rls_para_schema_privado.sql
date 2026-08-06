-- e_admin() e usuario_liberado() existem só para serem chamadas de dentro das
-- policies. Enquanto viviam em public elas ganhavam rota em /rest/v1/rpc/... —
-- que é o que o advisor acusa. O schema private não é exposto pelo PostgREST,
-- então some a rota; a role authenticated continua com EXECUTE porque as
-- policies são avaliadas com os privilégios de quem consulta.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.e_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.id = (select auth.uid()));
$$;

create or replace function private.usuario_liberado()
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

revoke all on function private.e_admin()          from public;
revoke all on function private.usuario_liberado() from public;
grant execute on function private.e_admin()          to authenticated;
grant execute on function private.usuario_liberado() to authenticated;

-- Refaz as policies apontando para o schema privado.
drop policy if exists "Admins veem a lista de admins" on public.admins;
create policy "Admins veem a lista de admins"
  on public.admins for select to authenticated
  using ( private.e_admin() );

drop policy if exists "Admin vê todos os perfis" on public.profiles;
create policy "Admin vê todos os perfis"
  on public.profiles for select to authenticated
  using ( private.e_admin() );

drop policy if exists "Admin atualiza qualquer perfil" on public.profiles;
create policy "Admin atualiza qualquer perfil"
  on public.profiles for update to authenticated
  using ( private.e_admin() ) with check ( private.e_admin() );

drop policy if exists "Usuário vê os próprios dispositivos" on public.dispositivos;
create policy "Usuário vê os próprios dispositivos"
  on public.dispositivos for select to authenticated
  using ( (select auth.uid()) = user_id or private.e_admin() );

drop policy if exists "Admin remove dispositivos" on public.dispositivos;
create policy "Admin remove dispositivos"
  on public.dispositivos for delete to authenticated
  using ( private.e_admin() );

drop policy if exists "Usuário vê os próprios acessos" on public.acessos;
create policy "Usuário vê os próprios acessos"
  on public.acessos for select to authenticated
  using ( (select auth.uid()) = user_id or private.e_admin() );

drop policy if exists "Usuários aprovados podem ler a base de NCMs" on public.ncm;
create policy "Usuários aprovados podem ler a base de NCMs"
  on public.ncm for select to authenticated
  using ( private.usuario_liberado() );

-- Funções que dependiam das versões em public.
create or replace function public.proteger_campos_de_controle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not private.e_admin() then
    if new.aprovado            is distinct from old.aprovado
    or new.bloqueado           is distinct from old.bloqueado
    or new.limite_dispositivos is distinct from old.limite_dispositivos
    or new.observacao          is distinct from old.observacao then
      raise exception 'Apenas administradores podem alterar aprovação, bloqueio, limite de dispositivos ou observação.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.listar_usuarios()
returns table (
  id uuid, email text, nome text, empresa text,
  aprovado boolean, bloqueado boolean, limite_dispositivos integer,
  admin boolean, email_confirmado boolean,
  assinou_em timestamptz, ultimo_login timestamptz,
  dispositivos integer, total_acessos bigint, ultimo_acesso timestamptz,
  observacao text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;
  return query
  select u.id, u.email::text, p.nome, p.empresa,
         coalesce(p.aprovado, false), coalesce(p.bloqueado, false),
         coalesce(p.limite_dispositivos, 2),
         (a.id is not null), (u.email_confirmed_at is not null),
         u.created_at, u.last_sign_in_at,
         coalesce(d.n, 0)::integer, coalesce(ac.n, 0), ac.ultimo, p.observacao
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.admins   a on a.id = u.id
  left join (select user_id, count(*) n from public.dispositivos group by 1) d on d.user_id = u.id
  left join (select user_id, count(*) n, max(quando) ultimo from public.acessos group by 1) ac on ac.user_id = u.id
  order by u.created_at desc;
end;
$$;

create or replace function public.promover_admin(p_email text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not private.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;
  select u.id into v_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'Não existe usuário com o e-mail %.', p_email using errcode = 'P0002';
  end if;
  insert into public.admins (id, criado_por) values (v_id, (select auth.uid()))
  on conflict (id) do nothing;
  update public.profiles set aprovado = true, bloqueado = false where id = v_id;
  return v_id;
end;
$$;

create or replace function public.rebaixar_admin(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_total integer;
begin
  if not private.e_admin() then
    raise exception 'Acesso restrito a administradores.' using errcode = '42501';
  end if;
  select count(*) into v_total from public.admins;
  if v_total <= 1 then
    raise exception 'Não é possível remover o último administrador.' using errcode = 'P0001';
  end if;
  delete from public.admins where id = p_id;
end;
$$;

drop function if exists public.e_admin();
drop function if exists public.usuario_liberado();
