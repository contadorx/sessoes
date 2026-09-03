-- Teste do mês que tem um número só (B44, migração 0069).
--
-- **Esta suíte não confere uma função: confere que quatro concordam.** É a
-- diferença que abriu a build — `retorno`, `financeiro_do_mes`, `livro_razao` e
-- `cockpit_do_mes` respondem "quanto entrou neste mês", e duas discordavam sem
-- que nenhuma tela dissesse por quê. Segunda fonte de verdade sobre dinheiro é
-- S1 automático neste projeto: se ela vir dois números que não batem, o produto
-- perdeu a discussão que existe para ganhar.
--
-- Divergência entre elas é **legítima quando dita** — elas respondem perguntas
-- diferentes, e unificá-las numa só está fora desta build por decisão. O que
-- esta suíte reprova é a divergência que nenhuma tela explica.
--
-- Quatro verificações decidem:
--
--   · a **3**, que exige que `livro_razao` ignore sessão importada. É o S1-A:
--     `financeiro_do_mes` filtra desde a 0040b — *"uma planilha com dois anos
--     despejaria dezenas de milhares de reais em meses fechados"* — e o livro
--     não filtrava. O cockpit herda do livro, então os quatro números da
--     primeira tela vinham contaminados;
--   · a **5**, que compara **as duas funções no mesmo período** e exige
--     igualdade. É o teste que faltava: consertar o filtro sem esta comparação
--     deixa a próxima divergência nascer pelo mesmo caminho;
--   · a **7**, que exige `retorno` = 0 numa conta de mensalistas sem
--     cancelamento nenhum. É o S1-B: a CTE somava os quatro tipos de cobrança,
--     e o número em serifa de 26 px na agenda era o faturamento do mês
--     apresentado como ganho da fila, sob a frase "que não teria entrado sem a
--     fila e sem a política";
--   · a **9**, que exige que o cockpit e o livro digam o mesmo do mesmo mês —
--     um herda do outro, e é assim que se prova que continua herdando.
--
-- Cuidados de escrita, herdados: toda variável leva `v_`, nenhum alias de uma
-- letra, e varredura de corpo de função usa `position()` e nunca `like`.
--
--   parte 1 · o histórico importado não vira receita
--     1. as duas funções existem com a assinatura esperada
--     2. sem importada, livro e financeiro já concordam (a linha de base)
--     3. com importada, o livro continua ignorando                        ← decide
--     4. ...e as horas também, senão o mês fica cheio e sem receita
--     5. a comparação direta das duas, no mesmo período                   ← decide
--     6. o filtro está no corpo, e nas oito consultas
--
--   parte 2 · retorno fala do que a fila e a política recuperaram
--     7. mensalista sem cancelamento: retorno zerado                      ← decide
--     8. com uma multa paga, retorno é exatamente ela
--
--   parte 3 · o cockpit herda
--     9. cockpit e livro dizem o mesmo do mesmo mês                       ← decide
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0069_um_mes_um_numero.sql

do $do$
declare
  v_auth uuid := '11111111-1111-4111-8111-111111111169';
  v_conta uuid; v_prof uuid;
  v_ana uuid; v_bia uuid;
  -- O `::timestamp` é a lição da 0013, e não é enfeite: `date_trunc` sobre um
  -- `date` resolve para a sobrecarga de **timestamptz**, promovendo o valor com
  -- o `TimeZone` da conexão. A partir daí toda conta de dia passa a depender de
  -- uma configuração de sessão que ninguém controla — e um teste que muda de
  -- resultado conforme quem o roda é pior que teste nenhum.
  v_de date := date_trunc('month', public.hoje_sp()::timestamp)::date;
  v_ate date := (date_trunc('month', public.hoje_sp()::timestamp)
                 + interval '1 month - 1 day')::date;
  v_livro jsonb; v_cockpit jsonb; v_fin jsonb;
  v_reconhecida numeric; v_realizado numeric; v_minutos integer;
  v_recebido numeric;
  v_corpo text; v_n integer;
  v_dia timestamptz;
begin

-- ============================================================ preâmbulo

delete from public.contas where nome = 'Numero Teste';
delete from auth.users where id = v_auth;

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'numero@teste.sessoes.com.br', '{"nome":"Numero Teste"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Ana Numero', '5511900000691', 'em_atendimento') returning id into v_ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Bia Numero', '5511900000692', 'em_atendimento') returning id into v_bia;
reset role;

-- O dia 4 do mês corrente, às 10h de São Paulo. Dia fixo para o teste não
-- depender de quando ele roda — o 4 existe em todo mês.
v_dia := (v_de + 3)::timestamptz + interval '10 hours';

raise notice '--- parte 1 · o histórico importado não vira receita ---';

-- 1 · As duas funções existem como esperado.
select count(*)::integer into v_n
  from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public' and pr.proname in ('livro_razao', 'financeiro_do_mes', 'retorno', 'cockpit_do_mes');
if v_n < 4 then
  raise exception 'FALHOU 1: faltam funções do mês (achei %)', v_n;
end if;

-- Uma sessão realizada de verdade, no mês corrente.
set local role postgres;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim,
                            estado, origem, valor, valor_reconhecido)
  values (v_conta, v_prof, v_ana, v_dia, v_dia + interval '50 minutes',
          'realizada', 'recorrencia', 200, 200);
reset role;

