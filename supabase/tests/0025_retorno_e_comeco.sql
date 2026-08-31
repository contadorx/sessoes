-- Teste do retorno e do começo (critério de pronto da B14).
--
-- O critério do doc 12 é humano: "uma psicóloga que nunca viu o sistema chega
-- sozinha, em menos de 30 minutos, ao estado em que a fila pode preencher a
-- primeira vaga". Isso se mede com gente, não com SQL.
--
-- O que dá para testar aqui é o que sustenta esse critério: que o roteiro de
-- começo reflete o **estado real** (e não uma lista marcada à mão), e que o
-- painel de retorno **não infla**. A segunda parte é a mais importante: um
-- painel que soma o que ainda não foi pago se autodestrói no primeiro mês, no
-- dia em que ela confere contra o extrato.
--
--   1. conta nova está zerada em todos os passos
--   2. cadastrar move os passos sozinho, e a agenda se materializa junto
--   3. mês sem cancelamento não inventa retorno
--   4. vaga preenchida conta como preenchida, com valor e horas
--   5. cobrança de cancelamento tardio entra em ABERTO, nunca em recebido
--   6. pagar move de aberto para recebido
--   7. depois da primeira vaga, o começo já não está no começo
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0025_retorno_e_comeco.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid; caio uuid;
  s1 uuid; of1 uuid; cob uuid; base timestamptz; r record; e jsonb;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ofertas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 1
  select public.estado_inicial() into e;
  if (e->>'pacientes')::int <> 0 or (e->>'na_fila')::int <> 0 or (e->>'vagas_abertas')::int <> 0 then
    raise exception '1 FUROU: conta nova não está zerada: %', e; end if;

  -- ---------------------------------------------------------------- 2
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.enquadres (paciente_id,dia_semana,hora,valor,politica_horas,politica_percentual) values (maria,2,'15:00',200.00,24,50);
  insert into public.fila_encaixe (paciente_id) values (caio);

  select public.estado_inicial() into e;
  if (e->>'pacientes')::int <> 2 then raise exception '2 FUROU: pacientes %', e->>'pacientes'; end if;
  if (e->>'enquadres')::int <> 1 then raise exception '2 FUROU: enquadres'; end if;
  if (e->>'na_fila')::int <> 1 then raise exception '2 FUROU: fila'; end if;
  if not (e->>'politica_definida')::boolean then raise exception '2 FUROU: política'; end if;
  if (e->>'com_canal')::int <> 2 then raise exception '2 FUROU: com_canal'; end if;
  if (e->>'sessoes')::int = 0 then raise exception '2 FUROU: a materialização não rodou'; end if;

  -- ---------------------------------------------------------------- 3
  select * into r from public.retorno(date_trunc('month', public.hoje_sp())::date, public.hoje_sp());
  if r.canceladas <> 0 or r.valor_preenchido <> 0 then raise exception '3 FUROU: %', r; end if;

  -- ---------------------------------------------------------------- 4
  base := now() + interval '3 hours';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa',200.00,24,50) returning id into s1;
  perform public.cancelar_sessao(s1,'paciente');
  select public.abrir_vaga(s1) into of1;
  if of1 is null then raise exception '4 FUROU: não ofertou'; end if;
  if public.responder_oferta(of1,'aceita') <> 'aceita' then raise exception '4 FUROU: aceite'; end if;

  select * into r from public.retorno(date_trunc('month', public.hoje_sp())::date, public.hoje_sp());
  if r.canceladas <> 1 then raise exception '4 FUROU: canceladas %', r.canceladas; end if;
  if r.preenchidas <> 1 then raise exception '4 FUROU: preenchidas %', r.preenchidas; end if;
  if r.taxa <> 100.0 then raise exception '4 FUROU: taxa %', r.taxa; end if;
  if r.valor_preenchido <= 0 then raise exception '4 FUROU: valor preenchido %', r.valor_preenchido; end if;
  if r.horas_recuperadas <= 0 then raise exception '4 FUROU: horas %', r.horas_recuperadas; end if;

  -- ---------------------------------------------------------------- 5
  -- O ponto do build inteiro: **cobrado não é recebido.**
  select id into cob from public.cobrancas where sessao_id=s1 and estado='aberta';
  if cob is null then raise exception '5 FUROU: sem cobrança'; end if;
  select * into r from public.retorno(date_trunc('month', public.hoje_sp())::date, public.hoje_sp());
  if r.valor_em_aberto <> 100.00 then raise exception '5 FUROU: em aberto %', r.valor_em_aberto; end if;
  if r.valor_recebido <> 0 then raise exception '5 FUROU: cobrado virou recebido sem ninguém pagar'; end if;

  -- ---------------------------------------------------------------- 6
  perform public.marcar_cobranca_paga(cob);
  select * into r from public.retorno(date_trunc('month', public.hoje_sp())::date, public.hoje_sp());
  if r.valor_recebido <> 100.00 then raise exception '6 FUROU: recebido %', r.valor_recebido; end if;
  if r.valor_em_aberto <> 0 then raise exception '6 FUROU: ficou em aberto'; end if;

  -- ---------------------------------------------------------------- 7
  select public.estado_inicial() into e;
  if (e->>'vagas_abertas')::int <> 1 or (e->>'preenchidas')::int <> 1 then
    raise exception '7 FUROU: %', e; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.cobrancas where conta_id=a_conta;
  delete from public.mensagens where conta_id=a_conta;
  delete from public.eventos_fila where conta_id=a_conta;
  delete from public.ofertas where conta_id=a_conta;
  delete from public.fila_encaixe where conta_id=a_conta;
  delete from public.sessoes where conta_id=a_conta;
  delete from public.enquadres where conta_id=a_conta;
  delete from public.pacientes where conta_id=a_conta;
  delete from auth.users where id=a_auth;
  delete from public.contas where id=a_conta;

  raise notice 'B14 OK — 7 verificações, todas passaram';
end $$;
