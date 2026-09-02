-- Teste da política assistida (P4, migrações 0058 e 0058b).
--
-- Esta suíte é o avesso da 0022. A antiga provava que a cobrança **nasce
-- sozinha**; esta prova que ela **não nasce** — e as duas não podem estar
-- verdes ao mesmo tempo, o que é o ponto do build.
--
-- Três verificações decidem o arquivo:
--
--   · a **3**, que é uma ausência: cancelar tarde não enfileira mensagem
--     nenhuma. É a linha inteira do P4 num `count(*) = 0`;
--   · a **15**, que fecha a porta pelos fundos: nem um `insert` cru consegue
--     criar multa sem decisão, porque a política de insert de `cobrancas` é
--     aberta desde a 0022 e sempre foi (legitimamente, pela cobrança avulsa);
--   · a **27**, que varre o banco atrás de função que faça proposta caducar.
--     Prazo de validade seria a decisão automática voltando com o default do
--     lado bom — e voltando mesmo assim.
--
-- E a **24** é a fronteira: a cobrança da sessão **realizada** continua
-- nascendo sozinha, de propósito. Hora prestada é preço combinado, não juízo
-- sobre o motivo de ninguém. Se um dia alguém "consertar" isso achando que o
-- P4 mandava, esta verificação reprova.
--
--   parte 1 · a régua para de decidir
--     1. cancelar tarde não cria cobrança
--     2. cria pergunta, com o retrato da política congelado nela
--     3. e não enfileira aviso nenhum                          ← decide
--     4. a pergunta não move um centavo do financeiro
--
--   parte 2 · a caixa e o histórico
--     5. a caixa traz a proposta, os dias esperando e o histórico
--     6. o histórico é contagem, e não conselho
--
--   parte 3 · a decisão
--     7. cobrar cria a cobrança, e ela aponta para a decisão
--     8. só então o aviso entra na fila, com a janela do atraso
--     9. decidir duas vezes é impossível
--    10. perdoar nasce `perdoada`, guarda o motivo e não manda nada
--    11. perdão com valor é recusado
--    12. cobrar menos funciona
--    13. cobrar mais que a sessão valia é recusado
--    14. cobrar zero é recusado
--
--   parte 4 · as trancas
--    15. `insert` cru de multa é recusado pelo banco              ← decide
--    16. a tela não inventa proposta
--    17. descartar à mão enquanto a falta existe é recusado
--    18. proposta decidida não muda de estado
--
--   parte 5 · o que o gatilho ainda faz sozinho
--    19. desfazer a falta descarta a pergunta
--    20. refazer faz uma pergunta nova
--    21. o mesmo estado de novo não duplica
--    22. política de 0% não gera nem pergunta
--    23. quem avisou no prazo não gera nada
--    24. a sessão realizada continua cobrando sozinha           ← fronteira
--    25. mensalidade não vira pergunta
--
--   parte 6 · o resto
--    26. `perdoar_cobranca` passou a guardar o motivo (dívida da B11)
--    27. nenhuma função no banco faz proposta caducar            ← decide
--    28. a vizinha não vê nem decide
--    29. o anônimo não lê nem executa
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0058_politica_assistida.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111158';
  b_auth uuid := '22222222-2222-4222-8222-222222222158';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  ana uuid; bia uuid; caio uuid; duda uuid;
  e_mensal uuid;
  s_tarde uuid; s_falta uuid; s_zero uuid; s_prazo uuid; s_feita uuid; s_mensal uuid;
  p_tarde uuid; p_falta uuid; p_nova uuid;
  cob uuid; cob2 uuid; s_livre uuid;
  v numeric;
  fin_antes jsonb; fin_depois jsonb;
  j jsonb; h jsonb; n integer; erro text; r record;
  hoje date; base timestamptz;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Politica Teste', 'Politica Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'politica@teste.sessoes.com.br', '{"nome":"Politica Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (b_auth, 'politicaviz@teste.sessoes.com.br', '{"nome":"Politica Vizinha"}'::jsonb);

select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
select id into a_prof from public.profissionais where conta_id = a_conta;
select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
select id into b_prof from public.profissionais where conta_id = b_conta;

hoje := public.hoje_sp();
-- Daqui a três horas, com política de 24 horas: desmarcar agora é tardio.
base := now() + interval '3 hours';

perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Ana Politica', '5511900000581', 'em_atendimento') returning id into ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Bia Politica', '5511900000582', 'em_atendimento') returning id into bia;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Caio Politica', '5511900000583', 'em_atendimento') returning id into caio;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Duda Politica', '5511900000584', 'em_atendimento') returning id into duda;

fin_antes := public.financeiro_do_mes(date_trunc('month', hoje)::date,
                                      (date_trunc('month', hoje) + interval '1 month - 1 day')::date);
reset role;

raise notice '--- parte 1 · a régua para de decidir ---';

-- 1 e 2 · cancelar em cima da hora.
--
-- A B11 fazia nascer cobrança aqui. Agora nasce pergunta — e o retrato da
-- política vai junto, porque "por que R$ 100?" precisa de resposta **na tela da
-- decisão**, não depois dela.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, base, base + interval '50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_tarde;

perform public.cancelar_sessao(s_tarde, 'paciente');
reset role;

select count(*) into n from public.cobrancas where sessao_id = s_tarde;
if n <> 0 then
  raise exception 'FALHOU 1: a cobrança nasceu sozinha (% linha[s]) — é exatamente o que o P4 desfaz', n;
end if;
raise notice 'ok 1 · a cobrança não nasce sozinha';

select * into r from public.propostas_de_cobranca where sessao_id = s_tarde;
if not found then
  raise exception 'FALHOU 2: não gerou pergunta nenhuma — deixar de cobrar em silêncio é pior que cobrar sozinho';
end if;
if r.estado <> 'pendente' then
  raise exception 'FALHOU 2: proposta já nasceu %', r.estado;
end if;
if r.valor_sugerido <> 100.00 then
  raise exception 'FALHOU 2: sugeriu % (a política era 50%% de 200)', r.valor_sugerido;
end if;
if r.politica_percentual <> 50 or r.politica_horas <> 24 or r.valor_da_sessao <> 200.00 then
  raise exception 'FALHOU 2: não congelou o retrato da política na pergunta';
end if;
if r.motivo <> 'cancelada_tarde' then
  raise exception 'FALHOU 2: motivo %', r.motivo;
end if;
p_tarde := r.id;
raise notice 'ok 2 · a pergunta nasce com a política congelada';

-- 3 · A ausência que é o build inteiro.  ← decide
select count(*) into n
  from public.mensagens
 where conta_id = a_conta and template = 'aviso_de_cobranca';
if n <> 0 then
  raise exception 'FALHOU 3: % aviso(s) de cobrança na fila sem ninguém ter decidido nada', n;
end if;
raise notice 'ok 3 · nenhum aviso sai sem decisão';

-- 4 · E a pergunta não é dinheiro: o mês não se mexe.
--
-- É a razão de a proposta morar em tabela própria, e não como estado novo de
-- `cobrancas`. Onze funções leem aquela tabela; um estado novo entraria calado
-- em todas, e "a receber" passaria a incluir o que ninguém deve.
set local role authenticated;
fin_depois := public.financeiro_do_mes(date_trunc('month', hoje)::date,
                                       (date_trunc('month', hoje) + interval '1 month - 1 day')::date);
reset role;
if fin_depois <> fin_antes then
  raise exception 'FALHOU 4: a pergunta mexeu no financeiro — antes % / depois %', fin_antes, fin_depois;
end if;
raise notice 'ok 4 · pergunta não é dinheiro';

raise notice '--- parte 2 · a caixa e o histórico ---';

-- 5 · A caixa, com o que a decisão precisa ter à mão.
set local role authenticated;
select count(*) into n from public.decisoes_pendentes();
if n <> 1 then
  raise exception 'FALHOU 5: a caixa tem % decisões (esperado 1)', n;
end if;

select * into r from public.decisoes_pendentes();
reset role;
if r.paciente <> 'Ana Politica' then
  raise exception 'FALHOU 5: sem o nome de quem faltou, a decisão é sobre um uuid';
end if;
if r.dias_esperando is null or r.dias_esperando < 0 then
  raise exception 'FALHOU 5: dias esperando = %', r.dias_esperando;
end if;
if r.historico is null then
  raise exception 'FALHOU 5: a proposta veio sem histórico — o doc 30 pede a política congelada E o histórico';
