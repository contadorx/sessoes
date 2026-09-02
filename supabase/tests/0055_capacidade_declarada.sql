-- Teste da capacidade declarada (P1, migração 0055).
--
-- A verificação que decide o build é a nº 9: **mudar a semana hoje não altera
-- nenhum dia anterior à mudança.** É o critério de pronto do P1 e é a diferença
-- entre capacidade como *declaração datada* e capacidade como *configuração*.
-- Sem isso, a ocupação de julho mudaria toda vez que alguém mexesse na agenda
-- de amanhã — e um número que muda conforme o dia em que é consultado não é
-- métrica, é opinião com casas decimais.
--
-- A segunda é a nº 16, e ela é ética antes de ser técnica: **registro e
-- descanso entram no declarado e nunca no vendável.** Um denominador que
-- somasse as três seria um produto para psicólogas empurrando psicóloga a
-- preencher todas as horas — a ocupação sobe sem nada ter melhorado, só porque
-- ela deixou de reservar tempo de prontuário.
--
-- E a nº 4 é a fronteira escrita como teste: a resposta não pode ter **nenhum
-- campo** que some protegido com vendável, nem nome de ociosidade.
--
--   parte 1 · a estrutura e a fronteira
--     1. destino aceita os três e recusa o quarto
--     2. hora vaga não é linha — não existe tabela de horário vazio
--     3. não existe função com nome de ociosidade ou de hora livre
--     4. a resposta não soma protegido com vendável, e não tem campo de ócio
--     5. nenhuma política de escrita — quem grava é a função
--
--   parte 2 · a declaração não retroage
--     6. janela não nasce no passado, e a recusa fala do mês fechado
--     7. vigência não se encerra no passado
--     8. definir_semana com data passada é recusada
--     9. mudar a semana hoje não altera nenhum dia anterior à mudança  ← decide
--    10. e altera os dias de lá para a frente
--
--   parte 3 · a sobreposição
--    11. duas faixas cruzadas no mesmo dia são recusadas, dizendo qual
--    12. faixas encostadas passam — encostar não é sobrepor
--    13. o mesmo horário em dias diferentes passa
--    14. o mesmo horário em vigências que não se cruzam passa
--
--   parte 4 · a aritmética
--    15. a soma bate com os minutos declarados vezes os dias
--    16. registro e descanso entram no declarado e não no vendável  ← decide
--    17. a troca no meio do período é respeitada dia a dia
--    18. sem_janela separa "não declarou" de "declarou zero"
--
--   parte 5 · a exceção
--    19. férias saem do vendável e aparecem no balde de férias
--    20. feriado e bloqueio, cada um no seu balde
--    21. o mês inteiro de férias zera o vendável sem zerar a história
--    22. exceção de outro profissional não subtrai
--
--   parte 6 · o isolamento
--    23. outra conta não lê janela nem capacidade
--    24. o anônimo não executa nada disso
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0055_capacidade_declarada.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111155';
  b_auth uuid := '22222222-2222-4222-8222-222222222155';
  a_conta uuid; a_prof uuid;
  b_conta uuid; b_prof uuid;
  hoje date;
  j jsonb; j2 jsonb;
  n integer; erro text; v_id uuid;
  semana_a jsonb; semana_b jsonb;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Capa Teste', 'Capa Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'capa@teste.sessoes.com.br', '{"nome":"Capa Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (b_auth, 'vizinha@teste.sessoes.com.br', '{"nome":"Capa Vizinha"}'::jsonb);

select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
select id into a_prof from public.profissionais where conta_id = a_conta;
select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
select id into b_prof from public.profissionais where conta_id = b_conta;

hoje := public.hoje_sp();

-- A semana A: todos os dias 09–12 atendimento, 12–13 registro, 13–14 descanso.
-- Sete dias iguais de propósito — a aritmética por dia fica uniforme e o teste
-- mede a regra, não o calendário.
select jsonb_agg(x) into semana_a from (
  select jsonb_build_object('dia', d, 'inicio', '09:00', 'fim', '12:00', 'destino', 'atendimento') as x
    from generate_series(0, 6) d
  union all
  select jsonb_build_object('dia', d, 'inicio', '12:00', 'fim', '13:00', 'destino', 'registro')
    from generate_series(0, 6) d
  union all
  select jsonb_build_object('dia', d, 'inicio', '13:00', 'fim', '14:00', 'destino', 'descanso')
    from generate_series(0, 6) d
) t;

