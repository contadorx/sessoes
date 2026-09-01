-- Teste da falta como dado clínico (critério de pronto da B27).
--
-- A verificação nº 9 é a que decide o build, e ela não olha um número: ela olha
-- **as chaves da resposta** e falha se alguma se parecer com juízo. `risco`,
-- `escore`, `alerta`, `abandono`, `padrao`, `atencao` — qualquer uma delas
-- significa que o software passou a interpretar, e o doc 07 põe isso entre as
-- linhas que não se atravessam. É a mesma técnica do teste que proíbe coluna de
-- dinheiro em fila e do que proíbe função de emitir na Receita: a fronteira
-- guardada por teste, não por lembrança.
--
--   1. a nota entra na falta
--   2. ...e no cancelamento, cedo e tarde
--   3. sessão realizada RECUSA nota — prontuário é fase 3
--   4. corrigir o desfecho depois NÃO apaga o que ela escreveu
--   5. o carimbo é do servidor: um `nota_em` forjado não cola
--   6. apagar a nota apaga o carimbo junto
--   7. a nota carimba a trilha de acesso
--   8. a linha do tempo junta desfecho, nota, dinheiro e origem
--   9. a aritmética não tem juízo nenhum — nem chave nem valor
--  10. as contagens batem, e previstas não entram
--  11. a cadeia corrente para na primeira realizada
--  12. sessão importada CONTA presença (e continua sem contar dinheiro)
--  13. os oito últimos saem do mais antigo para o mais recente
--  14. sem sessão nenhuma, a resposta é zero — e não erro
--  15. a nota sobrevive ao "esquecer contato" (guarda de 5 anos)
--  16. a nota sai na exportação do paciente e na da conta
--  17. a nota NÃO sai na pasta do contador
--  18. anotar sessão que não existe estoura em vez de não fazer nada
--  19. isolamento entre contas
--  20. o anônimo não lê nem executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0041_linha_do_tempo.sql

-- ==================== parte 1 · a nota tem lugar, e o carimbo é do servidor

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid;
  s_falta uuid; s_cedo uuid; s_tarde uuid; s_feita uuid;
  d date; r record; n int; falhou boolean; antes timestamptz;
