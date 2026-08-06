-- O trigger BEFORE INSERT dispara antes de o Postgres avaliar o ON CONFLICT.
-- Sem esta checagem, um upsert de um dispositivo JÁ registrado bateria no limite
-- e o usuário seria barrado no próprio aparelho de sempre.
create or replace function public.checar_limite_dispositivos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limite integer;
  v_atual  integer;
begin
  -- Aparelho já conhecido: é reconexão, não ocupa vaga nova.
  if exists (
    select 1 from public.dispositivos d
    where d.user_id = new.user_id and d.impressao = new.impressao
  ) then
    return new;
  end if;

  select coalesce(p.limite_dispositivos, 2) into v_limite
  from public.profiles p where p.id = new.user_id;
  if v_limite is null then v_limite := 2; end if;

  select count(*) into v_atual
  from public.dispositivos d where d.user_id = new.user_id;

  if v_atual >= v_limite then
    raise exception 'Limite de % dispositivo(s) atingido para este usuário.', v_limite
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.checar_limite_dispositivos() from public, anon, authenticated;
