-- Teste do reajuste com data e do mês de férias (B36, migração 0073).
--
-- Dois defeitos de dinheiro, e os dois eram invisíveis por motivos diferentes.
--
-- O da **pausa** era invisível porque a metade certa existia ao lado: quem cobra
-- por sessão já saía proporcional (`sessoes_do_mes` conta sessão de verdade, e a
-- que a exceção apagou não está lá), e quem cobra mensalidade saía cheio. Duas
-- respostas para "quanto ela me deve por outubro", no mesmo mês e na mesma conta.
--
-- O do **reajuste** era invisível porque só aparece **um dia em sete**: com o
-- fecho no mesmo dia da abertura, a semana da virada cai nos dois combinados —
-- mas só se a data da virada for o dia de semana da sessão. Nas outras seis
-- vezes a conta fecha certinha.
--
--    1. o mês de férias sai proporcional às ocorrências que sobraram   ← decide
--    2. quem cobra por sessão continua saindo pela sessão
--    3. mês sem exceção nenhuma continua cheio
--    4. o fecho cai na véspera, e a semana da virada não é cobrada duas vezes ← decide
--    5. vigência no passado é recusada                                  ← decide
--    6. vigência no dia em que o combinado começou é recusada
--    7. a cópia do combinado vem do catálogo, não de uma lista escrita
--    8. a sessão já materializada antes da virada mantém o valor antigo  ← decide
--    9. férias saem do vendável pelo balde certo, e não viram perda      ← decide
--   10. mensalidades_a_rever só enxerga o que está aberto
--   11. rever_mensalidade recusa o que já foi pago
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0073_reajuste_com_data_e_o_mes_de_ferias.sql

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111173';
  v_conta uuid; v_prof uuid;
  v_ana uuid; v_bia uuid;
  v_enq_ana uuid; v_enq_bia uuid; v_novo uuid;
  v_cob uuid;
  v_r jsonb; v_n numeric; v_i integer; v_erro text;
  v_cap jsonb; v_livro jsonb;
  -- Outubro de 2026: as quartas caem em 07, 14, 21 e 28. Quatro.
  v_comp date := date '2026-10-01';
begin

delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Reajuste e Pausa';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'b36@teste.sessoes.com.br', '{"nome":"Reajuste e Pausa"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_conta, v_prof, 'Ana Mensalista', '5511900000731', 'em_atendimento') returning id into v_ana;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_conta, v_prof, 'Bia Por Sessão', '5511900000732', 'em_atendimento') returning id into v_bia;

-- Quartas às 15h. Ana paga R$ 800 fixos no mês; Bia paga por sessão.
insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, mensalidade_valor,
                              politica_horas, politica_percentual, vigencia_inicio)
  values (v_ana, 3, '15:00', 50, 200.00, 800.00, 24, 50, date '2026-01-07') returning id into v_enq_ana;
insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor,
                              politica_horas, politica_percentual, vigencia_inicio)
  values (v_bia, 3, '16:00', 50, 200.00, 24, 50, date '2026-01-07') returning id into v_enq_bia;

-- 3 · sem exceção nenhuma, o mês é cheio.
v_n := public.valor_da_mensalidade(v_enq_ana, v_comp);
if v_n <> 800.00 then
  raise exception 'FALHOU 3: mês sem exceção saiu em % — devia sair cheio', v_n;
end if;

-- 1 · férias de 12 a 25/10 tiram duas das quatro quartas.  ← decide
insert into public.excecoes_agenda (profissional_id, tipo, inicio, fim)
  values (v_prof, 'ferias', date '2026-10-12', date '2026-10-25');

v_n := public.valor_da_mensalidade(v_enq_ana, v_comp);
if v_n <> 400.00 then
  raise exception 'FALHOU 1: com metade do mês em férias a mensalidade saiu em % — devia sair 400,00. A paciente pagava quatro e recebia duas', v_n;
end if;

-- 2 · quem cobra por sessão continua respondendo pela sessão, e não pela
--     vigência: `sessoes_do_mes` conta o que existe na agenda.
v_n := public.valor_da_mensalidade(v_enq_bia, v_comp);
if v_n is null then
  raise exception 'FALHOU 2: o modelo por sessão parou de responder';
