-- Teste da fila de vaga fixa (critério de pronto da B22).
--
-- A verificação nº 1 é a que decide o build: **reajuste não abre vaga**. Se ela
-- falhar, toda vez que a psicóloga corrigir um honorário a lista de espera
-- recebe "abriu um horário nas terças" — sobre a terça de quem continua sendo
-- atendida. Não é um bug de tela: é uma mensagem errada no celular de duas
-- pessoas ao mesmo tempo.
--
--   1. reajuste não abre vaga fixa
--   2. mudança de horário também não
--   3. encerramento abre, com dia, hora, duração, valor e de quem era
--   4. e as sessões futuras daquele horário somem: a vaga é real
--   5. a elegibilidade é explicável: todo mundo, com o motivo
--   6. a ordem é a de chegada
--   7. a cascata oferece ao primeiro, com prazo de vaga fixa e a mensagem certa
--   8. uma oferta viva por vaga
--   9. recusar passa para a próxima, e quem recusou não recebe de novo
--  10. aceitar fecha a vaga no nome da pessoa
--  11. e **não** cria enquadre: valor e política não se decidem por um SIM
--  12. aceitar duas vezes não é possível
--  13. arquivar encerra o combinado e abre a vaga (alta)
--  14. duas vagas vivas no mesmo dia e hora é impossível
--  15. sem ninguém elegível, a vaga se fecha como sem_takers
--  16. o prazo vencido passa para a próxima
--  17. quem tem oferta nas duas filas: o SIM vale para a mais recente
--  18. e o SIM da vaga fixa não marca sessão nenhuma
--  19. regressão da B10: o SIM do encaixe continua marcando a sessão
--  20. a reentrega do provedor não age duas vezes
--  21. isolamento entre contas
--  22. o anônimo não lê nem executa nada
--  23. a fila não tem coluna de dinheiro — nunca vira leilão
--  24. a policy deixa a tela escrever, mas o índice segura a invariante
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0036_vaga_fixa.sql

-- ========================== parte 1 · o que abre vaga, e o que não abre

-- As linhas de idempotência do webhook nascem com `conta_id` nulo (é assim que
-- a 0021 as guarda: a mensagem chega antes de se saber de quem é). Nenhum
-- preâmbulo por conta as alcança, então a suíte passava na primeira execução e
-- falhava na segunda, na verificação 17, acusando "repetida" contra si mesma.
-- Suíte que não roda duas vezes seguidas mente na segunda.
delete from public.mensagens_recebidas where provedor = 'teste' and provedor_msg_id in ('w1','w2');

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; bia uuid; caio uuid;
  e1 uuid; e2 uuid; e3 uuid; n int; v record; d0 date;
