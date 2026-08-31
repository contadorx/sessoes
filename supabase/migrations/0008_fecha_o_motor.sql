-- 0008 · Fecha o motor de materialização.
--
-- Três achados dos advisors depois da 0006, todos reais:
--
-- 1. `materializar_conta(uuid)` estava alcançável pelo **anônimo** em
--    /rest/v1/rpc, e é `security definer`: dava para mandar materializar a
--    agenda de outra conta passando o uuid dela. Não vazava conteúdo, mas
--    escrevia no tenant alheio.
--
--    A correção não é só revogar: é **parar de aceitar o tenant como
--    parâmetro**. Quem decide de que conta se está falando é `conta_atual()`,
--    nunca o cliente. Sem argumento não há como apontar para outro.
--
-- 2. `materializar_enquadre(uuid)` estava executável por `authenticated`. Os
--    gatilhos rodam como definidor e não precisam desse privilégio — só o
--    chamador de fora precisaria, e ninguém de fora deve chamar.
--
-- 3. `btree_gist` foi instalada no schema `public`. Vai para `extensions`, como
--    manda a convenção do Supabase. A restrição de exclusão guarda o OID do
--    operador, não o nome, então a mudança não a afeta.

-- ---------------------------------------------------------------- 1 e 2

drop function if exists public.materializar_conta(uuid);

create or replace function public.materializar_conta()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  minha_conta uuid := public.conta_atual();
  total int := 0;
begin
  if minha_conta is null then
    raise exception 'sem conta na sessão';
  end if;

  for r in
    select en.id
      from public.enquadres en
     where en.conta_id = minha_conta
       and en.vigencia_fim is null
  loop
    total := total + public.materializar_enquadre(r.id);
  end loop;

  return total;
end;
$$;

revoke execute on function public.materializar_conta() from public, anon;
grant execute on function public.materializar_conta() to authenticated;

revoke execute on function public.materializar_enquadre(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3

create schema if not exists extensions;
alter extension btree_gist set schema extensions;
