-- Teste do webhook de resposta (critério de pronto da B10).
--
-- O marco M3 do produto é uma frase: "você cancela, a oferta chega no celular,
-- a pessoa responde SIM e a agenda fecha sozinha". Tudo aqui existe para que a
-- última parte dessa frase seja verdade mesmo quando o mundo não colabora.
--
--   1. texto humano vira intenção (Sim! / SIM / não / NAO. / parar)
--   2. o que é conversa não vira aceite — chutar marca a agenda de alguém errado
--   3. telefone formatado casa com o cadastro
--   4. a recusa faz a fila andar
--   5. a MESMA mensagem reentregue não faz nada
--   6. o SIM fecha o encaixe
--   7. o SIM reentregue não cria um segundo encaixe
--   8. responder sem oferta viva não estoura
--   9. telefone desconhecido não inventa conta
--  10. duas ofertas vivas no mesmo telefone: responde a mais recente
--  11. resposta que é conversa mantém a oferta viva e vira trilha
--  12. "parar" vale em todas as contas — é o celular da pessoa, não a conta dela
--  13. e o que estava na fila de envio para ela não sai mais
--  14. depois do opt-out, nada mais é enfileirado
--  15. isolamento: uma conta não lê as respostas da outra
--  16. resposta de telefone sem dono não aparece para ninguém
--  17. nem a pessoa logada nem o anônimo executam o webhook
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0021_respostas.sql

-- ========================================================= parte 1 · a cascata

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; joao uuid;
  vaga uuid; of1 uuid; of2 uuid;
  terca timestamptz; r jsonb; n int;
