-- Teste dos documentos (critério de pronto da B17).
--
-- Recibo, declaração e informe saem com o nome e o CRP dela no papel. Isso muda
-- o que "correto" significa: um número errado aqui não é um bug de tela — é um
-- documento assinado por ela dizendo uma coisa que não aconteceu.
--
--   1. o recibo soma só as sessões REALIZADAS — falta cobrada não é atendimento
--   2. o retrato congela quem é quem, com CRP e CPF
--   3. a declaração de comparecimento não fala de dinheiro
--   4. o retrato não muda quando o mundo muda depois
--   5. documento emitido não se edita nem se apaga
--   6. cancelar exige motivo, e queima o número
--   7. cancelado não volta atrás
--   8. período sem atendimento não vira documento
--   9. período invertido é recusado
--  10. cada emissão entra na trilha de acesso (PR13)
--  11. isolamento — e a numeração de cada conta é dela
--  12. o anônimo não lê nem emite
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0029_documentos.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; b_pac uuid; d1 uuid; d2 uuid; d3 uuid;
  base date; n int; falhou boolean; doc record;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.documentos where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.cobrancas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.mensagens where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Paula Ferreira"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.profissionais set crp='06/123456', documento='12345678901' where id=a_prof;
  update public.contas set cidade='Sao Paulo' where id=a_conta;
  insert into public.pacientes (profissional_id,nome,telefone,cpf,estado)
    values (a_prof,'Maria Fernanda Reis','5511900000001','98765432100','em_atendimento') returning id into maria;

  base := (now() at time zone 'America/Sao_Paulo')::date - 20;

  -- Três realizadas (200 + 200 + 180) e uma falta cobrada, que NÃO deve entrar.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, (((base+0)::timestamp + time '15:00') at time zone 'America/Sao_Paulo'),
          (((base+0)::timestamp + time '15:50') at time zone 'America/Sao_Paulo'),'avulsa','realizada',200.00,24,50);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, (((base+7)::timestamp + time '15:00') at time zone 'America/Sao_Paulo'),
          (((base+7)::timestamp + time '15:50') at time zone 'America/Sao_Paulo'),'avulsa','realizada',200.00,24,50);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, (((base+14)::timestamp + time '15:00') at time zone 'America/Sao_Paulo'),
          (((base+14)::timestamp + time '15:50') at time zone 'America/Sao_Paulo'),'avulsa','realizada',180.00,24,50);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, (((base+3)::timestamp + time '15:00') at time zone 'America/Sao_Paulo'),
          (((base+3)::timestamp + time '15:50') at time zone 'America/Sao_Paulo'),'avulsa','falta',200.00,24,50);

  -- ---------------------------------------------------------------- 1
  select public.emitir_documento(maria,'recibo',base-1,base+30) into d1;
  select * into doc from public.documentos where id=d1;
  if doc.quantidade <> 3 then raise exception '1 FUROU: % sessões (esperado 3)', doc.quantidade; end if;
  if doc.valor_total <> 580.00 then raise exception '1 FUROU: total % (esperado 580)', doc.valor_total; end if;
  if doc.numero <> 1 then raise exception '1 FUROU: numero %', doc.numero; end if;

  -- ---------------------------------------------------------------- 2
  if doc.retrato->'profissional'->>'crp' <> '06/123456' then raise exception '2 FUROU: crp'; end if;
  if doc.retrato->'profissional'->>'documento' <> '12345678901' then raise exception '2 FUROU: documento'; end if;
  if doc.retrato->'paciente'->>'cpf' <> '98765432100' then raise exception '2 FUROU: cpf'; end if;
  if jsonb_array_length(doc.retrato->'itens') <> 3 then raise exception '2 FUROU: itens'; end if;
  if (doc.retrato->'itens'->0->>'valor') is null then raise exception '2 FUROU: recibo sem valor no item'; end if;

  -- ---------------------------------------------------------------- 3
  -- Documento para o trabalho ou a escola não diz quanto alguém pagou.
  select public.emitir_documento(maria,'declaracao_comparecimento',base-1,base+30) into d2;
  select * into doc from public.documentos where id=d2;
  if doc.valor_total <> 0 then raise exception '3 FUROU: declaração com valor %', doc.valor_total; end if;
  if (doc.retrato->'itens'->0) ? 'valor' then raise exception '3 FUROU: valor vazou no item da declaração'; end if;
  if doc.quantidade <> 3 then raise exception '3 FUROU: quantidade'; end if;
  if doc.numero <> 2 then raise exception '3 FUROU: numeração não avançou'; end if;

  -- ---------------------------------------------------------------- 4
  update public.profissionais set crp='06/999999' where id=a_prof;
  update public.pacientes set nome='Outro Nome' where id=maria;
  select * into doc from public.documentos where id=d1;
  if doc.retrato->'profissional'->>'crp' <> '06/123456' then
    raise exception '4 FUROU: o CRP mudou num recibo já emitido'; end if;
  if doc.retrato->'paciente'->>'nome' <> 'Maria Fernanda Reis' then
    raise exception '4 FUROU: o nome mudou'; end if;

  -- ---------------------------------------------------------------- 5
  falhou := false;
  begin update public.documentos set valor_total=1.00 where id=d1;
  exception when others then falhou := true; end;
  if not falhou then raise exception '5 FUROU: editou documento emitido'; end if;

  delete from public.documentos where id=d1;
  if (select count(*) from public.documentos where id=d1) <> 1 then
    raise exception '5 FUROU: apagou documento'; end if;

  -- ---------------------------------------------------------------- 6
  falhou := false;
  begin perform public.cancelar_documento(d2,'x');
  exception when others then falhou := true; end;
  if not falhou then raise exception '6 FUROU: cancelou sem motivo'; end if;

  perform public.cancelar_documento(d2,'emitido para o período errado');
  if (select cancelado_em from public.documentos where id=d2) is null then
    raise exception '6 FUROU: não cancelou'; end if;

  select public.emitir_documento(maria,'recibo',base-1,base+30) into d3;
  if (select numero from public.documentos where id=d3) <> 3 then
    raise exception '6 FUROU: reaproveitou o número queimado'; end if;

  -- ---------------------------------------------------------------- 7
  falhou := false;
  begin update public.documentos set cancelado_em=null where id=d2;
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: descancelou'; end if;

  -- ---------------------------------------------------------------- 8 e 9
  falhou := false;
  begin perform public.emitir_documento(maria,'recibo',base+100,base+130);
  exception when others then
    falhou := true;
    if sqlerrm not like '%sessão realizada%' then raise; end if;
  end;
  if not falhou then raise exception '8 FUROU: emitiu recibo de zero atendimento'; end if;

  falhou := false;
  begin perform public.emitir_documento(maria,'recibo',base+30,base);
  exception when others then falhou := true; end;
  if not falhou then raise exception '9 FUROU: aceitou período invertido'; end if;

  -- ---------------------------------------------------------------- 10
  select count(*) into n from public.trilha_acesso
   where paciente_id=maria and acao='exportou_paciente' and detalhe ? 'documento';
  if n < 3 then raise exception '10 FUROU: % emissões na trilha', n; end if;

  -- ---------------------------------------------------------------- 11
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.documentos;
  if n <> 0 then raise exception '11 FUROU: B viu % documentos de A', n; end if;
  falhou := false;
  begin perform public.emitir_documento(maria,'recibo',base-1,base+30);
  exception when others then falhou := true; end;
  if not falhou then raise exception '11 FUROU: B emitiu documento para paciente de A'; end if;

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (b_prof,'Paciente da Bruna','5511900000009','em_atendimento') returning id into b_pac;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (b_conta,b_prof,b_pac, (((base+1)::timestamp + time '10:00') at time zone 'America/Sao_Paulo'),
          (((base+1)::timestamp + time '10:50') at time zone 'America/Sao_Paulo'),'avulsa','realizada',300.00,24,50);
  select public.emitir_documento(b_pac,'recibo',base-1,base+30) into d1;
  if (select numero from public.documentos where id=d1) <> 1 then
    raise exception '11 FUROU: a numeração de B seguiu a de A'; end if;

  -- ---------------------------------------------------------------- 12
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.documentos;
  if n <> 0 then raise exception '12 FUROU: anon leu documentos'; end if;
  falhou := false;
  begin perform public.emitir_documento(maria,'recibo',base-1,base+30);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '12 FUROU: anon emitiu'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.documentos where conta_id in (a_conta,b_conta);
  delete from public.trilha_acesso where conta_id in (a_conta,b_conta);
  delete from public.sessoes where conta_id in (a_conta,b_conta);
  delete from public.pacientes where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B17 OK — 12 verificações, todas passaram';
end $$;
