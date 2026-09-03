-- Teste da remarcação guiada (critério de pronto da B21).
--
-- Metade das verificações é sobre o que o sistema **não** oferece. É onde este
-- build erra se errar: uma opção a mais parece generosidade e é uma armadilha —
-- ela atravessa a cidade para atender uma pessoa, ou descobre pela cobrança que
-- remarcar em cima da hora custava dinheiro.
--
--   1. acha opções, e no máximo três
--   2. o buraco vem antes do adjacente
--   3. dia sem nenhuma outra sessão viva nunca é oferecido, mesmo com buraco
--   4. uma opção por dia
--   5. hora ocupada nunca entra
--   6. a própria hora da sessão nunca entra
--   7. nada com menos de 12h nem além de 21 dias
--   8. férias e bloqueios nunca entram
--   9. uma remarcação viva por sessão; reabrir cancela a anterior
--  10. o cliente não escolhe token, nem opções, nem validade
--  11. o link mostra o mínimo, e anon não lê a tabela
--  12. escolher uma hora que nunca foi oferecida é recusado
--  13. a troca cria a sessão nova com origem `remarcada` e o mesmo retrato
--  14. a hora antiga cai pela classificação de sempre — no prazo, não cobra
--  15. e vira vaga na fila, na mesma transação
--  16. escolher duas vezes não cria uma segunda hora
--  17. remarcar em cima da hora **continua cobrando** — e a origem é presencial
--  18. link vencido não remarca
--  19. a tela não cria sessão de origem `remarcada`
--  20. isolamento entre contas
--  21. o anônimo não abre, não lê opções, não remarca
--  22. o custo diz a verdade no avulso, no mensal, no pacote e na política 0%
--  23. regressão da B7: o motor de encaixe ainda cria a sessão da oferta
--  24. a policy de criação de sessão continua sem `remarcada`
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0035_remarcacao.sql

-- ================================= parte 1 · o que entra e o que não entra

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  maria uuid; caio uuid; bea uuid; dudu uuid;
  s_maria uuid; d0 date; n int; r record; dow int;