begin
  delete from public.espelhos_calendario where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ocupacoes_externas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.calendarios where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pastas_contador where conta_id in (select id from public.contas where nome='Ana Solo');
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
  d := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,email,estado)
    values (a_prof,'Maria Fernanda Reis','5511987650001','maria@exemplo.com','em_atendimento')
    returning id into pac;

  -- Quatro horas no passado, uma de cada desfecho.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d - 28 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 28 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_feita;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d - 21 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 21 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','falta',200.00)
    returning id into s_falta;
  -- Cancelada exige o carimbo de quem e quando (check da 0010): o estado e o
  -- registro do cancelamento são a mesma coisa, e não se separam nem no teste.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,cancelada_em,cancelada_por)
    values (a_conta,a_prof,pac,(d - 14 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 14 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','cancelada_cedo',200.00,
            now() - interval '14 days', 'paciente')
    returning id into s_cedo;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,cancelada_em,cancelada_por)
    values (a_conta,a_prof,pac,(d - 7 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 7 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','cancelada_tarde',200.00,
            now() - interval '7 days', 'paciente')
    returning id into s_tarde;

  -- ---------------------------------------------------------------- 1
  perform public.anotar_ausencia(s_falta, 'Não avisou. Terceira do semestre.');
  select * into r from public.sessoes where id=s_falta;
  if r.nota is null then raise exception '1 FUROU: a nota não gravou'; end if;
  if r.nota_em is null then raise exception '1 FUROU: gravou sem carimbo'; end if;

  -- ---------------------------------------------------------------- 2
  perform public.anotar_ausencia(s_cedo, 'Avisou na véspera, viagem de trabalho.');
  perform public.anotar_ausencia(s_tarde, 'Ligou uma hora antes.');
  if (select count(*) from public.sessoes where paciente_id=pac and nota is not null) <> 3 then
    raise exception '2 FUROU: cancelamento não aceitou nota'; end if;

  -- ---------------------------------------------------------------- 3
  falhou := false;
  begin
    perform public.anotar_ausencia(s_feita, 'Trabalhamos a relação com a mãe.');
  exception when others then
    falhou := true;
    -- A B28 trocou a mensagem: ela deixou de só proibir e passou a encaminhar
    -- ("o que se escreve nela é a evolução"). A regra é a mesma; o teste segue
    -- a palavra que importa.
    if position('evolução' in sqlerrm) = 0 then
      raise exception '3 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then
    raise exception '3 FUROU: o prontuário começou de lado, por uma caixa de texto'; end if;

  -- ...e nem por PATCH direto no PostgREST.
  falhou := false;
  begin
    update public.sessoes set nota='pelo lado de fora' where id=s_feita;
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '3 FUROU: a regra vale na função e não na tabela'; end if;

  -- ---------------------------------------------------------------- 4
  -- Marcou falta, era engano: a pessoa veio. A nota que ela escreveu FICA.
  antes := (select nota_em from public.sessoes where id=s_falta);
  update public.sessoes set estado='realizada' where id=s_falta;
  select * into r from public.sessoes where id=s_falta;
  if r.nota is null then
    raise exception '4 FUROU: corrigir o desfecho apagou o que ela escreveu'; end if;
  if r.nota_em is distinct from antes then
    raise exception '4 FUROU: o carimbo mudou sem a nota mudar'; end if;
  update public.sessoes set estado='falta' where id=s_falta;

  -- ---------------------------------------------------------------- 5
  update public.sessoes
     set nota='outra coisa', nota_em = timestamptz '2020-01-01 10:00-03'
   where id=s_falta;
  select nota_em into antes from public.sessoes where id=s_falta;
  if antes < now() - interval '1 hour' then
    raise exception '5 FUROU: um carimbo forjado colou (%)', antes; end if;

  -- ---------------------------------------------------------------- 6
  perform public.anotar_ausencia(s_tarde, '   ');
  select * into r from public.sessoes where id=s_tarde;
  if r.nota is not null then raise exception '6 FUROU: nota em branco não apagou'; end if;
  if r.nota_em is not null then raise exception '6 FUROU: sobrou carimbo sem nota'; end if;

  -- ---------------------------------------------------------------- 7
  select count(*) into n from public.trilha_acesso
   where paciente_id=pac and acao='anotou_ausencia';
  if n < 4 then raise exception '7 FUROU: a trilha registrou só % anotações', n; end if;

  -- ---------------------------------------------------------------- 18
  falhou := false;
  begin
    perform public.anotar_ausencia(gen_random_uuid(), 'sessão que não existe');
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '18 FUROU: anotar o nada não fez nada e não reclamou'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · a nota tem lugar: ok';
end $do$;

-- ==================== parte 2 · a linha do tempo e a aritmética sem juízo

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; vazio uuid;
  s_imp uuid; d date; j jsonb; r record; n int; chave text;
  suspeitas text[] := array['risco','escore','score','alerta','abandono','padrao','padrão',
                            'atencao','atenção','grave','preocup','sinal','flag','nota_clinica'];
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into pac from public.pacientes where conta_id=a_conta limit 1;
  d := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- Uma prevista no futuro: ela NÃO pode entrar em contagem nenhuma.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d + 7 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d + 7 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00);

  -- ---------------------------------------------------------------- 12
  -- Duas sessões de outro sistema, bem antigas.
  select (public.importar_historico(jsonb_build_array(
     jsonb_build_object('paciente_id', pac,
       'inicio', (d - 400 + time '15:00') at time zone 'America/Sao_Paulo',
       'estado','realizada','valor',180.00),
     jsonb_build_object('paciente_id', pac,
       'inicio', (d - 393 + time '15:00') at time zone 'America/Sao_Paulo',
       'estado','falta','valor',180.00)
  ))->>'importadas')::int into n;
  if n <> 2 then raise exception '12 PREPARO: importou % linhas', n; end if;

  -- ---------------------------------------------------------------- 8
  select count(*) into n from public.linha_do_tempo(pac);
  if n <> 7 then raise exception '8 FUROU: a linha do tempo trouxe % linhas (esperado 7)', n; end if;

  select * into r from public.linha_do_tempo(pac) where sessao_id in
    (select id from public.sessoes where paciente_id=pac and estado='falta' and origem='avulsa');
  if r.nota is null then raise exception '8 FUROU: a nota não veio na linha do tempo'; end if;
  if r.origem <> 'avulsa' then raise exception '8 FUROU: a origem não veio'; end if;

  -- A cobrança da hora cancelada tarde é gerada pelo gatilho da B11 e tem de
  -- aparecer aqui: dinheiro e desfecho na mesma linha é o ponto da tela.
  if not exists (select 1 from public.linha_do_tempo(pac) where cobranca_estado is not null) then
    raise exception '8 FUROU: nenhuma linha trouxe o estado do dinheiro'; end if;

  -- A mais recente vem primeiro.
  select dia into d from public.linha_do_tempo(pac) limit 1;
  if d <> (select max((inicio at time zone 'America/Sao_Paulo')::date)
             from public.sessoes where paciente_id=pac) then
    raise exception '8 FUROU: a linha do tempo não veio da mais recente para a mais antiga'; end if;

  j := public.ausencias_do_paciente(pac);

  -- ---------------------------------------------------------------- 9
  -- A verificação que decide o build: nenhuma chave e nenhum valor de texto
  -- pode parecer juízo. O sistema conta; quem lê é ela.
  foreach chave in array suspeitas loop
    if exists (select 1 from jsonb_object_keys(j) k where lower(k) like '%' || chave || '%') then
      raise exception '9 FUROU: existe um campo de juízo clínico na saída (%) — doc 07', chave;
    end if;
  end loop;

  for chave in select k from jsonb_object_keys(j) k loop
    if jsonb_typeof(j->chave) = 'string'
       and (j->>chave) !~ '^\d{4}-\d{2}-\d{2}$'
       and (j->>chave) not in ('realizada','falta','cancelada_cedo','cancelada_tarde') then
      raise exception '9 FUROU: o campo % devolve texto livre ("%") — aritmética não tem adjetivo',
        chave, j->>chave;
    end if;
  end loop;

  -- ---------------------------------------------------------------- 10
  -- 4 avulsas com desfecho + 2 importadas = 6. A prevista fica de fora.
  if (j->>'sessoes')::int <> 6 then
    raise exception '10 FUROU: contou % sessões (a prevista entrou?)', j->>'sessoes'; end if;
  if (j->>'realizadas')::int <> 2 then
    raise exception '10 FUROU: % realizadas', j->>'realizadas'; end if;
  if (j->>'faltas')::int <> 2 then
    raise exception '10 FUROU: % faltas', j->>'faltas'; end if;
  if (j->>'cancelou_cedo')::int <> 1 or (j->>'cancelou_tarde')::int <> 1 then
    raise exception '10 FUROU: cancelamentos % / %', j->>'cancelou_cedo', j->>'cancelou_tarde'; end if;
  if (j->>'ausencias')::int <> 4 then
    raise exception '10 FUROU: % ausências (esperado 4)', j->>'ausencias'; end if;
  if (j->>'com_nota')::int <> 2 then
    raise exception '10 FUROU: % com nota', j->>'com_nota'; end if;

  -- ---------------------------------------------------------------- 11
  -- As três últimas com desfecho são falta, cancelada_cedo, cancelada_tarde —
  -- e antes delas há uma realizada. A cadeia corrente é 3.
  if (j->>'seguidas')::int <> 3 then
    raise exception '11 FUROU: cadeia corrente de % (esperado 3)', j->>'seguidas'; end if;

  -- ---------------------------------------------------------------- 12 (cont.)
  if (j->>'primeira')::date <> (public.hoje_sp() - 400) then
    raise exception '12 FUROU: a linha do tempo não começa no histórico importado (%)',
      j->>'primeira'; end if;
  -- ...e o dinheiro continua sem contá-las (a regra da B26 não foi afrouxada).
  if (public.financeiro_do_mes(public.hoje_sp() - 400, public.hoje_sp() - 390)
       ->'realizado'->>'valor')::numeric <> 0 then
    raise exception '12 FUROU: o importado voltou a contar dinheiro'; end if;

  -- ---------------------------------------------------------------- 13
  if jsonb_array_length(j->'ultimos') <> 6 then
    raise exception '13 FUROU: % desfechos na faixa', jsonb_array_length(j->'ultimos'); end if;
  if (j->'ultimos'->>0) <> 'realizada' then
    raise exception '13 FUROU: a faixa não começa pelo mais antigo (%)', j->'ultimos'; end if;
  if (j->'ultimos'->>5) <> 'cancelada_tarde' then
    raise exception '13 FUROU: a faixa não termina pelo mais recente (%)', j->'ultimos'; end if;

  -- ---------------------------------------------------------------- 14
  insert into public.pacientes (profissional_id,nome,estado)
    values (a_prof,'Ninguém Ainda','interessado') returning id into vazio;
  j := public.ausencias_do_paciente(vazio);
  if (j->>'sessoes')::int <> 0 or (j->>'seguidas')::int <> 0 then
    raise exception '14 FUROU: paciente sem sessão não deu zero (%)', j; end if;
  if j->>'dias_desde_a_ultima_realizada' is not null then
    raise exception '14 FUROU: inventou dias sem sessão nenhuma'; end if;
  if jsonb_array_length(j->'ultimos') <> 0 then
    raise exception '14 FUROU: faixa não vazia'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · a linha do tempo e a aritmética: ok';
