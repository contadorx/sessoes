-- Teste do registro que o CFP pede (critério de pronto da B28).
--
-- A verificação nº 12 é a que decide o build: uma evolução na camada
-- `documental` — a gaveta do Registro Documental, cujo acesso o Manual de
-- nov/2025 restringe à psicóloga — **não pode sair** na exportação que o
-- paciente pede. É o caminho por onde essa distinção vazaria sem ninguém
-- perceber, porque o arquivo sai correto em tudo o mais.
--
-- A nº 19 é a segunda mais importante e é nova no produto: a ficha de quem foi
-- atendido aos 9 anos **não** fica elegível para expurgo aos 14.
--
--   1. o registro nasce com os quatro blocos, e o bloco 1 não é duplicado
--   2. a modalidade é conteúdo mínimo, e só aceita os três valores
--   3. encerramento é data e tipo juntos, ou nenhum dos dois
--   4. um registro por paciente
--   5. a evolução entra na sessão realizada — a recusa da B27 foi levantada
--   6. ...e continua recusada na hora que não houve, com mensagem que encaminha
--   7. evolução em branco é recusada — o registro não guarda espaço vazio
--   8. evolução não se apaga: não existe política de DELETE
--   9. a evolução não muda de paciente nem de sessão
--  10. `editado_em` é do servidor; forjado não cola
--  11. uma evolução por sessão — reescrever atualiza, não duplica
--  12. A GAVETA NÃO SAI na exportação do paciente
--  13. ...e sai na exportação da conta, que é dela
--  14. a exportação do paciente diz o que não está nela
--  15. e continua marcada "cópia de documento sigiloso"
--  16. `sem_evolucao` diz quais horas ficaram sem registro (e ignora importadas)
--  17. apagar sessão com evolução é impossível
--  18. apagar paciente com registro é impossível
--  19. a guarda do menor conta da maioridade, não do último registro
--  20. ...e a maior das duas contas manda, com o motivo escrito
--  21. a nota da B27 e a evolução convivem na mesma pessoa
--  22. a trilha carimba a demanda e a evolução
--  23. isolamento entre contas
--  24. o anônimo não lê nem executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0042_registro_clinico.sql

-- ==================== parte 1 · o registro e a evolução

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid;
  s_feita uuid; s_falta uuid; s_outra uuid; ev uuid; reg uuid;
  d date; r record; n int; falhou boolean; antes timestamptz;