begin
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

  d0  := public.hoje_sp();
  dow := extract(dow from d0)::int;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000021','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000022','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Bea Lima','5511900000023','em_atendimento') returning id into bea;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Dudu Alves','5511900000024','em_atendimento') returning id into dudu;

  -- O enquadre fica na grade de HOJE, um dia que os testes nunca usam como
  -- opção: assim a fonte "grade" existe e não polui as asserções.
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,vigencia_inicio)
    values (maria,dow,'15:00',50,200.00,24,50,d0 - 30);

  -- A materialização acabou de encher a agenda. Limpo e ponho o cenário à mão,
  -- pelo mesmo caminho que a rotina usaria (a policy da 0006 só deixa o app
  -- criar encaixe e avulsa).
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.sessoes where conta_id=a_conta;

  -- a sessão que vai sair do lugar: daqui a 3 dias, 15h
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,(select id from public.enquadres where paciente_id=maria),
          ((d0+3) + time '15:00') at time zone 'America/Sao_Paulo',
          ((d0+3) + time '15:50') at time zone 'America/Sao_Paulo','recorrencia',200.00,24,50)
  returning id into s_maria;

  -- dia +5 é dia de trabalho (Caio às 10h) e tem um buraco às 14h
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,caio,((d0+5) + time '10:00') at time zone 'America/Sao_Paulo',
          ((d0+5) + time '10:50') at time zone 'America/Sao_Paulo','recorrencia',200.00,24,50);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,cancelada_em,cancelada_por,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,dudu,((d0+5) + time '14:00') at time zone 'America/Sao_Paulo',
          ((d0+5) + time '14:50') at time zone 'America/Sao_Paulo','recorrencia','cancelada_cedo',now(),'paciente',200.00,24,50);

  -- dia +7 é dia de trabalho sem buraco: só sobra o adjacente
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,bea,((d0+7) + time '09:00') at time zone 'America/Sao_Paulo',
          ((d0+7) + time '09:50') at time zone 'America/Sao_Paulo','recorrencia',200.00,24,50);

  -- dia +9 tem buraco e NENHUMA sessão viva: não pode virar opção
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,cancelada_em,cancelada_por,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,dudu,((d0+9) + time '11:00') at time zone 'America/Sao_Paulo',
          ((d0+9) + time '11:50') at time zone 'America/Sao_Paulo','recorrencia','cancelada_cedo',now(),'paciente',200.00,24,50);

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 1
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3);
  if n = 0 then raise exception '1 FUROU: não achou nenhuma opção'; end if;
  if n > 3 then raise exception '1 FUROU: % opções (o teto é três)', n; end if;

  -- ---------------------------------------------------------------- 2
  select * into r from public.opcoes_de_remarcacao(s_maria, 3) limit 1;
  if r.motivo <> 'buraco' then
    raise exception '2 FUROU: a primeira opção é % — o buraco tem de vir antes', r.motivo; end if;
  if (r.inicio at time zone 'America/Sao_Paulo')::date <> d0+5 then
    raise exception '2 FUROU: a primeira opção caiu em %', (r.inicio at time zone 'America/Sao_Paulo')::date; end if;
  if (r.inicio at time zone 'America/Sao_Paulo')::time <> time '14:00' then
    raise exception '2 FUROU: hora %', (r.inicio at time zone 'America/Sao_Paulo')::time; end if;

  -- ---------------------------------------------------------------- 3
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3)
   where (inicio at time zone 'America/Sao_Paulo')::date = d0+9;
  if n <> 0 then
    raise exception '3 FUROU: ofereceu o buraco de um dia sem nenhuma outra sessão — ela viria só para isso'; end if;

  -- ---------------------------------------------------------------- 4
  select count(*) into n from (
    select (inicio at time zone 'America/Sao_Paulo')::date as d
      from public.opcoes_de_remarcacao(s_maria, 3) group by 1 having count(*) > 1
  ) x;
  if n <> 0 then raise exception '4 FUROU: duas opções no mesmo dia'; end if;

  -- ---------------------------------------------------------------- 5
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3)
   where inicio = ((d0+5) + time '10:00') at time zone 'America/Sao_Paulo';
  if n <> 0 then raise exception '5 FUROU: ofereceu uma hora ocupada'; end if;

  -- ---------------------------------------------------------------- 6
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3)
   where inicio = (select inicio from public.sessoes where id=s_maria);
  if n <> 0 then raise exception '6 FUROU: ofereceu a própria hora da sessão'; end if;

  -- ---------------------------------------------------------------- 7
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3) where inicio < now() + interval '12 hours';
  if n <> 0 then raise exception '7 FUROU: ofereceu hora com menos de 12h de antecedência'; end if;
  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3) where inicio > now() + interval '21 days';
  if n <> 0 then raise exception '7 FUROU: ofereceu hora além do horizonte'; end if;

  -- ---------------------------------------------------------------- 8
  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.excecoes_agenda (conta_id,profissional_id,tipo,inicio,fim,motivo)
  values (a_conta,a_prof,'ferias',d0+5,d0+5,'teste');
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.opcoes_de_remarcacao(s_maria, 3)
   where (inicio at time zone 'America/Sao_Paulo')::date = d0+5;
  if n <> 0 then raise exception '8 FUROU: ofereceu uma hora dentro das férias'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.excecoes_agenda where conta_id=a_conta;

  raise notice 'parte 1 · o que entra e o que não entra: ok';
end $do$;