-- 2 · A linha de base: sem nada importado, as duas já concordam.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_livro := public.livro_razao(v_prof, v_de, v_ate);
v_fin   := public.financeiro_do_mes(v_de, v_ate);
v_reconhecida := (v_livro->>'receita_reconhecida')::numeric;
v_realizado   := (v_fin->'realizado'->>'valor')::numeric;

if v_reconhecida <> 200 or v_realizado <> 200 then
  raise exception 'FALHOU 2: a linha de base já não bate — livro % e financeiro %',
    v_reconhecida, v_realizado;
end if;
reset role;

-- Agora o histórico colado: quatro sessões importadas, no mesmo mês.
set local role postgres;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim,
                            estado, origem, valor, valor_reconhecido)
select v_conta, v_prof, v_bia, d, d + interval '50 minutes', 'realizada', 'importada', 300, 300
  from generate_series(v_dia + interval '1 day', v_dia + interval '4 days', interval '1 day') d;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_livro := public.livro_razao(v_prof, v_de, v_ate);
v_fin   := public.financeiro_do_mes(v_de, v_ate);
v_reconhecida := (v_livro->>'receita_reconhecida')::numeric;
v_realizado   := (v_fin->'realizado'->>'valor')::numeric;

-- 3 · O livro continua ignorando o importado.  ← decide
if v_reconhecida <> 200 then
  raise exception 'FALHOU 3: o livro contou o histórico importado (% em vez de 200) — uma planilha com dois anos despeja dezenas de milhares de reais em meses fechados, e a tela do lado mostra outro número', v_reconhecida;
end if;

-- 4 · E as horas também. Contar a hora sem contar a receita seria uma terceira
--     versão do mesmo mês: "você trabalhou e não ganhou nada".
v_minutos := (v_livro->>'minutos_usados')::integer;
if v_minutos <> 50 then
  raise exception 'FALHOU 4: os minutos do livro contam o importado (% em vez de 50) — o mês fica cheio de hora e vazio de receita', v_minutos;
end if;

-- 5 · A comparação direta, que é o teste que faltava.  ← decide
if v_reconhecida is distinct from v_realizado then
  raise exception 'FALHOU 5: livro-razão diz % e financeiro diz % para o mesmo mês da mesma conta — duas telas, dois números, nenhuma explicação', v_reconhecida, v_realizado;
end if;
reset role;

-- 6 · O filtro está no corpo, e nas oito consultas. `position()` e não `like`:
--     `_` é curinga em `like`, e `origem <> 'importada'` não tem underline, mas
--     a regra da casa é uma só para não haver exceção que alguém copie errado.
select pg_get_functiondef(pr.oid) into v_corpo
  from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public' and pr.proname = 'livro_razao';

v_n := (length(v_corpo) - length(replace(v_corpo, 'origem <> ''importada''', '')))
       / length('origem <> ''importada''');
if v_n < 8 then
  raise exception 'FALHOU 6: o filtro de importada aparece % vezes no corpo do livro_razao; são oito consultas sobre sessoes, e a que ficar de fora é a que diverge', v_n;
end if;

raise notice '--- parte 2 · retorno fala do que a fila recuperou ---';

-- Uma conta de mensalistas, sem cancelamento nenhum no mês.
set local role postgres;
insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, estado, valor, competencia)
values (v_conta, v_ana, 'mensalidade', 'mensalidade', 'paga', 800, v_de),
       (v_conta, v_bia, 'mensalidade', 'mensalidade', 'paga', 900, v_de),
       (v_conta, v_ana, 'pacote',      'pacote',      'paga', 1800, v_de);
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

select valor_recebido into v_recebido from public.retorno(v_de, v_ate);

-- 7 · Sem cancelamento, o retorno é zero.  ← decide
if v_recebido <> 0 then
  raise exception 'FALHOU 7: retorno diz % sem nenhum cancelamento no mês — é o faturamento apresentado na agenda como "que não teria entrado sem a fila e sem a política", que é afirmação contrafactual sobre o dinheiro dela', v_recebido;
end if;
reset role;

-- 8 · Com uma multa paga, o retorno é exatamente ela.
set local role postgres;
insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, estado, valor, competencia)
values (v_conta, v_ana, 'falta', 'falta', 'paga', 100, v_de);
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

select valor_recebido into v_recebido from public.retorno(v_de, v_ate);
if v_recebido <> 100 then
  raise exception 'FALHOU 8: retorno diz % com uma multa paga de 100', v_recebido;
end if;

raise notice '--- parte 3 · o cockpit herda ---';

-- 9 · O cockpit e o livro falam do mesmo mês.  ← decide
v_cockpit := public.cockpit_do_mes(v_prof, v_de, v_ate);
v_livro   := public.livro_razao(v_prof, v_de, v_ate);

if (v_cockpit->>'receita_reconhecida')::numeric
     is distinct from (v_livro->>'receita_reconhecida')::numeric then
  raise exception 'FALHOU 9: cockpit diz % e livro diz % — o cockpit herda do livro, e a primeira tela do produto passou a discordar da tela de fechamento',
    v_cockpit->>'receita_reconhecida', v_livro->>'receita_reconhecida';
end if;
reset role;

-- ============================================================ limpeza

set local role postgres;
delete from public.contas where nome = 'Numero Teste';
delete from auth.users where id = v_auth;
reset role;

raise notice 'OK · 0069 · um mês, um número — as quatro funções concordam';
end
$do$;