end if;
raise notice 'ok 5 · a caixa traz o que a decisão precisa';

-- 6 · O histórico conta, e não aconselha.
--
-- Fronteira 3 do doc 11 aplicada onde ela mais escapa: um campo "sugestão" ou
-- "reincidente" aqui seria o software opinando sobre a relação clínica de
-- alguém a partir de uma contagem de faltas.
h := r.historico;
if h->>'faltas' is null or h->>'perdoadas' is null or h->>'realizadas' is null then
  raise exception 'FALHOU 6: o histórico não conta o básico';
end if;
if h ?| array['sugestao', 'sugerido', 'recomendacao', 'recomendado', 'risco',
              'reincidente', 'perfil', 'nota', 'score', 'classificacao'] then
  raise exception 'FALHOU 6: o histórico opina (%) — ele conta, quem lê é ela', h;
end if;
raise notice 'ok 6 · o histórico conta, não aconselha';

raise notice '--- parte 3 · a decisão ---';

-- 7 e 8 · Cobrar. A cobrança nasce, e ela sabe de onde veio.
set local role authenticated;
j := public.decidir_cobranca(p_tarde, 'cobrar');
reset role;

if j->>'decisao' <> 'cobrar' then raise exception 'FALHOU 7: %', j; end if;
if (j->>'ajustada')::boolean then raise exception 'FALHOU 7: marcou ajuste onde não houve'; end if;

cob := (j->>'cobranca_id')::uuid;
select * into r from public.cobrancas where id = cob;
if not found then raise exception 'FALHOU 7: a decisão não gerou cobrança'; end if;
if r.estado <> 'aberta' then raise exception 'FALHOU 7: nasceu %', r.estado; end if;
if r.valor <> 100.00 then raise exception 'FALHOU 7: valor %', r.valor; end if;
if r.tipo <> 'falta' or r.motivo <> 'cancelada_tarde' then
  raise exception 'FALHOU 7: tipo/motivo % / %', r.tipo, r.motivo;
end if;
if r.proposta_id <> p_tarde then
  raise exception 'FALHOU 7: a cobrança não aponta para a decisão que a gerou';
end if;
if r.politica_percentual <> 50 or r.valor_da_sessao <> 200.00 then
  raise exception 'FALHOU 7: o retrato da política não atravessou a decisão';
end if;
raise notice 'ok 7 · cobrar cria a cobrança, e ela aponta para a decisão';

select * into r from public.mensagens where chave_idem = 'cobranca:' || cob::text;
if not found then raise exception 'FALHOU 8: decidiu cobrar e o aviso não entrou na fila'; end if;
if r.template <> 'aviso_de_cobranca' then raise exception 'FALHOU 8: template %', r.template; end if;
if (r.params->>'valor_centavos')::bigint <> 10000 then
  raise exception 'FALHOU 8: centavos %', r.params->>'valor_centavos';
end if;
-- A hora de silêncio da B11 sobrevive, com razão nova: já não é janela de
-- perdão (o perdão agora vem antes), é o tempo de desfazer um clique.
if r.agendada_para < now() + interval '50 minutes' then
  raise exception 'FALHOU 8: o aviso sai em cima da decisão, sem espaço para desfazer';
end if;
if j->>'aviso' <> 'agendado' then
  raise exception 'FALHOU 8: a decisão não disse o que vai acontecer com o aviso (%)', j->>'aviso';
end if;
raise notice 'ok 8 · o aviso entra na fila só depois da decisão';

-- 9 · Decidir de novo é impossível — a segunda decisão criaria a segunda
-- cobrança, e a pessoa receberia duas mensagens pela mesma falta.
erro := null;
begin
  set local role authenticated;
  perform public.decidir_cobranca(p_tarde, 'perdoar');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 9: decidiu duas vezes a mesma proposta'; end if;
select count(*) into n from public.cobrancas where proposta_id = p_tarde;
if n <> 1 then raise exception 'FALHOU 9: % cobranças para uma decisão', n; end if;
raise notice 'ok 9 · uma pergunta, uma decisão';

