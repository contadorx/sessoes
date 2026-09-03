-- Teste da anamnese e do aviso da terceira (critério de pronto da B29).
--
-- A verificação nº 1 é a que decide o build, e ela não olha dado nenhum: olha o
-- **esquema**. Se existir função que devolva anamnese por token, ou coluna de
-- token na tabela, alguém atravessou a fronteira 6 do doc 11 — *"perguntas
-- clínicas não vão por formulário ao paciente"*. A tentação é concreta e vai
-- voltar ("manda o link, economiza vinte minutos da primeira sessão"), e os
-- vinte minutos são a primeira sessão.
--
--   1. NÃO EXISTE caminho público para a anamnese — nem token, nem função
--   2. abrir traz o roteiro do modelo, com as seções em branco
--   3. os três modelos têm roteiro próprio, e nenhum tem pergunta fechada
--   4. uma anamnese por paciente; abrir de novo devolve a mesma
--   5. enquanto aberta, edita à vontade
--   6. fechar em branco é recusado — não se guarda seção de nada
--   7. fechada não se reescreve, nem por PATCH
--   8. fechada não reabre
--   9. `fechada_em` é do servidor; forjado não cola
--  10. adendo só depois de fechada — antes é edição disfarçada de data
--  11. adendo em branco é recusado
--  12. adendo não se edita nem se apaga (append-only de verdade)
--  13. a anamnese não muda de dono
--  14. a medicação é encontrável sem reler seis seções
--  15. o aviso da terceira: não aparece na segunda, aparece na terceira
--  16. ...e some quando a anamnese fecha
--  17. ...e não aparece em ficha arquivada
--  18. o número 3 mora numa função, e a rotina pergunta em vez de saber
--  19. o aviso fala do registro dela, nunca do paciente
--  20. sessão importada não conta para o aviso
--  21. a anamnese entra no registro do paciente (bloco 2 aprofundado)
--  22. as DUAS exportações levam anamnese e adendos
--  23. isolamento entre contas
--  24. o anônimo não lê nem executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0043_anamnese.sql

-- ==================== parte 1 · a fronteira, o roteiro e o congelamento

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; an uuid; ad uuid;
  d date; r record; j jsonb; n int; falhou boolean; antes timestamptz;
