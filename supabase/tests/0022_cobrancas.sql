-- Teste da política que se aplica sozinha (critério de pronto da B11).
--
-- A régua automática só é aceitável se o freio funcionar. Metade das
-- verificações abaixo é sobre não cobrar: quem avisou no prazo, quem tem
-- política de 0%, e quem foi perdoado antes de o aviso sair.
--
--   1. cancelar tarde gera cobrança com a política congelada na sessão
--   2. o aviso é enfileirado, mas não para agora — existe janela de perdão
--   3. perdoar segura o aviso que ainda não saiu
--   4. perdoar duas vezes não é possível
--   5. quem avisou no prazo não é cobrado
--   6. política de 0% não gera cobrança de zero
--   7. não vir é desmarcar com zero hora: cobra o mesmo percentual
--   8. desfazer cancela a cobrança E o aviso
--   9. refazer gera uma nova, sem esbarrar no índice
--  10. o mesmo estado de novo não duplica nada
--  11. a política de "segurar mensagem" (0023) não vira porta dos fundos
--  12. isolamento entre contas
--  13. o anônimo não lê nem executa
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0022_cobrancas.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; livre uuid;
  s1 uuid; s2 uuid; s3 uuid; cob uuid; cob2 uuid; mid uuid;
  base timestamptz; n int; r text; c record; falhou boolean; msg record;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.cobrancas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.mensagens where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
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
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Livre Silva','5511900000003','em_atendimento') returning id into livre;

  -- Daqui a 3 horas, com política de 24h: cancelar agora é tardio.
  base := now() + interval '3 hours';

  -- ---------------------------------------------------------------- 1
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa',200.00,24,50) returning id into s1;
  perform public.cancelar_sessao(s1,'paciente');

  select * into c from public.cobrancas where sessao_id=s1;
  if not found then raise exception '1 FUROU: não gerou cobrança'; end if;
  if c.valor <> 100.00 then raise exception '1 FUROU: valor %', c.valor; end if;
  if c.politica_percentual <> 50 or c.valor_da_sessao <> 200.00 then
    raise exception '1 FUROU: não guardou o retrato da política'; end if;
  cob := c.id;

  -- ---------------------------------------------------------------- 2
  select * into msg from public.mensagens where chave_idem = 'cobranca:'||cob::text;
  if not found then raise exception '2 FUROU: não enfileirou o aviso'; end if;
  if msg.template <> 'aviso_de_cobranca' then raise exception '2 FUROU: template %', msg.template; end if;
  if msg.agendada_para < now() + interval '50 minutes' then
    raise exception '2 FUROU: sem janela de perdão'; end if;
  if (msg.params->>'valor_centavos')::bigint <> 10000 then raise exception '2 FUROU: centavos'; end if;

  -- ---------------------------------------------------------------- 3
  select public.perdoar_cobranca(cob,'primeira vez') into r;
  if r <> 'perdoada' then raise exception '3 FUROU: %', r; end if;
  if (select estado from public.mensagens where chave_idem='cobranca:'||cob::text) <> 'cancelada' then
    raise exception '3 FUROU: o aviso ainda vai sair'; end if;

  -- ---------------------------------------------------------------- 4
  falhou := false;
  begin perform public.perdoar_cobranca(cob);
  exception when others then falhou := true; end;
  if not falhou then raise exception '4 FUROU: perdoou duas vezes'; end if;

  -- ---------------------------------------------------------------- 5
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,caio, now()+interval '5 days', now()+interval '5 days'+interval '50 min','avulsa',200.00,24,50) returning id into s2;
  perform public.cancelar_sessao(s2,'paciente');
  select count(*) into n from public.cobrancas where sessao_id=s2;
  if n <> 0 then raise exception '5 FUROU: cobrou quem avisou no prazo'; end if;

  -- ---------------------------------------------------------------- 6
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,livre,base+interval '1 hour',base+interval '1 hour 50 min','avulsa',200.00,24,0) returning id into s3;
  perform public.cancelar_sessao(s3,'paciente');
  select count(*) into n from public.cobrancas where sessao_id=s3;
  if n <> 0 then raise exception '6 FUROU: gerou cobrança zerada'; end if;

  -- ---------------------------------------------------------------- 7
  update public.sessoes set estado='prevista' where id=s2;
  update public.sessoes set inicio = now()-interval '2 hours', fim = now()-interval '1 hour' where id=s2;
  update public.sessoes set estado='falta' where id=s2;
  select * into c from public.cobrancas where sessao_id=s2 and estado='aberta';
  if not found then raise exception '7 FUROU: falta não gerou cobrança'; end if;
  if c.valor <> 100.00 then raise exception '7 FUROU: valor %', c.valor; end if;
  if c.motivo <> 'falta' then raise exception '7 FUROU: motivo %', c.motivo; end if;
  cob2 := c.id;

  -- ---------------------------------------------------------------- 8
  update public.sessoes set estado='realizada' where id=s2;
  if (select estado from public.cobrancas where id=cob2) <> 'cancelada' then
    raise exception '8 FUROU: a cobrança sobreviveu ao desfazer'; end if;
  if (select estado from public.mensagens where chave_idem='cobranca:'||cob2::text) <> 'cancelada' then
    raise exception '8 FUROU: o aviso ainda vai sair depois do desfazer'; end if;

  -- ---------------------------------------------------------------- 9 e 10
  update public.sessoes set estado='falta' where id=s2;
  select count(*) into n from public.cobrancas where sessao_id=s2;
  if n <> 2 then raise exception '9 FUROU: % cobranças (esperado 2)', n; end if;
  select count(*) into n from public.cobrancas where sessao_id=s2 and estado='aberta';
  if n <> 1 then raise exception '9 FUROU: % vivas', n; end if;

  update public.sessoes set estado='falta' where id=s2;
  select count(*) into n from public.cobrancas where sessao_id=s2 and estado='aberta';
  if n <> 1 then raise exception '10 FUROU: duplicou'; end if;

  -- ---------------------------------------------------------------- 11
  -- A 0023 abriu **uma** transição para o app: pendente → cancelada. Nem uma
  -- a mais.
  select id into mid from public.mensagens where conta_id=a_conta and estado='cancelada' limit 1;
  update public.mensagens set estado='pendente' where id=mid;
  if (select estado from public.mensagens where id=mid) = 'pendente' then
    raise exception '11 FUROU: ressuscitou mensagem cancelada'; end if;

  select public.enfileirar_mensagem(livre,'lembrete_de_sessao','z9') into mid;
  falhou := false;
  begin
    update public.mensagens set estado='enviada', provedor='forjado' where id=mid;
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '11 FUROU: o app marcou mensagem como enviada'; end if;

  update public.mensagens set estado='cancelada' where id=mid;
  if (select estado from public.mensagens where id=mid) <> 'cancelada' then
    raise exception '11 FUROU: não deu para segurar o envio'; end if;

  -- ---------------------------------------------------------------- 12
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.cobrancas;
  if n <> 0 then raise exception '12 FUROU: B viu % cobranças de A', n; end if;
  falhou := false;
  begin perform public.perdoar_cobranca(cob2);
  exception when others then falhou := true; end;
  if not falhou then raise exception '12 FUROU: B perdoou cobrança de A'; end if;
  if (select estado from public.cobrancas where id=cob2) <> 'aberta' then
    raise exception '12 FUROU: a cobrança de A mudou'; end if;

  -- ---------------------------------------------------------------- 13
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.cobrancas;
  if n <> 0 then raise exception '13 FUROU: anon leu cobranças'; end if;
  falhou := false;
  begin perform public.perdoar_cobranca(cob2);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '13 FUROU: anon perdoou'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.cobrancas where conta_id in (a_conta,b_conta);
  delete from public.mensagens where conta_id in (a_conta,b_conta);
  delete from public.sessoes where conta_id in (a_conta,b_conta);
  delete from public.pacientes where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B11 OK — 13 verificações, todas passaram';
end $$;