-- ===================================== parte 2 · o link, a escolha, a troca

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid;
  s_maria uuid; tok text; j jsonb; n int; d0 date; rid uuid;
  escolha timestamptz; nova uuid; s record; falhou boolean; lim timestamptz;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into maria from public.pacientes where conta_id=a_conta and nome='Maria Reis';
  select id into s_maria from public.sessoes where paciente_id=maria and estado='prevista';
  d0 := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 9
  tok := public.abrir_remarcacao(s_maria);
  if tok !~ '^[0-9a-f]{32}$' then raise exception '9 FUROU: token %', tok; end if;
  select count(*) into n from public.remarcacoes where sessao_id=s_maria and cancelada_em is null;
  if n <> 1 then raise exception '9 FUROU: % remarcações vivas', n; end if;

  -- Reabrir é o caso comum: ela reenvia porque a pessoa perdeu a mensagem.
  tok := public.abrir_remarcacao(s_maria);
  select count(*) into n from public.remarcacoes where sessao_id=s_maria and cancelada_em is null and escolhida_em is null;
  if n <> 1 then raise exception '9 FUROU: reabrir deixou % vivas', n; end if;

  falhou := false;
  begin
    insert into public.remarcacoes (sessao_id, conta_id, paciente_id, token, opcoes, expira_em)
    values (s_maria, a_conta, maria, 'deadbeefdeadbeefdeadbeefdeadbeef', '[]'::jsonb, now() + interval '10 years');
  exception when others then falhou := true; end;
  if not falhou then raise exception '9 FUROU: duas remarcações vivas na mesma sessão'; end if;

  -- ---------------------------------------------------------------- 10
  -- Um INSERT direto no PostgREST tentando plantar token, opções e validade.
  select id into rid from public.remarcacoes where sessao_id=s_maria and cancelada_em is null and escolhida_em is null;
  perform public.cancelar_remarcacao(rid);

  insert into public.remarcacoes (sessao_id, conta_id, paciente_id, token, opcoes, expira_em)
  values (s_maria, a_conta, maria, 'deadbeefdeadbeefdeadbeefdeadbeef',
          jsonb_build_array(jsonb_build_object('inicio', now() + interval '2 days',
                                               'fim', now() + interval '2 days 50 minutes',
                                               'motivo','forjado')),
          now() + interval '10 years');

  select r.token into tok from public.remarcacoes r
   where r.sessao_id=s_maria and r.cancelada_em is null and r.escolhida_em is null;
  if tok = 'deadbeefdeadbeefdeadbeefdeadbeef' then
    raise exception '10 FUROU: o cliente escolheu o token'; end if;
  select count(*) into n from public.remarcacoes r, jsonb_array_elements(r.opcoes) o
   where r.token=tok and o->>'motivo' = 'forjado';
  if n <> 0 then raise exception '10 FUROU: o cliente escreveu as opções'; end if;
  select expira_em into lim from public.remarcacoes where token=tok;
  if lim > now() + interval '3 days' then
    raise exception '10 FUROU: o cliente esticou a validade do link'; end if;

  -- ---------------------------------------------------------------- 11
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  j := public.remarcacao_por_token('00000000000000000000000000000000');
  if j->>'estado' <> 'inexistente' then raise exception '11 FUROU: token inexistente devolveu %', j; end if;
  j := public.remarcacao_por_token('nao-e-token');
  if j->>'estado' <> 'inexistente' then raise exception '11 FUROU: token malformado devolveu %', j; end if;

  j := public.remarcacao_por_token(tok);
  if j->>'estado' <> 'aberta' then raise exception '11 FUROU: estado %', j->>'estado'; end if;
  if j->>'nome' <> 'Maria' then raise exception '11 FUROU: o link mostra %', j->>'nome'; end if;
  if j ? 'telefone' or j ? 'paciente_id' or j ? 'conta_id' or j ? 'valor' then
    raise exception '11 FUROU: o link vaza cadastro: %', j; end if;
  if jsonb_array_length(j->'opcoes') = 0 then raise exception '11 FUROU: o link veio sem opções'; end if;

  select count(*) into n from public.remarcacoes;
  if n <> 0 then raise exception '11 FUROU: anon lê % remarcações direto na tabela', n; end if;

  -- ---------------------------------------------------------------- 12
  j := public.escolher_remarcacao(tok, ((d0+2) + time '03:00') at time zone 'America/Sao_Paulo');
  if (j->>'ok')::boolean is not false or j->>'motivo' <> 'nao_oferecida' then
    raise exception '12 FUROU: marcou uma hora que o sistema nunca ofereceu: %', j; end if;

  -- ---------------------------------------------------------------- 13
  select ((j2->>'inicio')::timestamptz) into escolha
    from public.remarcacao_por_token(tok) t, jsonb_array_elements(t->'opcoes') j2
   where (j2->>'livre')::boolean limit 1;
  if escolha is null then raise exception '13 FUROU: nenhuma opção livre'; end if;

  j := public.escolher_remarcacao(tok, escolha);
  if (j->>'ok')::boolean is not true then raise exception '13 FUROU: não conseguiu remarcar: %', j; end if;
  nova := (j->>'sessao')::uuid;

  -- ---------------------------------------------------------------- 16
  j := public.escolher_remarcacao(tok, escolha);
  if j->>'motivo' <> 'ja_escolhida' then raise exception '16 FUROU: escolheu duas vezes: %', j; end if;
  j := public.remarcacao_por_token(tok);
  if j->>'estado' <> 'escolhida' then raise exception '16 FUROU: estado %', j->>'estado'; end if;

  reset role; perform set_config('request.jwt.claims','',true);

  select * into s from public.sessoes where id=nova;
  if s.origem <> 'remarcada' then raise exception '13 FUROU: origem %', s.origem; end if;
  if s.estado <> 'prevista' then raise exception '13 FUROU: estado %', s.estado; end if;
  if s.inicio <> escolha then raise exception '13 FUROU: hora errada'; end if;
  if s.valor <> 200.00 or s.politica_horas <> 24 or s.politica_percentual <> 50 then
    raise exception '13 FUROU: o retrato do combinado não veio junto'; end if;
  if s.enquadre_id is null then raise exception '13 FUROU: perdeu o combinado'; end if;

  -- ---------------------------------------------------------------- 14
  select * into s from public.sessoes where id=s_maria;
  if s.estado <> 'cancelada_cedo' then
    raise exception '14 FUROU: a hora antiga ficou % (esperado cancelada_cedo)', s.estado; end if;
  select count(*) into n from public.cobrancas where sessao_id=s_maria;
  if n <> 0 then raise exception '14 FUROU: cobrou uma remarcação feita dentro do prazo'; end if;

  -- ---------------------------------------------------------------- 15
  select count(*) into n from public.eventos_fila where sessao_id=s_maria and tipo='vaga_aberta';
  if n <> 1 then raise exception '15 FUROU: a hora que vagou não virou vaga na fila (%)', n; end if;

  select count(*) into n from public.sessoes where paciente_id=maria and origem='remarcada';
  if n <> 1 then raise exception '16 FUROU: % sessões remarcadas', n; end if;

  raise notice 'parte 2 · o link, a escolha, a troca: ok';