begin
  delete from public.anamnese_adendos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.anamneses where conta_id in (select id from public.contas where nome='Ana Solo');
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

  -- ---------------------------------------------------------------- 1
  -- A verificação que decide o build, e ela é de estrutura.
  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name in ('anamneses','anamnese_adendos')
       and (column_name like '%token%' or column_name like '%publico%' or column_name like '%link%')
  ) then
    raise exception '1 FUROU: a anamnese ganhou coluna de token — ela é da sala, não do formulário'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public'
       and (p.proname like '%anamnese%por_token%' or p.proname like '%anamnese%publica%'
            or p.proname like '%anamnese%link%' or p.proname like 'responder_anamnese%')
  ) then
    raise exception '1 FUROU: existe função que expõe anamnese por link'; end if;

  -- E nenhuma das funções da anamnese é alcançável pelo anônimo (a 24 confere
  -- de novo pelo comportamento; esta olha a concessão).
  if exists (
    select 1 from information_schema.role_routine_grants
     where routine_schema='public' and grantee in ('anon','PUBLIC')
       and routine_name in ('abrir_anamnese','salvar_anamnese','fechar_anamnese',
                            'acrescentar_adendo','anamnese_do_paciente','roteiro_padrao')
  ) then
    raise exception '1 FUROU: o anônimo tem execute em função da anamnese'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,nascimento,estado)
    values (a_prof,'Maria Fernanda Reis','5511987650001', date '1990-04-12','em_atendimento')
    returning id into pac;

  -- ---------------------------------------------------------------- 2
  an := public.abrir_anamnese(pac, 'adulto');
  if an is null then raise exception '2 FUROU: a anamnese não abriu'; end if;

  select * into r from public.anamneses where id=an;
  if jsonb_array_length(r.conteudo) < 5 then
    raise exception '2 FUROU: o roteiro veio com % seções', jsonb_array_length(r.conteudo); end if;
  if exists (select 1 from jsonb_array_elements(r.conteudo) s where btrim(coalesce(s->>'texto','')) <> '') then
    raise exception '2 FUROU: o roteiro veio com texto preenchido — o ponto é a estrutura, não o conteúdo'; end if;
  if not (r.conteudo->0 ? 'titulo') then
    raise exception '2 FUROU: a seção não tem título'; end if;

  -- ---------------------------------------------------------------- 3
  if public.roteiro_padrao('infantil') = public.roteiro_padrao('adulto')
     or public.roteiro_padrao('casal') = public.roteiro_padrao('adulto') then
    raise exception '3 FUROU: os três modelos têm o mesmo roteiro'; end if;
  if position('scola' in public.roteiro_padrao('infantil')::text) = 0 then
    raise exception '3 FUROU: o roteiro infantil não fala de escola'; end if;
  -- Roteiro é título de seção, não pergunta fechada: nada de '?' nem de opções.
  if position('?' in public.roteiro_padrao('adulto')::text) > 0
     or position('?' in public.roteiro_padrao('infantil')::text) > 0
     or position('?' in public.roteiro_padrao('casal')::text) > 0 then
    raise exception '3 FUROU: o roteiro virou questionário — isso é instrumento clínico, e é de outra profissão'; end if;

  -- ---------------------------------------------------------------- 4
  if public.abrir_anamnese(pac, 'infantil') <> an then
    raise exception '4 FUROU: abriu uma segunda anamnese para a mesma pessoa'; end if;
  select count(*) into n from public.anamneses where paciente_id=pac;
  if n <> 1 then raise exception '4 FUROU: % anamneses', n; end if;

  -- ---------------------------------------------------------------- 5
  perform public.salvar_anamnese(an, jsonb_build_array(
    jsonb_build_object('titulo','Queixa e o que a trouxe agora','texto','Crises de ansiedade no trabalho.'),
    jsonb_build_object('titulo','História de vida','texto','')
  ), 'Sertralina 50mg pela manhã');
  select * into r from public.anamneses where id=an;
  if jsonb_array_length(r.conteudo) <> 2 then
    raise exception '5 FUROU: a edição não gravou'; end if;
  perform public.salvar_anamnese(an, r.conteudo || jsonb_build_array(
    jsonb_build_object('titulo','Objetivos','texto','Dormir e voltar a sair de casa.')), 'Sertralina 50mg pela manhã');

  -- ---------------------------------------------------------------- 14
  if (select medicacao_atual from public.anamneses where id=an) is null then
    raise exception '14 FUROU: a medicação não ficou encontrável'; end if;

  -- ---------------------------------------------------------------- 10 (antes)
  falhou := false;
  begin
    perform public.acrescentar_adendo(an, 'tentando adendar antes de fechar');
  exception when others then
    falhou := true;
    if position('ainda está aberta' in sqlerrm) = 0 then
      raise exception '10 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '10 FUROU: adendo em anamnese aberta é edição com data falsa'; end if;

  -- ---------------------------------------------------------------- 6
  perform public.abrir_anamnese(pac, 'adulto');
  falhou := false;
  begin
    perform public.salvar_anamnese(an, jsonb_build_array(
      jsonb_build_object('titulo','Queixa','texto','')), null);
    perform public.fechar_anamnese(an);
  exception when others then
    falhou := true;
    if position('em branco' in sqlerrm) = 0 then
      raise exception '6 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '6 FUROU: fechou uma anamnese sem uma linha escrita'; end if;

  -- Volta a ter conteúdo e fecha de verdade.
  perform public.salvar_anamnese(an, jsonb_build_array(
    jsonb_build_object('titulo','Queixa e o que a trouxe agora','texto','Crises de ansiedade no trabalho.'),
    jsonb_build_object('titulo','Objetivos','texto','Dormir e voltar a sair de casa.')
  ), 'Sertralina 50mg pela manhã');
  perform public.fechar_anamnese(an);

  select * into r from public.anamneses where id=an;
  if r.estado <> 'fechada' then raise exception '6 FUROU: não fechou'; end if;
  if r.fechada_em is null then raise exception '6 FUROU: fechou sem carimbo'; end if;
  antes := r.fechada_em;

  -- ---------------------------------------------------------------- 7
  falhou := false;
  begin
    perform public.salvar_anamnese(an, jsonb_build_array(
      jsonb_build_object('titulo','Reescrevendo','texto','por cima')), null);
  exception when others then
    falhou := true;
    if position('acrescente um adendo' in sqlerrm) = 0 then
      raise exception '7 FUROU: outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '7 FUROU: reescreveu anamnese fechada'; end if;

  falhou := false;
  begin
    update public.anamneses set conteudo = '[]'::jsonb where id=an;
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: reescreveu por PATCH direto'; end if;

  falhou := false;
  begin
    update public.anamneses set medicacao_atual = 'trocado por fora' where id=an;
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: trocou a medicação por fora'; end if;

  -- ---------------------------------------------------------------- 8
  falhou := false;
  begin
    update public.anamneses set estado='aberta', fechada_em=null where id=an;
  exception when others then
    falhou := true;
    if position('não reabre' in sqlerrm) = 0 then
      raise exception '8 FUROU: outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then raise exception '8 FUROU: a anamnese fechada reabriu'; end if;

  -- ---------------------------------------------------------------- 9
  update public.anamneses set fechada_em = timestamptz '2020-01-01 10:00-03' where id=an;
  if (select fechada_em from public.anamneses where id=an) is distinct from antes then
    raise exception '9 FUROU: um carimbo forjado colou'; end if;

  -- ---------------------------------------------------------------- 10 (depois)
  ad := public.acrescentar_adendo(an, 'Trouxe em maio que houve internação do pai em 2019.');
  if ad is null then raise exception '10 FUROU: o adendo não gravou'; end if;

  -- ---------------------------------------------------------------- 11
  falhou := false;
  begin perform public.acrescentar_adendo(an, '   ');
  exception when others then falhou := true; end;
  if not falhou then raise exception '11 FUROU: adendo em branco entrou'; end if;

  -- ---------------------------------------------------------------- 12
  update public.anamnese_adendos set texto='reescrito' where id=ad;
  if (select texto from public.anamnese_adendos where id=ad) = 'reescrito' then
    raise exception '12 FUROU: o adendo foi reescrito — append-only não é append-quase'; end if;
  delete from public.anamnese_adendos where id=ad;
  if not exists (select 1 from public.anamnese_adendos where id=ad) then
    raise exception '12 FUROU: o adendo foi apagado'; end if;
  if exists (
    select 1 from pg_policies where schemaname='public'
      and tablename in ('anamneses','anamnese_adendos') and cmd='DELETE'
  ) then raise exception '12 FUROU: existe política de DELETE'; end if;

  -- ---------------------------------------------------------------- 13
  falhou := false;
  begin
    update public.anamneses set paciente_id = gen_random_uuid() where id=an;
  exception when others then falhou := true; end;
  if not falhou then raise exception '13 FUROU: a anamnese mudou de dono'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · a fronteira, o roteiro e o congelamento: ok';