end $do$;

-- ==================== parte 3 · para onde a nota vai, e para onde não vai

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; s_cedo uuid; cob uuid; pasta uuid;
  mes date; exp jsonb; r record; n int; doc uuid;
  marca text := 'Zebulon-nota-clinica-Kryzanowski';
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  select id into s_cedo from public.sessoes
   where paciente_id=pac and estado='cancelada_cedo' and origem='avulsa';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  perform public.anotar_ausencia(s_cedo, marca);

  -- ---------------------------------------------------------------- 15
  -- Esquecer contato apaga telefone e e-mail. NÃO apaga registro: a guarda da
  -- Res. CFP 001/2009 é de cinco anos, e o que ela escreveu é registro.
  perform public.esquecer_contato(pac);
  select * into r from public.pacientes where id=pac;
  if r.telefone is not null or r.email is not null then
    raise exception '15 PREPARO: o esquecer não esqueceu o contato'; end if;
  if (select nota from public.sessoes where id=s_cedo) is null then
    raise exception '15 FUROU: esquecer contato apagou registro clínico'; end if;

  -- ---------------------------------------------------------------- 16
  exp := public.exportar_paciente(pac);
  if position(marca in exp::text) = 0 then
    raise exception '16 FUROU: a nota não saiu na exportação do paciente — é direito dele'; end if;
  exp := public.exportar_conta();
  if position(marca in exp::text) = 0 then
    raise exception '16 FUROU: a nota não saiu na exportação da conta'; end if;

  -- ---------------------------------------------------------------- 17
  -- A pasta do contador não tem paciente desde a B25. Com uma nota clínica na
  -- base, o teste do "Zebulon" da B25 ganha um segundo motivo para existir.
  mes := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;
  update public.contas set contador_email='contador@exemplo.com' where id=a_conta;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(mes + 4 + time '11:00') at time zone 'America/Sao_Paulo',
                               (mes + 4 + time '11:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into cob;
  perform public.registrar_recebimento(cob, mes + 6);

  pasta := public.fechar_mes_do_contador(mes);
  select * into r from public.pastas_contador where id=pasta;
  if position(marca in r.retrato::text || r.csv) > 0 then
    raise exception '17 FUROU: nota clínica saiu na pasta do contador'; end if;
  if position('Zebulon' in r.retrato::text || r.csv) > 0 then
    raise exception '17 FUROU: parte da nota vazou para o contador'; end if;

  -- E também não sai em documento nenhum. Emite um recibo de verdade do mês
  -- que acabou de ser fechado — asserção vazia não vale como fronteira.
  doc := public.emitir_documento(pac, 'recibo', mes,
           (date_trunc('month', mes::timestamp) + interval '1 month - 1 day')::date);
  select * into r from public.documentos where id=doc;
  if not found then raise exception '17 PREPARO: o recibo não saiu'; end if;
  if position(marca in r.retrato::text) > 0 then
    raise exception '17 FUROU: a nota clínica entrou num recibo que vai ao convênio e ao IR'; end if;
  if position('Zebulon' in r.retrato::text) > 0 then
    raise exception '17 FUROU: parte da nota vazou para o recibo'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · para onde a nota vai: ok';
end $do$;

-- ==================== parte 4 · isolamento e o anônimo

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_pac uuid; a_sessao uuid; b_prof uuid; n int; falhou boolean; j jsonb;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  select id into a_sessao from public.sessoes where paciente_id=a_pac and nota is not null limit 1;

  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Outra';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Outra"}'::jsonb);
  select id into b_prof from public.profissionais
   where conta_id=(select conta_id from public.usuarios where auth_user_id=b_auth);

  -- ---------------------------------------------------------------- 19
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.linha_do_tempo(a_pac);
  if n <> 0 then raise exception '19 FUROU: a Bia leu % linhas da ficha da Ana', n; end if;

  j := public.ausencias_do_paciente(a_pac);
  if (j->>'sessoes')::int <> 0 or (j->>'com_nota')::int <> 0 then
    raise exception '19 FUROU: a aritmética vazou entre contas (%)', j; end if;

  falhou := false;
  begin
    perform public.anotar_ausencia(a_sessao, 'invadindo');
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '19 FUROU: a Bia escreveu na ficha clínica da Ana'; end if;
  if (select nota from public.sessoes where id=a_sessao) = 'invadindo' then
    raise exception '19 FUROU: a nota da Ana foi reescrita'; end if;

  -- ---------------------------------------------------------------- 20
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  falhou := false;
  begin perform public.linha_do_tempo(a_pac); exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: o anônimo executa linha_do_tempo'; end if;

  falhou := false;
  begin perform public.ausencias_do_paciente(a_pac); exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: o anônimo executa ausencias_do_paciente'; end if;

  falhou := false;
  begin perform public.anotar_ausencia(a_sessao, 'x'); exception when others then falhou := true; end;
  if not falhou then raise exception '20 FUROU: o anônimo anota'; end if;

  falhou := false;
  begin perform public.nota_so_na_ausencia(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '20 FUROU: o gatilho está publicado em /rest/v1/rpc'; end if;

  select count(*) into n from public.sessoes;
  if n <> 0 then raise exception '20 FUROU: o anônimo lê sessões'; end if;

  reset role;
  raise notice 'parte 4 · isolamento e o anônimo: ok';
end $do$;

-- ==================== parte 5 · a suíte limpa o que emitiu
--
-- A verificação 17 emite um **recibo de verdade** — e recibo emitido não se
-- edita nem se apaga pelo app (0029). Como `documentos.paciente_id` é
-- `on delete restrict`, deixar um para trás faz a suíte seguinte travar no
-- próprio preâmbulo, ao tentar apagar o paciente de teste: uma suíte verde
-- derrubando doze, e nenhuma delas com defeito.
--
-- Os preâmbulos de limpeza envelhecem — o da B5 foi escrito antes de existir
-- tabela de documentos, e não tem como saber dela. Quem cria o rastro é quem
-- tem de recolhê-lo.

do $do$
declare
  a_conta uuid;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  if a_conta is null then
    raise notice 'parte 5 · nada a limpar';
    return;
  end if;

  delete from public.documentos where conta_id = a_conta;
  delete from public.recibos_rfb where conta_id = a_conta;
  delete from public.pastas_contador where conta_id = a_conta;

  raise notice 'parte 5 · rastro recolhido: ok';
  raise notice '=== 0041 · a falta como dado clínico: 20 verificações, todas passaram ===';
end $do$;