end if;

-- 9 · e o mês de férias não vira perda.  ← decide
--
-- A armadilha do arquivo da build, escrita como verificação: férias é
-- capacidade não declarada, não uma sequência de cancelamentos. Se os minutos
-- caíssem no vendável, o livro-razão encheria de "hora não ocupada" no mês em
-- que ela descansou.
insert into public.janelas_atendimento (profissional_id, dia_semana, inicio, fim, destino, vigencia_de)
  values (v_prof, 3, '14:00', '18:00', 'atendimento', date '2026-01-01');

v_cap := public.capacidade_vendavel(v_prof, date '2026-10-01', date '2026-10-31');

if (v_cap->'fora'->>'ferias')::int <= 0 then
  raise exception 'FALHOU 9: os minutos de férias não foram para o balde de férias';
end if;
if (v_cap->'fora'->>'ferias')::int <> 480 then
  raise exception 'FALHOU 9: duas quartas de 4h dariam 480 min, saiu %', (v_cap->'fora'->>'ferias')::int;
end if;
if (v_cap->>'vendavel_min')::int <> 480 then
  raise exception 'FALHOU 9: sobraram % min vendáveis — as duas quartas de férias continuam no denominador', (v_cap->>'vendavel_min')::int;
end if;

-- O livro só pode enxergar como "nunca vendida" o que estava no vendável. Com
-- 480 min vendáveis no mês, qualquer número acima disso significa que os 480 de
-- férias voltaram para o denominador pela porta dos fundos.
v_livro := public.livro_razao(v_prof, date '2026-10-01', date '2026-10-31');
if (select (c->>'minutos')::int
      from jsonb_array_elements(v_livro->'causas') c
     where c->>'causa' = 'hora_nunca_vendida') > 480 then
  raise exception 'FALHOU 9: a hora nunca vendida do mês contou o período de férias — férias é capacidade não declarada, não perda';
end if;

-- 4 · o fecho cai na véspera.  ← decide
--
-- 14/10 é quarta. Com o fecho no mesmo dia, aquela quarta cai nos dois
-- combinados e a mensalidade do mês a cobra duas vezes.
delete from public.excecoes_agenda where profissional_id = v_prof;

v_r := public.reajustar_enquadre(v_enq_ana, 240.00, 960.00, date '2026-10-14');

if (v_r->>'fechado_em')::date <> date '2026-10-13' then
  raise exception 'FALHOU 4: o combinado antigo foi fechado em % — a véspera de 14/10 é 13/10', v_r->>'fechado_em';
end if;

select id into v_novo from public.enquadres
 where paciente_id = v_ana and vigencia_fim is null;

if v_novo is null then raise exception 'FALHOU 4: ficou sem combinado aberto'; end if;

-- 07/10 no antigo (800/4 = 200) + 14, 21 e 28 no novo (960*3/4 = 720) = 920.
v_n := public.valor_da_mensalidade(v_enq_ana, v_comp)
     + public.valor_da_mensalidade(v_novo, v_comp);
if v_n <> 920.00 then
  raise exception 'FALHOU 4: o mês da virada saiu em % — esperado 920,00. Com o fecho no mesmo dia sai 1.120,00, e a semana de 14/10 é cobrada nos dois combinados', v_n;
end if;

-- 7 · a cópia veio do catálogo.
--
-- `confirmacao_horas_antes` é a coluna que a 0057 acrescentou depois de o
-- combinado existir. Uma lista escrita à mão dentro de `reajustar_enquadre`
-- teria deixado ela para trás, e o combinado novo nasceria sem pedir
-- confirmação — em silêncio.
update public.enquadres set confirmacao_horas_antes = 24 where id = v_novo;
v_r := public.reajustar_enquadre(v_novo, 260.00, 1040.00, date '2026-11-04');
select confirmacao_horas_antes into v_i from public.enquadres
 where paciente_id = v_ana and vigencia_fim is null;
