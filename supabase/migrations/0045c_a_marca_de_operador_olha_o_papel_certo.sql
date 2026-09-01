-- 0045c · A marca de operador olha o papel certo.
--
-- A 0045 protegeu `usuarios.operador` assim:
--
--     if current_setting('role', true) is distinct from 'service_role'
--        and session_user is distinct from 'postgres' then
--       raise exception ...
--
-- A intenção era "só a service_role concede". A escrita diz outra coisa:
-- **basta o `session_user` ser `postgres` para a guarda inteira se calar** —
-- e `session_user` não muda com `set role`. Ele é quem abriu a conexão, não
-- quem está executando.
--
-- Na prática isso significa que, numa conexão aberta como `postgres` (o editor
-- de SQL do Supabase, o MCP, qualquer ferramenta administrativa), um
-- `set role authenticated` seguido de um UPDATE passaria pela guarda. O papel
-- efetivo seria `authenticated` e a proteção não olhava para ele.
--
-- Achado pela verificação 4 da suíte, que fez exatamente isso e acusou "ela se
-- promoveu a operadora por PATCH". O teste estava certo; a guarda é que
-- media a coisa errada.
--
-- **A pergunta certa não é "quem abriu a conexão", é "com que papel esta
-- requisição está rodando".** O PostgREST executa toda requisição de pessoa
-- como `anon` ou `authenticated`, sempre — é assim que a RLS funciona neste
-- banco inteiro. Então a condição é direta: se o papel efetivo é um dos dois
-- papéis por onde entra gente, a marca não se concede. `service_role` e
-- `postgres` passam, que é o que se queria desde o começo.
--
-- `current_user` é o papel efetivo (muda com `set role`); `session_user` é o
-- da conexão (não muda). A troca de um pelo outro é a correção inteira.

create or replace function public.operador_nao_se_promove()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare papel text := current_user;
begin
  -- plpgsql NÃO faz curto-circuito: `tg_op = 'UPDATE' and old.operador ...`
  -- estouraria "record old is not assigned yet" no INSERT. Lição da 0041.
  if tg_op = 'UPDATE' then
    if new.operador is distinct from old.operador then
      if papel in ('authenticated', 'anon') then
        raise exception 'a marca de operador não se concede por aqui';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.operador then
      if papel in ('authenticated', 'anon') then
        raise exception 'usuário não nasce operador';
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.operador_nao_se_promove() from public, anon, authenticated;
