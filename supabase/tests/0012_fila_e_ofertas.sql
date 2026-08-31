-- Teste do motor da fila (critério de pronto da B7).
--
-- Reproduz a cascata do protótipo com dados reais e cobre os cenários que o
-- roadmap exige, mais os que apareceram construindo:
--
--   1. só horário cancelado vira vaga
--   2. elegibilidade **explicável**: todo mundo aparece, com o motivo
--   3. a cascata começa por quem está há mais tempo sem sessão
--   4. uma oferta viva por vaga
--   5. recusa faz a fila andar, e quem recusou passa a ter motivo
--   6. o aceite cria o encaixe com o preço do **próprio** paciente
--   7. oferta já respondida não aceita de novo
--   8. a métrica norte sai dos eventos, sem instrumentação extra
--   9. a trilha conta a história inteira
--  10. janela de silêncio: 23h30 vira 8h do dia seguinte
--  11. expiração faz a fila andar
--  12. fila esgotada registra sem_takers e não inventa encaixe
--  13. quem já recebeu a vaga não recebe de novo
--  14. a reivindicação do aceite é atômica (row_count)
--  15. dois aceites: o segundo erra
--  16. duas pessoas na mesma hora é impossível (restrição de exclusão)
--  17. vaga preenchida deixa de constar livre
--  18. férias tornam a hora indisponível para a fila
--  19. duas ofertas vivas na mesma vaga é impossível (índice parcial)
--  20–26. isolamento entre contas e contra o anônimo
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0012_fila_e_ofertas.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; joao uuid; bia uuid; rafael uuid; b_pac uuid;
  vaga uuid; vaga16 uuid; vaga18 uuid; of1 uuid; of2 uuid; o uuid;
  r text; n int; ganhou int; m record; alvo uuid; primeiro uuid; segundo uuid;
  terca timestamptz; terca16 timestamptz; sexta timestamptz;
  base timestamptz; quando timestamptz; livre boolean; falhou boolean;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.ofertas      where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.sessoes      where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.excecoes_agenda where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.enquadres    where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes    where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from auth.users where id in (a_auth, b_auth);
  delete from public.contas where nome in ('Ana Solo','Bruna Solo');

  insert into auth.users (id,email,raw_user_meta_data)
  values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- Terça 15h de uma semana futura. O `::timestamp` força a sobrecarga sem
  -- fuso do date_trunc — sem ele, o TimeZone da conexão entra na conta (0013).
  terca := ((date_trunc('week', ((now() at time zone 'America/Sao_Paulo')::date + 8)::timestamp)
             + interval '1 day' + interval '15 hours')::timestamp) at time zone 'America/Sao_Paulo';
  terca16 := terca + interval '1 hour';
  sexta   := terca + interval '3 days' + interval '3 hours';

  if extract(dow from (terca at time zone 'America/Sao_Paulo')) <> 2
     or (terca at time zone 'America/Sao_Paulo')::time <> time '15:00' then
    raise exception 'PREPARO: terça mal construída';
  end if;

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Fernanda Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'João Pedro Salles','5511900000003','em_atendimento') returning id into joao;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Bia Nogueira','5511900000004','em_atendimento') returning id into bia;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Rafael Tomé','5511900000005','pausa') returning id into rafael;

  -- João cobra R$ 180: ao entrar na vaga, paga o próprio combinado.
  insert into public.enquadres (paciente_id,dia_semana,hora,valor) values (joao,5,'10:00',180.00);

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,terca,terca+interval '50 min','avulsa',200.00,24,50) returning id into vaga;

  -- Caio está há mais tempo sem sessão que João.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
  values (a_conta,a_prof,caio, now()-interval '11 days', now()-interval '11 days'+interval '50 min','avulsa','realizada',200.00);
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
  values (a_conta,a_prof,joao, now()-interval '6 days', now()-interval '6 days'+interval '50 min','avulsa','realizada',180.00);

  insert into public.fila_encaixe (paciente_id,janelas) values (caio, '[{"dias":[2,3],"de":"13:00"}]'::jsonb);
  insert into public.fila_encaixe (paciente_id,janelas) values (joao, '[{"de":"14:00"}]'::jsonb);
  insert into public.fila_encaixe (paciente_id,janelas) values (bia,  '[{"de":"07:00","ate":"12:00"}]'::jsonb);
  insert into public.fila_encaixe (paciente_id) values (rafael);

  -- ---------------------------------------------------------------- 1
  begin
    perform public.abrir_vaga(vaga);
    raise exception '1 FUROU: abriu vaga de sessão não cancelada';
  exception when others then
    if sqlerrm not like '%cancelado%' then raise; end if;
  end;

  perform public.cancelar_sessao(vaga, 'paciente');

  -- ---------------------------------------------------------------- 2
  select count(*) into n from public.elegiveis_para_vaga(vaga);
  if n <> 4 then raise exception '2 FUROU: fila devolveu % linhas', n; end if;
  if (select motivo from public.elegiveis_para_vaga(vaga) where paciente_id=bia) <> 'fora da janela'
    then raise exception '2 FUROU: motivo da Bia'; end if;
  if (select motivo from public.elegiveis_para_vaga(vaga) where paciente_id=rafael) <> 'em pausa'
    then raise exception '2 FUROU: motivo do Rafael'; end if;
  select count(*) into n from public.elegiveis_para_vaga(vaga) where elegivel;
  if n <> 2 then raise exception '2 FUROU: % elegíveis (esperado 2)', n; end if;

  -- ---------------------------------------------------------------- 3 e 4
  select public.abrir_vaga(vaga) into of1;
  if of1 is null then raise exception '3 FUROU: não ofertou'; end if;
  select paciente_id into alvo from public.ofertas where id=of1;
  if alvo <> caio then raise exception '3 FUROU: não começou por quem está há mais tempo sem sessão'; end if;

  select count(*) into n from public.ofertas where sessao_id=vaga and estado='enviada';
  if n <> 1 then raise exception '4 FUROU: % ofertas vivas', n; end if;
  if public.avancar_fila(vaga) is not null then raise exception '4 FUROU: criou segunda oferta viva'; end if;

  -- ---------------------------------------------------------------- 5
  select public.responder_oferta(of1,'recusada') into r;
  if r <> 'recusada' then raise exception '5 FUROU: %', r; end if;
  select id, paciente_id into of2, alvo from public.ofertas where sessao_id=vaga and estado='enviada';
  if of2 is null then raise exception '5 FUROU: a fila não andou'; end if;
  if alvo <> joao then raise exception '5 FUROU: não foi para o João'; end if;
  if (select motivo from public.elegiveis_para_vaga(vaga) where paciente_id=caio) <> 'já recusou esta vaga'
    then raise exception '5 FUROU: motivo do Caio'; end if;

  -- ---------------------------------------------------------------- 6 e 7
  if public.responder_oferta(of2,'aceita') <> 'aceita' then raise exception '6 FUROU'; end if;
  select count(*) into n from public.sessoes
   where paciente_id=joao and origem='encaixe' and inicio=terca and valor=180.00;
  if n <> 1 then raise exception '6 FUROU: encaixe não saiu com o preço do próprio João'; end if;

  begin
    perform public.responder_oferta(of2,'aceita');
    raise exception '7 FUROU: aceitou duas vezes';
  exception when others then
    if sqlerrm not like '%respondida%' then raise; end if;
  end;

  -- ---------------------------------------------------------------- 8 e 9
  select * into m from public.taxa_de_preenchimento(
    (now() at time zone 'America/Sao_Paulo')::date - 1,
    (now() at time zone 'America/Sao_Paulo')::date + 1);
  if m.canceladas<>1 or m.oferecidas<>1 or m.preenchidas<>1 or m.taxa<>100.0 then
    raise exception '8 FUROU: c=% o=% p=% t=%', m.canceladas,m.oferecidas,m.preenchidas,m.taxa; end if;

  select count(*) into n from public.eventos_fila where sessao_id=vaga;
  if n < 5 then raise exception '9 FUROU: só % eventos', n; end if;

  -- ---------------------------------------------------------------- 10
  base := (timestamp '2026-09-08 23:30')::timestamp at time zone 'America/Sao_Paulo';
  quando := public.proximo_envio(a_conta, base);
  if (quando at time zone 'America/Sao_Paulo')::time <> time '08:00'
     or (quando at time zone 'America/Sao_Paulo')::date <> date '2026-09-09' then
    raise exception '10 FUROU: oferta das 23h30 sairia %', (quando at time zone 'America/Sao_Paulo'); end if;

  base := (timestamp '2026-09-09 03:00')::timestamp at time zone 'America/Sao_Paulo';
  quando := public.proximo_envio(a_conta, base);
  if (quando at time zone 'America/Sao_Paulo')::date <> date '2026-09-09'
     or (quando at time zone 'America/Sao_Paulo')::time <> time '08:00' then
    raise exception '10 FUROU: 3h da manhã'; end if;

  base := (timestamp '2026-09-09 15:00')::timestamp at time zone 'America/Sao_Paulo';
  if public.proximo_envio(a_conta, base) <> base then
    raise exception '10 FUROU: adiou uma oferta das 15h'; end if;

  -- ---------------------------------------------------------------- 11, 12 e 13
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,terca16,terca16+interval '50 min','avulsa',200.00,24,50) returning id into vaga16;
  perform public.cancelar_sessao(vaga16,'paciente');

  select count(*) into n from public.elegiveis_para_vaga(vaga16) where elegivel;
  if n <> 2 then raise exception '11 PREPARO: % elegíveis (esperado 2)', n; end if;

  select public.abrir_vaga(vaga16) into o;
  select paciente_id into primeiro from public.ofertas where id=o;

  update public.ofertas set enviar_em=now()-interval '2 hours', expira_em=now()-interval '1 hour' where id=o;
  select public.expirar_ofertas() into n;
  if n < 1 then raise exception '11 FUROU: nada expirou'; end if;
  if (select estado from public.ofertas where id=o) <> 'expirada' then
    raise exception '11 FUROU: não marcou expirada'; end if;
  select paciente_id into segundo from public.ofertas where sessao_id=vaga16 and estado='enviada';
  if segundo is null then raise exception '11 FUROU: a fila não andou após expirar'; end if;
  if segundo = primeiro then raise exception '11 FUROU: reofertou para o mesmo'; end if;

  loop
    select id into o from public.ofertas where sessao_id=vaga16 and estado='enviada';
    exit when o is null;
    perform public.responder_oferta(o,'recusada');
  end loop;

  if not exists (select 1 from public.eventos_fila where sessao_id=vaga16 and tipo='vaga_sem_takers') then
    raise exception '12 FUROU: esgotou sem registrar sem_takers'; end if;
  if exists (select 1 from public.sessoes where inicio=terca16 and origem='encaixe') then
    raise exception '12 FUROU: criou encaixe sem aceite'; end if;
  if public.avancar_fila(vaga16) is not null then
    raise exception '13 FUROU: ofertou de novo a quem já recusou'; end if;

  -- ---------------------------------------------------------------- 14 a 19
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,sexta,sexta+interval '50 min','avulsa',200.00,24,50) returning id into vaga18;
  perform public.cancelar_sessao(vaga18,'paciente');
  select public.abrir_vaga(vaga18) into o;
  if o is null then raise exception '14 PREPARO: não ofertou'; end if;

  update public.ofertas set estado='aceita', respondida_em=now() where id=o and estado='enviada';
  get diagnostics ganhou = row_count;
  if ganhou <> 1 then raise exception '14 FUROU: o primeiro não reivindicou'; end if;
  update public.ofertas set estado='aceita', respondida_em=now() where id=o and estado='enviada';
  get diagnostics ganhou = row_count;
  if ganhou <> 0 then raise exception '14 FUROU: o segundo também reivindicou'; end if;
  update public.ofertas set estado='enviada', respondida_em=null where id=o;

  if public.responder_oferta(o,'aceita') <> 'aceita' then raise exception '15 FUROU'; end if;
  begin
    perform public.responder_oferta(o,'aceita');
    raise exception '15 FUROU: dois aceites passaram';
  exception when others then
    if sqlerrm not like '%respondida%' then raise; end if;
  end;

  begin
    insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor)
    values (a_conta,a_prof,caio,sexta,sexta+interval '50 min','encaixe',200.00);
    raise exception '16 FUROU: duas pessoas na mesma hora';
  exception when exclusion_violation then null; end;

  select public.vaga_esta_livre(a_prof, sexta, sexta+interval '50 min', vaga18) into livre;
  if livre then raise exception '17 FUROU: horário preenchido ainda consta livre'; end if;

  insert into public.excecoes_agenda (profissional_id,tipo,inicio,fim)
  values (a_prof,'ferias',(sexta at time zone 'America/Sao_Paulo')::date + 30,
                          (sexta at time zone 'America/Sao_Paulo')::date + 40);
  select public.vaga_esta_livre(a_prof,
      ((sexta at time zone 'America/Sao_Paulo')::date + 32 + time '10:00') at time zone 'America/Sao_Paulo',
      ((sexta at time zone 'America/Sao_Paulo')::date + 32 + time '10:50') at time zone 'America/Sao_Paulo')
    into livre;
  if livre then raise exception '18 FUROU: a fila ofereceria hora dentro das férias'; end if;
  delete from public.excecoes_agenda where profissional_id=a_prof;

  begin
    insert into public.ofertas (conta_id,sessao_id,paciente_id,expira_em)
    values (a_conta,vaga18,caio,now()+interval '1 hour');
    insert into public.ofertas (conta_id,sessao_id,paciente_id,expira_em)
    values (a_conta,vaga18,joao,now()+interval '1 hour');
    raise exception '19 FUROU: duas ofertas vivas na mesma vaga';
  exception when unique_violation then null; end;

  -- ---------------------------------------------------------------- 20 a 26
  reset role;
  perform set_config('request.jwt.claims','',true);
  insert into auth.users (id,email,raw_user_meta_data)
  values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bruna Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;
  select id into b_prof from public.profissionais where conta_id=b_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.pacientes (profissional_id,nome,telefone) values (b_prof,'Paciente da Bruna','5511911110000') returning id into b_pac;

  select count(*) into n from public.fila_encaixe; if n<>0 then raise exception '20 FUROU: fila (%)', n; end if;
  select count(*) into n from public.ofertas;      if n<>0 then raise exception '20 FUROU: ofertas (%)', n; end if;
  select count(*) into n from public.eventos_fila; if n<>0 then raise exception '20 FUROU: eventos (%)', n; end if;

  select count(*) into n from public.elegiveis_para_vaga(vaga);
  if n<>0 then raise exception '21 FUROU: elegíveis vazou % linhas', n; end if;

  falhou := false;
  begin perform public.abrir_vaga(vaga16); falhou := true; exception when others then null; end;
  if falhou then raise exception '22 FUROU: B abriu vaga da A'; end if;

  falhou := false;
  begin perform public.responder_oferta(of1,'aceita'); falhou := true; exception when others then null; end;
  if falhou then raise exception '23 FUROU: B respondeu oferta da A'; end if;

  -- com o uuid do paciente da A na mão, o gatilho recusa
  falhou := false;
  begin insert into public.fila_encaixe (paciente_id) values (caio); falhou := true;
  exception when others then
    if sqlerrm not like '%outra conta%' then raise; end if;
  end;
  if falhou then raise exception '24 FUROU: B plantou paciente da A na fila'; end if;

  -- e a sonda da agenda alheia responde sobre o vazio (0015)
  if not public.vaga_esta_livre(a_prof, terca, terca+interval '50 min') then
    raise exception '24b FUROU: B enxergou a agenda da A'; end if;

  if (select canceladas from public.taxa_de_preenchimento(
        (now() at time zone 'America/Sao_Paulo')::date - 30,
        (now() at time zone 'America/Sao_Paulo')::date + 1)) <> 0 then
    raise exception '25 FUROU: a métrica de B contou vaga da A'; end if;

  reset role;
  perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.fila_encaixe; if n<>0 then raise exception '26 FUROU: anon leu fila'; end if;
  select count(*) into n from public.ofertas;      if n<>0 then raise exception '26 FUROU: anon leu ofertas'; end if;
  select count(*) into n from public.eventos_fila; if n<>0 then raise exception '26 FUROU: anon leu eventos'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role;
  perform set_config('request.jwt.claims','',true);
  delete from public.eventos_fila where conta_id in (a_conta,b_conta);
  delete from public.ofertas      where conta_id in (a_conta,b_conta);
  delete from public.fila_encaixe where conta_id in (a_conta,b_conta);
  delete from public.sessoes      where conta_id in (a_conta,b_conta);
  delete from public.excecoes_agenda where conta_id in (a_conta,b_conta);
  delete from public.enquadres    where conta_id in (a_conta,b_conta);
  delete from public.pacientes    where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B7 OK — 26 verificações, todas passaram';
end $$;
