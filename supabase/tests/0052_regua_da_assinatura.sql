-- =====================================================================
-- Suíte 0052 · a régua da assinatura, e o churn com causa
-- =====================================================================
--
-- Metade destas verificações confere o que o sistema **não pode** fazer, e aqui
-- a metade negativa é a que carrega a decisão ética da migração: uma conta
-- suspensa não perde registro, e o paciente dela não sente nada.
--
-- TRÊS LIÇÕES ANTIGAS ESTÃO APLICADAS
--
--   · **A ação roda como o papel; a conferência roda com `reset role`** (0050,
--     verificações 8 e 9). Asserção feita sob `set local role` lê pela RLS,
--     volta nula, e nulo num `if` é falso — passa por ausência de dado.
--
--   · **Asserção sobre o resultado, nunca sobre o mecanismo** (0044, 0017).
--     Onde a defesa é silenciosa mede-se o estado; onde ela levanta, mede-se a
--     exceção.
--
--   · **Contar as sobrecargas, e não ler o arquivo** (0052b). A verificação 1
--     existe porque a própria 0052 criou uma segunda `cancelar_assinatura` sem
--     querer, e o PostgREST teria continuado chamando a antiga.
-- =====================================================================

do $$
declare
  conta_a    uuid;
  auth_a     uuid := '55555555-5555-4555-8555-555555555555';
  prof_a     uuid;
  assin      uuid;
  fatura     uuid;
  fatura2    uuid;
  v_operador uuid;
  n          integer;
  r          record;
  j          jsonb;
  txt        text;
  bandeira   boolean;
begin

-- ============================================================ preâmbulo

delete from public.avisos_assinatura
 where conta_id in (select id from public.contas where nome = 'Suite 0052');
delete from public.faturas
 where conta_id in (select id from public.contas where nome = 'Suite 0052');
delete from public.assinaturas
 where conta_id in (select id from public.contas where nome = 'Suite 0052');
delete from auth.users where id = auth_a;
delete from public.contas where nome = 'Suite 0052';

select u.auth_user_id into v_operador
  from public.usuarios u where u.operador = true limit 1;
if v_operador is null then
  raise exception 'FALHOU no preâmbulo: nenhum usuário operador — as verificações mediriam o vazio';
end if;

insert into auth.users (id, email, raw_user_meta_data)
values (auth_a, 'suite0052@teste.sessoes.com.br', '{"nome":"Suite 0052"}'::jsonb);
select conta_id into conta_a from public.usuarios where auth_user_id = auth_a;
select id into prof_a from public.profissionais where conta_id = conta_a;

-- O operador entra na sessão: as funções são `security definer` com
-- `e_operador()` dentro, e sem os claims elas recusariam tudo.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_operador::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · a estrutura, e a sobrecarga ---';

-- 1 · existe UMA cancelar_assinatura, e ela tem três parâmetros.
--
-- Esta verificação é a 0052b virada teste. A 0052 acrescentou `p_causa` com
-- padrão, o que **cria uma segunda função** em vez de substituir a primeira — e
-- o PostgREST escolhe a sobrecarga pelos nomes que chegam na chamada. A tela
-- manda dois nomes, casaria com a antiga, e a causa nunca seria gravada. Sem
-- erro em lugar nenhum.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'cancelar_assinatura';
if n <> 1 then
  raise exception 'FALHOU 1: há % versões de cancelar_assinatura — o PostgREST vai escolher pela contagem de nomes da chamada, e a causa some em silêncio', n;
end if;
raise notice 'ok 1 · uma cancelar_assinatura só';

-- 2 · a régua da assinatura NÃO é a régua do paciente.
--
-- A da B18 não endurece, e há teste comparando o primeiro degrau com o
-- terceiro. Esta endurece de propósito — e a verificação existe para deixar
-- registrado que as duas são coisas diferentes, e que ninguém copiou uma na
-- outra por engano.
select count(*) into n from public.regua_da_assinatura();
if n <> 3 then
  raise exception 'FALHOU 2: a régua tem % degraus, esperava 3', n;
