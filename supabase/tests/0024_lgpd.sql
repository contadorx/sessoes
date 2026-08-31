-- Teste da LGPD, da trilha e da retenção (critério de pronto da B13).
--
-- A pergunta que este arquivo responde não é "o sistema apaga dado?". É:
-- **quando alguém pede para ser esquecido, o que exatamente acontece?**
--
-- A resposta certa é desconfortável e tem de estar no banco: o contato some, o
-- registro clínico fica (a Res. CFP 001/2009 obriga cinco anos), e a pessoa é
-- informada da data. Um sistema que oferecesse "excluir" e guardasse tudo
-- mentiria; um que apagasse de verdade colocaria a psicóloga em falta.
--
--   1. a trilha carimba quem, quando e de que conta — o que veio na linha é lixo
--   2. trilha não se edita nem se apaga, nem por quem é auditado
--   3. exportar ficha com restrição judicial exige declaração expressa
--   4. a exportação do paciente não vaza id de conta e traz o histórico
--   5. esquecer contato apaga contato, para o envio e explica o prazo
--   6. ... e não toca no registro clínico
--   7. arquivar exige o registro de encerramento (PR14)
--   8. ficha arquivada não volta atrás nem se edita
--   9. mas dá para anotar uma restrição judicial que chegou depois
--  10. apagar paciente não existe
--  11. exportar a conta traz tudo e entra na trilha
--  12. a retenção lista, nunca elimina sozinha
--  13. isolamento entre contas
--  14. o anônimo não lê nem executa
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0024_lgpd.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; menor uuid; s1 uuid; n int; r text; j jsonb; falhou boolean; t record;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.cobrancas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.mensagens where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,email,estado)
    values (a_prof,'Maria Reis','5511900000001','maria@teste.com','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado,restricao_judicial)
    values (a_prof,'Menor Silva','5511900000002','em_atendimento',true) returning id into menor;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, now()-interval '10 days', now()-interval '10 days'+interval '50 min','avulsa',200.00,24,50) returning id into s1;

  -- ---------------------------------------------------------------- 1
  -- Grava mentindo em tudo: conta alheia, outro autor, cinco anos atrás.
  insert into public.trilha_acesso (conta_id, auth_user_id, paciente_id, acao, em)
  values (b_conta, b_auth, maria, 'leu_ficha', now() - interval '5 years');
  select * into t from public.trilha_acesso where paciente_id=maria and acao='leu_ficha';
  if t.conta_id <> a_conta then raise exception '1 FUROU: conta forjada sobreviveu'; end if;
  if t.auth_user_id <> a_auth then raise exception '1 FUROU: autor forjado sobreviveu'; end if;
  if t.em < now() - interval '1 minute' then raise exception '1 FUROU: data forjada sobreviveu'; end if;

  -- ---------------------------------------------------------------- 2
  update public.trilha_acesso set acao='exportou_conta' where id=t.id;
  if (select acao from public.trilha_acesso where id=t.id) <> 'leu_ficha' then
    raise exception '2 FUROU: editou a trilha'; end if;
  delete from public.trilha_acesso where id=t.id;
  if (select count(*) from public.trilha_acesso where id=t.id) <> 1 then
    raise exception '2 FUROU: apagou a trilha'; end if;

  -- ---------------------------------------------------------------- 3
  falhou := false;
  begin perform public.exportar_paciente(menor);
  exception when others then
    falhou := true;
    if sqlerrm not like '%restrição judicial%' then raise; end if;
  end;
  if not falhou then raise exception '3 FUROU: exportou ficha com restrição judicial'; end if;

  select public.exportar_paciente(menor, true) into j;
  if j->'paciente'->>'nome' <> 'Menor Silva' then raise exception '3 FUROU: exportação vazia'; end if;
  if (select count(*) from public.trilha_acesso where paciente_id=menor and acao='exportou_paciente') <> 1 then
    raise exception '3 FUROU: exportação não entrou na trilha'; end if;

  -- ---------------------------------------------------------------- 4
  select public.exportar_paciente(maria) into j;
  if j->'paciente' ? 'conta_id' then raise exception '4 FUROU: vazou conta_id'; end if;
  if jsonb_array_length(j->'sessoes') <> 1 then raise exception '4 FUROU: sessões de fora'; end if;

  -- ---------------------------------------------------------------- 5 e 6
  perform public.enfileirar_mensagem(maria,'lembrete_de_sessao','lgpd1');
  select public.esquecer_contato(maria) into r;
  if r not like '%guardado até%' then raise exception '5 FUROU: resposta sem prazo: %', r; end if;
  if (select telefone from public.pacientes where id=maria) is not null then raise exception '5 FUROU: telefone ficou'; end if;
  if (select email from public.pacientes where id=maria) is not null then raise exception '5 FUROU: e-mail ficou'; end if;
  if (select msg_canal from public.pacientes where id=maria) <> 'nao_avisar' then raise exception '5 FUROU: canal'; end if;
  if (select estado from public.mensagens where chave_idem='lgpd1') <> 'cancelada' then
    raise exception '5 FUROU: mensagem pendente sobreviveu'; end if;

  if (select count(*) from public.sessoes where paciente_id=maria) <> 1 then
    raise exception '6 FUROU: apagou o registro clínico'; end if;

  -- ---------------------------------------------------------------- 7
  falhou := false;
  begin perform public.arquivar_paciente(maria, 'ok');
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: arquivou sem encerramento'; end if;

  select public.arquivar_paciente(maria, 'Alta por objetivos alcançados, combinada em sessão.') into r;
  if r <> 'arquivada' then raise exception '7 FUROU: %', r; end if;

  -- ---------------------------------------------------------------- 8
  falhou := false;
  begin update public.pacientes set estado='em_atendimento' where id=maria;
  exception when others then falhou := true; end;
  if not falhou then raise exception '8 FUROU: desarquivou'; end if;

  falhou := false;
  begin update public.pacientes set nome='Outro Nome' where id=maria;
  exception when others then falhou := true; end;
  if not falhou then raise exception '8 FUROU: editou ficha arquivada'; end if;

  -- ---------------------------------------------------------------- 9
  update public.pacientes set restricao_judicial=true where id=maria;
  if not (select restricao_judicial from public.pacientes where id=maria) then
    raise exception '9 FUROU: não deu para anotar a restrição'; end if;

  -- ---------------------------------------------------------------- 10
  delete from public.pacientes where id=maria;
  if (select count(*) from public.pacientes where id=maria) <> 1 then
    raise exception '10 FUROU: apagou o paciente'; end if;

  -- ---------------------------------------------------------------- 11
  select public.exportar_conta() into j;
  if jsonb_array_length(j->'pacientes') <> 2 then raise exception '11 FUROU: pacientes'; end if;
  if not (j ? 'trilha_acesso') then raise exception '11 FUROU: sem trilha na exportação'; end if;
  if (select count(*) from public.trilha_acesso where acao='exportou_conta') <> 1 then
    raise exception '11 FUROU: não registrou'; end if;

  -- ---------------------------------------------------------------- 12
  select count(*) into n from public.elegiveis_para_eliminacao();
  if n <> 0 then raise exception '12 FUROU: listou % como elegível hoje', n; end if;

  -- ---------------------------------------------------------------- 13
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.trilha_acesso;
  if n <> 0 then raise exception '13 FUROU: B leu a trilha de A'; end if;
  falhou := false;
  begin perform public.exportar_paciente(maria, true);
  exception when others then falhou := true; end;
  if not falhou then raise exception '13 FUROU: B exportou paciente de A'; end if;
  select public.exportar_conta() into j;
  if jsonb_array_length(j->'pacientes') <> 0 then raise exception '13 FUROU: exportação de B trouxe gente de A'; end if;

  -- ---------------------------------------------------------------- 14
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.trilha_acesso;
  if n <> 0 then raise exception '14 FUROU: anon leu a trilha'; end if;
  falhou := false;
  begin perform public.exportar_conta();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '14 FUROU: anon exportou'; end if;
  falhou := false;
  begin perform public.expurgar_mensagens(180);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '14 FUROU: anon expurgou'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.trilha_acesso where conta_id in (a_conta,b_conta);
  delete from public.mensagens where conta_id in (a_conta,b_conta);
  delete from public.sessoes where conta_id in (a_conta,b_conta);
  delete from public.pacientes where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B13 OK — 14 verificações, todas passaram';
end $$;