end $do$;

-- ============================= parte 3 · a política, o vencimento, as bordas

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  tarde uuid; s_tarde uuid; j jsonb; n int;
  escolha timestamptz; s record; falhou boolean; tok text;
  maria uuid; s_viva uuid;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into maria from public.pacientes where conta_id=a_conta and nome='Maria Reis';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Tarde Silva','5511900000025','em_atendimento') returning id into tarde;

  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,tarde, now()+interval '3 hours', now()+interval '3 hours 50 minutes','recorrencia',200.00,24,50)
  returning id into s_tarde;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 17
  j := public.custo_da_remarcacao(s_tarde);
  if (j->>'tardia')::boolean is not true then raise exception '17 FUROU: não viu que é tardia: %', j; end if;
  if (j->>'valor')::numeric <> 100.00 then raise exception '17 FUROU: valor % (esperado 100)', j->>'valor'; end if;

  select o.inicio into escolha from public.opcoes_de_remarcacao(s_tarde, 3) o limit 1;
  if escolha is null then raise exception '17 FUROU: sem opções para a sessão tardia'; end if;

  j := public.remarcar_presencial(s_tarde, escolha);
  if (j->>'ok')::boolean is not true then raise exception '17 FUROU: não remarcou: %', j; end if;

  select * into s from public.sessoes where id=s_tarde;
  if s.estado <> 'cancelada_tarde' then
    raise exception '17 FUROU: a hora antiga ficou % — remarcar virou atalho para fugir da política', s.estado; end if;
  -- **P4 (0058):** o que esta verificação sempre disse é que **remarcar não é
  -- atalho para fugir da política** — e isso continua inteiro. O que mudou é
  -- onde a política chega: ela chega como pergunta, e a cobrança nasce da
  -- decisão. As duas metades ficam provadas.
  select count(*) into n from public.propostas_de_cobranca
   where sessao_id=s_tarde and estado='pendente';
  if n <> 1 then raise exception '17 FUROU: a remarcação tardia escapou da política (%)', n; end if;

  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.sessao_id = s_tarde and p.estado = 'pendente';

  select count(*) into n from public.cobrancas where sessao_id=s_tarde and estado='aberta';
  if n <> 1 then raise exception '17 FUROU: a decisão de cobrar não gerou cobrança (%)', n; end if;
  if (select valor from public.cobrancas where sessao_id=s_tarde and estado='aberta') <> 100.00 then
    raise exception '17 FUROU: valor da cobrança errado'; end if;
  if (select origem from public.remarcacoes where sessao_id=s_tarde) <> 'presencial' then
    raise exception '17 FUROU: a origem da remarcação feita por ela não é presencial'; end if;

  -- ---------------------------------------------------------------- 18
  select id into s_viva from public.sessoes
   where paciente_id=maria and estado='prevista' and origem='remarcada';
  tok := public.abrir_remarcacao(s_viva);

  reset role; perform set_config('request.jwt.claims','',true);
  update public.remarcacoes set expira_em = now() - interval '1 hour' where token=tok;

  execute 'set local role anon';
  j := public.remarcacao_por_token(tok);
  if j->>'estado' <> 'expirada' then raise exception '18 FUROU: o link vencido não se declara vencido: %', j->>'estado'; end if;
  j := public.escolher_remarcacao(tok, now() + interval '5 days');
  if (j->>'ok')::boolean is not false or j->>'motivo' <> 'expirada' then
    raise exception '18 FUROU: remarcou por link vencido: %', j; end if;

  -- ---------------------------------------------------------------- 19
  reset role; perform set_config('request.jwt.claims','',true);
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  falhou := false;
  begin
    insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
    values (a_conta,a_prof,tarde, now()+interval '30 days', now()+interval '30 days 50 minutes','remarcada',200.00,24,50);
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '19 FUROU: a tela criou uma sessão de origem remarcada — só o motor da remarcação pode'; end if;

  -- ---------------------------------------------------------------- 20
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.remarcacoes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bruna Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bruna Solo';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.remarcacoes;
  if n <> 0 then raise exception '20 FUROU: a Bruna vê % remarcações da Ana', n; end if;
  select count(*) into n from public.opcoes_de_remarcacao(s_viva, 3);
  if n <> 0 then raise exception '20 FUROU: a Bruna leu a agenda da Ana (% opções)', n; end if;

  falhou := false;
  begin perform public.abrir_remarcacao(s_viva);
  exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: a Bruna abriu remarcação numa sessão da Ana'; end if;

  falhou := false;
  begin perform public.remarcar_presencial(s_viva, now() + interval '5 days');
  exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: a Bruna remarcou uma sessão da Ana'; end if;

  -- ---------------------------------------------------------------- 21
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.remarcacoes;
  if n <> 0 then raise exception '21 FUROU: anon leu remarcações'; end if;

  falhou := false;
  begin perform public.abrir_remarcacao(s_viva);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '21 FUROU: anon abriu remarcação'; end if;

  falhou := false;
  begin perform public.opcoes_de_remarcacao(s_viva, 3);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '21 FUROU: anon leu opções da agenda alheia'; end if;

  falhou := false;
  begin perform public.custo_da_remarcacao(s_viva);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '21 FUROU: anon leu o custo'; end if;

  falhou := false;
  begin perform public.remarcar_presencial(s_viva, now() + interval '5 days');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '21 FUROU: anon remarcou'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · a política, o vencimento, as bordas: ok';