begin
  -- Evoluções e registros primeiro: as duas apontam para `pacientes` com
  -- `on delete restrict`, e é essa a razão de existirem aqui — apagar paciente
  -- com registro clínico é impossível, inclusive num preâmbulo de teste.
  delete from public.evolucoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.registros where conta_id in (select id from public.contas where nome='Ana Solo');
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

  insert into public.pacientes (profissional_id,nome,telefone,nascimento,estado)
    values (a_prof,'Maria Fernanda Reis','5511987650001', date '1990-04-12','em_atendimento')
    returning id into pac;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d - 21 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 21 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_feita;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d - 14 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 14 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_outra;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d - 7 + time '15:00') at time zone 'America/Sao_Paulo',
                               (d - 7 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','falta',200.00)
    returning id into s_falta;

  -- ---------------------------------------------------------------- 1
  reg := public.salvar_demanda(pac, 'Buscou por crises de ansiedade no trabalho.',
                               'Reduzir as crises; retomar o sono.', 'semanal', 'presencial');
  if reg is null then raise exception '1 FUROU: o registro não abriu'; end if;

  -- O bloco 1 não se duplica: não existe nome, telefone nem nascimento aqui.
  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='registros'
       and column_name in ('nome','telefone','email','cpf','nascimento','responsaveis')
  ) then
    raise exception '1 FUROU: o registro duplicou identificação — campo repetido é campo que diverge'; end if;

  -- ---------------------------------------------------------------- 2
  falhou := false;
  begin
    perform public.salvar_demanda(pac, 'x', 'y', 'semanal', 'telepatia');
  exception when others then falhou := true; end;
  if not falhou then raise exception '2 FUROU: aceitou modalidade inventada'; end if;
  if (select modalidade from public.registros where id=reg) <> 'presencial' then
    raise exception '2 FUROU: a modalidade não gravou'; end if;

  -- ---------------------------------------------------------------- 3
  falhou := false;
  begin
    update public.registros set encerrado_em = now() where id=reg;
  exception when others then falhou := true; end;
  if not falhou then
    raise exception '3 FUROU: meio encerramento passou — registro incompleto é o que a norma proíbe'; end if;

  -- ---------------------------------------------------------------- 4
  perform public.salvar_demanda(pac, 'outra redação', null, null, 'remoto');
  select count(*) into n from public.registros where paciente_id=pac;
  if n <> 1 then raise exception '4 FUROU: % registros para a mesma pessoa', n; end if;

  -- ---------------------------------------------------------------- 5
  ev := public.escrever_evolucao(s_feita, 'Trabalhamos a antecipação das crises. Combinamos o registro diário.');
  if ev is null then raise exception '5 FUROU: a evolução não gravou'; end if;
  if (select texto from public.evolucoes where id=ev) is null then
    raise exception '5 FUROU: gravou vazio'; end if;

  -- ---------------------------------------------------------------- 6
  falhou := false;
  begin
    perform public.escrever_evolucao(s_falta, 'não veio');
  exception when others then
    falhou := true;
    if position('não houve' in sqlerrm) = 0 then
      raise exception '6 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '6 FUROU: escreveu evolução de hora que não aconteceu'; end if;

  -- E a mensagem da B27, do outro lado, agora encaminha em vez de só proibir.
  falhou := false;
  begin
    perform public.anotar_ausencia(s_feita, 'tentando pelo outro caminho');
  exception when others then
    falhou := true;
    if position('evolução' in sqlerrm) = 0 then
      raise exception '6 FUROU: a recusa da B27 não aponta para a evolução (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '6 FUROU: a nota entrou na sessão realizada'; end if;

  -- ---------------------------------------------------------------- 7
  falhou := false;
  begin
    perform public.escrever_evolucao(s_outra, '    ');
  exception when others then
    falhou := true;
    if position('espaço vazio' in sqlerrm) = 0 then
      raise exception '7 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '7 FUROU: guardou espaço em branco'; end if;

  falhou := false;
  begin
    update public.evolucoes set texto = '' where id=ev;
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: esvaziou por PATCH direto'; end if;

  -- ---------------------------------------------------------------- 8
  delete from public.evolucoes where id=ev;
  if not exists (select 1 from public.evolucoes where id=ev) then
    raise exception '8 FUROU: a evolução foi apagada — guarda de cinco anos não tem botão de apagar'; end if;
  if exists (
    select 1 from pg_policies where schemaname='public'
      and tablename in ('evolucoes','registros') and cmd='DELETE'
  ) then
    raise exception '8 FUROU: existe política de DELETE em registro clínico'; end if;

  -- ---------------------------------------------------------------- 9
  falhou := false;
  begin
    update public.evolucoes set sessao_id = s_outra where id=ev;
  exception when others then
    falhou := true;
    if position('daquele atendimento' in sqlerrm) = 0 then
      raise exception '9 FUROU: outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '9 FUROU: a evolução mudou de sessão — isso é fabricar registro'; end if;

  -- ---------------------------------------------------------------- 10
  update public.evolucoes
     set texto = 'Trabalhamos a antecipação das crises. Ela trouxe o registro da semana.',
         editado_em = timestamptz '2020-01-01 10:00-03'
   where id=ev;
  select editado_em into antes from public.evolucoes where id=ev;
  if antes < now() - interval '1 hour' then
    raise exception '10 FUROU: um carimbo forjado colou (%)', antes; end if;

  -- ---------------------------------------------------------------- 11
  perform public.escrever_evolucao(s_feita, 'terceira redação da mesma hora');
  select count(*) into n from public.evolucoes where sessao_id=s_feita;
  if n <> 1 then raise exception '11 FUROU: % evoluções para a mesma sessão', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · o registro e a evolução: ok';