if v_i is distinct from 24 then
  raise exception 'FALHOU 7: a cópia perdeu confirmacao_horas_antes — a lista escrita à mão esquece a coluna nova';
end if;

-- 5 · vigência no passado é recusada.  ← decide
begin
  perform public.reajustar_enquadre(
    (select id from public.enquadres where paciente_id = v_ana and vigencia_fim is null),
    300.00, null, public.hoje_sp() - 1);
  raise exception 'FALHOU 5: aceitou reajustar para trás — isso reescreveria o valor de sessão que já aconteceu';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 5' in v_erro) > 0 then raise; end if;
end;

-- 6 · vigência no dia em que o combinado começou é correção, não reajuste.
select id into v_novo from public.enquadres where paciente_id = v_ana and vigencia_fim is null;
begin
  perform public.reajustar_enquadre(v_novo, 300.00, null,
    (select vigencia_inicio from public.enquadres where id = v_novo));
  raise exception 'FALHOU 6: empilhou um combinado começando no mesmo dia do anterior';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 6' in v_erro) > 0 then raise; end if;
end;

-- 8 · a sessão já marcada mantém o valor da época.  ← decide
--
-- É a promessa que a tela faz antes de ela confirmar, e o produto inteiro
-- depende dela: o valor viaja **congelado na sessão**, não é lido do combinado
-- na hora de cobrar.
insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id,
                            inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (v_conta, v_prof, v_bia, v_enq_bia,
          (date '2026-09-30' + time '16:00') at time zone 'America/Sao_Paulo',
          (date '2026-09-30' + time '16:50') at time zone 'America/Sao_Paulo',
          'recorrencia', 'realizada', 200.00, 24, 50);

perform public.reajustar_enquadre(v_enq_bia, 260.00, null, public.hoje_sp() + 30);

select valor into v_n from public.sessoes
 where paciente_id = v_bia and estado = 'realizada';
if v_n <> 200.00 then
  raise exception 'FALHOU 8: a sessão que já aconteceu saiu para % — o reajuste reescreveu o passado', v_n;
end if;

-- 10 e 11 · a conferência das mensalidades.
insert into public.cobrancas (conta_id, paciente_id, enquadre_id, tipo, motivo, valor, competencia, estado)
  values (v_conta, v_ana, v_enq_ana, 'mensalidade', 'mensalidade', 800.00, v_comp, 'aberta')
  returning id into v_cob;

-- Sem exceção, a conta bate e ela não aparece.
if exists (select 1 from public.mensalidades_a_rever(v_comp, v_comp) x where x.cobranca = v_cob) then
  raise exception 'FALHOU 10: cobrança que bate com a conta do mês apareceu para rever';
end if;

insert into public.excecoes_agenda (profissional_id, tipo, inicio, fim)
  values (v_prof, 'ferias', date '2026-10-12', date '2026-10-25');

if not exists (select 1 from public.mensalidades_a_rever(v_comp, v_comp) x where x.cobranca = v_cob) then
  raise exception 'FALHOU 10: a pausa mudou a conta do mês e a cobrança aberta não apareceu para rever';
end if;

v_n := public.rever_mensalidade(v_cob);
if v_n <> 200.00 then
  raise exception 'FALHOU 10: rever devolveu % — 07/10 é a única quarta do combinado antigo fora das férias', v_n;
end if;

-- 11 · o que já foi pago não se mexe.
update public.cobrancas set estado = 'paga', paga_em = now() where id = v_cob;
begin
  perform public.rever_mensalidade(v_cob);
  raise exception 'FALHOU 11: reescreveu uma cobrança já paga';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 11' in v_erro) > 0 then raise; end if;
end;

if exists (select 1 from public.mensalidades_a_rever(v_comp, v_comp) x where x.cobranca = v_cob) then
  raise exception 'FALHOU 11: cobrança paga continua na lista de rever';
end if;

reset role;
perform set_config('request.jwt.claims', '', true);

set local role postgres;
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Reajuste e Pausa';
reset role;

raise notice 'OK · 0073 · o reajuste tem data e não reescreve o passado; o mês de férias sai proporcional e não vira perda';
end
$do$;