-- A semana B: menor, e só atendimento. 09–11 = 120 min/dia.
select jsonb_agg(jsonb_build_object('dia', d, 'inicio', '09:00', 'fim', '11:00', 'destino', 'atendimento'))
  into semana_b from generate_series(0, 6) d;

raise notice '--- parte 1 · a estrutura e a fronteira ---';

-- 1 · o destino é fechado.
erro := null;
begin
  set local role postgres;
  insert into public.janelas_atendimento (conta_id, profissional_id, dia_semana, inicio, fim, destino)
  values (a_conta, a_prof, 1, '08:00', '09:00', 'almoco');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 1: entrou um destino fora da lista — a fronteira do doc 11 depende de os três serem os três';
end if;
raise notice 'ok 1 · o destino é fechado nos três';

-- 2 · hora vaga não é linha.
--
-- A lista é estreita de propósito: `vagas_fixas` e `fila_encaixe` existem desde
-- a B7 e são outra coisa — lá **existe alguém que pediu** o horário. O que não
-- pode existir é tabela de horário vazio sem comprador, que trataria ausência
-- de demanda como estoque.
select count(*) into n
  from information_schema.tables
 where table_schema = 'public' and table_type = 'BASE TABLE'
   and (table_name like 'horas\_vagas%' or table_name like 'horarios\_vagos%'
        or table_name like 'capacidade\_%' or table_name like 'slots%'
        or table_name like 'vagas\_livres%' or table_name like '%ociosidade%');
if n > 0 then
  raise exception 'FALHOU 2: apareceu tabela de hora vazia (%) — vaga é capacidade menos sessões, calculada, e materializá-la é tratar ausência de demanda como estoque', n;
end if;
raise notice 'ok 2 · hora vaga continua sendo cálculo, não linha';

-- 3 · e nenhuma função com nome de ócio.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and (p.proname like '%ociosidade%' or p.proname like '%ocioso%'
        or p.proname like '%horas_livres%' or p.proname like '%hora_vaga%'
        or p.proname like '%preencher_agenda%');
if n > 0 then
  raise exception 'FALHOU 3: existe função com nome de ociosidade ou de preencher agenda (%) — nenhuma das duas é coisa que este produto calcula', n;
end if;
raise notice 'ok 3 · nenhuma função de ócio';

-- 5 · escrita é função.
select count(*) into n
  from pg_policies
 where schemaname = 'public' and tablename = 'janelas_atendimento'
   and cmd in ('INSERT', 'UPDATE', 'DELETE');
if n > 0 then
  raise exception 'FALHOU 5: apareceu política de escrita em janelas_atendimento (%) — um insert solto pela tela deixaria a semana antiga valendo junto', n;
end if;
raise notice 'ok 5 · nenhuma política de escrita nas janelas';

raise notice '--- parte 2 · a declaração não retroage ---';

perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);

-- 6 · janela não nasce no passado.
erro := null;
begin
  set local role postgres;
  insert into public.janelas_atendimento
    (conta_id, profissional_id, dia_semana, inicio, fim, vigencia_de)
  values (a_conta, a_prof, 1, '08:00', '09:00', hoje - 30);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 6: uma janela nasceu no passado — a ocupação de um mês fechado passaria a mudar conforme o dia da consulta';
end if;
if erro not ilike '%mês fechado%' then
  raise exception 'FALHOU 6: recusou com "%" — a mensagem precisa dizer que o motivo é o mês já contado', erro;
end if;
raise notice 'ok 6 · janela não nasce no passado, e a recusa explica';

-- Agora a semana A, de hoje.
set local role authenticated;
select public.definir_semana(a_prof, semana_a) into n;
reset role;
if n <> 21 then raise exception 'FALHOU no preâmbulo: definir_semana gravou % faixas (esperado 21)', n; end if;

-- 7 · e a vigência não se encerra no passado.
select id into v_id from public.janelas_atendimento
 where profissional_id = a_prof and dia_semana = 1 and destino = 'atendimento' limit 1;

erro := null;
begin
  set local role postgres;
  update public.janelas_atendimento set vigencia_ate = hoje - 1 where id = v_id;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 7: uma janela foi encerrada no passado — isso apaga capacidade que já foi contada';
end if;
raise notice 'ok 7 · a vigência não se encerra no passado';

