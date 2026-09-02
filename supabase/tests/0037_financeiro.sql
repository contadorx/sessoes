-- Teste do financeiro derivado da agenda (critério de pronto da B23).
--
-- A verificação nº 2 é a que decide o build: **o recebido é pela data do
-- pagamento, não pela competência**. Se ela falhar, o número que a psicóloga
-- copia para o carnê-leão não bate com o extrato dela — e quem descobre isso é
-- a Receita Federal, não um teste.
--
-- A nº 4 é a segunda em importância, e é doutrinária: não existe um campo
-- "total". Realizado e recebido são o mesmo mês visto de dois ângulos, e somar
-- os dois conta o mesmo dinheiro duas vezes.
--
--   1. realizado é competência: a sessão do mês entra no mês
--   2. recebido é caixa: o pagamento de abril por sessão de março é de ABRIL
--   3. ...e não aparece em março
--   4. não existe "total": somar as duas colunas seria contar duas vezes
--   5. a falta cobrada não entra no realizado, mas entra no recebido quando paga
--   6. perdoada não entra em recebido nem em em_aberto
--   7. cancelada não entra em nada
--   8. período invertido é recusado
--   9. registrar recebimento sem cobrança cria uma cobrança já paga
--  10. registrar duas vezes é recusado
--  11. sessão que não aconteceu não tem recebimento
--  12. sessão de mensalidade não tem recebimento avulso
--  13. sessão que comeu crédito de pacote também não
--  14. recebimento com data no futuro é recusado
--  15. recebimento com data de ontem carimba ontem
--  16. com `cobra_sessao`, a cobrança aberta vira paga — não nasce uma segunda
--  17. desfazer numa conta que não cobra pelo sistema CANCELA (ninguém entra na régua)
--  18. desfazer numa conta que cobra REABRE
--  19. desfazer pagamento do provedor é recusado
--  20. sem_registro lista o que falta e some depois do registro
--  21. despesa no futuro é recusada
--  22. categoria inventada é recusada
--  23. valor zero ou negativo é recusado
--  24. a tabela de despesas não tem paciente — e nunca vai ter
--  25. a despesa entra na sobra e na quebra por categoria
--  26. regressão B20: o recibo do avulso agora EXIGE pagamento registrado
--  27. ...e sai com valor por linha, base cobrancas_por_sessao
--  28. a declaração de comparecimento continua saindo sem pagamento nenhum
--  29. regressão B20: o recibo do mensalista continua sem valor por linha
--  30. isolamento entre contas: despesa, recebimento e painel
--  31. o anônimo não executa nada disto
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0037_financeiro.sql

-- ===================================== parte 1 · as duas colunas do mês

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; bia uuid; caio uuid;
  s1 uuid; s2 uuid; s3 uuid; sf uuid;
  cob uuid; cfalta uuid;
  m0 date; mp date; mpp date; fim_mp date; fim_mpp date;
  f jsonb; n numeric;