end if;
select corpo into txt from public.regua_da_assinatura() where degrau = 1;
select count(*) into n from public.regua_da_assinatura() where degrau = 3 and corpo = txt;
if n <> 0 then
  raise exception 'FALHOU 2b: o degrau 3 é igual ao 1 — isto aqui é a régua do negócio, e ela pode endurecer';
end if;
raise notice 'ok 2 · três degraus, e eles não são o mesmo texto';

-- 3 · o degrau 3 promete o que a migração cumpre.
--
-- É a verificação mais chata de escrever e a mais importante: o texto que sai
-- para a cliente diz que agenda, prontuário e exportação continuam. Se algum
-- dia a suspensão passar a tirar isso, o texto vira mentira — e mentira num
-- e-mail de cobrança é o pior lugar possível.
select corpo into txt from public.regua_da_assinatura() where degrau = 3;
if position('prontuário' in txt) = 0 or position('exportação' in txt) = 0 then
  raise exception 'FALHOU 3: o aviso de suspensão não diz o que continua de pé';
end if;
raise notice 'ok 3 · o aviso diz o que a suspensão não tira';

-- 4 · mudanca_de_plano não está na lista de churn.
select count(*) into n
  from unnest(public.causas_de_churn()) c where c = 'mudanca_de_plano';
if n <> 0 then
  raise exception 'FALHOU 4: troca de plano voltou a contar como churn';
end if;
select count(*) into n
  from unnest(public.causas_de_churn()) c where c = 'inadimplencia';
if n <> 1 then
  raise exception 'FALHOU 4b: inadimplência saiu do churn — perder por falta de pagamento é perder';
end if;
raise notice 'ok 4 · troca de plano não é churn; inadimplência é';

raise notice '--- parte 2 · a régua correndo ---';

set local role authenticated;
select public.abrir_assinatura(conta_a, 'solo') into assin;
select public.emitir_fatura(assin, (public.hoje_sp() - interval '30 days')::date) into fatura;
reset role;

-- A fatura nasce com vencimento futuro; a suíte precisa dela vencida.
update public.faturas set vencimento = public.hoje_sp() - 4 where id = fatura;

-- 5 · a passada vence a fatura e põe a assinatura em atraso.
select public.passar_a_regua_das_assinaturas() into j;
select estado into txt from public.faturas where id = fatura;
if txt <> 'vencida' then
  raise exception 'FALHOU 5: a fatura não venceu (estado %)', txt;
end if;
select estado into txt from public.assinaturas where id = assin;
if txt <> 'em_atraso' then
  raise exception 'FALHOU 5b: a assinatura não entrou em atraso (estado %)', txt;
end if;
raise notice 'ok 5 · vence a fatura e atrasa a assinatura';

-- 6 · o degrau 1 saiu, e só ele.
select count(*) into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 1 then
  raise exception 'FALHOU 6: saíram % avisos com 4 dias de atraso, esperava 1', n;
end if;
select degrau into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 1 then
  raise exception 'FALHOU 6b: saiu o degrau % com 4 dias de atraso', n;
end if;
raise notice 'ok 6 · o degrau certo, na hora certa';

-- 7 · a passada repetida não duplica o aviso.
--
-- O cron roda todo dia. Sem o índice único, a caixa de entrada dela teria
-- trinta cópias do mesmo texto — que é pior que nenhum aviso.
perform public.passar_a_regua_das_assinaturas();
perform public.passar_a_regua_das_assinaturas();
select count(*) into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 1 then
  raise exception 'FALHOU 7: três passadas produziram % avisos', n;
end if;
raise notice 'ok 7 · a passada repetida não duplica';