-- 10 · Perdoar: nasce marcada, com o motivo, e sem mensagem.
--
-- A linha em `cobrancas` existe de propósito. A 0022 escreveu a razão e ela não
-- envelheceu: "quantas vezes ela abriu mão" é uma das coisas mais úteis que
-- este sistema devolve para alguém que acha que não sabe cobrar.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, base, base + interval '50 min', 'avulsa', 300.00, 24, 40)
  returning id into s_falta;
perform public.cancelar_sessao(s_falta, 'paciente');
reset role;

select id into p_falta from public.propostas_de_cobranca where sessao_id = s_falta;

set local role authenticated;
j := public.decidir_cobranca(p_falta, 'perdoar', null, 'primeira vez, e ela avisou depois');
reset role;

cob2 := (j->>'cobranca_id')::uuid;
select * into r from public.cobrancas where id = cob2;
if r.estado <> 'perdoada' then raise exception 'FALHOU 10: nasceu %', r.estado; end if;
if r.valor <> 120.00 then raise exception 'FALHOU 10: valor % (40%% de 300)', r.valor; end if;
if r.perdoada_em is null then raise exception 'FALHOU 10: perdão sem carimbo'; end if;
if r.perdoada_motivo is null then raise exception 'FALHOU 10: o motivo do perdão sumiu de novo'; end if;
if j->>'aviso' is not null then
  raise exception 'FALHOU 10: perdão com aviso (%) — robô avisando "foi perdoado" transforma um gesto em notificação', j->>'aviso';
end if;
select count(*) into n from public.mensagens where chave_idem = 'cobranca:' || cob2::text;
if n <> 0 then raise exception 'FALHOU 10: o perdão enfileirou mensagem'; end if;
raise notice 'ok 10 · perdoar marca, e não fala com ninguém';

-- 11 · Perdão com valor não existe. Cobrar menos é **cobrar**, e a diferença
-- importa: se perdão parcial contasse como perdão, a contagem de perdões
-- deixaria de significar coisa alguma.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, caio, base, base + interval '50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_zero;
perform public.cancelar_sessao(s_zero, 'paciente');
reset role;
select id into p_nova from public.propostas_de_cobranca where sessao_id = s_zero;

erro := null;
begin
  set local role authenticated;
  perform public.decidir_cobranca(p_nova, 'perdoar', 50.00);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 11: aceitou perdão pela metade'; end if;
raise notice 'ok 11 · perdão não tem valor';

-- 12 · Cobrar menos, que é o caso comum.
set local role authenticated;
j := public.decidir_cobranca(p_nova, 'cobrar', 50.00, 'cobrei metade, ela avisou tarde mas avisou');
reset role;
if not (j->>'ajustada')::boolean then raise exception 'FALHOU 12: não marcou o ajuste'; end if;
if (j->>'valor')::numeric <> 50.00 then raise exception 'FALHOU 12: valor %', j->>'valor'; end if;
select valor into v from public.cobrancas where id = (j->>'cobranca_id')::uuid;
if v <> 50.00 then raise exception 'FALHOU 12: a cobrança saiu com %', v; end if;
select * into r from public.propostas_de_cobranca where id = p_nova;
if r.valor_decidido <> 50.00 or r.motivo_da_decisao is null then
  raise exception 'FALHOU 12: a decisão não guardou o valor nem o motivo';
end if;
if r.decidida_por is null then
  raise exception 'FALHOU 12: decisão sem autor — é o que a trilha existe para responder';
end if;
raise notice 'ok 12 · cobrar menos funciona, e fica escrito';

-- 13 · Cobrar mais que a hora valia, não. Multa maior que o serviço não é
-- política de faltas, é penalidade, e nenhum combinado assinado previu isso.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, duda, base, base + interval '50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_prazo;
perform public.cancelar_sessao(s_prazo, 'paciente');
reset role;
select id into p_nova from public.propostas_de_cobranca where sessao_id = s_prazo;

erro := null;
begin
  set local role authenticated;
  perform public.decidir_cobranca(p_nova, 'cobrar', 250.00);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 13: aceitou cobrar mais do que a sessão valia'; end if;

-- 14 · E zero também não: quem não quer cobrar perdoa, e o perdão fica contado.
erro := null;
begin
  set local role authenticated;
  perform public.decidir_cobranca(p_nova, 'cobrar', 0);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 14: aceitou cobrança de zero'; end if;