begin
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.despesas where conta_id in (select id from public.contas where nome='Ana Solo');
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

  m0     := date_trunc('month', public.hoje_sp())::date;
  mp     := (m0 - interval '1 month')::date;
  mpp    := (m0 - interval '2 months')::date;
  fim_mp := (m0 - interval '1 day')::date;
  fim_mpp:= (mp - interval '1 day')::date;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Ana Avulsa','5511900000061','em_atendimento') returning id into ana;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Bia Mensal','5511900000062','em_atendimento') returning id into bia;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Falta','5511900000063','em_atendimento') returning id into caio;

  -- Sessões gravadas direto no estado final: o gatilho de transição é `before
  -- update`, então inserir realizada não gera cobrança. É exatamente o cenário
  -- da conta padrão (`cobra_sessao` desligado) — atendeu e não registrou nada.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mpp + 4 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mpp + 4 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mp + 4 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mp + 4 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s2;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mp + 11 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mp + 11 + time '15:50') at time zone 'America/Sao_Paulo','encaixe','realizada',200.00)
    returning id into s3;

  -- ---------------------------------------------------------------- 1
  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'realizado'->>'valor')::numeric <> 400.00 then
    raise exception '1 FUROU: realizado do mês deu % em vez de 400', (f->'realizado'->>'valor'); end if;
  if (f->'realizado'->>'sessoes')::int <> 2 then
    raise exception '1 FUROU: contou % sessões', (f->'realizado'->>'sessoes'); end if;

  -- ---------------------------------------------------------------- 2 e 3
  -- A sessão é do mês retrasado; o dinheiro entrou no mês passado.
  cob := public.registrar_recebimento(s1, mp + 4);

  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'recebido'->>'valor')::numeric <> 200.00 then
    raise exception '2 FUROU: o pagamento não caiu no mês em que entrou (% em vez de 200) — o número do carnê-leão não bate com o extrato',
      (f->'recebido'->>'valor'); end if;

  f := public.financeiro_do_mes(mpp, fim_mpp);
  if (f->'recebido'->>'valor')::numeric <> 0 then
    raise exception '3 FUROU: o dinheiro apareceu no mês da sessão em vez do mês do pagamento (%)',
      (f->'recebido'->>'valor'); end if;
  if (f->'realizado'->>'valor')::numeric <> 200.00 then
    raise exception '3 FUROU: o realizado do mês retrasado sumiu (%)', (f->'realizado'->>'valor'); end if;

  -- ---------------------------------------------------------------- 4
  f := public.financeiro_do_mes(mp, fim_mp);
  if f ? 'total' then
    raise exception '4 FUROU: existe um campo "total" — somar realizado e recebido conta o mesmo dinheiro duas vezes'; end if;
  if f ? 'lucro' then
    raise exception '4 FUROU: existe um campo "lucro" — isto não é DRE (doc 03 §7)'; end if;

  -- ---------------------------------------------------------------- 5
  -- Uma falta cobrada: nasce do gatilho, e não é atendimento prestado.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
    values (a_conta,a_prof,caio,(mp + 18 + time '10:00') at time zone 'America/Sao_Paulo',
                        (mp + 18 + time '10:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00,24,50)
    returning id into sf;
  update public.sessoes set estado='falta' where id=sf;
  -- **P4 (0058):** a falta virou pergunta, e a cobrança só nasce da decisão.
  -- Esta suíte mede o que vem **depois** de a cobrança existir — então ela
  -- decide cobrar, pelo caminho de produção, e segue medindo a mesma coisa.
  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.sessao_id = sf and p.estado = 'pendente';

  select id into cfalta from public.cobrancas where sessao_id=sf and tipo='falta';
  if cfalta is null then raise exception '5 FUROU: a falta não gerou cobrança (regressão da B11)'; end if;

  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'realizado'->>'sessoes')::int <> 2 then
    raise exception '5 FUROU: a falta entrou no realizado — falta não é atendimento prestado'; end if;
  if (f->'em_aberto'->>'valor')::numeric <> 100.00 then
    raise exception '5 FUROU: a multa não apareceu em aberto (%)', (f->'em_aberto'->>'valor'); end if;

  perform public.marcar_cobranca_paga(cfalta);
  update public.cobrancas set paga_em = ((mp + 20 + time '12:00') at time zone 'America/Sao_Paulo') where id=cfalta;

  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'recebido'->>'valor')::numeric <> 300.00 then
    raise exception '5 FUROU: a multa paga não entrou no recebido (%)', (f->'recebido'->>'valor'); end if;
  if (f->'recuperado'->>'valor_faltas')::numeric <> 100.00 then
    raise exception '5 FUROU: a multa paga não contou como recuperada'; end if;
  if (f->'recuperado'->>'valor_encaixes')::numeric <> 200.00 then
    raise exception '5 FUROU: o encaixe realizado não contou como recuperado (%)',
      (f->'recuperado'->>'valor_encaixes'); end if;

  -- ---------------------------------------------------------------- 6
  update public.cobrancas set estado='aberta', paga_em=null where id=cfalta;
  perform public.perdoar_cobranca(cfalta, 'dia ruim');
  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'recebido'->>'valor')::numeric <> 200.00 then
    raise exception '6 FUROU: cobrança perdoada continuou contando como recebida'; end if;
  if (f->'em_aberto'->>'valor')::numeric <> 0 then
    raise exception '6 FUROU: cobrança perdoada continuou em aberto'; end if;
  if (f->'perdoado'->>'valor')::numeric <> 100.00 then
    raise exception '6 FUROU: o perdão não aparece em lugar nenhum — some do painel'; end if;

  -- ---------------------------------------------------------------- 7
  update public.cobrancas set estado='cancelada' where id=cfalta;
  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'perdoado'->>'valor')::numeric <> 0 or (f->'em_aberto'->>'valor')::numeric <> 0 then
    raise exception '7 FUROU: cobrança cancelada continuou somando'; end if;

  -- ---------------------------------------------------------------- 8
  begin
    f := public.financeiro_do_mes(fim_mp, mp);
    raise exception '8 FUROU: aceitou período invertido';
  exception when others then
    if position('invertido' in sqlerrm) = 0 then raise; end if;
  end;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · as duas colunas: ok';
