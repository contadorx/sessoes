-- Teste da lei 2, varrida do catálogo (migração 0077).
--
-- Esta suíte não tem conta de teste, não insere linha e não apaga nada. Ela é
-- de uma família diferente das outras 45: em vez de provar um comportamento,
-- ela **varre o catálogo** e reprova o que a lei 2 do `CLAUDE.md` proíbe.
--
--     "RLS desde a primeira tabela. Função `security definer` sempre com
--      `search_path` fixado; políticas com `(select auth.uid())`; FK sempre
--      indexada."
--
-- As três metades da lei eram verdade quando cada build passou, e nenhuma
-- delas era conferida depois. O resultado, medido em 03/09: **vinte** chaves
-- estrangeiras sem índice, nascidas em quinze builds diferentes, nenhuma
-- encontrada lendo código.
--
-- É o mesmo remédio da lei 7 — varrer o catálogo em vez de conferir por lista
-- escrita à mão — aplicado à lei 2. Uma suíte que enumerasse as FKs de hoje
-- estaria errada na próxima tabela.
--
--    1. toda tabela de `public` com RLS ligada
--    2. toda FK com índice de cobertura                                ← decide
--    3. todo `security definer` com search_path fixado
--    4. toda política de leitura sem `auth.uid()` nu
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0077_a_lei_2_se_varre.sql

do $do$
declare
  v_txt text;
begin

-- ------------------------------------------------------------------------ 1
select string_agg(c.relname, ', ' order by c.relname) into v_txt
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

if v_txt is not null then
  raise exception 'FALHOU 1: tabela sem RLS: %', v_txt;
end if;

-- ------------------------------------------------------------------------ 2
--
-- A conferência é "existe índice cujas colunas iniciais são exatamente as da
-- chave". Índice parcial conta: `col = X` implica `col is not null`, e o
-- planejador usa o índice parcial para a checagem da FK — é o padrão da 0045e
-- e o da 0077.
--
-- O que isto custa quando falta: `arquivar_paciente`, o expurgo da B13 e
-- `eliminar_conta` apagam em cascata. Cada FK sem índice do lado que
-- referencia é uma tabela inteira varrida a cada linha apagada.
select string_agg(x.rotulo, ', ' order by x.rotulo) into v_txt
  from (
    select cl.relname || '.' || con.conname as rotulo
      from pg_constraint con
      join pg_class cl on cl.oid = con.conrelid
      join pg_namespace n on n.oid = cl.relnamespace
     where n.nspname = 'public' and con.contype = 'f'
       and not exists (
         select 1 from pg_index i
          where i.indrelid = con.conrelid
            and (i.indkey::smallint[])[0:array_length(con.conkey, 1) - 1] = con.conkey)
  ) x;

if v_txt is not null then
  raise exception 'FALHOU 2: FK sem índice de cobertura: % — lei 2, e cada uma é uma varredura de tabela inteira por linha apagada', v_txt;
end if;

-- ------------------------------------------------------------------------ 3
--
-- Sem `search_path` fixado, quem controla o schema de busca escolhe qual
-- `contas` a função vai ler — de dentro de uma função que roda como dona.
select string_agg(p.proname, ', ' order by p.proname) into v_txt
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
                    where cfg like 'search_path=%');

if v_txt is not null then
  raise exception 'FALHOU 3: security definer sem search_path: %', v_txt;
end if;

-- ------------------------------------------------------------------------ 4
--
-- `auth.uid()` nu dentro de uma política é reavaliado por linha; a forma
-- `(select auth.uid())` é avaliada uma vez. Numa tabela com trinta mil sessões
-- a diferença deixa de ser acadêmica.
--
-- O catálogo devolve a expressão já normalizada pelo Postgres, então a busca é
-- pelo par: a política cita `auth.uid()` **e** não tem a forma
-- `( SELECT auth.uid()`. Hoje há uma política só que cita a função, e ela está
-- na forma certa; se um dia uma política citar as duas formas de uma vez, esta
-- verificação deixa a errada passar — e aí ela precisa olhar ocorrência a
-- ocorrência em vez de política a política.
select string_agg(p.tablename || '.' || p.policyname, ', '
                  order by p.tablename || '.' || p.policyname) into v_txt
  from pg_policies p
 where p.schemaname = 'public'
   and coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') ~ 'auth\.uid\(\)'
   and coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '')
       !~* '\( *select +auth\.uid\(\)';

if v_txt is not null then
  raise exception 'FALHOU 4: política com auth.uid() fora de subselect: % — reavaliado por linha (lei 2)', v_txt;
end if;

raise notice 'OK · 0077 · a lei 2 se varre do catálogo: RLS, FK indexada, search_path e auth.uid() em subselect';
end
$do$;