-- 8 · aos 25 dias, suspende — e o degrau 3 saiu antes.
update public.faturas set vencimento = public.hoje_sp() - 26 where id = fatura;
perform public.passar_a_regua_das_assinaturas();

select count(*) into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 3 then
  raise exception 'FALHOU 8: suspendeu com % avisos, esperava os 3 degraus — conta que pausa sem ter sido avisada é a versão comercial do 307 mudo', n;
end if;

select estado into txt from public.assinaturas where id = assin;
if txt <> 'suspensa' then
  raise exception 'FALHOU 8b: não suspendeu aos 26 dias (estado %)', txt;
end if;
raise notice 'ok 8 · suspende depois de avisar três vezes';

raise notice '--- parte 3 · o que a suspensão NÃO faz ---';

-- 9 · a conta suspensa está no plano Grátis, e é assim que a decisão vale.
select plano into txt from public.contas where id = conta_a;
if txt <> 'gratis' then
  raise exception 'FALHOU 9: a conta suspensa ficou no plano % — a suspensão é o piso, não um estado paralelo', txt;
end if;
raise notice 'ok 9 · suspender é voltar ao Grátis';

-- 10 · e o plano Grátis continua sendo tudo o que é registro.
--
-- Esta é a verificação que sustenta a decisão inteira: se um dia o Grátis
-- perder o registro, a suspensão passa a tirar prontuário sem ninguém ter
-- decidido isso. O limite de pacientes do Grátis é nulo desde a 0048, e o de
-- mensagens alcança só as não-essenciais.
select limite_pacientes_ativos into n from public.planos where codigo = 'gratis';
if n is not null then
  raise exception 'FALHOU 10: o plano Grátis voltou a limitar pacientes (%) — e a suspensão passa por ele', n;
end if;
raise notice 'ok 10 · o piso continua habitável';

-- 11 · o paciente não sente: template essencial não depende de plano.
--
-- Lembrete de véspera, aviso de desmarque e confirmação de encaixe saem em
-- qualquer plano. Alguém iria ao consultório encontrar a porta fechada porque
-- **eu** não fui pago, e essa pessoa não escolheu nada disto.
select count(*) into n from public.templates where essencial and motivo is not null;
if n < 3 then
  raise exception 'FALHOU 11: só % templates essenciais com motivo escrito', n;
end if;
select count(*) into n from public.templates where codigo = 'lembrete_de_sessao' and essencial;
if n <> 1 then
  raise exception 'FALHOU 11b: o lembrete de véspera deixou de ser essencial';
end if;
raise notice 'ok 11 · o essencial sai em qualquer plano';

-- 12 · o registro clínico da conta suspensa continua legível por ela.
--
-- A asserção roda **como ela**, porque o que se mede aqui é o que ela enxerga —
-- e é o único caso desta suíte em que a leitura é o assunto.
declare
  pac uuid;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', auth_a::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (prof_a, 'Paciente da Suspensa', '5511900000052', 'em_atendimento')
  returning id into pac;

  select count(*) into n from public.pacientes where id = pac;
  reset role;

  if n <> 1 then
    raise exception 'FALHOU 12: a conta suspensa não enxerga o próprio cadastro';
  end if;

  -- E a exportação — que é o que ela mais precisa exatamente agora.
  perform set_config('request.jwt.claims',
    json_build_object('sub', auth_a::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select public.exportar_conta() into j;
  reset role;

  if jsonb_array_length(j->'pacientes') < 1 then
    raise exception 'FALHOU 12b: a exportação de uma conta suspensa veio vazia — exportação bloqueada por inadimplência é sequestro de arquivo';
  end if;

  delete from public.pacientes where id = pac;
end;

raise notice 'ok 12 · registro e exportação continuam de pé na conta suspensa';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_operador::text, 'role', 'authenticated')::text, true);

