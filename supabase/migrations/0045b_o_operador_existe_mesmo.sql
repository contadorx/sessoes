-- 0045b · O operador existe mesmo.
--
-- A 0045 escreveu `e_operador()` assim:
--
--     select coalesce(bool_or(u.operador), false) into r
--       from public.usuarios u
--      where u.usuario_id = auth.uid();
--
-- `public.usuarios` não tem coluna `usuario_id`. A coluna que aponta para
-- `auth.users` chama-se `auth_user_id` desde a B2; `usuario_id` existe em
-- `profissionais`, e aponta para outra coisa. Erro de nome, banal.
--
-- **O que não é banal é o que ele teria feito.** A função termina com:
--
--     exception when others then
--       return false;
--
-- Esse tratamento está certo e continua aqui: falha em checagem de permissão
-- tem de virar negativa, nunca liberação. Só que ele também engole o erro de
-- coluna. O resultado: `e_operador()` devolveria **false para sempre**, o
-- painel do negócio responderia "só o operador vê o painel" a mim mesmo, e
-- não haveria erro nenhum em lugar nenhum para investigar. Eu procuraria o
-- defeito na marca do usuário, na RLS, no grant — em tudo menos numa função
-- que estava fazendo exatamente o que eu mandei.
--
-- É a mesma família da lição da B11 (policy faltando devolve zero linha, não
-- erro) e da B26 (o `exception when others` do `importar_historico` escondendo
-- uma coluna inexistente por uma build inteira). O padrão que se repete:
-- **todo tratamento de erro que converte falha em resposta segura também
-- converte defeito em silêncio.**
--
-- A correção tem duas partes, e a segunda importa mais que a primeira:
--
--   1. o nome certo da coluna;
--   2. o `exception` deixa de ser cego. Erro de permissão continua devolvendo
--      false; **erro de programação (`undefined_column`, `undefined_table`,
--      `undefined_function`) estoura.** A distinção é a que faltava: uma
--      função de segurança pode falhar fechada sem por isso ter de mentir
--      sobre estar quebrada.
--
-- Achado pela verificação 3 da suíte 0045 — que só a encontrou porque a suíte
-- cria usuário de verdade em vez de confiar no catálogo.

create or replace function public.e_operador()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r boolean;
begin
  select coalesce(bool_or(u.operador), false) into r
    from public.usuarios u
   where u.auth_user_id = auth.uid();
  return coalesce(r, false);

exception
  -- Defeito meu não vira "não autorizado": estoura, e eu conserto.
  when undefined_column or undefined_table or undefined_function then
    raise;
  -- Qualquer outra coisa — inclusive não haver sessão — é negativa.
  when others then
    return false;
end;
$$;

revoke execute on function public.e_operador() from public, anon;
grant execute on function public.e_operador() to authenticated;