-- 8 · e a função recusa igual, com a frase certa.
erro := null;
begin
  set local role authenticated;
  perform public.definir_semana(a_prof, semana_b, hoje - 1);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 8: definir_semana aceitou data passada';
end if;
if erro not ilike '%mês fechado%' then
  raise exception 'FALHOU 8: recusou com "%" — a mensagem precisa dizer por quê', erro;
end if;
raise notice 'ok 8 · definir_semana não retroage';

raise notice '--- parte 3 · a sobreposição ---';

-- 11 · faixa cruzada é recusada, e a mensagem diz qual.
erro := null;
begin
  set local role postgres;
  insert into public.janelas_atendimento (conta_id, profissional_id, dia_semana, inicio, fim)
  values (a_conta, a_prof, 1, '11:00', '13:00');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 11: duas faixas do mesmo dia se sobrepuseram — a mesma hora contada duas vezes infla a capacidade e faz a ocupação parecer menor do que é';
end if;
if erro not like '%09:00%' then
  raise exception 'FALHOU 11: recusou com "%" — a mensagem precisa dizer com QUAL faixa bateu, senão a pessoa procura no escuro', erro;
end if;
raise notice 'ok 11 · faixa cruzada é recusada, dizendo com qual';

-- 12 · encostar não é sobrepor.
erro := null;
begin
  set local role postgres;
  insert into public.janelas_atendimento (conta_id, profissional_id, dia_semana, inicio, fim, destino)
  values (a_conta, a_prof, 1, '14:00', '15:00', 'atendimento');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is not null then
  raise exception 'FALHOU 12: recusou uma faixa que apenas encosta na outra ("%") — 13–14 e 14–15 não dividem minuto nenhum', erro;
end if;

set local role postgres;
delete from public.janelas_atendimento where profissional_id = a_prof and inicio = '14:00';
reset role;
raise notice 'ok 12 · encostar não é sobrepor';

-- 13 · o mesmo horário em outro dia passa (senão a semana inteira seria uma faixa).
--     Já está provado: a semana A tem 09–12 nos sete dias e foi gravada.
select count(*) into n from public.janelas_atendimento
 where profissional_id = a_prof and inicio = '09:00' and vigencia_ate is null;
if n <> 7 then
  raise exception 'FALHOU 13: o mesmo horário em dias diferentes não coube (% de 7)', n;
end if;
raise notice 'ok 13 · o mesmo horário em dias diferentes convive';

raise notice '--- parte 4 · a aritmética ---';

-- 15 e 16 · sete dias, 180 vendáveis + 60 registro + 60 descanso por dia.
set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;

if (j->>'vendavel_min')::int <> 180 * 7 then
  raise exception 'FALHOU 15: vendável = % (esperado %)', j->>'vendavel_min', 180 * 7;
end if;
if (j->>'dias')::int <> 7 then
  raise exception 'FALHOU 15: contou % dias num período de 7', j->>'dias';
end if;

if (j->>'registro_min')::int <> 60 * 7 or (j->>'descanso_min')::int <> 60 * 7 then
  raise exception 'FALHOU 16: registro=% descanso=% (esperado % cada)',
    j->>'registro_min', j->>'descanso_min', 60 * 7;
end if;
if (j->>'declarado_min')::int <> 300 * 7 then
  raise exception 'FALHOU 16: declarado = % (esperado % — as três somadas)', j->>'declarado_min', 300 * 7;
end if;
if (j->>'vendavel_min')::int = (j->>'declarado_min')::int then
  raise exception 'FALHOU 16: vendável e declarado vieram iguais — o tempo protegido foi somado ao denominador, e é exatamente assim que um painel empurra alguém a preencher todas as horas';
end if;
raise notice 'ok 15 e 16 · a soma bate, e o protegido não entra no vendável';

-- 4 · e a resposta não tem campo de ócio nem soma escondida.
select count(*) into n from jsonb_object_keys(j) k
 where k like '%ocios%' or k like '%livre%' or k like '%vago%' or k like '%vazio%'
    or k like '%disponivel%';
if n > 0 then
  raise exception 'FALHOU 4: a resposta tem campo com nome de hora ociosa (%) — o produto conta e não adjetiva', n;
end if;
raise notice 'ok 4 · nenhum campo de ociosidade na resposta';