-- 12b · e uma conta suspensa não ganha uma segunda assinatura viva.
--
-- Este é o buraco da 0052d, virado teste. `abrir_assinatura` guardava a
-- invariante "uma assinatura viva por conta" com a lista de estados escrita à
-- mão, e a 0052 acrescentou `suspensa` sem que ela soubesse. A conta ficaria
-- com duas — uma suspensa devendo, outra ativa — e o MRR passaria a somar
-- sobre uma base que não deveria existir.
--
-- Quem faria isso? Eu, tentando resolver na mão um caso que a régua suspendeu.
set local role authenticated;
bandeira := false;
begin
  perform public.abrir_assinatura(conta_a, 'pro');
  bandeira := true;
exception when others then
  null;
end;
reset role;
if bandeira then
  raise exception 'FALHOU 12c: a conta suspensa ganhou uma segunda assinatura viva';
end if;
select count(*) into n from public.assinaturas
 where conta_id = conta_a and estado in ('trial', 'ativa', 'em_atraso', 'suspensa');
if n <> 1 then
  raise exception 'FALHOU 12d: % assinaturas vivas na mesma conta', n;
end if;
raise notice 'ok 12b · suspensa continua sendo uma assinatura viva';

raise notice '--- parte 4 · a volta ---';

-- 13 · pagar devolve tudo, no mesmo instante.
set local role authenticated;
perform public.baixar_fatura(fatura);
reset role;

select estado into txt from public.assinaturas where id = assin;
if txt <> 'ativa' then
  raise exception 'FALHOU 13: pagar não reativou a assinatura (estado %)', txt;
end if;
select plano into txt from public.contas where id = conta_a;
if txt <> 'solo' then
  raise exception 'FALHOU 13b: pagar não devolveu o plano (plano %)', txt;
end if;
raise notice 'ok 13 · pagar devolve o plano na hora';

-- 14 · e os avisos que não saíram são cancelados.
--
-- Mandar o degrau 3 no dia seguinte ao pagamento é o tipo de coisa que faz
-- alguém cancelar de raiva um serviço que já pagou.
select count(*) into n from public.avisos_assinatura
 where fatura_id = fatura and estado = 'pendente';
if n <> 0 then
  raise exception 'FALHOU 14: sobraram % avisos pendentes de uma fatura paga', n;
end if;
raise notice 'ok 14 · aviso de fatura paga não sai';

-- 15 · com duas faturas vencidas, pagar uma não reativa.
set local role authenticated;
select public.emitir_fatura(assin, (public.hoje_sp() - interval '60 days')::date) into fatura2;
reset role;
update public.faturas set vencimento = public.hoje_sp() - 10 where id = fatura2;
perform public.passar_a_regua_das_assinaturas();

set local role authenticated;
select public.emitir_fatura(assin, (public.hoje_sp() - interval '90 days')::date) into fatura;
reset role;
update public.faturas set vencimento = public.hoje_sp() - 5 where id = fatura;
perform public.passar_a_regua_das_assinaturas();

set local role authenticated;
perform public.baixar_fatura(fatura2);
reset role;

select estado into txt from public.assinaturas where id = assin;
if txt <> 'em_atraso' then
  raise exception 'FALHOU 15: pagar uma de duas faturas vencidas reativou a assinatura (estado %)', txt;
end if;
raise notice 'ok 15 · uma de duas não reativa';

set local role authenticated;
perform public.baixar_fatura(fatura);
reset role;
select estado into txt from public.assinaturas where id = assin;
if txt <> 'ativa' then
  raise exception 'FALHOU 15b: pagar a última não reativou (estado %)', txt;
end if;
raise notice 'ok 15b · pagar a última reativa';

raise notice '--- parte 5 · quem a régua não alcança ---';

-- 16 · conta de teste não recebe aviso.
update public.contas set is_teste = true where id = conta_a;
set local role authenticated;
select public.emitir_fatura(assin, (public.hoje_sp() - interval '120 days')::date) into fatura;
reset role;
update public.faturas set vencimento = public.hoje_sp() - 30 where id = fatura;
perform public.passar_a_regua_das_assinaturas();

