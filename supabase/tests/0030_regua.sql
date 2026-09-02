-- Teste da régua de inadimplência (critério de pronto da B18).
--
-- Este é o único teste do projeto em que a maior parte das verificações é sobre
-- o sistema **não** mandar mensagem. É de propósito.
--
-- Uma régua automática apontada para pacientes de psicoterapia é, por
-- construção, um robô insistindo sobre dinheiro com gente que às vezes está em
-- dificuldade — e cuja dificuldade financeira, com frequência, é material da
-- própria terapia. O doc 03 diz para que a D6 existe: o alívio emocional **dela**.
-- Não a pressão sobre quem deve.
--
--   1. três cobranças abertas viram UMA linha, com o total
--   2. e UMA mensagem, nunca três
--   3. rodar de novo não repete
--   4. o degrau seguinte só vence no dia dele
--   5. teto: depois do último, a régua para e devolve o assunto
--   6. ela desliga a régua para uma pessoa
--   7. quem pediu para não ser avisado nunca entra
--   8. quem respondeu nos últimos dias cala a régua
--   9. só quem está ativo recebe
--  10. perdoar tira da régua na hora
--  11. a régua desligada na conta para tudo
--  12. o teto de três degraus é do banco, não da tela
--  13. só o worker dispara; ela lê a própria régua; o anônimo não vê nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0030_regua.sql

-- ======================================== parte 1 · a agregação e os degraus

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid;
  s1 uuid; s2 uuid; s3 uuid; n int; r record; base timestamptz;
begin
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;

  base := now() - interval '10 days';

  -- Três faltas cobradas: a armadilha das três mensagens no mesmo minuto.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa','prevista',200.00,24,50) returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base+interval '1 day',base+interval '1 day 50 min','avulsa','prevista',200.00,24,50) returning id into s2;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base+interval '2 days',base+interval '2 days 50 min','avulsa','prevista',200.00,24,50) returning id into s3;
  update public.sessoes set estado='falta' where id in (s1,s2,s3);
  -- **P4 (0058):** a falta virou pergunta, e a cobrança só nasce da decisão.
  -- Esta suíte mede o que vem **depois** de a cobrança existir — então ela
  -- decide cobrar, pelo caminho de produção, e segue medindo a mesma coisa.
  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.conta_id = a_conta and p.estado = 'pendente';

  reset role; perform set_config('request.jwt.claims','',true);
  update public.cobrancas set criado_em = now() - interval '9 days' where paciente_id=maria;
  update public.mensagens set estado='cancelada' where paciente_id=maria and estado='pendente';

  -- ---------------------------------------------------------------- 1
  select * into r from public.regua_pendente() where paciente_id=maria;
  if r.quantidade <> 3 then raise exception '1 FUROU: % cobranças agregadas', r.quantidade; end if;
  if r.total <> 300.00 then raise exception '1 FUROU: total %', r.total; end if;
  if r.passo <> 1 then raise exception '1 FUROU: passo % (9 dias, degrau 7)', r.passo; end if;
  if r.pausada then raise exception '1 FUROU: pausada sem motivo (%)', r.motivo_pausa; end if;

  select count(*) into n from public.regua_pendente() where paciente_id=maria;
  if n <> 1 then raise exception '1 FUROU: % linhas para a mesma pessoa', n; end if;

  -- ---------------------------------------------------------------- 2
  select public.agendar_regua() into n;
  if n <> 1 then raise exception '2 FUROU: agendou % mensagens', n; end if;
  select count(*) into n from public.mensagens
   where paciente_id=maria and template='lembrete_de_pagamento';
  if n <> 1 then raise exception '2 FUROU: % mensagens de régua', n; end if;
  if (select (params->>'valor_centavos')::bigint from public.mensagens
       where paciente_id=maria and template='lembrete_de_pagamento') <> 30000 then
    raise exception '2 FUROU: o total da mensagem não é a soma'; end if;

  -- ---------------------------------------------------------------- 3
  select public.agendar_regua() into n;
  if n <> 0 then raise exception '3 FUROU: repetiu %', n; end if;

  -- ---------------------------------------------------------------- 4
  select * into r from public.regua_pendente() where paciente_id=maria;
  if r.passo is not null then raise exception '4 FUROU: segundo degrau aos 9 dias'; end if;
  if r.enviados <> 1 then raise exception '4 FUROU: enviados %', r.enviados; end if;

  update public.cobrancas set criado_em = now() - interval '25 days' where paciente_id=maria;
  select * into r from public.regua_pendente() where paciente_id=maria;
  if r.passo <> 2 then raise exception '4 FUROU: passo % aos 25 dias', r.passo; end if;

  -- ---------------------------------------------------------------- 5
  select public.agendar_regua() into n;
  if n <> 1 then raise exception '5 FUROU: agendou % no passo 2', n; end if;

  update public.cobrancas set criado_em = now() - interval '200 days' where paciente_id=maria;
  select * into r from public.regua_pendente() where paciente_id=maria;
  if r.passo is not null then raise exception '5 FUROU: passou do teto'; end if;
  if r.motivo_pausa <> 'a régua terminou; daqui é com você' then
    raise exception '5 FUROU: motivo %', r.motivo_pausa; end if;
  select public.agendar_regua() into n;
  if n <> 0 then raise exception '5 FUROU: mandou um terceiro'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.cobrancas where conta_id=a_conta;
  delete from public.mensagens where conta_id=a_conta;
  delete from public.sessoes where conta_id=a_conta;
  delete from public.pacientes where conta_id=a_conta;
  delete from auth.users where id=a_auth;
  delete from public.contas where id=a_conta;

  raise notice 'B18 · parte 1 ok — 5 verificações';