end $do$;

-- ==================== parte 2 · a gaveta, e o que sai de cada porta

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; s_outra uuid; s_imp uuid;
  exp jsonb; expc jsonb; reg jsonb; n int; falhou boolean;
  na_gaveta text := 'WAIS-IV aplicado; protocolo arquivado. Zebulon-gaveta-Kryzanowski';
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into pac from public.pacientes where conta_id=a_conta limit 1;
  select id into s_outra from public.sessoes
   where paciente_id=pac and estado='realizada' and not exists
     (select 1 from public.evolucoes e where e.sessao_id = public.sessoes.id);

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  perform public.escrever_evolucao(s_outra, na_gaveta, 'documental');

  -- ---------------------------------------------------------------- 12
  exp := public.exportar_paciente(pac);
  if position(na_gaveta in exp::text) > 0 then
    raise exception '12 FUROU: o Registro Documental saiu na cópia do paciente — é a gaveta do CFP'; end if;
  if position('Zebulon-gaveta' in exp::text) > 0 then
    raise exception '12 FUROU: parte do material de acesso exclusivo vazou'; end if;
  -- Asserção estrutural, e não por texto: são duas evoluções na base — uma em
  -- cada camada — e a cópia do paciente tem de trazer **exatamente uma**. Um
  -- teste que procura por uma frase específica passa a mentir na primeira vez
  -- que alguém reescreve a frase.
  if jsonb_array_length(exp->'evolucoes') <> 1 then
    raise exception '12 FUROU: a cópia do paciente trouxe % evoluções (esperado 1: só a do prontuário)',
      jsonb_array_length(exp->'evolucoes'); end if;
  if (exp->'evolucoes'->0->>'camada') <> 'prontuario' then
    raise exception '12 FUROU: saiu uma evolução que não é da camada do prontuário'; end if;

  -- ---------------------------------------------------------------- 13
  expc := public.exportar_conta();
  if position(na_gaveta in expc::text) = 0 then
    raise exception '13 FUROU: a gaveta não saiu na exportação da conta — que é dela, e é portabilidade'; end if;
  if not (expc ? 'registros') or not (expc ? 'evolucoes') then
    raise exception '13 FUROU: faltam registros ou evoluções na exportação da conta'; end if;

  -- ---------------------------------------------------------------- 14
  if position('Registro Documental' in exp::text) = 0 then
    raise exception '14 FUROU: a cópia do paciente não diz o que não está nela'; end if;

  -- ---------------------------------------------------------------- 15
  if position('cópia de documento sigiloso' in lower(exp::text)) = 0 then
    raise exception '15 FUROU: a cópia perdeu a marca de sigilo'; end if;
  if not (exp ? 'registro') then
    raise exception '15 FUROU: o registro não entrou na cópia do paciente'; end if;

  -- ---------------------------------------------------------------- 16
  -- Uma hora realizada sem evolução tem de aparecer dizendo que está sem.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(public.hoje_sp() - 3 + time '15:00') at time zone 'America/Sao_Paulo',
                               (public.hoje_sp() - 3 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00);

  reg := public.registro_do_paciente(pac);
  if jsonb_array_length(reg->'sem_evolucao') <> 1 then
    raise exception '16 FUROU: % horas sem registro (esperado 1) — buraco silencioso é pior que anunciado',
      jsonb_array_length(reg->'sem_evolucao'); end if;

  -- A importada veio de outro sistema: cobrar evolução dela seria pedir que ela
  -- escreva o que não viu.
  select (public.importar_historico(jsonb_build_array(jsonb_build_object(
      'paciente_id', pac,
      'inicio', (public.hoje_sp() - 300 + time '15:00') at time zone 'America/Sao_Paulo',
      'estado','realizada','valor',180.00)))->>'importadas')::int into n;
  if n <> 1 then raise exception '16 PREPARO: a importação não entrou'; end if;

  reg := public.registro_do_paciente(pac);
  if jsonb_array_length(reg->'sem_evolucao') <> 1 then
    raise exception '16 FUROU: a sessão importada entrou na cobrança de evolução'; end if;

  if jsonb_array_length(reg->'evolucoes') <> 2 then
    raise exception '16 FUROU: % evoluções no registro', jsonb_array_length(reg->'evolucoes'); end if;
  if (reg->'demanda'->>'modalidade') <> 'remoto' then
    raise exception '16 FUROU: o bloco da demanda não veio'; end if;
  if (reg->'identificacao'->>'nome') is null then
    raise exception '16 FUROU: o bloco da identificação não veio'; end if;

  -- ---------------------------------------------------------------- 17
  reset role;
  falhou := false;
  begin
    delete from public.sessoes where id=s_outra;
  exception when foreign_key_violation then falhou := true; end;
  if not falhou then
    raise exception '17 FUROU: apagar a sessão levou o registro clínico junto'; end if;

  -- ---------------------------------------------------------------- 18
  falhou := false;
  begin
    delete from public.pacientes where id=pac;
  exception when foreign_key_violation then falhou := true; end;
  if not falhou then
    raise exception '18 FUROU: apagar paciente com registro foi permitido'; end if;
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 21
  -- As duas escritas convivem na mesma pessoa e não se confundem: a nota é da
  -- hora que não houve (B27), a evolução é da hora que houve (B28).
  execute 'set local role authenticated';
  perform public.anotar_ausencia(
    (select id from public.sessoes where paciente_id=pac and estado='falta' limit 1),
    'Avisou no dia seguinte que tinha ficado doente.');

  if (select count(*) from public.sessoes where paciente_id=pac and nota is not null) <> 1 then
    raise exception '21 FUROU: a nota da B27 não convive com a evolução'; end if;
  if (select count(*) from public.evolucoes where paciente_id=pac) <> 2 then
    raise exception '21 FUROU: as evoluções sumiram quando a nota entrou'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · a gaveta e as duas portas: ok';