select count(*) into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 0 then
  raise exception 'FALHOU 16: a régua cobrou uma conta de teste (% avisos) — é cobrar de mim', n;
end if;
select estado into txt from public.assinaturas where id = assin;
if txt = 'suspensa' then
  raise exception 'FALHOU 16b: suspendeu uma conta de teste';
end if;
raise notice 'ok 16 · conta de teste fica de fora';

update public.contas set is_teste = false where id = conta_a;

-- 17 · assinatura de cortesia também não.
update public.assinaturas set origem = 'cortesia' where id = assin;
perform public.passar_a_regua_das_assinaturas();
select count(*) into n from public.avisos_assinatura where fatura_id = fatura;
if n <> 0 then
  raise exception 'FALHOU 17: a régua cobrou uma cortesia (% avisos)', n;
end if;
raise notice 'ok 17 · cortesia fica de fora';

update public.assinaturas set origem = 'painel' where id = assin;

raise notice '--- parte 6 · o churn com causa ---';

-- 18 · cancelar sem causa válida é recusado, e a frase explica.
set local role authenticated;
bandeira := false;
begin
  perform public.cancelar_assinatura(assin, 'motivo escrito por extenso', 'inventada');
  bandeira := true;
exception when others then
  null;
end;
reset role;
if bandeira then
  raise exception 'FALHOU 18: uma causa fora da lista entrou';
end if;
select estado into txt from public.assinaturas where id = assin;
if txt = 'cancelada' then
  raise exception 'FALHOU 18b: a chamada foi recusada e a assinatura foi cancelada assim mesmo';
end if;
raise notice 'ok 18 · a lista de causas é fechada';

-- 19 · a frase continua obrigatória.
set local role authenticated;
bandeira := false;
begin
  perform public.cancelar_assinatura(assin, 'ok', 'preco');
  bandeira := true;
exception when others then
  null;
end;
reset role;
if bandeira then
  raise exception 'FALHOU 19: cancelou com motivo de dois caracteres — a categoria não substitui a frase';
end if;
raise notice 'ok 19 · a categoria não substitui a frase';

-- 20 · trocar de plano marca a causa sozinho.
--
-- É o defeito do cabeçalho, virado teste.
set local role authenticated;
perform public.mudar_plano(conta_a, 'pro', 'subiu de plano na conversa de setembro');
reset role;

select causa_cancelamento into txt from public.assinaturas where id = assin;
if txt is distinct from 'mudanca_de_plano' then
  raise exception 'FALHOU 20: a troca de plano gravou causa % — e toda promoção volta a contar como churn', coalesce(txt, 'nula');
end if;
raise notice 'ok 20 · a troca de plano se declara';

-- 21 · e o churn não conta essa linha.
--
-- A conferência é o par da 20: sem ela, a 20 passaria com uma coluna preenchida
-- que ninguém lê.
select * into r from public.churn_do_mes(public.hoje_sp());
select count(*) into n
  from public.assinaturas a
 where a.id = assin and a.cancelada_em >= date_trunc('month', public.hoje_sp());
if n <> 1 then
  raise exception 'FALHOU 21: o cenário não montou — a assinatura trocada não foi cancelada neste mês';
end if;
select count(*) into n
  from public.assinaturas a
  join public.contas ct on ct.id = a.conta_id
 where not ct.is_teste
   and a.cancelada_em >= date_trunc('month', public.hoje_sp())
   and coalesce(a.causa_cancelamento, 'outra') = any (public.causas_de_churn())
   and a.conta_id = conta_a;
if n <> 0 then
  raise exception 'FALHOU 21b: a troca de plano entrou na conta do churn';
end if;
raise notice 'ok 21 · a troca de plano não vira churn';

