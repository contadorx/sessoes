-- Teste adversarial de pacientes e enquadres (critério de pronto da B4).
--
-- Estas são as primeiras tabelas com dado de paciente. O que se prova aqui:
--   1. `conta_id` é derivado por gatilho, não digitado pelo cliente
--   2. cada conta enxerga só os próprios pacientes e enquadres
--   3. nem o telefone alheio se edita
--   4. não se cadastra paciente sob o profissional de outra conta
--   5. não se abre enquadre no paciente de outra conta
--   6. só existe um enquadre aberto por paciente
--   7. o mecanismo do reajuste (fecha um, abre outro) preserva o histórico
--   8. os checks de domínio recusam telefone e modo de mensagem inválidos
--   9. o anônimo não lê nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0005_pacientes_enquadres.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; b_conta uuid; a_prof uuid; b_prof uuid;
  a_pac uuid; b_pac uuid; a_enq uuid; n int; falhou boolean;
begin
  -- Limpeza na ordem certa: `pacientes.profissional_id` é `on delete restrict`,
  -- então apagar o auth.user antes esbarra na FK. Isso é de propósito — não se
  -- perde o vínculo de um profissional que tem paciente.
  delete from public.enquadres where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth, b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.sessoes.com.br', '{"nome":"Ana Solo"}'::jsonb),
         (b_auth, 'b@teste.sessoes.com.br', '{"nome":"Bruna Solo"}'::jsonb);

  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta;
  select id into b_prof from public.profissionais where conta_id = b_conta;

  -- ---------------------------------------------------- a conta B monta a dela
  perform set_config('request.jwt.claims', json_build_object('sub', b_auth, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id, nome, telefone, msg_canal, msg_modo)
  values (b_prof, 'Paciente da Bruna', '5511999990000', 'whatsapp', 'discreto') returning id into b_pac;
  insert into public.enquadres (paciente_id, dia_semana, hora, valor) values (b_pac, 4, '19:00', 250.00);

  -- ------------------------------------------------------------- e a conta A
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- O caso do critério de pronto: Maria Fernanda, terça 15h, R$ 200, 24h/50%,
  -- WhatsApp em modo discreto.
  insert into public.pacientes (profissional_id, nome, telefone, msg_canal, msg_modo)
  values (a_prof, 'Maria Fernanda Reis', '5511987654321', 'whatsapp', 'discreto') returning id into a_pac;
  insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual)
  values (a_pac, 2, '15:00', 50, 200.00, 24, 50) returning id into a_enq;

  if (select conta_id from public.pacientes where id = a_pac) <> a_conta then
    raise exception '1 FUROU: conta_id do paciente não foi derivado'; end if;
  if (select conta_id from public.enquadres where id = a_enq) <> a_conta then
    raise exception '1 FUROU: conta_id do enquadre não foi derivado'; end if;

  select count(*) into n from public.pacientes;
  if n <> 1 then raise exception '2 FUROU: A enxerga % pacientes', n; end if;
  select count(*) into n from public.enquadres;
  if n <> 1 then raise exception '2 FUROU: A enxerga % enquadres', n; end if;

  update public.pacientes set telefone = '5511000000000' where id = b_pac;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '3 FUROU: A alterou paciente da B'; end if;

  falhou := false;
  begin
    insert into public.pacientes (profissional_id, nome) values (b_prof, 'Plantado');
    falhou := true;
  exception when others then null; end;
  if falhou then raise exception '4 FUROU: A usou o profissional da B'; end if;

  falhou := false;
  begin
    insert into public.enquadres (paciente_id, dia_semana, hora, valor) values (b_pac, 1, '10:00', 100.00);
    falhou := true;
  exception when others then null; end;
  if falhou then raise exception '5 FUROU: A abriu enquadre no paciente da B'; end if;

  falhou := false;
  begin
    insert into public.enquadres (paciente_id, dia_semana, hora, valor) values (a_pac, 3, '16:00', 220.00);
    falhou := true;
  exception when unique_violation then null; end;
  if falhou then raise exception '6 FUROU: dois enquadres abertos no mesmo paciente'; end if;

  -- O mecanismo do reajuste (D14): fecha o corrente, abre o próximo.
  update public.enquadres set vigencia_fim = public.hoje_sp(), motivo_fim = 'reajuste' where id = a_enq;
  insert into public.enquadres (paciente_id, dia_semana, hora, valor) values (a_pac, 2, '15:00', 230.00);

  select count(*) into n from public.enquadres where paciente_id = a_pac;
  if n <> 2 then raise exception '7 FUROU: o histórico do combinado não ficou de pé'; end if;
  select count(*) into n from public.enquadres where paciente_id = a_pac and vigencia_fim is null;
  if n <> 1 then raise exception '7 FUROU: % enquadres abertos após o reajuste', n; end if;

  falhou := false;
  begin insert into public.pacientes (profissional_id, nome, telefone) values (a_prof,'X','abc'); falhou := true;
  exception when check_violation then null; end;
  if falhou then raise exception '8 FUROU: telefone inválido passou'; end if;

  falhou := false;
  begin insert into public.pacientes (profissional_id, nome, msg_modo) values (a_prof,'X','secreto'); falhou := true;
  exception when check_violation then null; end;
  if falhou then raise exception '8 FUROU: msg_modo inválido passou'; end if;

  reset role;
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  select count(*) into n from public.pacientes; if n <> 0 then raise exception '9 FUROU: anon leu pacientes'; end if;
  select count(*) into n from public.enquadres; if n <> 0 then raise exception '9 FUROU: anon leu enquadres'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.enquadres where conta_id in (a_conta, b_conta);
  delete from public.pacientes where conta_id in (a_conta, b_conta);
  delete from auth.users where id in (a_auth, b_auth);
  delete from public.contas where id in (a_conta, b_conta);

  raise notice 'B4 ISOLAMENTO OK — 9 verificações, todas passaram';
end $$;