begin
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.mensagens     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.eventos_fila  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'João Salles','5511900000003','em_atendimento') returning id into joao;

  terca := (((now() at time zone 'America/Sao_Paulo')::date + 8) + time '15:00') at time zone 'America/Sao_Paulo';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,terca,terca+interval '50 min','avulsa',200.00,24,50) returning id into vaga;

  insert into public.fila_encaixe (paciente_id) values (caio);
  insert into public.fila_encaixe (paciente_id) values (joao);
  perform public.cancelar_sessao(vaga,'paciente');
  select public.abrir_vaga(vaga) into of1;
  if (select paciente_id from public.ofertas where id=of1) <> caio then
    raise exception 'PREPARO: a oferta não foi para o Caio'; end if;

  -- Daqui para baixo é o service_role: é ele que o webhook usa.
  reset role; perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 1
  if public.interpretar_resposta('Sim!') <> 'aceitar' then raise exception '1 FUROU: Sim!'; end if;
  if public.interpretar_resposta('  SIM  ') <> 'aceitar' then raise exception '1 FUROU: espaços'; end if;
  if public.interpretar_resposta('não') <> 'recusar' then raise exception '1 FUROU: não'; end if;
  if public.interpretar_resposta('NAO.') <> 'recusar' then raise exception '1 FUROU: NAO.'; end if;
  if public.interpretar_resposta('Parar de receber') <> 'parar' then raise exception '1 FUROU: parar'; end if;

  -- ---------------------------------------------------------------- 2
  -- Um "sim" com condição é conversa, e conversa é da psicóloga.
  if public.interpretar_resposta('sim, mas só depois das 16h') <> 'indefinida' then
    raise exception '2 FUROU: chutou um sim condicional'; end if;
  if public.interpretar_resposta('não sei ainda, te falo') <> 'indefinida' then
    raise exception '2 FUROU: chutou um não condicional'; end if;
  if public.interpretar_resposta('') <> 'indefinida' then raise exception '2 FUROU: vazio'; end if;

  -- ---------------------------------------------------------------- 3 e 4
  select public.responder_do_whatsapp('teste','m1','+55 (11) 90000-0002','não') into r;
  if r->>'estado' <> 'recusada' then raise exception '3 FUROU: %', r; end if;

  select id into of2 from public.ofertas where sessao_id=vaga and estado='enviada';
  if of2 is null then raise exception '4 FUROU: a fila não andou'; end if;
  if (select paciente_id from public.ofertas where id=of2) <> joao then
    raise exception '4 FUROU: não foi para o João'; end if;

  -- ---------------------------------------------------------------- 5
  select public.responder_do_whatsapp('teste','m1','+55 (11) 90000-0002','não') into r;
  if r->>'estado' <> 'repetida' then raise exception '5 FUROU: %', r; end if;
  select count(*) into n from public.mensagens_recebidas where provedor='teste' and provedor_msg_id='m1';
  if n <> 1 then raise exception '5 FUROU: % linhas', n; end if;
  if (select id from public.ofertas where sessao_id=vaga and estado='enviada') <> of2 then
    raise exception '5 FUROU: a reentrega mexeu na fila'; end if;

  -- ---------------------------------------------------------------- 6 e 7
  select public.responder_do_whatsapp('teste','m2','5511900000003','sim') into r;
  if r->>'estado' <> 'aceita' then raise exception '6 FUROU: %', r; end if;
  select count(*) into n from public.sessoes where paciente_id=joao and origem='encaixe' and inicio=terca;
  if n <> 1 then raise exception '6 FUROU: não criou o encaixe'; end if;

  select public.responder_do_whatsapp('teste','m2','5511900000003','sim') into r;
  if r->>'estado' <> 'repetida' then raise exception '7 FUROU: %', r; end if;
  select count(*) into n from public.sessoes where paciente_id=joao and origem='encaixe' and inicio=terca;
  if n <> 1 then raise exception '7 FUROU: % encaixes para a mesma vaga', n; end if;

  -- ---------------------------------------------------------------- 8 e 9
  select public.responder_do_whatsapp('teste','m3','5511900000003','sim') into r;
  if r->>'estado' <> 'sem_oferta' then raise exception '8 FUROU: %', r; end if;

  select public.responder_do_whatsapp('teste','m4','5511999998888','sim') into r;
  if r->>'estado' <> 'sem_oferta' then raise exception '9 FUROU: %', r; end if;
  if (select conta_id from public.mensagens_recebidas where provedor_msg_id='m4') is not null then
    raise exception '9 FUROU: inventou uma conta'; end if;

  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.mensagens     where conta_id in (a_conta,b_conta);
  delete from public.eventos_fila  where conta_id in (a_conta,b_conta);
  delete from public.ofertas       where conta_id in (a_conta,b_conta);
  delete from public.fila_encaixe  where conta_id in (a_conta,b_conta);
  delete from public.sessoes       where conta_id in (a_conta,b_conta);
  delete from public.pacientes     where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B10 · parte 1 ok — 9 verificações';
end $$;

-- ============================== parte 2 · o mesmo celular em duas psicólogas

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; b_caio uuid; alvo uuid;
  vaga uuid; vaga_b uuid; of1 uuid; ofb uuid;
  terca timestamptz; quarta timestamptz; r jsonb; n int; falhou boolean;