end $do$;

-- ==================== parte 2 · o aviso da terceira

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; novo uuid; an uuid;
  d date; j jsonb; i int; n int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  d := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,estado)
    values (a_prof,'Novo Sem Anamnese','em_atendimento') returning id into novo;

  -- ---------------------------------------------------------------- 18
  if public.sessoes_ate_fechar_anamnese() <> 3 then
    raise exception '18 FUROU: o limite saiu de %', public.sessoes_ate_fechar_anamnese(); end if;
  j := public.aviso_de_anamnese(novo);
  if (j->>'limite')::int <> public.sessoes_ate_fechar_anamnese() then
    raise exception '18 FUROU: a rotina tem um número próprio em vez de perguntar'; end if;

  -- ---------------------------------------------------------------- 15
  for i in 1..2 loop
    insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
      values (a_conta,a_prof,novo,(d - 30 + i*7 + time '16:00') at time zone 'America/Sao_Paulo',
                                  (d - 30 + i*7 + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00);
  end loop;

  j := public.aviso_de_anamnese(novo);
  if (j->>'mostrar')::boolean then
    raise exception '15 FUROU: avisou na segunda sessão — alarme que grita cedo vira paisagem'; end if;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,novo,(d - 30 + 21 + time '16:00') at time zone 'America/Sao_Paulo',
                                (d - 30 + 21 + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00);

  j := public.aviso_de_anamnese(novo);
  if not (j->>'mostrar')::boolean then
    raise exception '15 FUROU: não avisou na terceira (%)', j; end if;
  if (j->>'sessoes')::int <> 3 then
    raise exception '15 FUROU: contou % sessões', j->>'sessoes'; end if;
  if (j->>'existe')::boolean then
    raise exception '15 FUROU: disse que existe anamnese onde não há'; end if;

  -- ---------------------------------------------------------------- 20
  select (public.importar_historico(jsonb_build_array(jsonb_build_object(
     'paciente_id', novo,
     'inicio', (d - 500 + time '16:00') at time zone 'America/Sao_Paulo',
     'estado','realizada','valor',180.00)))->>'importadas')::int into n;
  if n <> 1 then raise exception '20 PREPARO: a importação não entrou'; end if;

  j := public.aviso_de_anamnese(novo);
  if (j->>'sessoes')::int <> 3 then
    raise exception '20 FUROU: a sessão importada entrou na conta do aviso (%)', j->>'sessoes'; end if;

  -- ---------------------------------------------------------------- 16
  an := public.abrir_anamnese(novo, 'adulto');
  j := public.aviso_de_anamnese(novo);
  if not (j->>'mostrar')::boolean then
    raise exception '16 FUROU: abrir a anamnese já apagou o aviso — o que fecha o aviso é fechar a anamnese'; end if;

  perform public.salvar_anamnese(an, jsonb_build_array(
    jsonb_build_object('titulo','Queixa','texto','Procurou por indicação da irmã.')), null);
  perform public.fechar_anamnese(an);

  j := public.aviso_de_anamnese(novo);
  if (j->>'mostrar')::boolean then
    raise exception '16 FUROU: o aviso ficou depois de a anamnese fechar'; end if;

  -- ---------------------------------------------------------------- 19
  -- O aviso fala do registro dela. Nenhuma chave e nenhum texto pode virar
  -- juízo sobre a pessoa — é a mesma fronteira que a B27 guarda.
  if exists (
    select 1 from jsonb_object_keys(j) k
     where lower(k) similar to '%(risco|alerta|atras|abandono|escore|problema)%'
  ) then raise exception '19 FUROU: o aviso ganhou campo de juízo sobre o paciente'; end if;

  -- ---------------------------------------------------------------- 17
  perform public.arquivar_paciente(novo, 'Encerramento registrado para efeito de teste.', 'alta');
  j := public.aviso_de_anamnese(novo);
  if (j->>'mostrar')::boolean then
    raise exception '17 FUROU: avisou sobre ficha arquivada, onde não há o que fazer'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · o aviso da terceira: ok';
end $do$;

-- ==================== parte 3 · o registro, as duas exportações

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; pac uuid; j jsonb; exp jsonb; expc jsonb;
  marca text := 'Zebulon-anamnese-Kryzanowski';
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  perform public.acrescentar_adendo(
    (select id from public.anamneses where paciente_id=pac), marca);

  -- ---------------------------------------------------------------- 21
  j := public.registro_do_paciente(pac);
  if j->'anamnese' is null or j->'anamnese' = 'null'::jsonb then
    raise exception '21 FUROU: o registro não sabe que existe anamnese — o bloco 2 continuaria vazio'; end if;
  if (j->'anamnese'->>'estado') <> 'fechada' then
    raise exception '21 FUROU: estado errado no registro'; end if;
  if (j->'anamnese'->>'secoes_escritas')::int < 1 then
    raise exception '21 FUROU: não contou as seções escritas'; end if;
  if (j->'anamnese'->>'adendos')::int < 1 then
    raise exception '21 FUROU: não contou os adendos'; end if;

  -- ---------------------------------------------------------------- 22
  exp := public.exportar_paciente(pac);
  if not (exp ? 'anamnese') or not (exp ? 'anamnese_adendos') then
    raise exception '22 FUROU: a cópia do paciente saiu sem a anamnese — ela é prontuário'; end if;
  if position(marca in exp::text) = 0 then
    raise exception '22 FUROU: o adendo não saiu na cópia do paciente'; end if;

  expc := public.exportar_conta();
  if not (expc ? 'anamneses') or not (expc ? 'anamnese_adendos') then
    raise exception '22 FUROU: a exportação da conta saiu sem a anamnese — é a lição da 0042b, de novo'; end if;
  if position(marca in expc::text) = 0 then
    raise exception '22 FUROU: o adendo não saiu na exportação da conta'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · o registro e as duas exportações: ok';
end $do$;

-- ==================== parte 4 · isolamento e o anônimo

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_pac uuid; a_an uuid; n int; falhou boolean; j jsonb;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  select id into a_an from public.anamneses where paciente_id=a_pac;

  delete from public.anamnese_adendos where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.anamneses where conta_id in (select id from public.contas where nome='Bia Outra');
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

  select count(*) into n from public.anamneses;
  if n <> 0 then raise exception '23 FUROU: a Bia lê % anamneses da Ana', n; end if;
  select count(*) into n from public.anamnese_adendos;
  if n <> 0 then raise exception '23 FUROU: a Bia lê os adendos da Ana'; end if;

  if public.anamnese_do_paciente(a_pac) is not null then
    raise exception '23 FUROU: a anamnese da Ana veio pela função'; end if;

  falhou := false;
  begin perform public.acrescentar_adendo(a_an, 'invadindo'); exception when others then falhou := true; end;
  if not falhou then raise exception '23 FUROU: a Bia adendou a anamnese da Ana'; end if;

  falhou := false;
  begin perform public.abrir_anamnese(a_pac, 'adulto'); exception when others then falhou := true; end;
  if not falhou then raise exception '23 FUROU: a Bia abriu anamnese no paciente da Ana'; end if;

  j := public.aviso_de_anamnese(a_pac);
  if (j->>'mostrar')::boolean then
    raise exception '23 FUROU: o aviso vazou entre contas'; end if;

  -- ---------------------------------------------------------------- 24
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.anamneses;
  if n <> 0 then raise exception '24 FUROU: o anônimo lê anamnese'; end if;
  select count(*) into n from public.anamnese_adendos;
  if n <> 0 then raise exception '24 FUROU: o anônimo lê adendo'; end if;

  falhou := false;
  begin perform public.anamnese_do_paciente(a_pac); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo executa anamnese_do_paciente'; end if;

  falhou := false;
  begin perform public.abrir_anamnese(a_pac,'adulto'); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo abre anamnese'; end if;

  falhou := false;
  begin perform public.roteiro_padrao('adulto'); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo lê o roteiro'; end if;

  falhou := false;
  begin perform public.aviso_de_anamnese(a_pac); exception when others then falhou := true; end;
  if not falhou then raise exception '24 FUROU: o anônimo executa aviso_de_anamnese'; end if;

  falhou := false;
  begin perform public.anamnese_fechada_nao_muda(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '24 FUROU: o gatilho está publicado em /rest/v1/rpc'; end if;

  reset role;
  raise notice 'parte 4 · isolamento e o anônimo: ok';
end $do$;

-- ==================== parte 5 · a suíte recolhe o próprio rastro
--
-- `anamneses` e `anamnese_adendos` apontam para `pacientes` e entre si com
-- `on delete restrict` — a guarda de cinco anos escrita na FK. Qualquer
-- preâmbulo que apague `pacientes` (e são todos) trava se esta deixar registro
-- para trás. Lição da B27, agora com três tabelas clínicas em vez de uma.

do $do$
declare
  a_conta uuid;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  if a_conta is null then
    raise notice 'parte 5 · nada a limpar';
    return;
  end if;

  delete from public.anamnese_adendos where conta_id = a_conta;
  delete from public.anamneses where conta_id = a_conta;
  delete from public.evolucoes where conta_id = a_conta;
  delete from public.registros where conta_id = a_conta;
  delete from public.documentos where conta_id = a_conta;
  delete from public.recibos_rfb where conta_id = a_conta;
  delete from public.pastas_contador where conta_id = a_conta;

  raise notice 'parte 5 · rastro recolhido: ok';
  raise notice '=== 0043 · a anamnese e o aviso da terceira: 24 verificações, todas passaram ===';
end $do$;
