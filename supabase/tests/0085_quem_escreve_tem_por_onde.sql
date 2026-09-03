-- Teste da classe inteira: quem escreve tem por onde (migrações 0084 e 0085).
--
-- **Este arquivo é uma varredura, e é a única verificação dele que interessa.**
-- Os dois defeitos que ele fecha — o link que não se revoga e a vaga fixa que
-- não abre em base nova — não têm nada em comum na tela e têm tudo em comum no
-- banco: uma função escreve numa tabela por onde a RLS não a deixa passar, e a
-- RLS **filtra em vez de recusar**. Zero linhas, zero erro, e a função devolve
-- sucesso.
--
-- É a lei 8 com o banco no lugar do adaptador: *adaptador ausente recusa, não
-- finge*. O `insert` grita; o `update` e o `delete` mentem.
--
--   1. nenhuma função alcançável por ela escreve onde a RLS não deixa  ← decide
--   2. esquecer_contato revoga o link de verdade                       ← S1-2
--   3. e a página fecha para quem está com o token na mão              ← S1-2
--   4. ofertas_fixas tem as três policies, como ofertas                ← S1-1
--   5. a decisão da 0066 continua de pé: links_do_paciente sem escrita
--
-- A **1** é a que sobrevive às outras quatro. Ela não lista função nenhuma:
-- lê o `pg_proc`, acha os `insert`/`update`/`delete` no corpo, e cobra a
-- policy correspondente — **e só para quem `authenticated` consegue chamar**,
-- que é a pergunta que separa doze achados de dois. Uma função que só o cron
-- chama roda como `service_role`, e ali não há RLS no caminho.
--
-- A **4** é o S1-1, e ele é especial: no banco de produção ele não reproduz,
-- porque as duas policies estavam vivas lá **sem estar em migração nenhuma**.
-- Era a lei 5 furada, e a 0084 fechou. Em base nova, sem a 0084, esta
-- verificação reprova — que é exatamente o ponto.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0085_quem_escreve_tem_por_onde.sql

do $do$
declare
  v_ela   uuid := '22222222-2222-4222-8222-222222222285';
  v_conta uuid; v_prof uuid; v_pac uuid;
  v_tok text; v_rev timestamptz; v_r text; v_est text;
  v_erro text; v_n integer;
begin

-- ------------------------------------------------------------------------ 1
--
-- A varredura. Enumerar as funções aqui seria repetir o erro: a décima terceira
-- entraria sem ninguém notar, que é como o `update` cru da 0076 entrou.
select string_agg(x.linha, E'\n  ' order by x.linha), count(*)::integer
  into v_erro, v_n
  from (
    select distinct
           a.tabela || ' · ' || a.cmd || ' · ' || a.proname as linha
      from (
        select p.oid, p.proname,
               lower(split_part(m[1], ' ', 1)) as cmd,
               m[2] as tabela
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
          cross join lateral regexp_matches(
            pg_get_functiondef(p.oid),
            '\m(insert\s+into|update|delete\s+from)\s+public\.([a-z_]+)', 'gi') m
         where p.prokind = 'f'
           -- `security definer` roda como o dono e não passa por policy.
           and not p.prosecdef
           -- E o que só o cron chama roda como `service_role`, onde não há RLS
           -- no caminho. É esta linha que separa doze achados de dois.
           and has_function_privilege('authenticated', p.oid, 'execute')
      ) a
      join pg_class c
        on c.relname = a.tabela and c.relrowsecurity
      join pg_namespace n2
        on n2.oid = c.relnamespace and n2.nspname = 'public'
     where not exists (
       select 1
         from pg_policy pol
         join pg_class c2 on c2.oid = pol.polrelid
        where c2.relname = a.tabela
          -- `polroles = {0}` é a policy sem cláusula `TO`, que vale para
          -- PUBLIC e portanto também para ela.
          and (pol.polroles = '{0}'::oid[]
               or exists (select 1 from pg_roles r
                           where r.oid = any(pol.polroles) and r.rolname = 'authenticated'))
          and (pol.polcmd = '*'
               or pol.polcmd = case a.cmd when 'insert' then 'a'
                                          when 'update' then 'w'
                                          when 'delete' then 'd' end)
     )
  ) x;

if v_n > 0 then
  raise exception 'FALHOU 1: % função(ões) invoker escrevem onde a RLS não deixa passar, e a RLS filtra em vez de recusar — zero linhas, zero erro, sucesso devolvido:%  %', v_n, E'\n  ', v_erro;