-- 22 · um cancelamento de verdade entra.
declare nova uuid;
begin
  select id into nova from public.assinaturas
   where conta_id = conta_a and estado in ('ativa', 'trial') limit 1;

  set local role authenticated;
  perform public.cancelar_assinatura(
    nova, 'disse que ia parar de atender no fim do ano', 'parou_de_atender');
  reset role;
end;

select causa_cancelamento into txt from public.assinaturas
 where conta_id = conta_a and estado = 'cancelada' and causa_cancelamento = 'parou_de_atender';
if txt is null then
  raise exception 'FALHOU 22: o cancelamento de verdade não gravou a causa';
end if;
raise notice 'ok 22 · o cancelamento de verdade grava causa e frase';

-- 23 · a retenção lista a causa e o dinheiro, e não a porcentagem.
--
-- Com uma dúzia de contas, "33% saíram por preço" são duas pessoas. A tela
-- mostra inteiro; a porcentagem entra quando a base sustentar uma.
set local role authenticated;
select public.retencao_do_painel() into j;
reset role;

if not (j ? 'por_causa') or not (j ? 'lista') then
  raise exception 'FALHOU 23: a retenção não trouxe causa nem lista';
end if;
if j ? 'pct_por_causa' then
  raise exception 'FALHOU 23b: apareceu porcentagem por causa — sobre dois cancelamentos ela finge saber';
end if;
if (j->>'quantas')::integer < 1 then
  raise exception 'FALHOU 23c: a retenção não contou o cancelamento de verdade';
end if;
raise notice 'ok 23 · a retenção conta e não estima';

-- 24 · e a lista traz a frase junto com a categoria.
select j->'lista'->0->>'motivo' into txt;
if txt is null or length(txt) < 5 then
  raise exception 'FALHOU 24: a lista veio sem a frase — a categoria sozinha não diz o que construir';
end if;
raise notice 'ok 24 · a frase viaja junto com a categoria';

raise notice '--- parte 7 · o que não é do operador ---';

-- 25 · a passada da régua não está publicada para quem tem qualquer login.
--
-- Uma função que suspende conta não pode estar em /rest/v1/rpc para
-- `authenticated`. E a asserção é sobre o **grant**, não sobre a exceção: esta
-- defesa é do banco, não da função.
select count(*) into n
  from information_schema.role_routine_grants g
  join pg_proc p on p.proname = g.routine_name
 where g.routine_schema = 'public'
   and g.routine_name = 'passar_a_regua_das_assinaturas'
   and g.grantee in ('anon', 'authenticated', 'PUBLIC');
if n > 0 then
  raise exception 'FALHOU 25: a régua está executável por quem tem login (% grants)', n;
end if;
raise notice 'ok 25 · a régua é do cron, e só';

-- 26 · e a retenção recusa quem não é operador.
perform set_config('request.jwt.claims',
  json_build_object('sub', auth_a::text, 'role', 'authenticated')::text, true);
set local role authenticated;
bandeira := false;
begin
  perform public.retencao_do_painel();
  bandeira := true;
exception when others then
  null;
end;
reset role;
if bandeira then
  raise exception 'FALHOU 26: uma conta comum leu a retenção do negócio';
end if;
raise notice 'ok 26 · a retenção é minha';

-- ============================================================ limpeza
perform set_config('request.jwt.claims', null, true);

delete from public.avisos_assinatura where conta_id = conta_a;
delete from public.faturas where conta_id = conta_a;
delete from public.assinaturas where conta_id = conta_a;
delete from public.pacientes where conta_id = conta_a;
delete from auth.users where id = auth_a;
delete from public.contas where id = conta_a;

select count(*) into n from public.contas where nome = 'Suite 0052';
if n <> 0 then
  raise exception 'FALHOU na limpeza: sobrou conta da suíte';
end if;

raise notice '';
raise notice '=====================================================';
raise notice '  0052 · 26 verificações passaram';
raise notice '=====================================================';

end $$;