raise notice 'ok 13 e 14 · o ajuste tem as duas bordas';

raise notice '--- parte 4 · as trancas ---';

-- 15 · A porta dos fundos.  ← decide
--
-- `cobrancas` tem política de insert aberta desde a 0022, e legitimamente — a
-- cobrança avulsa é criada pela tela. Sem esta tranca, "nenhuma multa nasce
-- sozinha" seria uma promessa sobre um gatilho, não uma propriedade do banco.
-- Sessão nova de propósito: uma que já tivesse cobrança viva seria recusada
-- pelo índice único da 0022, e a verificação passaria pelo motivo errado.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, base + interval '2 hours', base + interval '2 hours 50 min',
          'avulsa', 200.00, 24, 50)
  returning id into s_livre;
reset role;

erro := null;
begin
  set local role authenticated;
  insert into public.cobrancas
    (conta_id, paciente_id, sessao_id, tipo, motivo, valor, competencia)
    values (a_conta, ana, s_livre, 'falta', 'falta', 999.00, date_trunc('month', hoje)::date);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 15: um insert cru criou multa sem decisão nenhuma';
end if;
raise notice 'ok 15 · multa sem decisão o banco recusa';

-- 16 · E a tela não inventa a pergunta. Quem cria proposta é o fato — a sessão
-- que virou falta. Uma interface capaz de inventar multa é uma segunda régua,
-- desta vez sem política congelada.
erro := null;
begin
  set local role authenticated;
  insert into public.propostas_de_cobranca
    (conta_id, paciente_id, sessao_id, motivo, valor_sugerido, competencia)
    values (a_conta, ana, s_livre, 'falta', 500.00, date_trunc('month', hoje)::date);
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 16: a tela criou uma proposta de multa do nada';
end if;
raise notice 'ok 16 · a pergunta vem do fato, não da tela';

-- 17 · Descartar à mão enquanto a falta existe: não. Seria a decisão sumindo
-- sem deixar linha — nem cobrança, nem perdão, nem contagem.
select id into p_nova from public.propostas_de_cobranca
 where sessao_id = s_prazo and estado = 'pendente';
erro := null;
begin
  set local role authenticated;
  update public.propostas_de_cobranca set estado = 'descartada' where id = p_nova;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 17: descartou a pergunta com a falta ainda de pé';
end if;
raise notice 'ok 17 · descartar não é decidir';

-- 18 · E o que já foi decidido não volta atrás por update.
erro := null;
begin
  set local role authenticated;
  update public.propostas_de_cobranca set estado = 'pendente' where id = p_tarde;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 18: reabriu uma decisão já tomada'; end if;
raise notice 'ok 18 · decisão tomada não se reabre';

raise notice '--- parte 5 · o que o gatilho ainda faz sozinho ---';

-- 19 · Desfazer a falta descarta a pergunta. Uma decisão pendente sobre um fato
-- que deixou de existir é pior que nenhuma: é uma cobrança esperando um clique
-- distraído.
set local role postgres;
update public.sessoes set estado = 'prevista' where id = s_prazo;
reset role;
select estado into erro from public.propostas_de_cobranca where id = p_nova;
if erro <> 'descartada' then
  raise exception 'FALHOU 19: a pergunta sobreviveu ao desfazer (%)', erro;
end if;
raise notice 'ok 19 · desfazer a falta apaga a pergunta';

-- 20 e 21 · Refazer pergunta de novo; e o mesmo estado outra vez não duplica.
set local role postgres;
update public.sessoes set inicio = now() - interval '2 hours', fim = now() - interval '1 hour'
 where id = s_prazo;
update public.sessoes set estado = 'falta' where id = s_prazo;
reset role;

select count(*) into n from public.propostas_de_cobranca
 where sessao_id = s_prazo and estado = 'pendente';
if n <> 1 then raise exception 'FALHOU 20: % perguntas vivas para uma falta', n; end if;
select count(*) into n from public.propostas_de_cobranca where sessao_id = s_prazo;
if n <> 2 then raise exception 'FALHOU 20: a trilha ficou com % linhas (esperado 2)', n; end if;

set local role postgres;
update public.sessoes set estado = 'falta' where id = s_prazo;
reset role;
select count(*) into n from public.propostas_de_cobranca
 where sessao_id = s_prazo and estado = 'pendente';
