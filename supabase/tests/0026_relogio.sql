-- Teste do relógio (o que fecha a fase 1).
--
-- Não é teste de lógica nova: é teste de peças corretas que não tinham quem
-- lhes desse corda. Auditando o repositório antes da fase 2, quatro rotinas só
-- rodavam quando alguém clicava num botão — e nenhuma suíte pegou isso, porque
-- teste de função não pergunta *quem chama a função*.
--
--   1. o lembrete só entra para sessão dentro da janela e para quem quer receber
--   2. e sai na antecedência combinada, não agora
--   3. rodar de novo não duplica
--   4. desmarcar a sessão cancela o lembrete antes que ele saia
--   5. a expiração faz a fila andar sem ninguém olhando
--   6. materializar_tudo funciona sem conta na sessão (é do cron)
--   7. materializar_conta continua exigindo conta (é da tela)
--   8. nem a pessoa logada nem o anônimo dão corda no relógio
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0026_relogio.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid; caio uuid; calado uuid;
  s1 uuid; s2 uuid; s3 uuid; of1 uuid; n int; m record; falhou boolean;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ofertas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome='Ana Solo');
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
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado,msg_canal) values (a_prof,'Teresa Quieta','5511900000003','em_atendimento','nao_avisar') returning id into calado;

  -- daqui a 30h (dentro da janela de 24+24), 5 dias (fora), 32h mas caladinha
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria, now()+interval '30 hours', now()+interval '30 hours 50 min','avulsa',200,24,50) returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,caio, now()+interval '5 days', now()+interval '5 days 50 min','avulsa',200,24,50) returning id into s2;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,calado, now()+interval '32 hours', now()+interval '32 hours 50 min','avulsa',200,24,50) returning id into s3;

  -- Daqui para baixo é o cron: service_role, sem conta na sessão.
  reset role; perform set_config('request.jwt.claims','',true);

  -- ---------------------------------------------------------------- 1
  select public.agendar_lembretes() into n;
  if n <> 1 then raise exception '1 FUROU: agendou % (esperado 1)', n; end if;
  if (select count(*) from public.mensagens where chave_idem='lembrete:'||s2::text) <> 0 then
    raise exception '1 FUROU: agendou sessão de 5 dias'; end if;
  if (select count(*) from public.mensagens where chave_idem='lembrete:'||s3::text) <> 0 then
    raise exception '1 FUROU: agendou para quem pediu para não ser avisado'; end if;

  -- ---------------------------------------------------------------- 2
  select * into m from public.mensagens where chave_idem='lembrete:'||s1::text;
  if m.agendada_para > now() + interval '8 hours' or m.agendada_para < now() + interval '4 hours' then
    raise exception '2 FUROU: agendado para % (esperado ~6h)', m.agendada_para; end if;
  if m.template <> 'lembrete_de_sessao' then raise exception '2 FUROU: template %', m.template; end if;

  -- ---------------------------------------------------------------- 3
  select public.agendar_lembretes() into n;
  if n <> 0 then raise exception '3 FUROU: duplicou %', n; end if;
  if (select count(*) from public.mensagens where chave_idem='lembrete:'||s1::text) <> 1 then
    raise exception '3 FUROU: duas linhas para a mesma sessão'; end if;

  -- ---------------------------------------------------------------- 4
  -- "Lembrete do seu horário" chegando para quem desmarcou é o tipo de erro que
  -- faz a pessoa deixar de confiar em tudo o que vem depois.
  perform public.cancelar_sessao(s1,'paciente');
  if (select estado from public.mensagens where chave_idem='lembrete:'||s1::text) <> 'cancelada' then
    raise exception '4 FUROU: o lembrete de uma sessão desmarcada ainda vai sair'; end if;

  -- ---------------------------------------------------------------- 5
  insert into public.fila_encaixe (paciente_id) values (caio);
  select public.abrir_vaga(s1) into of1;
  if of1 is null then raise exception '5 FUROU: não ofertou'; end if;
  update public.ofertas
     set enviar_em = now() - interval '2 hours', expira_em = now() - interval '1 minute'
   where id = of1;
  select public.expirar_ofertas() into n;
  if n <> 1 then raise exception '5 FUROU: expirou %', n; end if;
  if (select estado from public.ofertas where id=of1) <> 'expirada' then
    raise exception '5 FUROU: não expirou'; end if;

  -- ---------------------------------------------------------------- 6 e 7
  select public.materializar_tudo() into n;
  if n is null then raise exception '6 FUROU: materializar_tudo devolveu null'; end if;

  falhou := false;
  begin perform public.materializar_conta();
  exception when others then falhou := true; end;
  if not falhou then raise exception '7 FUROU: materializar_conta rodou sem conta'; end if;

  -- ---------------------------------------------------------------- 8
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  falhou := false;
  begin perform public.materializar_tudo();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '8 FUROU: authenticated materializou tudo'; end if;

  falhou := false;
  begin perform public.agendar_lembretes();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '8 FUROU: authenticated agendou lembretes'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  falhou := false;
  begin perform public.agendar_lembretes();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '8 FUROU: anon agendou lembretes'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.cobrancas where conta_id=a_conta;
  delete from public.mensagens where conta_id=a_conta;
  delete from public.eventos_fila where conta_id=a_conta;
  delete from public.ofertas where conta_id=a_conta;
  delete from public.fila_encaixe where conta_id=a_conta;
  delete from public.sessoes where conta_id=a_conta;
  delete from public.enquadres where conta_id=a_conta;
  delete from public.pacientes where conta_id=a_conta;
  delete from auth.users where id=a_auth;
  delete from public.contas where id=a_conta;

  raise notice 'relógio OK — 8 verificações, todas passaram';
end $$;