end $do$;

-- ================================= parte 2 · "recebi", e o que ele recusa

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; bia uuid; dora uuid;
  s_futura uuid; s_mensal uuid; s_pacote uuid; s_boa uuid; s_cobra uuid;
  e_mensal uuid; e_pacote uuid;
  pac uuid; cob uuid; c2 uuid; r text;
  m0 date; mp date; fim_mp date; n int; f jsonb; d date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into ana from public.pacientes where conta_id=a_conta and nome='Ana Avulsa';
  select id into bia from public.pacientes where conta_id=a_conta and nome='Bia Mensal';

  m0 := date_trunc('month', public.hoje_sp())::date;
  mp := (m0 - interval '1 month')::date;
  fim_mp := (m0 - interval '1 day')::date;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 9
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mp + 25 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mp + 25 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_boa;

  cob := public.registrar_recebimento(s_boa, mp + 25);
  select count(*) into n from public.cobrancas where sessao_id=s_boa and estado='paga';
  if n <> 1 then raise exception '9 FUROU: não nasceu uma cobrança paga (%)', n; end if;
  select count(*) into n from public.cobrancas
   where id=cob and tipo='sessao' and motivo='sessao_realizada' and confirmado_por='ela' and valor=200.00;
  if n <> 1 then raise exception '9 FUROU: a cobrança nasceu com a cara errada'; end if;

  -- ---------------------------------------------------------------- 10
  begin
    perform public.registrar_recebimento(s_boa);
    raise exception '10 FUROU: registrou o mesmo recebimento duas vezes';
  exception when others then
    if position('já está registrada' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 11
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(public.hoje_sp() + 10 + time '15:00') at time zone 'America/Sao_Paulo',
                       (public.hoje_sp() + 10 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00)
    returning id into s_futura;
  begin
    perform public.registrar_recebimento(s_futura);
    raise exception '11 FUROU: registrou dinheiro de uma sessão que não aconteceu';
  exception when others then
    if position('só sessão realizada' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 12
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,
                                modelo_cobranca,mensalidade_valor)
    values (bia,2,'16:00',50,200.00,24,50,'mensal',750.00) returning id into e_mensal;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,bia,e_mensal,(mp + 5 + time '16:00') at time zone 'America/Sao_Paulo',
                                (mp + 5 + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_mensal;
  begin
    perform public.registrar_recebimento(s_mensal);
    raise exception '12 FUROU: registrou recebimento avulso numa sessão de mensalidade — o mês entraria duas vezes';
  exception when others then
    if position('mensalidade' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 13
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Dora Pacote','5511900000064','em_atendimento') returning id into dora;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,modelo_cobranca)
    values (dora,3,'17:00',50,200.00,24,50,'pacote') returning id into e_pacote;
  pac := public.vender_pacote(dora, 4::smallint, 700.00, (public.hoje_sp() + 90));

  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,dora,e_pacote,(mp + 6 + time '17:00') at time zone 'America/Sao_Paulo',
                                 (mp + 6 + time '17:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00)
    returning id into s_pacote;
  update public.sessoes set estado='realizada' where id=s_pacote;

  select count(*) into n from public.pacote_consumos where sessao_id=s_pacote;
  if n <> 1 then raise exception '13 FUROU: a sessão do pacote não consumiu crédito (regressão da B20)'; end if;

  begin
    perform public.registrar_recebimento(s_pacote);
    raise exception '13 FUROU: registrou recebimento de uma sessão já paga dentro do pacote';
  exception when others then
    if position('pacote' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 14
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mp + 26 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mp + 26 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_cobra;
  begin
    perform public.registrar_recebimento(s_cobra, public.hoje_sp() + 1);
    raise exception '14 FUROU: aceitou recebimento com data no futuro';
  exception when others then
    if position('futuro' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 15
  d := public.hoje_sp() - 1;
  c2 := public.registrar_recebimento(s_cobra, d);
  select (paga_em at time zone 'America/Sao_Paulo')::date into d
    from public.cobrancas where id=c2;
  if d <> public.hoje_sp() - 1 then
    raise exception '15 FUROU: o carimbo caiu em % em vez de ontem', d; end if;

  -- ---------------------------------------------------------------- 16
  perform public.desfazer_recebimento(s_cobra);
  update public.contas set cobra_sessao = true where id = a_conta;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(mp + 27 + time '15:00') at time zone 'America/Sao_Paulo',
                       (mp + 27 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00)
    returning id into s_cobra;
  update public.sessoes set estado='realizada' where id=s_cobra;

  select count(*) into n from public.cobrancas where sessao_id=s_cobra and estado='aberta';
  if n <> 1 then raise exception '16 FUROU: com cobra_sessao ligado não nasceu a cobrança aberta (%)', n; end if;

  cob := public.registrar_recebimento(s_cobra);
  select count(*) into n from public.cobrancas where sessao_id=s_cobra and estado <> 'cancelada';
  if n <> 1 then raise exception '16 FUROU: nasceu uma segunda cobrança para a mesma sessão (%)', n; end if;
  select count(*) into n from public.cobrancas where id=cob and estado='paga' and confirmado_por='ela';
  if n <> 1 then raise exception '16 FUROU: a cobrança aberta não virou paga'; end if;

  -- ---------------------------------------------------------------- 18
  r := public.desfazer_recebimento(s_cobra);
  if r <> 'reaberta' then
    raise exception '18 FUROU: numa conta que cobra pelo sistema, desfazer deveria reabrir (deu %)', r; end if;

  -- ---------------------------------------------------------------- 17
  update public.contas set cobra_sessao = false where id = a_conta;
  update public.cobrancas set estado='cancelada' where sessao_id=s_cobra;
  cob := public.registrar_recebimento(s_cobra);
  r := public.desfazer_recebimento(s_cobra);
  if r <> 'cancelada' then
    raise exception '17 FUROU: numa conta que não cobra pelo sistema, desfazer reabriu a cobrança — a pessoa entraria na régua de inadimplência por um dinheiro que nunca foi cobrado por aqui (deu %)', r; end if;

  -- ---------------------------------------------------------------- 19
  cob := public.registrar_recebimento(s_cobra);
  update public.cobrancas set confirmado_por='provedor' where id=cob;
  begin
    perform public.desfazer_recebimento(s_cobra);
    raise exception '19 FUROU: desfez um pagamento confirmado pelo provedor';
  exception when others then
    if position('provedor' in sqlerrm) = 0 then raise; end if;
  end;
  update public.cobrancas set estado='cancelada', confirmado_por=null where id=cob;

  -- ---------------------------------------------------------------- 20
  select count(*) into n from public.sessoes_sem_registro(mp, fim_mp) where sessao_id = s_cobra;
  if n <> 1 then raise exception '20 FUROU: a sessão sem recebimento não aparece na lista'; end if;

  select count(*) into n from public.sessoes_sem_registro(mp, fim_mp) where sessao_id = s_mensal;
  if n <> 0 then raise exception '20 FUROU: a sessão de mensalidade entrou na lista — registrar ali cobraria o mês duas vezes'; end if;

  select count(*) into n from public.sessoes_sem_registro(mp, fim_mp) where sessao_id = s_pacote;
  if n <> 0 then raise exception '20 FUROU: a sessão do pacote entrou na lista'; end if;

  perform public.registrar_recebimento(s_cobra, mp + 27);
  select count(*) into n from public.sessoes_sem_registro(mp, fim_mp) where sessao_id = s_cobra;
  if n <> 0 then raise exception '20 FUROU: continuou na lista depois de registrada'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · "recebi": ok';
end $do$;

-- ==================================== parte 3 · as despesas, e o que elas não são

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid;
  m0 date; mp date; fim_mp date;
  d1 uuid; n int; f jsonb; cat jsonb;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  m0 := date_trunc('month', public.hoje_sp())::date;
  mp := (m0 - interval '1 month')::date;
  fim_mp := (m0 - interval '1 day')::date;

  -- ---------------------------------------------------------------- 24
  -- Antes de qualquer coisa: a estrutura. O contador recebe dado financeiro,
  -- nunca clínico (F3, doc 07) — e a forma de garantir isso é a coluna não
  -- existir, não a tela não mostrar.
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name='despesas'
     and column_name in ('paciente_id','sessao_id','enquadre_id');
  if n <> 0 then
    raise exception '24 FUROU: a tabela de despesas tem coluna ligando a paciente — a pasta do contador passaria a carregar dado clínico'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 21
  begin
    insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
      values (a_conta, public.hoje_sp() + 1, 'aluguel', 'Sala do mês que vem', 900.00);
    raise exception '21 FUROU: aceitou despesa com data no futuro — isto viraria contas a pagar (doc 03 §7)';
  exception when others then
    if position('futuro' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 22
  begin
    insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
      values (a_conta, mp + 5, 'marketing', 'Anúncio', 100.00);
    raise exception '22 FUROU: aceitou categoria fora da lista — categoria livre vira quarenta em três meses';
  exception when others then
    if sqlstate <> '23514' and position('categoria' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 23
  begin
    insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
      values (a_conta, mp + 5, 'aluguel', 'Sala', 0);
    raise exception '23 FUROU: aceitou despesa de zero';
  exception when others then
    if sqlstate <> '23514' then raise; end if;
  end;
  begin
    insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
      values (a_conta, mp + 5, 'aluguel', 'Sala', -900.00);
    raise exception '23 FUROU: aceitou despesa negativa — sinal é contrato (lei nº 4, doc 05)';
  exception when others then
    if sqlstate <> '23514' then raise; end if;
  end;

  -- ---------------------------------------------------------------- 25
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, mp + 5, 'aluguel', 'Sala compartilhada', 900.00) returning id into d1;
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, mp + 10, 'supervisao', 'Supervisão quinzenal', 300.00);
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, mp + 20, 'supervisao', 'Supervisão quinzenal', 300.00);
  -- Fora do período: não pode entrar.
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, public.hoje_sp(), 'software', 'Assinatura', 69.00);

  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'despesas'->>'valor')::numeric <> 1500.00 then
    raise exception '25 FUROU: as despesas do mês somaram % em vez de 1500', (f->'despesas'->>'valor'); end if;
  if (f->'despesas'->>'lancamentos')::int <> 3 then
    raise exception '25 FUROU: contou % lançamentos', (f->'despesas'->>'lancamentos'); end if;

  select x into cat from jsonb_array_elements(f->'despesas'->'por_categoria') x
   where x->>'categoria' = 'supervisao';
  if cat is null or (cat->>'valor')::numeric <> 600.00 or (cat->>'lancamentos')::int <> 2 then
    raise exception '25 FUROU: a quebra por categoria está errada (%)', cat; end if;

  if (f->>'sobra')::numeric <> (f->'recebido'->>'valor')::numeric - 1500.00 then
    raise exception '25 FUROU: a sobra não é recebido menos despesa'; end if;

  -- Apagar é permitido: é dinheiro dela, sem ninguém do outro lado.
  delete from public.despesas where id = d1;
  select count(*) into n from public.despesas where id = d1;
  if n <> 0 then raise exception '25 FUROU: não deu para apagar uma despesa lançada errada'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · as despesas: ok';
end $do$;

-- =============================== parte 4 · o recibo, agora simétrico (B20)

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; bia uuid; eva uuid;
  s1 uuid; s2 uuid; e_mensal uuid;
  doc uuid; r record; item jsonb;
  m0 date; mp date; fim_mp date; n int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into bia from public.pacientes where conta_id=a_conta and nome='Bia Mensal';

  m0 := date_trunc('month', public.hoje_sp())::date;
  mp := (m0 - interval '1 month')::date;
  fim_mp := (m0 - interval '1 day')::date;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.profissionais set crp='06/123456', documento='12345678901' where id=a_prof;

  insert into public.pacientes (profissional_id,nome,telefone,cpf,estado)
    values (a_prof,'Eva Recibo','5511900000065','39053344705','em_atendimento') returning id into eva;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,eva,(mp + 7 + time '11:00') at time zone 'America/Sao_Paulo',
                       (mp + 7 + time '11:50') at time zone 'America/Sao_Paulo','avulsa','realizada',180.00)
    returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,eva,(mp + 14 + time '11:00') at time zone 'America/Sao_Paulo',
                       (mp + 14 + time '11:50') at time zone 'America/Sao_Paulo','avulsa','realizada',180.00)
    returning id into s2;

  -- ---------------------------------------------------------------- 26
  -- Era o furo deixado escrito na 0034: aqui, antes da B23, saía um recibo de
  -- R$ 360 sem que ninguém tivesse dito que recebeu nada.
  begin
    doc := public.emitir_documento(eva, 'recibo', mp, fim_mp);
    raise exception '26 FUROU: emitiu recibo de avulso sem pagamento registrado — o documento assina que entrou dinheiro que pode não ter entrado';
  exception when others then
    if position('não há pagamento registrado' in sqlerrm) = 0 then raise; end if;
  end;

  -- ---------------------------------------------------------------- 28
  -- A declaração fala de presença, não de dinheiro. Continua saindo.
  doc := public.emitir_documento(eva, 'declaracao_comparecimento', mp, fim_mp);
  select * into r from public.documentos where id=doc;
  if r.quantidade <> 2 or r.valor_total <> 0 then
    raise exception '28 FUROU: a declaração saiu errada (% sessões, R$ %)', r.quantidade, r.valor_total; end if;
  if r.retrato->>'base' <> 'sessoes' then
    raise exception '28 FUROU: a declaração deixou de sair das sessões'; end if;
  select x into item from jsonb_array_elements(r.retrato->'itens') x limit 1;
  if item ? 'valor' then
    raise exception '28 FUROU: a declaração de comparecimento trouxe valor — informação que ninguém pediu'; end if;

  -- ---------------------------------------------------------------- 27
  perform public.registrar_recebimento(s1, mp + 7);
  perform public.registrar_recebimento(s2, mp + 14);

  doc := public.emitir_documento(eva, 'recibo', mp, fim_mp);
  select * into r from public.documentos where id=doc;
  if r.valor_total <> 360.00 then
    raise exception '27 FUROU: o recibo somou % em vez de 360', r.valor_total; end if;
  if r.quantidade <> 2 then raise exception '27 FUROU: contou % linhas', r.quantidade; end if;
  if r.retrato->>'base' <> 'cobrancas_por_sessao' then
    raise exception '27 FUROU: a base do recibo é % — quem ler daqui a dois anos não sabe de onde saiu o número', r.retrato->>'base'; end if;
  select x into item from jsonb_array_elements(r.retrato->'itens') x limit 1;
  if not (item ? 'valor') or (item->>'valor')::numeric <> 180.00 then
    raise exception '27 FUROU: o recibo do avulso perdeu o valor por linha — é ele que o convênio pede (%)', item; end if;

  -- ---------------------------------------------------------------- 29
  -- Regressão da B20: no mensalista o total é do combinado do mês, e as linhas
  -- saem sem valor para as duas contas não se contradizerem no mesmo papel.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,bia,(select id from public.enquadres where paciente_id=bia and vigencia_fim is null),
            (mp + 12 + time '16:00') at time zone 'America/Sao_Paulo',
            (mp + 12 + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00);

  insert into public.cobrancas (conta_id,paciente_id,enquadre_id,tipo,motivo,valor,competencia)
    values (a_conta, bia, (select id from public.enquadres where paciente_id=bia and vigencia_fim is null),
            'mensalidade','mensalidade',750.00, mp);

  begin
    doc := public.emitir_documento(bia, 'recibo', mp, fim_mp);
    raise exception '29 FUROU: emitiu recibo de mensalidade com a cobrança ainda aberta';
  exception when others then
    if position('não há pagamento registrado' in sqlerrm) = 0 then raise; end if;
  end;

  perform public.marcar_cobranca_paga(
    (select id from public.cobrancas where paciente_id=bia and tipo='mensalidade' and competencia=mp));

  doc := public.emitir_documento(bia, 'recibo', mp, fim_mp);
  select * into r from public.documentos where id=doc;
  if r.valor_total <> 750.00 then
    raise exception '29 FUROU: o recibo do mensalista somou % (a soma das sessões seria 400)', r.valor_total; end if;
  if r.retrato->>'base' <> 'cobrancas_pagas' then
    raise exception '29 FUROU: base errada no recibo do mensalista (%)', r.retrato->>'base'; end if;
  select x into item from jsonb_array_elements(r.retrato->'itens') x limit 1;
  if item ? 'valor' then
    raise exception '29 FUROU: o recibo do mensalista voltou a trazer valor por linha'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 4 · o recibo simétrico: ok';
end $do$;

-- ================================ parte 5 · isolamento e o visitante

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; b_conta uuid; b_prof uuid;
  s_ana uuid; n int; f jsonb; falhou boolean;
  m0 date; mp date; fim_mp date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  m0 := date_trunc('month', public.hoje_sp())::date;
  mp := (m0 - interval '1 month')::date;
  fim_mp := (m0 - interval '1 day')::date;

  select id into s_ana from public.sessoes
   where conta_id=a_conta and estado='realizada' order by inicio limit 1;

  delete from public.despesas where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 30
  select count(*) into n from public.despesas;
  if n <> 0 then raise exception '30 FUROU: a conta B enxerga % despesas da conta A', n; end if;

  falhou := false;
  begin
    insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
      values (a_conta, mp + 5, 'aluguel', 'Sala alheia', 900.00);
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '30 FUROU: a conta B lançou despesa na conta A'; end if;

  falhou := false;
  begin
    perform public.registrar_recebimento(s_ana);
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '30 FUROU: a conta B registrou recebimento numa sessão da conta A'; end if;

  f := public.financeiro_do_mes(mp, fim_mp);
  if (f->'realizado'->>'valor')::numeric <> 0 or (f->'recebido'->>'valor')::numeric <> 0
     or (f->'despesas'->>'valor')::numeric <> 0 then
    raise exception '30 FUROU: o painel da conta B contou dinheiro da conta A (%)', f; end if;

  select count(*) into n from public.sessoes_sem_registro(mp, fim_mp);
  if n <> 0 then raise exception '30 FUROU: a conta B lista sessões da conta A como sem registro (%)', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 31
  execute 'set local role anon';

  falhou := false;
  begin perform public.financeiro_do_mes(mp, fim_mp);
  exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executou financeiro_do_mes'; end if;

  falhou := false;
  begin perform public.registrar_recebimento(s_ana);
  exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executou registrar_recebimento'; end if;

  falhou := false;
  begin perform public.desfazer_recebimento(s_ana);
  exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executou desfazer_recebimento'; end if;

  falhou := false;
  begin perform * from public.sessoes_sem_registro(mp, fim_mp);
  exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executou sessoes_sem_registro'; end if;

  select count(*) into n from public.despesas;
  if n <> 0 then raise exception '31 FUROU: o anônimo lê despesas'; end if;

  reset role;
  raise notice 'parte 5 · isolamento e visitante: ok';
end $do$;

do $do$ begin raise notice '0037 · financeiro: todas as verificações passaram'; end $do$;