if n <> 1 then raise exception 'FALHOU 21: duplicou a pergunta'; end if;
raise notice 'ok 20 e 21 · refazer pergunta de novo, sem duplicar';

-- 22 · Política de 0% não interrompe ninguém. Perguntar "quer cobrar R$ 0,00?"
-- é pior que a cobrança zerada que a B11 já recusava.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, base + interval '1 hour', base + interval '1 hour 50 min',
          'avulsa', 200.00, 24, 0)
  returning id into s_zero;
perform public.cancelar_sessao(s_zero, 'paciente');
reset role;
select count(*) into n from public.propostas_de_cobranca where sessao_id = s_zero;
if n <> 0 then raise exception 'FALHOU 22: pediu decisão sobre R$ 0,00'; end if;
raise notice 'ok 22 · zero por cento não vira pergunta';

-- 23 · E quem avisou no prazo não gera nada, como sempre.
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, now() + interval '5 days',
          now() + interval '5 days 50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_prazo;
perform public.cancelar_sessao(s_prazo, 'paciente');
reset role;
select count(*) into n from public.propostas_de_cobranca where sessao_id = s_prazo;
if n <> 0 then raise exception 'FALHOU 23: perguntou sobre quem avisou no prazo'; end if;
raise notice 'ok 23 · avisar no prazo não gera pergunta';

-- 24 · A FRONTEIRA.
--
-- A cobrança da sessão **realizada** continua nascendo sozinha, e tem de
-- continuar. Cobrar por uma hora prestada não é juízo sobre o motivo de
-- ninguém: é o preço combinado de um serviço entregue, e não existe exceção
-- clínica a ponderar. Pedir confirmação de cada uma transformaria a régua num
-- formulário diário.
set local role postgres;
update public.contas set cobra_sessao = true where id = a_conta;
reset role;

set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, caio, now() - interval '3 hours', now() - interval '2 hours',
          'avulsa', 180.00, 24, 50)
  returning id into s_feita;
reset role;

set local role postgres;
update public.sessoes set estado = 'realizada' where id = s_feita;
reset role;

select * into r from public.cobrancas where sessao_id = s_feita;
if not found then
  raise exception 'FALHOU 24: a cobrança da sessão prestada parou de nascer — o P4 é sobre a multa, não sobre o preço combinado';
end if;
if r.motivo <> 'sessao_realizada' or r.valor <> 180.00 then
  raise exception 'FALHOU 24: motivo % / valor %', r.motivo, r.valor;
end if;
if r.proposta_id is not null then
  raise exception 'FALHOU 24: a hora prestada virou pergunta';
end if;
select count(*) into n from public.propostas_de_cobranca where sessao_id = s_feita;
if n <> 0 then raise exception 'FALHOU 24: gerou % proposta(s) para uma hora prestada', n; end if;
raise notice 'ok 24 · hora prestada segue cobrando sozinha';

-- 25 · E a mensalidade não vira pergunta: a hora já está dentro do mês pago.
set local role postgres;
insert into public.enquadres
  (paciente_id, dia_semana, hora, duracao_min, valor,
   politica_horas, politica_percentual, modelo_cobranca)
  values (duda, 3, '11:00', 50, 200, 24, 50, 'mensal')
  returning id into e_mensal;

insert into public.sessoes
  (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, duda, e_mensal, now() - interval '30 hours',
          now() - interval '29 hours', 'recorrencia', 200.00, 24, 50)
  returning id into s_mensal;
update public.sessoes set estado = 'falta' where id = s_mensal;
reset role;

select count(*) into n from public.propostas_de_cobranca where sessao_id = s_mensal;
if n <> 0 then raise exception 'FALHOU 25: a falta do mensalista virou pergunta de multa'; end if;
raise notice 'ok 25 · mensalidade não vira pergunta';

raise notice '--- parte 6 · o resto ---';

-- 26 · A dívida da B11: `perdoar_cobranca` recebia o motivo desde a 0022 e o
-- jogava fora, porque não havia coluna. Num sistema cuja tese é que a pergunta
-- "por quê" importa, isso é defeito.
select id into cob from public.cobrancas
 where sessao_id = s_feita and estado = 'aberta';
