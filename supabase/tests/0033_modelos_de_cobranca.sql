-- Teste dos três modelos de cobrança (critério de pronto da B20).
--
-- Metade destas verificações é sobre **não cobrar duas vezes pela mesma hora**.
-- É onde este build erra se errar: quem paga mensalidade e falta já pagou
-- aquela hora; quem comprou pacote já pagou aquela hora. Cobrar por cima é o
-- tipo de erro que a psicóloga descobre pela reclamação do paciente, e que
-- destrói a confiança em todo o resto do sistema de uma vez.
--
--   1. março/2026 tem cinco terças, abril tem quatro
--   2. valor fixo: o mês de cinco sai pelo mesmo preço
--   3. por sessão: o mês de cinco sai maior, o de quatro sai menor
--   4. quem entra no meio do mês paga proporcional
--   5. férias não descontam o valor fixo — no modo por sessão, descontam
--   6. cancelada com antecedência não entra na conta
--   7. a mensalidade não nasce duas vezes no mesmo mês
--   8. a mensalidade tem competência, motivo e nenhuma sessão presa
--   9. falta dentro do mensal não gera cobrança nem aviso
--  10. ela pode pedir para cobrar à parte, e aí cobra
--  11. avulso com `cobra_sessao` desligado: sessão realizada não cobra
--  12. ligado: cobra uma vez, e não manda mensagem para quem saiu da sala
--  13. desfazer a realizada cancela a cobrança
--  14. vender pacote gera uma cobrança e o saldo nasce cheio
--  15. sessão realizada consome crédito e não cobra
--  16. falta consome crédito e não cobra
--  17. desfazer devolve o crédito
--  18. sem saldo, a sessão volta a ser avulsa e a política vale
--  19. a tela não planta nem apaga consumo — o saldo não é opinião
--  20. pacote com validade no passado é recusado
--  21. cancelar o pacote cancela a cobrança aberta e preserva os consumos
--  22. recibo de mensalista sem pagamento registrado é recusado
--  23. e com pagamento, o valor vem da cobrança paga, não da soma das sessões
--  24. (B23) o avulso também exige recebimento — e mantém o valor por linha
--  25. isolamento entre contas
--  26. o anônimo não lê, não vende, não cancela e não roda a rotina
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0033_modelos_de_cobranca.sql

-- ======================================== parte 1 · a aritmética do mês

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  fixa uuid; porsessao uuid; borda uuid;
  e_fixa uuid; e_por uuid; e_borda uuid;
  v numeric; d date;