begin
  delete from public.ofertas_fixas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.vagas_fixas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_entrada where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.remarcacoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacote_consumos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacotes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.documentos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.aceites where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.contratos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ofertas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.excecoes_agenda where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  d0 := public.hoje_sp();

  -- **As contas de teste vão para o Solo, e isto é da migração 0061.**
  --
  -- O gatilho de signup cria conta em `gratis`, e desde a 0061 o Grátis manda à
  -- mão: mensagem de template não-essencial nasce em `na_sua_mao`, o worker não a
  -- reserva, e oferta cuja mensagem está na mão dela não expira. Esta suíte testa
  -- o **motor automático**, que é o do plano pago — o caminho manual tem suíte
  -- própria, a 0061.
  --
  -- Sem esta linha a suíte testaria um plano que não é o que ela descreve, e
  -- falharia dizendo "nada expirou" sobre um sistema que está funcionando.
  set local role postgres;
  update public.contas set plano = 'solo' where id in (a_conta);
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Ana Reajuste','5511900000041','em_atendimento') returning id into ana;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Bia Mudanca','5511900000042','em_atendimento') returning id into bia;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Alta','5511900000043','em_atendimento') returning id into caio;

  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (ana,2,'08:00',50,200.00,24,50) returning id into e1;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (bia,2,'09:00',50,200.00,24,50) returning id into e2;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (caio,2,'10:00',50,200.00,24,50) returning id into e3;

  -- ---------------------------------------------------------------- 1
  update public.enquadres set vigencia_fim=d0, motivo_fim='reajuste' where id=e1;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,vigencia_inicio)
    values (ana,2,'08:00',50,240.00,24,50,d0);
  select count(*) into n from public.vagas_fixas where enquadre_id=e1;
  if n <> 0 then
    raise exception '1 FUROU: reajuste abriu vaga fixa — a lista de espera receberia a terça de quem continua sendo atendida'; end if;

  -- ---------------------------------------------------------------- 2
  update public.enquadres set vigencia_fim=d0, motivo_fim='mudanca_horario' where id=e2;
  select count(*) into n from public.vagas_fixas where enquadre_id=e2;
  if n <> 0 then raise exception '2 FUROU: mudança de horário abriu vaga fixa'; end if;

  -- ---------------------------------------------------------------- 3
  update public.enquadres set vigencia_fim=d0, motivo_fim='encerramento' where id=e3;
  select * into v from public.vagas_fixas where enquadre_id=e3;
  if not found then raise exception '3 FUROU: encerramento não abriu vaga fixa'; end if;
  if v.dia_semana <> 2 or v.hora <> time '10:00' or v.duracao_min <> 50 then
    raise exception '3 FUROU: a vaga não guardou o horário: % % %', v.dia_semana, v.hora, v.duracao_min; end if;
  if v.valor_anterior <> 200.00 then raise exception '3 FUROU: perdeu o valor anterior'; end if;
  if v.paciente_anterior <> caio then raise exception '3 FUROU: perdeu de quem era'; end if;
  if v.fechada_em is not null then raise exception '3 FUROU: a vaga já nasceu fechada'; end if;

  select count(*) into n from public.eventos_fila where vaga_fixa_id=v.id and tipo='vaga_fixa_aberta';
  if n <> 1 then raise exception '3 FUROU: não registrou o evento (%)', n; end if;

  -- ---------------------------------------------------------------- 4
  -- Depois do último dia de vigência, e não depois de agora — a hora de hoje
  -- ainda é do combinado que se encerra hoje. Ver a mesma correção na 0006.
  select count(*) into n from public.sessoes
   where enquadre_id=e3 and estado='prevista'
     and (inicio at time zone 'America/Sao_Paulo')::date > public.hoje_sp();
  if n <> 0 then raise exception '4 FUROU: sobraram % sessões previstas de um combinado encerrado', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · o que abre vaga: ok';
end $do$;