set local role authenticated;
perform public.perdoar_cobranca(cob, 'a sessão foi curta, cobrei na próxima');
reset role;
select perdoada_motivo into erro from public.cobrancas where id = cob;
if erro is null then
  raise exception 'FALHOU 26: o motivo do perdão continua indo para o lixo';
end if;
raise notice 'ok 26 · o perdão passou a dizer por quê';

-- 27 · Nada faz proposta caducar.  ← decide
--
-- Prazo de validade seria a decisão automática de volta, com o default do lado
-- bom — e voltando mesmo assim. A caixa cresce; o remédio para a caixa cheia é
-- uma decisão em lote, que continua sendo decisão dela.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.prokind = 'f'
   and (
     -- Nome com cara de expirar proposta. A fila **legitimamente** tem
     -- `expirar_ofertas` e `expirar_ofertas_fixas` desde a B7 e a B22, e elas
     -- não têm nada com isto: a varredura pede as duas palavras juntas.
     p.proname ~ '(caduc|expir|vencer|descartar).*(proposta|decisao|cobranca)'
     or p.proname ~ '(proposta|decisao|multa).*(caduc|expir|vence)'
     or (
       -- quem escreve `descartada` em `propostas_de_cobranca` é o gatilho do
       -- fato, e mais ninguém — a tranca da transição só a menciona para
       -- recusá-la.
       pg_get_functiondef(p.oid) ~* 'propostas_de_cobranca'
       and pg_get_functiondef(p.oid) ~* 'descartada'
       and p.proname not in ('ao_mudar_estado_da_sessao', 'proposta_so_sai_por_decisao')
     )
   );
if n <> 0 then
  raise exception 'FALHOU 27: % função(ões) com cara de caducar proposta — sem decisão, nada acontece, e é escolha', n;
end if;
raise notice 'ok 27 · proposta não caduca';

-- 28 · A vizinha não vê nem decide.
perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*) into n from public.propostas_de_cobranca;
if n <> 0 then raise exception 'FALHOU 28: a vizinha viu % propostas da outra conta', n; end if;
select count(*) into n from public.decisoes_pendentes();
if n <> 0 then raise exception 'FALHOU 28: a caixa da vizinha veio com % decisões alheias', n; end if;
reset role;

select id into p_nova from public.propostas_de_cobranca
 where conta_id = a_conta and estado = 'pendente' limit 1;
if p_nova is null then
  raise exception 'FALHOU 28: o teste perdeu a proposta pendente que ia usar';
end if;
if true then
  erro := null;
  begin
    set local role authenticated;
    perform public.decidir_cobranca(p_nova, 'cobrar');
    reset role;
  exception when others then erro := sqlerrm;
  end;
  reset role;
  if erro is null then raise exception 'FALHOU 28: a vizinha decidiu a cobrança de outra conta'; end if;
end if;
raise notice 'ok 28 · a decisão é de quem atende';

-- 29 · E o anônimo não passa da porta.
perform set_config('request.jwt.claims', null, true);
set local role anon;
select count(*) into n from public.propostas_de_cobranca;
if n <> 0 then raise exception 'FALHOU 29: anon leu % propostas', n; end if;
erro := null;
begin
  perform public.decidir_cobranca(p_tarde, 'cobrar');
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then raise exception 'FALHOU 29: anon decidiu uma cobrança'; end if;
raise notice 'ok 29 · o anônimo não decide nada';

-- ============================================================ recolher o rastro
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.mensagens where conta_id in (a_conta, b_conta);
delete from public.eventos_fila where conta_id in (a_conta, b_conta);
delete from public.ofertas where conta_id in (a_conta, b_conta);
delete from public.fila_encaixe where conta_id in (a_conta, b_conta);
delete from public.recibos_rfb where conta_id in (a_conta, b_conta);
delete from public.propostas_de_cobranca where conta_id in (a_conta, b_conta);
delete from public.cobrancas where conta_id in (a_conta, b_conta);
delete from public.sessoes where conta_id in (a_conta, b_conta);
delete from public.enquadres where conta_id in (a_conta, b_conta);
delete from public.pacientes where conta_id in (a_conta, b_conta);
delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Politica Teste', 'Politica Vizinha');
reset role;

raise notice 'SUITE 0058 PASSOU: 29 verificações';
end $do$;
