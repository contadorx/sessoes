-- Teste da conciliação de pagamento (B16).
--
-- O doc 10 descreve o webhook do Asaas: entrega "at least once", sem assinatura
-- HMAC, fila que pausa após 15 falhas e eventos apagados em 14 dias. Tudo aqui
-- existe para que nenhuma dessas quatro coisas vire dinheiro contado errado.
--
--   1. o txid é derivado da cobrança — curto e reconhecível no extrato
--   2. um pagamento do provedor errado não casa com a cobrança
--   3. o pagamento certo concilia e registra quem confirmou
--   4. a reentrega do mesmo evento não faz nada
--   5. a varredura diária achando o que o webhook já resolveu não é erro
--   6. estorno reabre a cobrança em vez de apagá-la
--   7. pagamento que chega numa cobrança perdoada NÃO sobrescreve o perdão
--   8. evento de tipo desconhecido é registrado, não estoura
--   9. isolamento entre contas, e só o worker concilia
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0028_pagamentos.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  maria uuid; s1 uuid; cob uuid; r jsonb; n int; falhou boolean; est text;
  base timestamptz;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.eventos_pagamento where provedor in ('teste','asaas');
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.cobrancas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.mensagens where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;

  base := now() + interval '3 hours';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa',200.00,24,50) returning id into s1;
  perform public.cancelar_sessao(s1,'paciente');
  -- **P4 (0058):** a falta virou pergunta, e a cobrança só nasce da decisão.
  -- Esta suíte mede o que vem **depois** de a cobrança existir — então ela
  -- decide cobrar, pelo caminho de produção, e segue medindo a mesma coisa.
  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.sessao_id = s1 and p.estado = 'pendente';
  select id into cob from public.cobrancas where sessao_id=s1;
  if cob is null then raise exception 'PREPARO: sem cobrança'; end if;

  -- ---------------------------------------------------------------- 1
  if public.txid_da_cobranca(cob) !~ '^SES[0-9A-F]{32}$' then
    raise exception '1 FUROU: txid %', public.txid_da_cobranca(cob); end if;

  update public.cobrancas
     set provedor='asaas', provedor_cobranca_id='pay_001', txid=public.txid_da_cobranca(cob)
   where id=cob;

  -- Daqui para baixo é o worker: quem recebe o webhook.
  reset role; perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 2
  select public.conciliar_pagamento('teste','ev1','PAYMENT_RECEIVED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'sem_cobranca' then raise exception '2 FUROU: provedor errado casou: %', r; end if;

  -- ---------------------------------------------------------------- 3
  select public.conciliar_pagamento('asaas','ev2','PAYMENT_RECEIVED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'paga' then raise exception '3 FUROU: %', r; end if;
  if (select estado from public.cobrancas where id=cob) <> 'paga' then
    raise exception '3 FUROU: não marcou paga'; end if;
  if (select confirmado_por from public.cobrancas where id=cob) <> 'provedor' then
    raise exception '3 FUROU: não registrou quem confirmou'; end if;

  -- (B24) a multa de falta não é atendimento prestado: o webhook não pode
  -- criar pendência de recibo de serviço de saúde para ela.
  select count(*) into n from public.recibos_rfb where cobranca_id=cob;
  if n <> 0 then
    raise exception 'B24 FUROU: o webhook criou pendência de recibo para uma multa de falta'; end if;

  -- ---------------------------------------------------------------- 4
  select public.conciliar_pagamento('asaas','ev2','PAYMENT_RECEIVED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'repetido' then raise exception '4 FUROU: %', r; end if;
  select count(*) into n from public.eventos_pagamento where evento_id='ev2';
  if n <> 1 then raise exception '4 FUROU: % linhas', n; end if;

  -- ---------------------------------------------------------------- 5
  select public.conciliar_pagamento('asaas','ev3','PAYMENT_CONFIRMED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'ja_paga' then raise exception '5 FUROU: %', r; end if;

  -- ---------------------------------------------------------------- 6
  select public.conciliar_pagamento('asaas','ev4','PAYMENT_REFUNDED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'reaberta' then raise exception '6 FUROU: %', r; end if;
  if (select estado from public.cobrancas where id=cob) <> 'aberta' then
    raise exception '6 FUROU: não reabriu'; end if;
  if (select paga_em from public.cobrancas where id=cob) is not null then
    raise exception '6 FUROU: manteve a data de pagamento'; end if;

  -- ---------------------------------------------------------------- 7
  -- Dinheiro caindo numa cobrança perdoada é conversa entre duas pessoas, não
  -- decisão de sistema. Fica registrado, e o perdão fica de pé.
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.perdoar_cobranca(cob);
  reset role; perform set_config('request.jwt.claims','',true);

  select public.conciliar_pagamento('asaas','ev5','PAYMENT_RECEIVED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'fora_de_estado' then raise exception '7 FUROU: %', r; end if;
  if (select estado from public.cobrancas where id=cob) <> 'perdoada' then
    raise exception '7 FUROU: sobrescreveu o perdão'; end if;

  -- ---------------------------------------------------------------- 8
  select public.conciliar_pagamento('asaas','ev6','PAYMENT_UPDATED','pay_001','{}'::jsonb) into r;
  if r->>'estado' <> 'ignorado' then raise exception '8 FUROU: %', r; end if;

  select count(*) into n from public.cobrancas_a_conciliar(100);
  if n <> 0 then raise exception '8 FUROU: a fila trouxe % (a cobrança está perdoada)', n; end if;

  -- ---------------------------------------------------------------- 9
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.eventos_pagamento;
  if n <> 0 then raise exception '9 FUROU: B leu % eventos de A', n; end if;
  falhou := false;
  begin perform public.conciliar_pagamento('asaas','x','PAYMENT_RECEIVED','pay_001');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '9 FUROU: authenticated conciliou'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.eventos_pagamento;
  if n <> 0 then raise exception '9 FUROU: anon leu eventos'; end if;
  falhou := false;
  begin perform public.cobrancas_a_conciliar(10);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '9 FUROU: anon leu a fila de conciliação'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.eventos_pagamento where conta_id in (a_conta,b_conta);
  delete from public.cobrancas where conta_id in (a_conta,b_conta);
  delete from public.mensagens where conta_id in (a_conta,b_conta);
  delete from public.sessoes where conta_id in (a_conta,b_conta);
  delete from public.pacientes where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B16 OK — 9 verificações, todas passaram';
end $$;