end if;

-- ------------------------------------------------------------------------ 4
--
-- O S1-1, dito como igualdade: a vaga fixa nasceu como cópia da fila de
-- encaixe, e a 0036 copiou as funções e deixou as policies. Comparar as duas
-- tabelas é mais forte que exigir três policies, porque no dia em que
-- `ofertas` ganhar uma quarta, esta verificação cobra a quarta na irmã.
select string_agg(f.cmd, ', ' order by f.cmd), count(*)::integer
  into v_erro, v_n
  from (
    select case pol.polcmd when 'r' then 'select' when 'a' then 'insert'
                           when 'w' then 'update' when 'd' then 'delete'
                           else 'all' end as cmd
      from pg_policy pol join pg_class c on c.oid = pol.polrelid
     where c.relname = 'ofertas'
    except
    select case pol.polcmd when 'r' then 'select' when 'a' then 'insert'
                           when 'w' then 'update' when 'd' then 'delete'
                           else 'all' end
      from pg_policy pol join pg_class c on c.oid = pol.polrelid
     where c.relname = 'ofertas_fixas'
  ) f;

if v_n > 0 then
  raise exception 'FALHOU 4: ofertas_fixas não tem policy de % que ofertas tem — a vaga fixa copiou as funções da fila de encaixe e não as policies, e os três update da tabela afetam zero linhas devolvendo sucesso', v_erro;
end if;

-- ------------------------------------------------------------------------ 5
--
-- E a decisão da 0066 tem de continuar de pé. O conserto do S1-2 poderia ter
-- sido "dá policy de escrita para links_do_paciente", e teria sido o errado:
-- abriria a tabela do token para todo update que passar.
select count(*)::integer into v_n
  from pg_policy pol join pg_class c on c.oid = pol.polrelid
 where c.relname = 'links_do_paciente' and pol.polcmd <> 'r';

if v_n > 0 then
  raise exception 'FALHOU 5: links_do_paciente ganhou % policy de escrita — a 0066 decidiu que quem cria e revoga são as funções definer, e o token não é campo de update solto', v_n;
end if;

-- ------------------------------------------------------------- 2 e 3, ao vivo
delete from auth.users where id = v_ela;
delete from public.contas where nome = 'Quem Escreve 0085';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_ela, 'quemescreve@teste.sessoes.com.br', '{"nome":"Quem Escreve 0085"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_ela;
update public.contas set nome = 'Quem Escreve 0085' where id = v_conta;
select p.id into v_prof from public.profissionais p where p.conta_id = v_conta limit 1;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, telefone)
  values (v_conta, v_prof, 'Belmiro Tanquinho Nepomuceno', '5511922221111')
  returning id into v_pac;

-- Pela porta de verdade: quem cria o link é a função da 0066, porque a tabela
-- não tem policy de insert — e é a mesma razão pela qual o `update` cru mentia.
select public.abrir_link_do_paciente(v_pac) into v_tok;
select public.esquecer_contato(v_pac) into v_r;

reset role;

if v_r not like '%revogad%' then
  raise exception 'FALHOU 2: a frase de retorno parou de prometer a revogação (%) — se a promessa saiu, esta verificação muda junto', v_r;
end if;

select revogado_em into v_rev from public.links_do_paciente where paciente_id = v_pac;
if v_rev is null then
  raise exception 'FALHOU 2: a função devolveu "%" e revogado_em continua vazio — a RLS filtrou o update em vez de recusá-lo', v_r;
end if;

-- ------------------------------------------------------------------------ 3
--
-- E a conferência que importa não é a coluna: é a porta. Quem tem o token na
-- mão é um visitante `anon`, e é por ele que a página abre.
set local role anon;
select (public.pagina_do_paciente(v_tok) ->> 'estado') into v_est;
reset role;

if v_est = 'aberta' then
  raise exception 'FALHOU 3: depois de "o link do paciente revogado", a página continua aberta para quem tem o token — cobrança com Pix, sessões a confirmar e documentos dos últimos 90 dias';
end if;

-- ------------------------------------------------------------------------ fim
delete from public.contas where id = v_conta;
delete from auth.users where id = v_ela;

raise notice 'OK · 0085 · quem escreve tem por onde — e a RLS voltou a recusar em vez de filtrar';
end
$do$;