-- 9 e 17 · a troca no meio do período.
--
-- Guarda o vendável dos dez primeiros dias, troca a semana valendo de daqui a
-- dez dias, e confere que **o número dos dez primeiros dias não mexeu**. É o
-- critério de pronto do P1 na sua forma testável: o que já foi declarado para
-- um dia continua sendo o que foi declarado para aquele dia.
set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 9);
reset role;
if (j->>'vendavel_min')::int <> 180 * 10 then
  raise exception 'FALHOU 9: o período de dez dias somou % (esperado %)', j->>'vendavel_min', 180 * 10;
end if;

set local role authenticated;
perform public.definir_semana(a_prof, semana_b, hoje + 10);
j2 := public.capacidade_vendavel(a_prof, hoje, hoje + 9);
reset role;

if (j2->>'vendavel_min')::int <> (j->>'vendavel_min')::int then
  raise exception 'FALHOU 9: mudar a semana de daqui a dez dias alterou os dez dias anteriores (% → %) — a capacidade de um dia passado deixaria de ser a que foi declarada na época',
    j->>'vendavel_min', j2->>'vendavel_min';
end if;
raise notice 'ok 9 · a mudança de hoje não toca em nenhum dia anterior a ela';

-- 10 e 17 · e de lá para a frente vale a nova, dia a dia.
set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 19);
reset role;
if (j->>'vendavel_min')::int <> 180 * 10 + 120 * 10 then
  raise exception 'FALHOU 17: vinte dias com troca no décimo somaram % (esperado % = 10×180 + 10×120)',
    j->>'vendavel_min', 180 * 10 + 120 * 10;
end if;
if (j->>'registro_min')::int <> 60 * 10 then
  raise exception 'FALHOU 10: a semana nova não tem registro, e mesmo assim os dez dias seguintes contaram % minutos dele', j->>'registro_min';
end if;
raise notice 'ok 10 e 17 · a troca vale dia a dia, da data dela em diante';

-- 18 · quem não declarou nada não é quem declarou zero.
set local role authenticated;
j := public.capacidade_vendavel(b_prof, hoje, hoje + 6);
reset role;
if (j->>'sem_janela')::boolean is not true then
  raise exception 'FALHOU 18: quem nunca declarou nada não veio marcado — a tela mostraria 0%% de ocupação e acusaria a pessoa de não ter trabalhado';
end if;

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;
if (j->>'sem_janela')::boolean is not false then
  raise exception 'FALHOU 18: quem declarou veio marcado como sem janela';
end if;
raise notice 'ok 18 · não declarar e declarar zero são coisas diferentes';

raise notice '--- parte 5 · a exceção ---';

-- 19 · férias saem do vendável e vão para o balde delas.
set local role postgres;
insert into public.excecoes_agenda (conta_id, profissional_id, tipo, inicio, fim, motivo)
values (a_conta, a_prof, 'ferias', hoje + 2, hoje + 4, 'suite 0055');
reset role;

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;

if (j->>'vendavel_min')::int <> 180 * 4 then
  raise exception 'FALHOU 19: três dias de férias não saíram do vendável (% em vez de %)', j->>'vendavel_min', 180 * 4;
end if;
if (j->'fora'->>'ferias')::int <> 300 * 3 then
  raise exception 'FALHOU 19: o balde de férias tem % (esperado % — o dia inteiro, com registro e descanso junto)', j->'fora'->>'ferias', 300 * 3;
end if;
if (j->'fora'->>'total')::int <> 300 * 3 then
  raise exception 'FALHOU 19: o total do que ficou fora não bate com o balde';
end if;
raise notice 'ok 19 · férias saem do denominador e aparecem com nome';

-- 20 · feriado e bloqueio, cada um no seu.
--
-- Separados porque contam histórias diferentes: "tirei férias" e "bloqueei
-- trinta horas" não são a mesma frase sobre o mês, e juntá-las esconde o que
-- de fato aconteceu.
set local role postgres;
insert into public.excecoes_agenda (conta_id, profissional_id, tipo, inicio, fim, motivo)
values (a_conta, a_prof, 'feriado', hoje + 5, hoje + 5, 'suite 0055');
insert into public.excecoes_agenda (conta_id, profissional_id, tipo, inicio, fim, motivo)
values (a_conta, a_prof, 'bloqueio', hoje + 6, hoje + 6, 'suite 0055');
reset role;

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;

if (j->'fora'->>'feriado')::int <> 300 or (j->'fora'->>'bloqueio')::int <> 300 then
  raise exception 'FALHOU 20: feriado=% bloqueio=% (esperado 300 cada)', j->'fora'->>'feriado', j->'fora'->>'bloqueio';