end $do$;

-- ================================ parte 4 · o custo nos modelos e a B7

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  men uuid; pac uuid; zero uuid; fulano uuid;
  e_men uuid; e_pac uuid;
  s_men uuid; s_pac uuid; s_zero uuid;
  j jsonb; n int; ofe uuid; r text; qual text;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into b_conta from public.contas where nome='Bruna Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Men Salista','5511900000031','em_atendimento') returning id into men;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Pac Ote','5511900000032','em_atendimento') returning id into pac;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Zero Politica','5511900000033','em_atendimento') returning id into zero;

  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,mensalidade_valor,politica_horas,politica_percentual)
    values (men,1,'07:00',50,200.00,'mensal',800.00,24,50) returning id into e_men;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,modelo_cobranca,politica_horas,politica_percentual)
    values (pac,1,'07:00',50,250.00,'pacote',24,50) returning id into e_pac;

  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,men,e_men, now()+interval '4 hours', now()+interval '4 hours 50 minutes','recorrencia',200.00,24,50)
  returning id into s_men;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,enquadre_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,pac,e_pac, now()+interval '6 hours', now()+interval '6 hours 50 minutes','recorrencia',250.00,24,50)
  returning id into s_pac;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,zero, now()+interval '8 hours', now()+interval '8 hours 50 minutes','recorrencia',200.00,24,0)
  returning id into s_zero;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 22
  j := public.custo_da_remarcacao(s_men);
  if (j->>'tardia')::boolean is not true then raise exception '22 FUROU: mensal não viu que é tardia'; end if;
  if (j->>'valor')::numeric <> 0 then raise exception '22 FUROU: mensal cobrou % por cima da mensalidade', j->>'valor'; end if;
  if position('mensalidade' in (j->>'texto')) = 0 then raise exception '22 FUROU: o texto do mensal não explica: %', j->>'texto'; end if;

  j := public.custo_da_remarcacao(s_pac);
  if (j->>'valor')::numeric <> 0 then raise exception '22 FUROU: pacote gerou cobrança em dinheiro'; end if;
  if position('crédito' in (j->>'texto')) = 0 then raise exception '22 FUROU: o texto do pacote não fala do crédito: %', j->>'texto'; end if;

  j := public.custo_da_remarcacao(s_zero);
  if (j->>'valor')::numeric <> 0 then raise exception '22 FUROU: política de 0%% cobrou %', j->>'valor'; end if;

  -- A hora que está **dentro** do prazo, criada aqui de propósito.
  --
  -- Antes esta linha pegava `origem='remarcada'` com `limit 1`, e isso era um
  -- teste instável por dois motivos: sem `order by`, qualquer linha servia; e a
  -- sessão remarcada da parte 2 nasce de uma opção que o gerador só garante
  -- estar a **12 horas** de distância — ou seja, ela pode legitimamente cair
  -- dentro de uma política de 24h e ser tardia de verdade.
  --
  -- O teste passava ou falhava conforme a hora do dia em que rodasse, que é a
  -- pior espécie de teste: o que reprova código correto de vez em quando.
  reset role; perform set_config('request.jwt.claims','',true);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,zero, now()+interval '3 days', now()+interval '3 days 50 minutes','remarcada',200.00,24,50)
  returning id into fulano;
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  j := public.custo_da_remarcacao(fulano);
  if (j->>'tardia')::boolean is not false then raise exception '22 FUROU: chamou de tardia o que está a três dias, com política de 24h: %', j; end if;

  -- ---------------------------------------------------------------- 23
  -- Regressão da B7: a policy de sessões foi reescrita nesta migração. O motor
  -- de encaixe ainda tem de conseguir criar a sessão que nasce de uma oferta.
  insert into public.fila_encaixe (conta_id, paciente_id, ativo, janelas)
    values (a_conta, zero, true, '[]'::jsonb);

  perform public.cancelar_sessao(s_pac, 'paciente');
  select public.abrir_vaga(s_pac) into ofe;
  if ofe is null then raise exception '23 FUROU: a fila não ofereceu a vaga a ninguém'; end if;

  select public.responder_oferta(ofe, 'aceita') into r;
  if r <> 'aceita' then raise exception '23 FUROU: responder_oferta devolveu %', r; end if;

  select count(*) into n from public.sessoes
   where paciente_id=zero and origem='encaixe' and inicio=(select inicio from public.sessoes where id=s_pac);
  if n <> 1 then raise exception '23 FUROU: o encaixe não criou a sessão (%)', n; end if;

  -- ---------------------------------------------------------------- 24
  reset role; perform set_config('request.jwt.claims','',true);
  select with_check into qual from pg_policies
   where schemaname='public' and tablename='sessoes' and cmd='INSERT';
  if position('encaixe' in qual) = 0 or position('avulsa' in qual) = 0 then
    raise exception '24 FUROU: a policy de criação de sessão perdeu encaixe/avulsa: %', qual; end if;
  if position('remarcada' in qual) > 0 then
    raise exception '24 FUROU: a policy passou a deixar o cliente criar remarcada: %', qual; end if;

  -- ------------------------------------------------------------------- fim
  -- A 0035 não recolhia o rastro: 'Ana Solo' e 'Bruna Solo' ficavam de pé
  -- depois dela, e é a mesma raiz da 'Bia Solo' órfã que apareceu no banco. A
  -- conta antes de `auth.users`: `pacientes.profissional_id` e `registros.*`
  -- são RESTRICT de propósito.
  delete from public.remarcacoes    where conta_id in (a_conta, b_conta);
  delete from public.propostas_de_cobranca where conta_id in (a_conta, b_conta);
  delete from public.cobrancas      where conta_id in (a_conta, b_conta);
  delete from public.mensagens      where conta_id in (a_conta, b_conta);
  delete from public.eventos_fila   where conta_id in (a_conta, b_conta);
  delete from public.ofertas        where conta_id in (a_conta, b_conta);
  delete from public.fila_encaixe   where conta_id in (a_conta, b_conta);
  delete from public.sessoes        where conta_id in (a_conta, b_conta);
  delete from public.enquadres      where conta_id in (a_conta, b_conta);
  delete from public.pacientes      where conta_id in (a_conta, b_conta);
  delete from public.contas         where id in (a_conta, b_conta);
  delete from auth.users            where id in (a_auth, b_auth);

  raise notice 'parte 4 · o custo nos modelos e a B7: ok';
  raise notice '0035 · 24 verificações passaram.';
end $do$;