begin
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacote_consumos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacotes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.aceites where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.contratos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.documentos where conta_id in (select id from public.contas where nome='Ana Solo');
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
  if public.ocorrencias_do_dia_no_mes(2::smallint,'2026-03-01') <> 5 then
    raise exception '1 FUROU: março/2026 não tem 5 terças'; end if;
  if public.ocorrencias_do_dia_no_mes(2::smallint,'2026-04-01') <> 4 then
    raise exception '1 FUROU: abril/2026 não tem 4 terças'; end if;
  -- Qualquer dia do mês responde a mesma coisa: a competência é o mês.
  if public.ocorrencias_do_dia_no_mes(2::smallint,'2026-03-19') <> 5 then
    raise exception '1 FUROU: a competência não é o mês inteiro'; end if;

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Fixa Mensal','5511900000011','em_atendimento') returning id into fixa;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Por Sessao','5511900000012','em_atendimento') returning id into porsessao;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Meio Do Mes','5511900000013','em_atendimento') returning id into borda;

  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,mensalidade_valor,vigencia_inicio)
    values (fixa,2,'08:00',50,200.00,'mensal',750.00,'2026-01-06') returning id into e_fixa;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,mensalidade_valor,vigencia_inicio)
    values (porsessao,2,'09:00',50,200.00,'mensal',null,'2026-01-06') returning id into e_por;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,mensalidade_valor,vigencia_inicio)
    values (borda,2,'10:00',50,200.00,'mensal',750.00,'2026-03-17') returning id into e_borda;

  -- Sessão de recorrência é da materialização, não do cliente: a policy da 0006
  -- só deixa o app criar encaixe e avulsa. O fixture entra pelo mesmo caminho
  -- que a rotina usaria.
  reset role;
  foreach d in array array['2026-03-03','2026-03-10','2026-03-17','2026-03-24','2026-03-31',
                           '2026-04-07','2026-04-14','2026-04-21','2026-04-28']::date[] loop
    insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
    values (a_conta,a_prof,porsessao,e_por,(d + time '09:00') at time zone 'America/Sao_Paulo',
            (d + time '09:50') at time zone 'America/Sao_Paulo','recorrencia',200.00,24,50);
  end loop;
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 2
  v := public.valor_da_mensalidade(e_fixa,'2026-03-01');
  if v <> 750.00 then raise exception '2 FUROU: mês de cinco terças no valor fixo saiu %', v; end if;
  v := public.valor_da_mensalidade(e_fixa,'2026-04-01');
  if v <> 750.00 then raise exception '2 FUROU: mês de quatro terças no valor fixo saiu %', v; end if;

  -- ---------------------------------------------------------------- 3
  v := public.valor_da_mensalidade(e_por,'2026-03-01');
  if v <> 1000.00 then raise exception '3 FUROU: cinco sessões por 200 deram %', v; end if;
  v := public.valor_da_mensalidade(e_por,'2026-04-01');
  if v <> 800.00 then raise exception '3 FUROU: quatro sessões por 200 deram %', v; end if;

  -- ---------------------------------------------------------------- 4
  -- Entrou em 17/03: cabem três das cinco terças.
  v := public.valor_da_mensalidade(e_borda,'2026-03-01');
  if v <> 450.00 then raise exception '4 FUROU: proporcional de entrada saiu % (esperado 450)', v; end if;
  v := public.valor_da_mensalidade(e_borda,'2026-04-01');
  if v <> 750.00 then raise exception '4 FUROU: o mês seguinte inteiro não saiu cheio: %', v; end if;

  -- ---------------------------------------------------------------- 5
  reset role;
  delete from public.sessoes where enquadre_id=e_por and (inicio at time zone 'America/Sao_Paulo')::date='2026-03-31';
  execute 'set local role authenticated';
  v := public.valor_da_mensalidade(e_fixa,'2026-03-01');
  if v <> 750.00 then raise exception '5 FUROU: o valor fixo encolheu com a agenda'; end if;
  v := public.valor_da_mensalidade(e_por,'2026-03-01');
  if v <> 800.00 then raise exception '5 FUROU: por sessão, quatro deveriam dar 800, deu %', v; end if;

  -- ---------------------------------------------------------------- 6
  reset role;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,estado,cancelada_em,cancelada_por,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,porsessao,e_por,
          ('2026-03-31'::date + time '09:00') at time zone 'America/Sao_Paulo',
          ('2026-03-31'::date + time '09:50') at time zone 'America/Sao_Paulo',
          'recorrencia','cancelada_cedo', now(), 'paciente', 200.00,24,50);
  execute 'set local role authenticated';
  v := public.valor_da_mensalidade(e_por,'2026-03-01');
  if v <> 800.00 then raise exception '6 FUROU: cancelada_cedo entrou na conta (%)', v; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · a aritmética do mês: ok';
end $do$;