-- ============================= parte 2 · a cascata da fila de entrada

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid;
  vaga uuid; ofe uuid; ofe2 uuid; n int; r record; s text; falhou boolean; v record; b boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into vaga from public.vagas_fixas where conta_id=a_conta and fechada_em is null;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Dora Primeira','5511900000051','interessado') returning id into d1;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Eva Segunda','5511900000052','interessado') returning id into d2;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Fabi Calada','5511900000053','interessado') returning id into d3;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Gina Ocupada','5511900000054','em_atendimento') returning id into d4;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Hela Manha','5511900000055','interessado') returning id into d5;

  update public.pacientes set msg_canal='nao_avisar' where id=d3;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (d4,4,'18:00',50,200.00,24,50);

  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (d1, a_conta, now() - interval '30 days');
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (d2, a_conta, now() - interval '10 days');
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (d3, a_conta, now() - interval '40 days');
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (d4, a_conta, now() - interval '50 days');
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em, janelas)
    values (d5, a_conta, now() - interval '60 days', '[{"dias":[2],"de":"07:00","ate":"09:00"}]'::jsonb);

  -- ---------------------------------------------------------------- 5
  select count(*) into n from public.elegiveis_para_vaga_fixa(vaga);
  if n <> 5 then raise exception '5 FUROU: a lista não é explicável — devolveu % de 5 pessoas', n; end if;

  select * into r from public.elegiveis_para_vaga_fixa(vaga) where paciente_id=d3;
  if r.elegivel or r.motivo <> 'pediu para não ser avisado' then raise exception '5 FUROU: %', r.motivo; end if;

  select * into r from public.elegiveis_para_vaga_fixa(vaga) where paciente_id=d4;
  if r.elegivel or r.motivo <> 'já tem horário fixo' then raise exception '5 FUROU: %', r.motivo; end if;

  select * into r from public.elegiveis_para_vaga_fixa(vaga) where paciente_id=d5;
  if r.elegivel or r.motivo <> 'fora da janela' then raise exception '5 FUROU: %', r.motivo; end if;

  -- ---------------------------------------------------------------- 6
  select * into r from public.elegiveis_para_vaga_fixa(vaga) where elegivel order by ordem limit 1;
  if r.paciente_id <> d1 then raise exception '6 FUROU: a ordem não é a de chegada'; end if;

  -- ---------------------------------------------------------------- 7
  ofe := public.avancar_fila_fixa(vaga);
  if ofe is null then raise exception '7 FUROU: a cascata não ofereceu a ninguém'; end if;
  select * into r from public.ofertas_fixas where id=ofe;
  if r.paciente_id <> d1 then raise exception '7 FUROU: ofereceu para quem não era o primeiro'; end if;
  if r.expira_em < now() + interval '23 hours' then
    raise exception '7 FUROU: prazo curto demais para uma vaga fixa (%)', r.expira_em; end if;

  select count(*) into n from public.mensagens
   where chave_idem = 'ofertafixa:'||ofe::text and template='oferta_de_vaga_fixa';
  if n <> 1 then raise exception '7 FUROU: não enfileirou a mensagem da vaga fixa (%)', n; end if;
  select count(*) into n from public.mensagens
   where chave_idem = 'ofertafixa:'||ofe::text and params->>'horario_fixo' = 'terça, 10h';
  if n <> 1 then raise exception '7 FUROU: o rótulo do horário não foi junto'; end if;

  -- ---------------------------------------------------------------- 8
  if public.avancar_fila_fixa(vaga) is not null then
    raise exception '8 FUROU: abriu uma segunda oferta viva para a mesma vaga'; end if;

  -- ---------------------------------------------------------------- 9
  s := public.responder_oferta_fixa(ofe, 'recusada');
  if s <> 'recusada' then raise exception '9 FUROU: %', s; end if;
  select * into r from public.ofertas_fixas where vaga_id=vaga and estado='enviada';
  if not found then raise exception '9 FUROU: recusar não passou para a próxima'; end if;
  if r.paciente_id <> d2 then raise exception '9 FUROU: a próxima não é a Eva'; end if;
  ofe2 := r.id;

  select * into r from public.elegiveis_para_vaga_fixa(vaga) where paciente_id=d1;
  if r.elegivel or r.motivo <> 'já recusou esta vaga' then
    raise exception '9 FUROU: quem recusou voltaria a receber: %', r.motivo; end if;

  -- ---------------------------------------------------------------- 10
  s := public.responder_oferta_fixa(ofe2, 'aceita');
  if s <> 'aceita' then raise exception '10 FUROU: %', s; end if;

  select * into v from public.vagas_fixas where id=vaga;
  if v.fechada_por <> 'preenchida' then raise exception '10 FUROU: a vaga não fechou (%)', v.fechada_por; end if;
  if v.novo_paciente <> d2 then raise exception '10 FUROU: não guardou quem ficou com ela'; end if;

  -- ---------------------------------------------------------------- 11
  select count(*) into n from public.enquadres where paciente_id=d2;
  if n <> 0 then
    raise exception '11 FUROU: o sistema combinou enquadre sozinho — valor e política decididos por um SIM no WhatsApp'; end if;

  select count(*) into n from public.eventos_fila where vaga_fixa_id=vaga and tipo='vaga_fixa_preenchida';
  if n <> 1 then raise exception '11 FUROU: não registrou o preenchimento'; end if;

  select ativo into b from public.fila_entrada where paciente_id=d2;
  if b then raise exception '11 FUROU: quem conseguiu a vaga continua na fila de entrada'; end if;

  -- ---------------------------------------------------------------- 12
  falhou := false;
  begin perform public.responder_oferta_fixa(ofe2, 'aceita');
  exception when others then falhou := true; end;
  if not falhou then raise exception '12 FUROU: aceitou duas vezes'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · a cascata: ok';
end $do$;

