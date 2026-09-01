-- 0045d · Dentro de um `security definer`, só `role` diz a verdade.
--
-- Terceira escrita da mesma guarda de dez linhas. As três merecem ficar
-- registradas, porque a lição não é sobre esta feature — é sobre como se
-- pergunta "quem está chamando" dentro deste banco, e a resposta certa não é
-- a intuitiva.
--
--   0045   `session_user is distinct from 'postgres'` — mede **quem abriu a
--          conexão**. `set role` não muda `session_user`, então qualquer
--          ferramenta conectada como postgres (o editor de SQL do Supabase,
--          o MCP) escapava da guarda inteira depois de um `set role`.
--
--   0045c  `current_user in ('authenticated','anon')` — mede o papel efetivo,
--          o que estaria certo em qualquer outro lugar. Mas a função é
--          `security definer`, e **dentro de um definer `current_user` é o
--          dono da função**, não o chamador. Vale `postgres` sempre, para
--          todo mundo. A guarda ficou medindo a si mesma.
--
--   0045d  `current_setting('role', true)`. Conferido no banco antes de
--          escrever, com uma sonda que chamou um definer de dentro de cada
--          papel:
--
--              caso            current_user   session_user   role
--              sem set role    postgres       postgres       none
--              authenticated   postgres       postgres       authenticated
--              service_role    postgres       postgres       service_role
--              anon            postgres       postgres       anon
--
--          As duas primeiras colunas são cegas. A terceira é a única que
--          enxerga o chamador — porque `role` é um GUC de sessão, e o
--          `security definer` troca o usuário, não os GUCs.
--
-- **A regra que fica, e ela vale para toda função `security definer` deste
-- banco:** para saber quem chamou, use `current_setting('role', true)`.
-- `current_user` e `session_user` respondem sobre a função e sobre a conexão,
-- nunca sobre a requisição.
--
-- A condição, agora, é a direta: o PostgREST executa **toda** requisição de
-- pessoa como `anon` ou `authenticated` — é assim que a RLS funciona neste
-- banco inteiro. Se o papel é um desses dois, tem gente do outro lado, e a
-- marca de operador não se concede. `service_role` e `none` (conexão
-- administrativa) passam.
--
-- E a função deixa de ser `security definer`: ela só lê `new` e `old`, nunca
-- precisou de privilégio nenhum. `definer` sem necessidade foi o que fez a
-- 0045c falhar, e é dívida em qualquer gatilho.
--
-- Achado pela verificação 4 da suíte 0045, duas vezes seguidas. Ela estava
-- certa as duas vezes.

create or replace function public.operador_nao_se_promove()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare papel text := coalesce(current_setting('role', true), 'none');
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