-- ================================ parte 2 · o mensal e o avulso no gatilho

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  fixa uuid; avulso uuid; e_fixa uuid; e_av uuid;
  s uuid; sa uuid; n int; c record;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into fixa from public.pacientes where conta_id=a_conta and nome='Fixa Mensal';
  select id into e_fixa from public.enquadres where paciente_id=fixa and vigencia_fim is null;

  -- ---------------------------------------------------------------- 7 e 8
  reset role; perform set_config('request.jwt.claims','',true);
  select public.agendar_mensalidades() into n;
  if n < 1 then raise exception '7 FUROU: não gerou nenhuma mensalidade (%)', n; end if;

  select * into c from public.cobrancas
   where enquadre_id=e_fixa and tipo='mensalidade' and estado<>'cancelada';
  if not found then raise exception '8 FUROU: a mensalidade do combinado fixo não nasceu'; end if;
  if c.valor <> 750.00 then raise exception '8 FUROU: valor da mensalidade %', c.valor; end if;
  if c.motivo <> 'mensalidade' then raise exception '8 FUROU: motivo %', c.motivo; end if;
  if c.competencia <> date_trunc('month', public.hoje_sp())::date then
    raise exception '8 FUROU: competência %', c.competencia; end if;
  if c.sessao_id is not null then raise exception '8 FUROU: mensalidade presa a uma sessão'; end if;

  -- Rodar de novo é o caso real: alguém reexecuta o cron à mão.
  perform public.agendar_mensalidades();
  perform public.agendar_mensalidades();
  select count(*) into n from public.cobrancas
   where enquadre_id=e_fixa and tipo='mensalidade' and estado<>'cancelada';
  if n <> 1 then raise exception '7 FUROU: % mensalidades para o mesmo mês', n; end if;

  -- ---------------------------------------------------------------- 9
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,fixa,e_fixa, now()-interval '3 hours', now()-interval '2 hours 10 minutes','recorrencia',200.00,24,50)
  returning id into s;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  update public.sessoes set estado='falta' where id=s;

  select count(*) into n from public.cobrancas where sessao_id=s;
  if n <> 0 then raise exception '9 FUROU: cobrou a falta por cima da mensalidade — duas vezes pela mesma hora'; end if;
  select count(*) into n from public.mensagens where (params->>'sessao_id')=s::text;
  if n <> 0 then raise exception '9 FUROU: mandou aviso de cobrança de uma hora já paga'; end if;

  -- ---------------------------------------------------------------- 10
  update public.sessoes set estado='prevista', cancelada_em=null, cancelada_por=null where id=s;
  update public.enquadres set falta_cobra_a_parte=true where id=e_fixa;
  update public.sessoes set estado='falta' where id=s;
  select * into c from public.cobrancas where sessao_id=s and estado='aberta';
  if not found then raise exception '10 FUROU: ela pediu para cobrar à parte e não cobrou'; end if;
  if c.valor <> 100.00 then raise exception '10 FUROU: valor %', c.valor; end if;
  update public.enquadres set falta_cobra_a_parte=false where id=e_fixa;

  -- ---------------------------------------------------------------- 11
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Avulso Silva','5511900000014','em_atendimento') returning id into avulso;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,vigencia_inicio)
    values (avulso,2,'14:00',50,300.00,'avulso','2026-01-06') returning id into e_av;

  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,avulso,e_av, now()-interval '5 hours', now()-interval '4 hours 10 minutes','recorrencia',300.00,24,50)
  returning id into sa;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  update public.sessoes set estado='realizada' where id=sa;
  select count(*) into n from public.cobrancas where sessao_id=sa;
  if n <> 0 then raise exception '11 FUROU: cobrou a sessão realizada com cobra_sessao desligado'; end if;

  -- ---------------------------------------------------------------- 12
  update public.sessoes set estado='prevista' where id=sa;
  reset role; perform set_config('request.jwt.claims','',true);
  update public.contas set cobra_sessao=true where id=a_conta;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.sessoes set estado='realizada' where id=sa;
  select * into c from public.cobrancas where sessao_id=sa and estado='aberta';
  if not found then raise exception '12 FUROU: não cobrou a sessão realizada'; end if;
  if c.valor <> 300.00 or c.tipo <> 'sessao' or c.motivo <> 'sessao_realizada' then
    raise exception '12 FUROU: cobrança errada: % % %', c.valor, c.tipo, c.motivo; end if;
  select count(*) into n from public.mensagens where (params->>'sessao_id')=sa::text;
  if n <> 0 then raise exception '12 FUROU: mandou mensagem para quem acabou de sair da sala'; end if;

  -- ---------------------------------------------------------------- 13
  update public.sessoes set estado='prevista' where id=sa;
  if (select estado from public.cobrancas where id=c.id) <> 'cancelada' then
    raise exception '13 FUROU: desfazer a realizada não cancelou a cobrança'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.contas set cobra_sessao=false where id=a_conta;
  raise notice 'parte 2 · o mensal e o avulso: ok';
