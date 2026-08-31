-- Teste do outbox (critério de pronto da B9).
--
-- O outbox é a peça que faz o app falar com o mundo. Por isso ele é testado
-- pelo avesso: não "será que envia?", e sim "o que acontece quando alguém
-- tenta enganá-lo?".
--
--   1. enfileirar cria mensagem pendente com o destino do cadastro
--   2. idempotência: a mesma chave duas vezes é uma mensagem só
--   3. destino forjado é descartado — vale o cadastro
--   4. canal forjado é descartado
--   5. estado forjado ('enviada') nasce pendente do mesmo jeito
--   6. tentativas e provedor forjados também
--   7. janela de silêncio é invariante: 23h30 vira 8h
--   8. silêncio vale também para um insert direto com horário forjado
--   9. agendar no passado não faz a mensagem nascer atrasada
--  10. quem pediu para não ser avisado: enfileirar devolve null
--  11. ... e o insert direto levanta exceção
--  12. paciente sem contato no canal escolhido levanta exceção
--  13. template fora da lista fechada é recusado pela restrição
--  14. mensagem sem paciente é recusada
--  15. a reserva é atômica: sai de pendente e conta a tentativa
--  16. o que já está reservado não é reservado de novo
--  17. o que está agendado para o futuro não é reservado
--  18. marcar_enviada grava provedor e id externo
--  19. marcar_falha devolve para a fila com espera crescente
--  20. depois de 5 tentativas, desiste
--  21. destravar devolve o que ficou preso em 'enviando'
--  22. a cascata enfileira de verdade, com a oferta como chave
--  23. avançar a fila de novo não duplica a mensagem da mesma oferta
--  24. o app não muda estado de envio (sem política de update)
--  25. o app não apaga trilha de mensagem (sem política de delete)
--  26. outra conta não lê as mensagens desta
--  27. o anônimo não lê nada
--  28. o anônimo não executa as funções do worker
--  29. nem o motor da fila da B7 (o revoke que faltava, 0018)
--  30. desistir do definitivo é do worker, e não gasta tentativa
--  31. ... e não mexe no que já saiu
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0017_outbox.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; calado uuid; semzap uuid; b_pac uuid;
  vaga uuid; of1 uuid; m1 uuid; m2 uuid; msg uuid; b_msg uuid;
  terca timestamptz; noite timestamptz; esperado timestamptz;
  n int; r text; linha record; agendou timestamptz; falhou boolean;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.mensagens     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.eventos_fila  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth, b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data)
  values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  insert into auth.users (id,email,raw_user_meta_data)
  values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Maria Fernanda Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado,msg_canal)
    values (a_prof,'Teresa Quieta','5511900000003','em_atendimento','nao_avisar') returning id into calado;
  insert into public.pacientes (profissional_id,nome,email,estado,msg_canal)
    values (a_prof,'Otávio Só E-mail','otavio@teste.sessoes.com.br','em_atendimento','email') returning id into semzap;

  -- ---------------------------------------------------------------- 1
  select public.enfileirar_mensagem(maria,'lembrete_de_sessao','t1') into m1;
  if m1 is null then raise exception '1 FUROU: não enfileirou'; end if;
  select * into linha from public.mensagens where id=m1;
  if linha.estado <> 'pendente' then raise exception '1 FUROU: estado %', linha.estado; end if;
  if linha.canal <> 'whatsapp' then raise exception '1 FUROU: canal %', linha.canal; end if;
  if linha.destino <> '5511900000001' then raise exception '1 FUROU: destino %', linha.destino; end if;
  if linha.conta_id <> a_conta then raise exception '1 FUROU: conta errada'; end if;
  if linha.params->>'nome' <> 'Maria Fernanda Reis' then raise exception '1 FUROU: nome não viajou'; end if;
  if linha.params->>'modo' <> 'discreto' then raise exception '1 FUROU: modo não viajou'; end if;

  -- ---------------------------------------------------------------- 2
  if public.enfileirar_mensagem(maria,'lembrete_de_sessao','t1') is not null then
    raise exception '2 FUROU: a mesma chave enfileirou duas vezes'; end if;
  select count(*) into n from public.mensagens where chave_idem='t1';
  if n <> 1 then raise exception '2 FUROU: % linhas para a mesma chave', n; end if;

  -- ------------------------------------------------------------ 3, 4, 5, 6
  -- Um PATCH direto no PostgREST tentando mandar para um número de fora,
  -- por um canal que o paciente não escolheu, já marcado como entregue.
  insert into public.mensagens
    (conta_id,paciente_id,canal,template,destino,chave_idem,estado,tentativas,provedor,provedor_msg_id)
  values
    (a_conta,maria,'sms','lembrete_de_sessao','+5599999999999','t2','enviada',9,'inventado','abc')
  returning id into m2;

  select * into linha from public.mensagens where id=m2;
  if linha.destino <> '5511900000001' then raise exception '3 FUROU: destino forjado sobreviveu (%)', linha.destino; end if;
  if linha.canal   <> 'whatsapp'      then raise exception '4 FUROU: canal forjado sobreviveu (%)', linha.canal; end if;
  if linha.estado  <> 'pendente'      then raise exception '5 FUROU: nasceu % ', linha.estado; end if;
  if linha.tentativas <> 0            then raise exception '6 FUROU: tentativas %', linha.tentativas; end if;
  if linha.provedor is not null or linha.provedor_msg_id is not null then
    raise exception '6 FUROU: provedor forjado sobreviveu'; end if;

  -- ---------------------------------------------------------------- 7
  -- Silêncio padrão da conta. 23h30 de hoje em SP tem de virar o fim do
  -- silêncio no dia seguinte.
  noite := ((now() at time zone 'America/Sao_Paulo')::date + time '23:30') at time zone 'America/Sao_Paulo';
  esperado := public.proximo_envio(a_conta, noite);
  if esperado = noite then raise exception '7 FUROU: preparo — 23h30 não caiu no silêncio da conta'; end if;

  select public.enfileirar_mensagem(maria,'lembrete_de_sessao','t3','{}'::jsonb, noite) into msg;
  select agendada_para into agendou from public.mensagens where id=msg;
  if agendou <> esperado then raise exception '7 FUROU: agendou % (esperado %)', agendou, esperado; end if;

  -- ---------------------------------------------------------------- 8
  insert into public.mensagens (conta_id,paciente_id,canal,template,destino,chave_idem,agendada_para)
  values (a_conta,maria,'whatsapp','lembrete_de_sessao','5511900000001','t4', noite)
  returning id into msg;
  select agendada_para into agendou from public.mensagens where id=msg;
  if agendou <> esperado then raise exception '8 FUROU: insert direto furou o silêncio (%)', agendou; end if;

  -- ---------------------------------------------------------------- 9
  select public.enfileirar_mensagem(caio,'lembrete_de_sessao','t5','{}'::jsonb, now() - interval '2 days') into msg;
  select agendada_para into agendou from public.mensagens where id=msg;
  if agendou < now() - interval '1 minute' then
    raise exception '9 FUROU: nasceu atrasada (%)', agendou; end if;

  -- ---------------------------------------------------------------- 10
  if public.enfileirar_mensagem(calado,'lembrete_de_sessao','t6') is not null then
    raise exception '10 FUROU: enfileirou para quem pediu para não ser avisado'; end if;
  select count(*) into n from public.mensagens where paciente_id=calado;
  if n <> 0 then raise exception '10 FUROU: criou linha para quem não quer aviso'; end if;

  -- ---------------------------------------------------------------- 11
  falhou := false;
  begin
    insert into public.mensagens (conta_id,paciente_id,canal,template,destino,chave_idem)
    values (a_conta,calado,'whatsapp','lembrete_de_sessao','5511900000003','t7');
  exception when others then
    falhou := true;
    if sqlerrm not like '%não ser avisado%' then raise; end if;
  end;
  if not falhou then raise exception '11 FUROU: insert direto burlou o "não avisar"'; end if;

  -- ---------------------------------------------------------------- 12
  update public.pacientes set msg_canal='email' where id=caio;   -- Caio não tem e-mail
  falhou := false;
  begin
    perform public.enfileirar_mensagem(caio,'lembrete_de_sessao','t8');
  exception when others then
    falhou := true;
    if sqlerrm not like '%e-mail%' then raise; end if;
  end;
  if not falhou then raise exception '12 FUROU: prometeu canal que o cadastro não tem'; end if;
  update public.pacientes set msg_canal='whatsapp' where id=caio;

  -- O caminho feliz do e-mail: destino sai do campo certo.
  select public.enfileirar_mensagem(semzap,'lembrete_de_sessao','t9') into msg;
  if (select destino from public.mensagens where id=msg) <> 'otavio@teste.sessoes.com.br' then
    raise exception '12 FUROU: destino de e-mail errado'; end if;

  -- ---------------------------------------------------------------- 13
  falhou := false;
  begin
    insert into public.mensagens (conta_id,paciente_id,canal,template,destino,chave_idem)
    values (a_conta,maria,'whatsapp','promocao_de_black_friday','5511900000001','t10');
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '13 FUROU: aceitou template fora da lista'; end if;

  -- ---------------------------------------------------------------- 14
  falhou := false;
  begin
    insert into public.mensagens (conta_id,paciente_id,canal,template,destino,chave_idem)
    values (a_conta,null,'whatsapp','lembrete_de_sessao','5511900000001','t11');
  exception when others then
    falhou := true;
    if sqlerrm not like '%precisa de paciente%' then raise; end if;
  end;
  if not falhou then raise exception '14 FUROU: mensagem sem paciente'; end if;

  -- ------------------------------------------------------------- o worker
  -- Daqui para baixo é o service_role: quem chama de fora, sem RLS.
  reset role;
  perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 15
  update public.mensagens set estado='cancelada' where conta_id=a_conta and id not in (m1);
  update public.mensagens set agendada_para = now() - interval '1 minute' where id=m1;

  select count(*) into n from public.reservar_mensagens(10);
  if n <> 1 then raise exception '15 FUROU: reservou % (esperado 1)', n; end if;
  select * into linha from public.mensagens where id=m1;
  if linha.estado <> 'enviando' then raise exception '15 FUROU: estado %', linha.estado; end if;
  if linha.tentativas <> 1 then raise exception '15 FUROU: tentativas %', linha.tentativas; end if;

  -- ---------------------------------------------------------------- 16
  select count(*) into n from public.reservar_mensagens(10);
  if n <> 0 then raise exception '16 FUROU: reservou de novo o que já estava em envio'; end if;

  -- ---------------------------------------------------------------- 17
  update public.mensagens set estado='pendente', agendada_para = now() + interval '30 minutes' where id=m1;
  select count(*) into n from public.reservar_mensagens(10);
  if n <> 0 then raise exception '17 FUROU: reservou o que ainda não venceu'; end if;

  -- ---------------------------------------------------------------- 18
  update public.mensagens set agendada_para = now() - interval '1 minute' where id=m1;
  perform public.reservar_mensagens(10);
  perform public.marcar_enviada(m1,'gupshup','wamid.123');
  select * into linha from public.mensagens where id=m1;
  if linha.estado <> 'enviada' then raise exception '18 FUROU: estado %', linha.estado; end if;
  if linha.provedor <> 'gupshup' or linha.provedor_msg_id <> 'wamid.123' then
    raise exception '18 FUROU: não gravou o rastro do provedor'; end if;

  -- ---------------------------------------------------------------- 19
  update public.mensagens set estado='enviando', tentativas=2, agendada_para=now() where id=m1;
  select public.marcar_falha(m1,'timeout do provedor') into r;
  if r <> 'pendente' then raise exception '19 FUROU: %', r; end if;
  select * into linha from public.mensagens where id=m1;
  -- 2 tentativas → 4 minutos de espera.
  if linha.agendada_para < now() + interval '3 minutes'
     or linha.agendada_para > now() + interval '5 minutes' then
    raise exception '19 FUROU: espera fora do degrau (%)', linha.agendada_para; end if;
  if linha.erro is null then raise exception '19 FUROU: não guardou o erro'; end if;

  -- ---------------------------------------------------------------- 20
  update public.mensagens set estado='enviando', tentativas=5 where id=m1;
  select public.marcar_falha(m1,'número inválido') into r;
  if r <> 'falhou' then raise exception '20 FUROU: % (esperado falhou)', r; end if;

  -- ---------------------------------------------------------------- 21
  update public.mensagens set estado='enviando' where id=m1;

  -- Antes de destravar: o carimbo de tempo não se falsifica. Tentar plantar
  -- `atualizado_em` no passado — para fazer a varredura pegar uma mensagem que
  -- acabou de sair — não funciona, porque o gatilho reescreve com o relógio do
  -- servidor. É a mesma lei da 0011 aplicada aqui.
  update public.mensagens set atualizado_em = now() - interval '30 minutes' where id=m1;
  if (select atualizado_em from public.mensagens where id=m1) < now() - interval '1 minute' then
    raise exception '21 FUROU: dá para plantar atualizado_em no passado'; end if;
  select public.destravar_mensagens(10) into n;
  if n <> 0 then raise exception '21 FUROU: destravou mensagem recém-reservada'; end if;

  -- E com uma janela que de fato a alcança, ela volta para a fila.
  select public.destravar_mensagens(-1) into n;
  if n <> 1 then raise exception '21 FUROU: destravou %', n; end if;
  if (select estado from public.mensagens where id=m1) <> 'pendente' then
    raise exception '21 FUROU: não voltou para a fila'; end if;

  -- --------------------------------------------------------- 22 e 23: a cascata
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  terca := (((now() at time zone 'America/Sao_Paulo')::date + 8) + time '15:00') at time zone 'America/Sao_Paulo';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,terca,terca+interval '50 min','avulsa',200.00,24,50) returning id into vaga;

  insert into public.fila_encaixe (paciente_id) values (caio);
  perform public.cancelar_sessao(vaga,'paciente');
  select public.abrir_vaga(vaga) into of1;
  if of1 is null then raise exception '22 FUROU: preparo — não ofertou'; end if;

  select count(*) into n from public.mensagens
   where chave_idem = 'oferta:'||of1::text and template='oferta_de_vaga' and paciente_id=caio;
  if n <> 1 then raise exception '22 FUROU: a cascata não enfileirou a mensagem'; end if;
  if (select params->>'oferta_id' from public.mensagens where chave_idem='oferta:'||of1::text) <> of1::text then
    raise exception '22 FUROU: a mensagem não sabe de que oferta é'; end if;

  perform public.avancar_fila(vaga);
  select count(*) into n from public.mensagens where chave_idem = 'oferta:'||of1::text;
  if n <> 1 then raise exception '23 FUROU: duplicou a mensagem da mesma oferta'; end if;

  -- ---------------------------------------------------------------- 24
  update public.mensagens set estado='entregue' where id=m1;
  if (select estado from public.mensagens where id=m1) = 'entregue' then
    raise exception '24 FUROU: o app mudou estado de envio'; end if;

  -- ---------------------------------------------------------------- 25
  delete from public.mensagens where id=m1;
  select count(*) into n from public.mensagens where id=m1;
  if n <> 1 then raise exception '25 FUROU: o app apagou trilha de mensagem'; end if;

  -- ---------------------------------------------------------------- 26
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.mensagens;
  if n <> 0 then raise exception '26 FUROU: a conta B leu % mensagens da A', n; end if;

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (b_prof,'Paciente da Bruna','5511900000009','em_atendimento') returning id into b_pac;
  falhou := false;
  begin
    perform public.enfileirar_mensagem(maria,'lembrete_de_sessao','t12');
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '26 FUROU: a conta B enfileirou para paciente da A'; end if;

  -- ---------------------------------------------------------------- 27 e 28
  reset role;
  perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.mensagens;
  if n <> 0 then raise exception '27 FUROU: anon leu mensagens'; end if;

  falhou := false;
  begin
    perform public.reservar_mensagens(10);
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '28 FUROU: anon reservou mensagens'; end if;

  falhou := false;
  begin
    perform public.destravar_mensagens(10);
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '28 FUROU: anon destravou mensagens'; end if;

  falhou := false;
  begin
    perform public.marcar_enviada(m1,'x');
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '28 FUROU: anon marcou mensagem como enviada'; end if;

  -- ---------------------------------------------------------------- 29
  -- O motor da fila (B7) tinha o mesmo buraco: PUBLIC com execute. A 0018
  -- fechou, e este é o teste que impede a regressão.
  falhou := false;
  begin
    perform public.abrir_vaga(vaga);
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '29 FUROU: anon abriu vaga'; end if;

  falhou := false;
  begin
    perform public.responder_oferta(of1,'recusada');
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '29 FUROU: anon respondeu oferta'; end if;

  falhou := false;
  begin
    perform public.expirar_ofertas();
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '29 FUROU: anon expirou ofertas'; end if;

  falhou := false;
  begin
    perform public.elegiveis_para_vaga(vaga);
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '29 FUROU: anon leu a fila de uma vaga'; end if;

  falhou := false;
  begin
    perform public.taxa_de_preenchimento(current_date - 1, current_date + 1);
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '29 FUROU: anon leu a métrica norte'; end if;

  -- ---------------------------------------------------------------- 30 e 31
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select public.enfileirar_mensagem(maria,'lembrete_de_sessao','t13') into msg;

  falhou := false;
  begin perform public.desistir_mensagem(msg,'x');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '30 FUROU: a pessoa logada desistiu de uma mensagem'; end if;

  reset role;
  perform set_config('request.jwt.claims','',true);
  perform public.desistir_mensagem(msg, 'número não existe no WhatsApp');
  if (select estado from public.mensagens where id=msg) <> 'falhou' then
    raise exception '30 FUROU: não encerrou'; end if;
  if (select tentativas from public.mensagens where id=msg) <> 0 then
    raise exception '30 FUROU: desistir gastou tentativa'; end if;

  update public.mensagens set estado='enviada' where id=msg;
  perform public.desistir_mensagem(msg,'tarde demais');
  if (select estado from public.mensagens where id=msg) <> 'enviada' then
    raise exception '31 FUROU: desistir reescreveu mensagem já enviada'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role;
  perform set_config('request.jwt.claims','',true);
  delete from public.mensagens    where conta_id in (a_conta,b_conta);
  delete from public.eventos_fila where conta_id in (a_conta,b_conta);
  delete from public.ofertas      where conta_id in (a_conta,b_conta);
  delete from public.fila_encaixe where conta_id in (a_conta,b_conta);
  delete from public.sessoes      where conta_id in (a_conta,b_conta);
  delete from public.enquadres    where conta_id in (a_conta,b_conta);
  delete from public.pacientes    where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B9 OK — 31 verificações, todas passaram';
end $$;
