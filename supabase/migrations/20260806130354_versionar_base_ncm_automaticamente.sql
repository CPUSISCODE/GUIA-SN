-- A versão da base é o md5 do conteúdo inteiro. O navegador guarda a base no
-- localStorage junto com essa versão; se ela mudar, o cache é descartado e a
-- base é baixada de novo. Recalcular por trigger evita cache velho caso alguém
-- edite a tabela e esqueça de atualizar a versão na mão.

create or replace function public.recalcular_versao_ncm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_versao text;
  v_total  integer;
begin
  select md5(coalesce(string_agg(
           n.ncm || '|' || n.descricao || '|' || coalesce(n.segmento, '') || '|' ||
           coalesce(n.mva::text, '') || '|' || coalesce(n.monofasico, ''),
           E'\n' order by n.ncm), '')),
         count(*)
    into v_versao, v_total
  from public.ncm n;

  insert into public.ncm_versao (id, versao, total, atualizado_em)
  values (true, v_versao, v_total, now())
  on conflict (id) do update
    set versao = excluded.versao,
        total = excluded.total,
        atualizado_em = excluded.atualizado_em;

  return null;
end;
$$;

drop trigger if exists ncm_versao_sync on public.ncm;
create trigger ncm_versao_sync
  after insert or update or delete or truncate on public.ncm
  for each statement
  execute function public.recalcular_versao_ncm();

revoke all on function public.recalcular_versao_ncm() from public, anon, authenticated;

-- Primeira carga da versão, já que os dados entraram antes do trigger existir.
insert into public.ncm_versao (id, versao, fonte, total, atualizado_em)
select true,
       md5(string_agg(
         n.ncm || '|' || n.descricao || '|' || coalesce(n.segmento, '') || '|' ||
         coalesce(n.mva::text, '') || '|' || coalesce(n.monofasico, ''),
         E'\n' order by n.ncm)),
       'RICMS/AC 06/2026 + SPED 4.3.x + NCM v4 (descrições normalizadas)',
       count(*),
       now()
from public.ncm n
on conflict (id) do update
  set versao = excluded.versao,
      fonte = excluded.fonte,
      total = excluded.total,
      atualizado_em = excluded.atualizado_em;