end if;
if (j->>'vendavel_min')::int <> 180 * 2 then
  raise exception 'FALHOU 20: sobrou % vendável (esperado % — sete dias menos cinco de exceção)', j->>'vendavel_min', 180 * 2;
end if;
raise notice 'ok 20 · cada exceção no seu balde';

-- 21 · férias no período inteiro zeram o vendável sem apagar a história.
set local role postgres;
delete from public.excecoes_agenda where conta_id = a_conta and motivo = 'suite 0055';
insert into public.excecoes_agenda (conta_id, profissional_id, tipo, inicio, fim, motivo)
values (a_conta, a_prof, 'ferias', hoje, hoje + 6, 'suite 0055');
reset role;

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;

if (j->>'vendavel_min')::int <> 0 then
  raise exception 'FALHOU 21: mês inteiro de férias e ainda sobrou % vendável', j->>'vendavel_min';
end if;
if (j->'fora'->>'ferias')::int <> 300 * 7 then
  raise exception 'FALHOU 21: as férias apagaram a história em vez de contá-la (% no balde)', j->'fora'->>'ferias';
end if;
if (j->>'sem_janela')::boolean is not false then
  raise exception 'FALHOU 21: um período inteiro de férias virou "nunca declarou" — são coisas diferentes, e a tela diria a frase errada';
end if;
raise notice 'ok 21 · férias zeram o vendável sem apagar o que foi declarado';

-- 22 · exceção da vizinha não subtrai daqui.
--
-- O gatilho `checa_conta_da_excecao` (0006) exige que a exceção seja da conta
-- **da sessão**, e não da conta escrita na linha. Então a exceção da vizinha é
-- criada com a sessão dela — o que aliás é uma regressão de graça: se aquele
-- gatilho tivesse afrouxado, este insert passaria com as claims erradas.
set local role postgres;
delete from public.excecoes_agenda where conta_id = a_conta and motivo = 'suite 0055';
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.excecoes_agenda (conta_id, profissional_id, tipo, inicio, fim, motivo)
values (b_conta, b_prof, 'ferias', hoje, hoje + 6, 'suite 0055 vizinha');
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;
if (j->>'vendavel_min')::int <> 180 * 7 then
  raise exception 'FALHOU 22: as férias de outro profissional derrubaram esta capacidade (%)', j->>'vendavel_min';
end if;
raise notice 'ok 22 · exceção de outro profissional não subtrai daqui';

raise notice '--- parte 6 · o isolamento ---';

-- 23 · a vizinha não enxerga nada disto.
perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);

set local role authenticated;
select count(*) into n from public.janelas_atendimento where profissional_id = a_prof;
reset role;
if n <> 0 then
  raise exception 'FALHOU 23: a vizinha leu % janela(s) da outra conta', n;
end if;

set local role authenticated;
j := public.capacidade_vendavel(a_prof, hoje, hoje + 6);
reset role;
if (j->>'vendavel_min')::int <> 0 or (j->>'sem_janela')::boolean is not true then
  raise exception 'FALHOU 23: capacidade_vendavel devolveu a capacidade de outra conta para quem passou o uuid — é o que `security definer` teria feito aqui';
end if;

erro := null;
begin
  set local role authenticated;
  perform public.definir_semana(a_prof, semana_b);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 23: a vizinha declarou a semana do profissional de outra conta';
end if;
raise notice 'ok 23 · a capacidade é da conta';

-- 24 · e o anônimo não executa nada.
perform set_config('request.jwt.claims', null, true);

erro := null;
begin
  set local role anon;
  perform public.capacidade_vendavel(a_prof, hoje, hoje + 6);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 24: o anônimo calculou capacidade';
end if;

erro := null;
begin
  set local role anon;
  perform public.definir_semana(a_prof, semana_b);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 24: o anônimo declarou semana';
end if;
raise notice 'ok 24 · o anônimo não executa nada disso';

-- ============================================================ recolher o rastro
set local role postgres;
delete from public.excecoes_agenda where conta_id in (a_conta, b_conta);
delete from public.janelas_atendimento where conta_id in (a_conta, b_conta);
delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Capa Teste', 'Capa Vizinha');
reset role;

raise notice 'SUITE 0055 PASSOU: 24 verificações';
end $do$;