end $$;

-- ============================================ parte 2 · quando ela deve calar

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid; caio uuid; joao uuid; quieta uuid;
  s uuid; cob uuid; n int; r record; falhou boolean; base timestamptz;
begin
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'João Salles','5511900000003','em_atendimento') returning id into joao;
  insert into public.pacientes (profissional_id,nome,telefone,estado,msg_canal)
    values (a_prof,'Teresa Quieta','5511900000004','em_atendimento','nao_avisar') returning id into quieta;

  base := now() - interval '10 days';

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa','prevista',200.00,24,50) returning id into s;
  update public.sessoes set estado='falta' where id=s;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,caio,base+interval '1 hour',base+interval '1 hour 50 min','avulsa','prevista',200.00,24,50) returning id into s;
  update public.sessoes set estado='falta' where id=s;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,joao,base+interval '2 hours',base+interval '2 hours 50 min','avulsa','prevista',200.00,24,50) returning id into s;
  update public.sessoes set estado='falta' where id=s;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,quieta,base+interval '3 hours',base+interval '3 hours 50 min','avulsa','prevista',200.00,24,50) returning id into s;
  update public.sessoes set estado='falta' where id=s;
  -- **P4 (0058):** a falta virou pergunta, e a cobrança só nasce da decisão.
  -- Esta suíte mede o que vem **depois** de a cobrança existir — então ela
  -- decide cobrar, pelo caminho de produção, e segue medindo a mesma coisa.
  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.conta_id = a_conta and p.estado = 'pendente';

  -- ---------------------------------------------------------------- 6
  update public.pacientes set regua_ativa=false where id=caio;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.cobrancas set criado_em = now() - interval '9 days';
  update public.mensagens set estado='cancelada' where estado='pendente';

  select * into r from public.regua_pendente() where paciente_id=caio;
  if not r.pausada then raise exception '6 FUROU: não pausou para o Caio'; end if;
  if r.motivo_pausa <> 'você desligou a régua para esta pessoa' then
    raise exception '6 FUROU: motivo %', r.motivo_pausa; end if;

  -- ---------------------------------------------------------------- 7
  select * into r from public.regua_pendente() where paciente_id=quieta;
  if not r.pausada then raise exception '7 FUROU: régua para quem pediu silêncio'; end if;

  -- ---------------------------------------------------------------- 8
  -- Robô falando por cima de uma conversa humana sobre dinheiro é o oposto do
  -- que o produto promete.
  perform public.responder_do_whatsapp('teste','rg1','5511900000003','oi, posso pagar semana que vem?');
  select * into r from public.regua_pendente() where paciente_id=joao;
  if not r.pausada then raise exception '8 FUROU: falou por cima de uma conversa'; end if;
  if r.motivo_pausa <> 'ela respondeu nos últimos dias — a conversa é sua' then
    raise exception '8 FUROU: motivo %', r.motivo_pausa; end if;

  -- ---------------------------------------------------------------- 9
  select public.agendar_regua() into n;
  if n <> 1 then raise exception '9 FUROU: mandou % (esperado só a Maria)', n; end if;
  select count(*) into n from public.mensagens
   where template='lembrete_de_pagamento' and paciente_id in (caio,joao,quieta);
  if n <> 0 then raise exception '9 FUROU: mandou para quem estava pausado'; end if;

  -- ---------------------------------------------------------------- 10
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select id into cob from public.cobrancas where paciente_id=maria and estado='aberta';
  perform public.perdoar_cobranca(cob);
  reset role; perform set_config('request.jwt.claims','',true);

  select count(*) into n from public.regua_pendente() where paciente_id=maria;
  if n <> 0 then raise exception '10 FUROU: perdoada e ainda na régua'; end if;

  -- ---------------------------------------------------------------- 11
  update public.contas set regua_ativa=false where id=a_conta;
  select count(*) into n from public.regua_pendente() where not pausada;
  if n <> 0 then raise exception '11 FUROU: % ativos com a régua desligada', n; end if;
  select public.agendar_regua() into n;
  if n <> 0 then raise exception '11 FUROU: mandou com a régua desligada'; end if;
  update public.contas set regua_ativa=true where id=a_conta;

  -- ---------------------------------------------------------------- 12
  falhou := false;
  begin update public.contas set regua_dias='{3,7,14,21}' where id=a_conta;
  exception when others then falhou := true; end;
  if not falhou then raise exception '12 FUROU: aceitou quatro degraus'; end if;

  -- ---------------------------------------------------------------- 13
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  falhou := false;
  begin perform public.agendar_regua();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '13 FUROU: authenticated disparou a régua'; end if;

  select count(*) into n from public.regua_pendente();
  if n = 0 then raise exception '13 FUROU: ela não consegue ver a própria régua'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  falhou := false;
  begin perform public.regua_pendente();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '13 FUROU: anon leu a régua'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.cobrancas where conta_id=a_conta;
  delete from public.mensagens where conta_id=a_conta;
  delete from public.sessoes where conta_id=a_conta;
  delete from public.pacientes where conta_id=a_conta;
  delete from auth.users where id=a_auth;
  delete from public.contas where id=a_conta;

  raise notice 'B18 OK — 13 verificações, todas passaram';
end $$;