-- ================== parte 3 · a alta, o prazo e as duas filas no webhook

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; iara uuid; joana uuid;
  v2 uuid; v3 uuid; ofe uuid; ofe_enc uuid; s_enc uuid;
  n int; j jsonb; falhou boolean; r record; e_ana uuid; h time;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into ana from public.pacientes where conta_id=a_conta and nome='Ana Reajuste';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 13
  select id into e_ana from public.enquadres where paciente_id=ana and vigencia_fim is null;
  insert into public.fila_encaixe (conta_id, paciente_id) values (a_conta, ana);

  perform public.arquivar_paciente(ana, 'Alta combinada em sessão, com fechamento do processo.', 'alta');

  select count(*) into n from public.enquadres where id=e_ana and vigencia_fim is null;
  if n <> 0 then
    raise exception '13 FUROU: arquivar deixou o combinado aberto — a agenda seguiria criando sessões para quem não vem mais'; end if;

  select * into r from public.vagas_fixas where enquadre_id=e_ana;
  if not found then raise exception '13 FUROU: arquivar não abriu a vaga fixa'; end if;
  if r.motivo <> 'alta' then raise exception '13 FUROU: motivo % (esperado alta)', r.motivo; end if;
  v2 := r.id; h := r.hora;

  select count(*) into n from public.fila_encaixe where paciente_id=ana;
  if n <> 0 then raise exception '13 FUROU: a ficha arquivada ficou na fila de encaixe'; end if;

  -- ---------------------------------------------------------------- 14
  falhou := false;
  begin perform public.abrir_vaga_fixa(a_prof, 2::smallint, h, 50::smallint, 'abandono');
  exception when others then falhou := true; end;
  if not falhou then raise exception '14 FUROU: duas vagas vivas no mesmo dia e hora'; end if;

  v3 := public.abrir_vaga_fixa(a_prof, 5::smallint, '19:00'::time, 50::smallint, 'abandono');
  if v3 is null then raise exception '14 FUROU: não abriu vaga à mão'; end if;

  -- ---------------------------------------------------------------- 15
  update public.fila_entrada set ativo=false where conta_id=a_conta;
  if public.avancar_fila_fixa(v3) is not null then
    raise exception '15 FUROU: ofereceu para uma fila vazia'; end if;
  select * into r from public.vagas_fixas where id=v3;
  if r.fechada_por <> 'sem_takers' then
    raise exception '15 FUROU: a vaga sem ninguém não se fechou (%)', r.fechada_por; end if;

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Iara Dupla','5511900000061','interessado') returning id into iara;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Joana Fila','5511900000062','interessado') returning id into joana;
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (iara, a_conta, now() - interval '5 days');
  insert into public.fila_entrada (paciente_id, conta_id, entrou_em) values (joana, a_conta, now() - interval '1 day');

  -- ---------------------------------------------------------------- 16
  ofe := public.avancar_fila_fixa(v2);
  if ofe is null then raise exception '16 FUROU: não ofereceu a vaga da alta'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.ofertas_fixas
     set enviar_em = now() - interval '2 hours', expira_em = now() - interval '1 minute'
   where id=ofe;
  select public.expirar_ofertas_fixas() into n;
  if n < 1 then raise exception '16 FUROU: não expirou (%)', n; end if;
  select * into r from public.ofertas_fixas where vaga_id=v2 and estado='enviada';
  if not found then raise exception '16 FUROU: expirar não passou para a próxima'; end if;
  if r.paciente_id <> joana then raise exception '16 FUROU: a próxima não é a Joana'; end if;
  ofe := r.id;

  -- Uma pessoa pode esperar as duas coisas: uma hora extra e um horário fixo.
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.fila_encaixe (conta_id, paciente_id) values (a_conta, joana);

  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,cancelada_em,cancelada_por,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,iara, now()+interval '4 days', now()+interval '4 days 50 minutes','recorrencia','cancelada_cedo',now(),'paciente',200.00,24,50)
  returning id into s_enc;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  ofe_enc := public.abrir_vaga(s_enc);
  if ofe_enc is null then raise exception '17 FUROU: a fila de encaixe não ofereceu'; end if;
  if (select paciente_id from public.ofertas where id=ofe_enc) <> joana then
    raise exception '17 FUROU: o encaixe não foi para a Joana'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.ofertas set enviar_em = now() - interval '2 hours' where id=ofe_enc;
  update public.ofertas_fixas set enviar_em = now() - interval '1 hour' where id=ofe;

  -- ---------------------------------------------------------------- 17
  j := public.responder_do_whatsapp('teste','w1','5511900000062','sim');
  -- **Lição da 0058c**, e ela é sobre testes, não sobre filas: comparar
  -- `j->>'fila'` com um texto **não acusa a chave que sumiu**. Em SQL,
  -- `null <> 'entrada'` é nulo, e um `if` sobre nulo não dispara. Foi assim que
  -- a 0057 apagou a fila de entrada desta função e esta suíte continuou verde.
  -- Primeiro se cobra a existência da chave; depois o valor dela.
  if not (j ? 'fila') then
    raise exception '17 FUROU: a resposta voltou sem dizer de que fila era: %', j; end if;
  if j->>'fila' <> 'entrada' then raise exception '17 FUROU: o SIM foi para a fila %', j->>'fila'; end if;
  if j->>'estado' <> 'aceita' then raise exception '17 FUROU: %', j; end if;

  -- ---------------------------------------------------------------- 18
  -- `is distinct from` e não `<>`, pela mesma razão de cima: com a vaga ainda
  -- aberta, `fechada_por` é nulo, e a comparação crua não reprovaria nada.
  if (select fechada_por from public.vagas_fixas where id=v2) is distinct from 'preenchida' then
    raise exception '18 FUROU: a vaga fixa não foi preenchida pelo SIM'; end if;
  select count(*) into n from public.sessoes where paciente_id=joana;
  if n <> 0 then
    raise exception '18 FUROU: o SIM da vaga fixa marcou uma sessão — a pessoa apareceria num dia que ninguém combinou'; end if;

  -- ---------------------------------------------------------------- 19
  j := public.responder_do_whatsapp('teste','w2','5511900000062','sim');
  if j->>'fila' <> 'encaixe' then raise exception '19 FUROU: fila %', j->>'fila'; end if;
  if j->>'estado' <> 'aceita' then raise exception '19 FUROU: %', j; end if;
  select count(*) into n from public.sessoes
   where paciente_id=joana and origem='encaixe' and estado='prevista';
  if n <> 1 then raise exception '19 FUROU: o encaixe não criou a sessão (%)', n; end if;

  -- ---------------------------------------------------------------- 20
  j := public.responder_do_whatsapp('teste','w2','5511900000062','sim');
  if j->>'estado' <> 'repetida' then raise exception '20 FUROU: a reentrega agiu duas vezes: %', j; end if;

  raise notice 'parte 3 · a alta e as duas filas: ok';
