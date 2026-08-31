-- Teste da materialização da agenda (critério de pronto da B5).
--
-- O que se prova:
--   1. criar um enquadre gera a janela de 8 semanas, pelo gatilho
--   2. o retrato do combinado (valor e política) vai junto em cada sessão
--   3. toda ocorrência cai no dia e na hora certos **no fuso de São Paulo**
--   4. rodar a materialização de novo não duplica nada
--   5. férias de duas semanas apagam só as instâncias — o enquadre fica intacto
--   6. desmarcar as férias devolve a recorrência sozinha
--   7. feriado de um dia limpa só aquele dia
--   8. reajuste fecha um enquadre e abre outro sem deixar previsão órfã
--   9. agenda dupla é impossível por construção
--  10. cancelar libera o horário — é este buraco que a fila vai preencher
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0006_materializacao.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; a_pac uuid; a_enq uuid; novo_enq uuid;
  n int; esperado int; hoje date; prox_terca date; falhou boolean; ex uuid;
begin
  delete from public.sessoes where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from public.excecoes_agenda where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from auth.users where id = a_auth;
  delete from public.contas where nome = 'Ana Solo';

  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.sessoes.com.br', '{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta;
  hoje := public.hoje_sp();

  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id, nome, telefone)
  values (a_prof, 'Maria Fernanda Reis', '5511987654321') returning id into a_pac;

  -- A terça das 15h é da Maria: R$ 200, política de 24h/50%.
  insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual)
  values (a_pac, 2, '15:00', 50, 200.00, 24, 50) returning id into a_enq;

  select count(*) into esperado
    from generate_series(hoje, hoje + 56, interval '1 day') d
   where extract(dow from d) = 2
     and ((d::date + time '15:00') at time zone 'America/Sao_Paulo') >= now();

  select count(*) into n from public.sessoes where enquadre_id = a_enq;
  if n <> esperado then raise exception '1 FUROU: % sessões, esperado %', n, esperado; end if;
  if n < 8 then raise exception '1 FUROU: janela curta demais (%)', n; end if;

  select count(*) into n from public.sessoes
   where enquadre_id = a_enq and valor = 200.00 and politica_horas = 24 and politica_percentual = 50;
  if n <> esperado then raise exception '2 FUROU: o retrato do combinado não foi copiado'; end if;

  select count(*) into n from public.sessoes
   where enquadre_id = a_enq
     and (extract(dow from (inicio at time zone 'America/Sao_Paulo')) <> 2
          or (inicio at time zone 'America/Sao_Paulo')::time <> time '15:00');
  if n <> 0 then raise exception '3 FUROU: % sessões fora da terça 15h em São Paulo', n; end if;

  perform public.materializar_enquadre(a_enq);
  perform public.materializar_enquadre(a_enq);
  select count(*) into n from public.sessoes where enquadre_id = a_enq;
  if n <> esperado then raise exception '4 FUROU: rodar de novo duplicou (%)', n; end if;

  select min((inicio at time zone 'America/Sao_Paulo')::date) into prox_terca
    from public.sessoes where enquadre_id = a_enq;

  insert into public.excecoes_agenda (profissional_id, tipo, inicio, fim, motivo)
  values (a_prof, 'ferias', prox_terca, prox_terca + 13, 'férias') returning id into ex;

  select count(*) into n from public.sessoes
   where enquadre_id = a_enq
     and (inicio at time zone 'America/Sao_Paulo')::date between prox_terca and prox_terca + 13;
  if n <> 0 then raise exception '5 FUROU: % sessões sobreviveram às férias', n; end if;
  if (select count(*) from public.enquadres where id = a_enq and vigencia_fim is null) <> 1 then
    raise exception '5 FUROU: as férias mexeram no enquadre'; end if;
  select count(*) into n from public.sessoes where enquadre_id = a_enq;
  if n <> esperado - 2 then raise exception '5 FUROU: sobraram % (esperado %)', n, esperado - 2; end if;

  delete from public.excecoes_agenda where id = ex;
  select count(*) into n from public.sessoes where enquadre_id = a_enq;
  if n <> esperado then raise exception '6 FUROU: a recorrência não voltou (%)', n; end if;

  insert into public.excecoes_agenda (profissional_id, tipo, inicio, fim, motivo)
  values (a_prof, 'feriado', prox_terca, prox_terca, 'feriado');
  select count(*) into n from public.sessoes where enquadre_id = a_enq;
  if n <> esperado - 1 then raise exception '7 FUROU: o feriado tirou % sessões', esperado - n; end if;
  delete from public.excecoes_agenda where profissional_id = a_prof;

  -- O reajuste (D14): fecha um, abre outro. A sessão de hoje, se houver, fica
  -- com o valor antigo — já estava combinada assim.
  update public.enquadres set vigencia_fim = hoje, motivo_fim = 'reajuste' where id = a_enq;
  insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual, vigencia_inicio)
  values (a_pac, 2, '15:00', 50, 230.00, 24, 50, hoje) returning id into novo_enq;

  select count(*) into n from public.sessoes where enquadre_id = novo_enq and valor = 230.00;
  if n = 0 then raise exception '8 FUROU: o enquadre novo não materializou'; end if;
  select count(*) into n from public.sessoes where enquadre_id = a_enq and inicio > now();
  if n <> 0 then raise exception '8 FUROU: sobraram % previsões do enquadre fechado', n; end if;

  falhou := false;
  begin
    insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, valor)
    select conta_id, profissional_id, paciente_id, null, inicio, fim, 'encaixe', 100.00
      from public.sessoes where enquadre_id = novo_enq limit 1;
    falhou := true;
  exception when exclusion_violation then null; end;
  if falhou then raise exception '9 FUROU: dois pacientes no mesmo horário'; end if;

  update public.sessoes set estado = 'cancelada_tarde', cancelada_em = now(), cancelada_por = 'paciente'
   where id = (select id from public.sessoes where enquadre_id = novo_enq order by inicio limit 1);
  insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, valor)
  select conta_id, profissional_id, paciente_id, null, inicio, fim, 'encaixe', 200.00
    from public.sessoes where enquadre_id = novo_enq and estado = 'cancelada_tarde' limit 1;
  select count(*) into n from public.sessoes where origem = 'encaixe';
  if n <> 1 then raise exception '10 FUROU: a vaga cancelada não aceitou encaixe'; end if;

  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.sessoes where conta_id = a_conta;
  delete from public.excecoes_agenda where conta_id = a_conta;
  delete from public.enquadres where conta_id = a_conta;
  delete from public.pacientes where conta_id = a_conta;
  delete from auth.users where id = a_auth;
  delete from public.contas where id = a_conta;

  raise notice 'B5 OK — 10 verificações, janela de % sessões', esperado;
end $$;