begin
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.mensagens     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.eventos_fila  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe  where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes       where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes     where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  terca  := (((now() at time zone 'America/Sao_Paulo')::date + 8) + time '15:00') at time zone 'America/Sao_Paulo';
  quarta := terca + interval '1 day';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,terca,terca+interval '50 min','avulsa',200.00,24,50) returning id into vaga;
  insert into public.fila_encaixe (paciente_id) values (caio);
  perform public.cancelar_sessao(vaga,'paciente');
  select public.abrir_vaga(vaga) into of1;

  -- O mesmo Caio, mesmo telefone, também é paciente da Bruna. Acontece.
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (b_prof,'Caio N.','5511900000002','em_atendimento') returning id into b_caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (b_prof,'Outra Pessoa','5511900000009','em_atendimento') returning id into alvo;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (b_conta,b_prof,alvo,quarta,quarta+interval '50 min','avulsa',300.00,24,50) returning id into vaga_b;
  insert into public.fila_encaixe (paciente_id) values (b_caio);
  perform public.cancelar_sessao(vaga_b,'paciente');
  select public.abrir_vaga(vaga_b) into ofb;
  if ofb is null then raise exception 'PREPARO: B não ofertou'; end if;

  reset role; perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 10
  -- Quem responde está olhando a última mensagem que chegou.
  update public.ofertas set enviar_em = now() - interval '2 hours' where id=of1;
  update public.ofertas set enviar_em = now() - interval '5 minutes' where id=ofb;
  select public.responder_do_whatsapp('teste','n1','5511900000002','sim') into r;
  if r->>'estado' <> 'aceita' then raise exception '10 FUROU: %', r; end if;
  if (r->>'oferta')::uuid <> ofb then raise exception '10 FUROU: respondeu a oferta antiga'; end if;
  if (select estado from public.ofertas where id=of1) <> 'enviada' then
    raise exception '10 FUROU: mexeu na oferta da outra conta'; end if;

  -- ---------------------------------------------------------------- 11
  select public.responder_do_whatsapp('teste','n2','5511900000002','sim, mas só depois das 16h') into r;
  if r->>'estado' <> 'nao_entendi' then raise exception '11 FUROU: %', r; end if;
  if (select estado from public.ofertas where id=of1) <> 'enviada' then
    raise exception '11 FUROU: matou a oferta por não entender'; end if;
  select count(*) into n from public.eventos_fila where tipo='resposta_nao_entendida' and oferta_id=of1;
  if n <> 1 then raise exception '11 FUROU: não registrou na trilha'; end if;

  -- ---------------------------------------------------------- 12, 13 e 14
  select public.responder_do_whatsapp('teste','n3','5511900000002','PARAR') into r;
  if r->>'estado' <> 'parou' then raise exception '12 FUROU: %', r; end if;
  if (r->>'cadastros')::int <> 2 then raise exception '12 FUROU: parou em % cadastros', r->>'cadastros'; end if;
  if (select msg_canal from public.pacientes where id=caio) <> 'nao_avisar' then raise exception '12 FUROU: conta A'; end if;
  if (select msg_canal from public.pacientes where id=b_caio) <> 'nao_avisar' then raise exception '12 FUROU: conta B'; end if;

  select count(*) into n from public.mensagens m join public.pacientes p on p.id=m.paciente_id
   where public.so_digitos(p.telefone)='5511900000002' and m.estado='pendente';
  if n <> 0 then raise exception '13 FUROU: % mensagens ainda pendentes depois do parar', n; end if;

  if public.enfileirar_mensagem(caio,'lembrete_de_sessao','p1') is not null then
    raise exception '14 FUROU: enfileirou depois do opt-out'; end if;

  -- ---------------------------------------------------------------- 15
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.mensagens_recebidas where conta_id = a_conta;
  if n <> 0 then raise exception '15 FUROU: B leu resposta de A'; end if;

  -- ---------------------------------------------------------------- 16
  reset role; perform set_config('request.jwt.claims','',true);
  perform public.responder_do_whatsapp('teste','n9','5511777776666','sim');
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.mensagens_recebidas where provedor_msg_id='n9';
  if n <> 0 then raise exception '16 FUROU: a psicóloga viu resposta de telefone sem dono'; end if;

  -- ---------------------------------------------------------------- 17
  falhou := false;
  begin perform public.responder_do_whatsapp('teste','x1','5511900000002','sim');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '17 FUROU: authenticated chamou o webhook'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  falhou := false;
  begin perform public.responder_do_whatsapp('teste','x2','5511900000002','sim');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '17 FUROU: anon chamou o webhook'; end if;
  falhou := false;
  begin perform public.marcar_entregue('qualquer');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '17 FUROU: anon marcou entrega'; end if;
  select count(*) into n from public.mensagens_recebidas;
  if n <> 0 then raise exception '17 FUROU: anon leu respostas'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.mensagens_recebidas where provedor='teste';
  delete from public.mensagens     where conta_id in (a_conta,b_conta);
  delete from public.eventos_fila  where conta_id in (a_conta,b_conta);
  delete from public.ofertas       where conta_id in (a_conta,b_conta);
  delete from public.fila_encaixe  where conta_id in (a_conta,b_conta);
  delete from public.sessoes       where conta_id in (a_conta,b_conta);
  delete from public.pacientes     where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B10 OK — 17 verificações, todas passaram';
end $$;