end $do$;

-- ================================== parte 4 · fronteiras e a que não se cruza

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  vaga uuid; ofe uuid; n int; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into vaga from public.vagas_fixas where conta_id=a_conta limit 1;
  select id into ofe from public.ofertas_fixas where conta_id=a_conta limit 1;

  -- ---------------------------------------------------------------- 21
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.ofertas_fixas where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.vagas_fixas where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.fila_entrada where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bruna Solo';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.vagas_fixas;
  if n <> 0 then raise exception '21 FUROU: a Bruna vê % vagas fixas da Ana', n; end if;
  select count(*) into n from public.fila_entrada;
  if n <> 0 then raise exception '21 FUROU: a Bruna vê % pessoas na fila de entrada da Ana', n; end if;
  select count(*) into n from public.ofertas_fixas;
  if n <> 0 then raise exception '21 FUROU: a Bruna vê % ofertas da Ana', n; end if;
  select count(*) into n from public.elegiveis_para_vaga_fixa(vaga);
  if n <> 0 then raise exception '21 FUROU: a Bruna leu a fila da Ana (%)', n; end if;

  falhou := false;
  begin perform public.abrir_vaga_fixa(a_prof, 3::smallint, '11:00'::time, 50::smallint, 'outro');
  exception when others then falhou := true; end;
  if not falhou then raise exception '21 FUROU: a Bruna abriu vaga na agenda de um profissional da Ana'; end if;

  perform public.fechar_vaga_fixa(vaga, 'cancelada');
  if (select fechada_por from public.vagas_fixas where id=vaga) = 'cancelada' then
    raise exception '21 FUROU: a Bruna fechou uma vaga da Ana'; end if;

  -- ---------------------------------------------------------------- 22
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.vagas_fixas;
  if n <> 0 then raise exception '22 FUROU: anon leu vagas fixas'; end if;
  select count(*) into n from public.fila_entrada;
  if n <> 0 then raise exception '22 FUROU: anon leu a fila de entrada'; end if;

  falhou := false;
  begin perform public.abrir_vaga_fixa(a_prof, 3::smallint, '11:00'::time, 50::smallint, 'outro');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '22 FUROU: anon abriu vaga fixa'; end if;

  falhou := false;
  begin perform public.avancar_fila_fixa(vaga);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '22 FUROU: anon rodou a cascata'; end if;

  falhou := false;
  begin perform public.responder_oferta_fixa(ofe, 'aceita');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '22 FUROU: anon respondeu por outra pessoa'; end if;

  falhou := false;
  begin perform public.expirar_ofertas_fixas();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '22 FUROU: anon rodou o expurgo de ofertas'; end if;

  falhou := false;
  begin perform public.elegiveis_para_vaga_fixa(vaga);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '22 FUROU: anon leu a fila'; end if;

  -- ---------------------------------------------------------------- 23
  -- A fila nunca vira leilão (doc 11): não existe coluna que permita ordenar
  -- por dinheiro. É teste de estrutura de propósito — a fronteira que se guarda
  -- com atenção é a que se atravessa numa sexta-feira.
  reset role; perform set_config('request.jwt.claims','',true);
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name in ('fila_entrada','fila_encaixe')
     and column_name ~ '(valor|preco|pagamento|plano|tarifa|lance)';
  if n <> 0 then
    raise exception '23 FUROU: a fila ganhou % coluna(s) de dinheiro — é o começo do leilão', n; end if;

  -- ---------------------------------------------------------------- 24
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select v.id into vaga from public.vagas_fixas v where v.conta_id=a_conta and v.fechada_em is null limit 1;
  if vaga is null then
    vaga := public.abrir_vaga_fixa(a_prof, 3::smallint, '11:00'::time, 50::smallint, 'outro');
  end if;

  insert into public.ofertas_fixas (conta_id, vaga_id, paciente_id, expira_em)
  select a_conta, vaga, p.id, now() + interval '1 day'
    from public.pacientes p where p.conta_id=a_conta limit 1;

  falhou := false;
  begin
    insert into public.ofertas_fixas (conta_id, vaga_id, paciente_id, expira_em)
    select a_conta, vaga, p.id, now() + interval '1 day'
      from public.pacientes p where p.conta_id=a_conta offset 1 limit 1;
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '24 FUROU: duas ofertas vivas para a mesma vaga — a fila virou broadcast'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 4 · fronteiras: ok';
  raise notice '0036 · 24 verificações passaram.';
end $do$;

-- ==================== o desmonte
--
-- O preâmbulo limpa o rastro da rodada passada; este bloco limpa o da rodada
-- de agora. Só o segundo devolve o banco como o encontrou — e sem ele a conta
-- fica de pé com `is_teste = false`, porque quem nasce pelo gatilho de
-- `auth.users` nasce como conta de verdade e vira linha em toda métrica de
-- operação do painel do negócio.
--
-- A conta leva o resto por cascata; o `auth.users` sai depois dela, porque
-- `pacientes.profissional_id` e `registros.profissional_id` são RESTRICT e a
-- ordem inversa trava.
do $do$
declare c uuid;
begin
  for c in select id from public.contas where nome in ('Ana Solo','Bruna Solo') loop
    delete from public.contas where id = c;
  end loop;
  delete from auth.users where id in ('11111111-1111-4111-8111-111111111111',
                                      '22222222-2222-4222-8222-222222222222');
  if exists (select 1 from public.contas where nome in ('Ana Solo','Bruna Solo')) then
    raise exception 'DESMONTE FUROU: sobrou conta de teste no banco'; end if;
  raise notice 'desmonte: ok';
end $do$;