end $do$;

-- ==================== parte 3 · a guarda, e a regra do menor

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; menor uuid; adulto uuid; virou uuid;
  d date; r record; n int; achou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  d := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- Atendida aos 9 anos, arquivada logo depois. Hoje ela tem 14: passou o prazo
  -- de cinco anos do último registro, e **não** pode estar elegível.
  insert into public.pacientes (profissional_id,nome,nascimento,estado)
    values (a_prof,'Criança de Nove', (d - interval '14 years')::date, 'em_atendimento')
    returning id into menor;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,menor,(d - 1900 + time '10:00') at time zone 'America/Sao_Paulo',
                                 (d - 1900 + time '10:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00);

  -- Um adulto na mesma situação, para provar que a regra geral não mudou.
  insert into public.pacientes (profissional_id,nome,nascimento,estado)
    values (a_prof,'Adulto de Sempre', (d - interval '40 years')::date, 'em_atendimento')
    returning id into adulto;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,adulto,(d - 1900 + time '11:00') at time zone 'America/Sao_Paulo',
                                  (d - 1900 + time '11:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00);

  -- `elegiveis_para_eliminacao` conta a partir do maior entre a última sessão e
  -- o `criado_em` da ficha (regra da B13, e ela está certa: a ficha aberta hoje
  -- é registro de hoje). Num teste, `criado_em` é sempre agora — então a ficha
  -- precisa nascer velha para o cenário existir.
  reset role;
  update public.pacientes set criado_em = now() - interval '1900 days'
   where id in (menor, adulto);
  execute 'set local role authenticated';

  perform public.arquivar_paciente(menor, 'Encerrado por mudança de cidade da família; encaminhada a colega da nova cidade.', 'encaminhamento');
  perform public.arquivar_paciente(adulto, 'Alta combinada em sessão; objetivos do plano alcançados.', 'alta');

  -- ---------------------------------------------------------------- 19
  achou := exists (select 1 from public.elegiveis_para_eliminacao() x where x.paciente_id = menor);
  if achou then
    raise exception '19 FUROU: a ficha de quem foi atendido aos 9 ficou elegível aos 14'; end if;

  -- ---------------------------------------------------------------- 20
  achou := exists (select 1 from public.elegiveis_para_eliminacao() x where x.paciente_id = adulto);
  if not achou then
    raise exception '20 FUROU: a regra geral parou de valer — o adulto devia estar elegível'; end if;

  select * into r from public.elegiveis_para_eliminacao() x where x.paciente_id = adulto;
  if r.motivo <> 'ultimo_registro' then
    raise exception '20 FUROU: motivo "%" para o adulto', r.motivo; end if;

  -- A terceira ficha é a que prova a conta do menor pelo lado de dentro: quem
  -- foi atendido criança, hoje tem 24, e cujo último registro é de quase sete
  -- anos atrás. As duas contas já venceram — e a que manda é a da maioridade,
  -- porque ela vence depois. Sem esta ficha, o `motivo` nunca seria exercitado.
  reset role;
  insert into public.pacientes (conta_id,profissional_id,nome,nascimento,estado,criado_em)
    values (a_conta,a_prof,'Virou Adulta', (d - interval '24 years')::date, 'em_atendimento',
            now() - interval '2500 days')
    returning id into virou;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,virou,(d - 2500 + time '09:00') at time zone 'America/Sao_Paulo',
                                 (d - 2500 + time '09:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00);
  execute 'set local role authenticated';
  perform public.arquivar_paciente(virou, 'Alta combinada; encerramento registrado na época.', 'alta');

  select * into r from public.elegiveis_para_eliminacao() x where x.paciente_id = virou;
  if not found then
    raise exception '20 FUROU: passados os 18 com folga, a ficha continua presa'; end if;
  if r.motivo <> 'maioridade' then
    raise exception '20 FUROU: a conta que mandou foi a do último registro (motivo "%") — a da maioridade vence depois', r.motivo; end if;
  if r.guardar_ate is null then raise exception '20 FUROU: sem prazo escrito'; end if;
  if r.guardar_ate <> (d - interval '24 years' + interval '18 years' + interval '5 years')::date then
    raise exception '20 FUROU: o prazo saiu em % — esperado maioridade + retenção', r.guardar_ate; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · a guarda e a regra do menor: ok';
end $do$;

-- ==================== parte 4 · trilha, isolamento e o anônimo

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_pac uuid; a_ev uuid; a_sessao uuid; n int; falhou boolean; j jsonb;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  select id into a_ev from public.evolucoes where paciente_id=a_pac limit 1;
  select sessao_id into a_sessao from public.evolucoes where id=a_ev;

  -- ---------------------------------------------------------------- 22
  select count(*) into n from public.trilha_acesso
   where paciente_id=a_pac and acao='escreveu_evolucao';
  if n < 2 then raise exception '22 FUROU: a trilha registrou % evoluções', n; end if;
  select count(*) into n from public.trilha_acesso
   where paciente_id=a_pac and acao='editou_registro';
  if n < 2 then raise exception '22 FUROU: a trilha não registrou a demanda'; end if;

  delete from public.evolucoes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.registros where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Outra';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Outra"}'::jsonb);

  -- ---------------------------------------------------------------- 23
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.evolucoes;
  if n <> 0 then raise exception '23 FUROU: a Bia lê % evoluções da Ana', n; end if;
  select count(*) into n from public.registros;
  if n <> 0 then raise exception '23 FUROU: a Bia lê o registro da Ana'; end if;

  j := public.registro_do_paciente(a_pac);
  if j is not null and jsonb_array_length(coalesce(j->'evolucoes','[]'::jsonb)) > 0 then
    raise exception '23 FUROU: o registro da Ana veio pela função'; end if;

  falhou := false;
  begin perform public.escrever_evolucao(a_sessao, 'invadindo'); exception when others then falhou := true; end;
  if not falhou then raise exception '23 FUROU: a Bia escreveu no prontuário da Ana'; end if;

  falhou := false;
  begin perform public.salvar_demanda(a_pac, 'x', null, null, 'presencial'); exception when others then falhou := true; end;
  if not falhou then raise exception '23 FUROU: a Bia escreveu a demanda da Ana'; end if;

  if (select texto from public.evolucoes where id=a_ev) = 'invadindo' then
    raise exception '23 FUROU: a evolução da Ana foi reescrita'; end if;

  -- ---------------------------------------------------------------- 24
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.evolucoes;
  if n <> 0 then raise exception '24 FUROU: o anônimo lê evolução'; end if;
  select count(*) into n from public.registros;
  if n <> 0 then raise exception '24 FUROU: o anônimo lê registro'; end if;

  falhou := false;
  begin perform public.registro_do_paciente(a_pac); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo executa registro_do_paciente'; end if;

  falhou := false;
  begin perform public.escrever_evolucao(a_sessao,'x'); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo escreve evolução'; end if;

  falhou := false;
  begin perform public.elegiveis_para_eliminacao(); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo lista fichas para expurgo'; end if;

  falhou := false;
  begin perform public.evolucao_nao_se_reescreve(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '24 FUROU: o gatilho está publicado em /rest/v1/rpc'; end if;

  reset role;
  raise notice 'parte 4 · trilha, isolamento e o anônimo: ok';
end $do$;

-- ==================== parte 5 · a suíte recolhe o próprio rastro
--
-- `evolucoes` e `registros` apontam para `pacientes` com `on delete restrict` —
-- é a guarda de cinco anos escrita na FK. A consequência para as suítes é
-- direta: qualquer preâmbulo que apague `pacientes` (e são todos) trava se esta
-- deixar registro clínico para trás. É a lição da B27, e agora com uma FK que
-- **existe de propósito** e não vai afrouxar.

do $do$
declare
  a_conta uuid;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  if a_conta is null then
    raise notice 'parte 5 · nada a limpar';
    return;
  end if;

  delete from public.evolucoes where conta_id = a_conta;
  delete from public.registros where conta_id = a_conta;
  delete from public.documentos where conta_id = a_conta;
  delete from public.recibos_rfb where conta_id = a_conta;
  delete from public.pastas_contador where conta_id = a_conta;

  -- E agora as contas. Recolher só o registro clínico deixava 'Ana Solo' e
  -- 'Bia Outra' de pé — as duas com `is_teste = false`, porque quem nasce pelo
  -- gatilho de `auth.users` nasce como conta de verdade, e conta de teste que
  -- fica vira linha em toda métrica de operação do painel do negócio.
  --
  -- A conta leva o resto por cascata; o `auth.users` sai depois dela, porque
  -- `pacientes.profissional_id` e `registros.profissional_id` são RESTRICT.
  delete from public.contas where id = a_conta;
  delete from public.contas where nome = 'Bia Outra';
  delete from auth.users where id in ('11111111-1111-4111-8111-111111111111',
                                      '22222222-2222-4222-8222-222222222222');
  if exists (select 1 from public.contas where nome in ('Ana Solo','Bia Outra')) then
    raise exception 'DESMONTE FUROU: sobrou conta de teste no banco'; end if;

  raise notice 'parte 5 · rastro recolhido: ok';
  raise notice '=== 0042 · o registro que o CFP pede: 24 verificações, todas passaram ===';
end $do$;