end $do$;

-- ======================================================= parte 3 · o pacote

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  pac uuid; e_pac uuid; p1 uuid; p2 uuid;
  s1 uuid; s2 uuid; s3 uuid; n int; c record; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Pacote Souza','5511900000015','em_atendimento') returning id into pac;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,vigencia_inicio)
    values (pac,2,'16:00',50,250.00,'pacote','2026-01-06') returning id into e_pac;

  -- ---------------------------------------------------------------- 14
  select public.vender_pacote(pac, 2::smallint, 900.00, public.hoje_sp() + 90) into p1;
  if public.saldo_do_pacote(p1) <> 2 then
    raise exception '14 FUROU: saldo inicial %', public.saldo_do_pacote(p1); end if;

  select * into c from public.cobrancas where pacote_id=p1;
  if not found then raise exception '14 FUROU: a venda não gerou cobrança'; end if;
  if c.valor <> 900.00 or c.tipo <> 'pacote' then
    raise exception '14 FUROU: cobrança % %', c.valor, c.tipo; end if;
  select count(*) into n from public.cobrancas where pacote_id=p1;
  if n <> 1 then raise exception '14 FUROU: % cobranças para um pacote', n; end if;

  -- ---------------------------------------------------------------- 15
  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,pac,e_pac, now()-interval '30 hours', now()-interval '29 hours 10 minutes','recorrencia',250.00,24,50)
  returning id into s1;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.sessoes set estado='realizada' where id=s1;
  if public.saldo_do_pacote(p1) <> 1 then
    raise exception '15 FUROU: a sessão realizada não consumiu crédito (saldo %)', public.saldo_do_pacote(p1); end if;
  select count(*) into n from public.cobrancas where sessao_id=s1;
  if n <> 0 then raise exception '15 FUROU: cobrou uma sessão que estava dentro do pacote'; end if;

  -- ---------------------------------------------------------------- 16
  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,pac,e_pac, now()-interval '10 hours', now()-interval '9 hours 10 minutes','recorrencia',250.00,24,50)
  returning id into s2;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.sessoes set estado='falta' where id=s2;
  if public.saldo_do_pacote(p1) <> 0 then
    raise exception '16 FUROU: a falta não consumiu crédito (saldo %)', public.saldo_do_pacote(p1); end if;
  select count(*) into n from public.cobrancas where sessao_id=s2;
  if n <> 0 then raise exception '16 FUROU: cobrou a multa por cima de um crédito consumido'; end if;

  -- ---------------------------------------------------------------- 17
  update public.sessoes set estado='prevista', cancelada_em=null, cancelada_por=null where id=s2;
  if public.saldo_do_pacote(p1) <> 1 then
    raise exception '17 FUROU: desfazer não devolveu o crédito (saldo %)', public.saldo_do_pacote(p1); end if;
  update public.sessoes set estado='falta' where id=s2;

  -- ---------------------------------------------------------------- 18
  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,pac,e_pac, now()-interval '4 hours', now()-interval '3 hours 10 minutes','recorrencia',250.00,24,50)
  returning id into s3;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.sessoes set estado='falta' where id=s3;
  if public.saldo_do_pacote(p1) <> 0 then raise exception '18 FUROU: consumiu crédito inexistente'; end if;
  select * into c from public.cobrancas where sessao_id=s3 and estado='aberta';
  if not found then raise exception '18 FUROU: sem saldo, a falta deixou de ser cobrada'; end if;
  if c.valor <> 125.00 then raise exception '18 FUROU: valor % (esperado 125)', c.valor; end if;

  -- ---------------------------------------------------------------- 19
  falhou := false;
  begin
    insert into public.pacote_consumos (conta_id,pacote_id,sessao_id,motivo)
    values (a_conta,p1,s3,'realizada');
  exception when others then falhou := true; end;
  if not falhou then raise exception '19 FUROU: a tela plantou um consumo'; end if;

  delete from public.pacote_consumos where pacote_id=p1;
  if public.saldo_do_pacote(p1) <> 0 then
    raise exception '19 FUROU: a tela apagou consumo e mudou o saldo'; end if;

  -- ---------------------------------------------------------------- 20
  falhou := false;
  begin perform public.vender_pacote(pac, 4::smallint, 900.00, public.hoje_sp() - 1);
  exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: vendeu pacote com validade no passado'; end if;

  -- ---------------------------------------------------------------- 21
  select public.vender_pacote(pac, 4::smallint, 800.00, public.hoje_sp() + 30) into p2;
  perform public.cancelar_pacote(p2, 'desistiu');
  if (select estado from public.cobrancas where pacote_id=p2) <> 'cancelada' then
    raise exception '21 FUROU: cancelar o pacote não cancelou a cobrança aberta'; end if;
  select count(*) into n from public.pacote_consumos where pacote_id=p1;
  if n <> 2 then raise exception '21 FUROU: os consumos do outro pacote sumiram (%)', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · o pacote: ok';
end $do$;

-- ============================ parte 4 · o recibo e as fronteiras

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  fixa uuid; avulso uuid; e_fixa uuid; pac uuid; p1 uuid;
  mens uuid; s uuid; sa uuid; doc uuid; d record; n int; falhou boolean;
  de date; ate date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into fixa from public.pacientes where conta_id=a_conta and nome='Fixa Mensal';
  select id into avulso from public.pacientes where conta_id=a_conta and nome='Avulso Silva';
  select id into pac from public.pacientes where conta_id=a_conta and nome='Pacote Souza';
  select id into e_fixa from public.enquadres where paciente_id=fixa and vigencia_fim is null;
  select id into p1 from public.pacotes where paciente_id=pac and cancelado_em is null limit 1;
  select id into sa from public.sessoes where paciente_id=avulso and inicio < now() order by inicio limit 1;

  -- O mês corrente, esticado para trás o quanto for preciso para conter as
  -- sessões que este próprio teste cria (`now() - 50 horas`). Sem o `least`,
  -- a suíte passava trinta dias por mês e falhava no dia 1º: as sessões caem no
  -- mês anterior e o recibo do mês corrente não acha atendimento nenhum.
  de  := least(date_trunc('month', public.hoje_sp())::date,
               ((now() - interval '60 hours') at time zone 'America/Sao_Paulo')::date);
  ate := (date_trunc('month', public.hoje_sp()) + interval '1 month - 1 day')::date;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.profissionais set assina_como='Ana Ferreira', crp='06/123456', documento='12345678901' where id=a_prof;
  update public.contas set cidade='São Paulo' where id=a_conta;
  update public.sessoes set estado='realizada' where id=sa;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,fixa,e_fixa, now()-interval '50 hours', now()-interval '49 hours 10 minutes','recorrencia','realizada',200.00,24,50)
  returning id into s;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 22
  falhou := false;
  begin doc := public.emitir_documento(fixa,'recibo',de,ate);
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '22 FUROU: emitiu recibo de mensalidade sem pagamento registrado'; end if;

  -- ---------------------------------------------------------------- 23
  select id into mens from public.cobrancas
   where enquadre_id=e_fixa and tipo='mensalidade' and estado='aberta';
  perform public.marcar_cobranca_paga(mens);

  doc := public.emitir_documento(fixa,'recibo',de,ate);
  select * into d from public.documentos where id=doc;
  if d.valor_total <> 750.00 then
    raise exception '23 FUROU: recibo de mensalista saiu por % — a soma das sessões daria outro número', d.valor_total; end if;
  if d.retrato->>'base' <> 'cobrancas_pagas' then
    raise exception '23 FUROU: a base do recibo é %', d.retrato->>'base'; end if;
  if (d.retrato->'itens'->0) ? 'valor' then
    raise exception '23 FUROU: o recibo lista valor por sessão e um total que não bate com eles'; end if;

  -- ---------------------------------------------------------------- 24
  -- Mudou na B23. A 0034 deixou anotado que o recibo do avulso não conferia
  -- nada; agora confere, porque passou a existir um jeito de dizer "recebi em
  -- dinheiro" sem ligar a cobrança por sessão. Os dois lados exigem pagamento.
  falhou := false;
  begin doc := public.emitir_documento(avulso,'recibo',de,ate);
  exception when others then
    falhou := true;
    if sqlerrm not like '%pagamento registrado%' then raise; end if;
  end;
  if not falhou then
    raise exception '24 FUROU: o recibo do avulso saiu sem nenhum recebimento registrado'; end if;

  for d in select id from public.sessoes
            where paciente_id=avulso and estado='realizada'
              and (inicio at time zone 'America/Sao_Paulo')::date between de and ate loop
    perform public.registrar_recebimento(d.id);
  end loop;

  doc := public.emitir_documento(avulso,'recibo',de,ate);
  select * into d from public.documentos where id=doc;
  if d.retrato->>'base' <> 'cobrancas_por_sessao' then
    raise exception '24 FUROU: o avulso mudou de base (%)', d.retrato->>'base'; end if;
  if d.valor_total <> 300.00 then
    raise exception '24 FUROU: o recibo do avulso saiu por %', d.valor_total; end if;
  if not ((d.retrato->'itens'->0) ? 'valor') then
    raise exception '24 FUROU: o avulso perdeu o valor por linha — é ele que o convênio pede'; end if;

  -- ---------------------------------------------------------------- 25
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.pacote_consumos where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.pacotes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bruna Solo';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.pacotes;
  if n <> 0 then raise exception '25 FUROU: a Bruna viu % pacotes da Ana', n; end if;
  select count(*) into n from public.pacote_consumos;
  if n <> 0 then raise exception '25 FUROU: a Bruna viu % consumos da Ana', n; end if;

  falhou := false;
  begin perform public.cancelar_pacote(p1,'não é meu');
  exception when others then falhou := true; end;
  if not falhou then raise exception '25 FUROU: a Bruna cancelou o pacote da Ana'; end if;
  if (select cancelado_em from public.pacotes where id=p1) is not null then
    raise exception '25 FUROU: o pacote da Ana ficou cancelado'; end if;

  falhou := false;
  begin perform public.vender_pacote(pac, 2::smallint, 100.00, public.hoje_sp()+30);
  exception when others then falhou := true; end;
  if not falhou then raise exception '25 FUROU: a Bruna vendeu pacote para paciente da Ana'; end if;

  -- ---------------------------------------------------------------- 26
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.pacotes;
  if n <> 0 then raise exception '26 FUROU: anon leu pacotes'; end if;

  falhou := false;
  begin perform public.agendar_mensalidades();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '26 FUROU: anon rodou agendar_mensalidades'; end if;

  falhou := false;
  begin perform public.vender_pacote(pac, 2::smallint, 100.00, public.hoje_sp()+30);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '26 FUROU: anon vendeu pacote'; end if;

  falhou := false;
  begin perform public.cancelar_pacote(p1);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '26 FUROU: anon cancelou pacote'; end if;

  falhou := false;
  begin perform public.valor_da_mensalidade(e_fixa, de);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '26 FUROU: anon calculou mensalidade alheia'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 4 · o recibo e as fronteiras: ok';
  raise notice '0033 · 26 verificações passaram.';
end $do$;
