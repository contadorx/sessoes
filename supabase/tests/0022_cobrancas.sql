-- Teste da cobrança de falta — **reescrito pelo P4 (migração 0058)**.
--
-- Esta suíte chamava-se, e a migração ainda se chama, "a política se aplica
-- sozinha". Ela provava exatamente isso: que cancelar em cima da hora fazia
-- nascer cobrança e enfileirar aviso, sem ninguém tocar em nada. Passava, e
-- estava certa sobre o código.
--
-- O P4 desfez o comportamento por razão ética, e por isso **esta suíte não
-- podia continuar verde**: um teste que segue passando depois de uma mudança de
-- comportamento é um teste que não estava testando o comportamento. A
-- verificação 1 agora prova o contrário do que provava, e é a única linha desta
-- suíte que mudou de sinal.
--
-- **O que sobreviveu inteiro, e é a maior parte:** a aritmética da multa com a
-- política congelada na sessão; a hora de silêncio antes do aviso; o perdão que
-- marca e não apaga; o desfazer que cancela cobrança *e* aviso; as transições
-- de `mensagens` que a 0023 fechou; o isolamento entre contas. Nada disso era
-- sobre quem decide — era sobre acertar a conta e não vazar. Continua valendo.
--
-- A régua automática só era aceitável se o freio funcionasse. Agora não há
-- régua automática, e metade das verificações continua sendo sobre **não**
-- cobrar — só que agora o padrão está do lado certo.
--
--   1. cancelar tarde **não** cobra: faz uma pergunta        ← inverteu
--   2. e não sai mensagem nenhuma antes da decisão           ← inverteu
--   3. decidir cobrar gera a cobrança com a política congelada
--   4. o aviso é enfileirado, mas não para agora — sobrou espaço para desfazer
--   5. perdoar segura o aviso que ainda não saiu
--   6. perdoar duas vezes não é possível
--   7. quem avisou no prazo não é cobrado nem perguntado
--   8. política de 0% não gera cobrança nem pergunta
--   9. não vir é desmarcar com zero hora: mesma conta, mesmo caminho
--  10. desfazer cancela a cobrança E o aviso
--  11. refazer pergunta de novo, sem esbarrar no índice
--  12. o mesmo estado de novo não duplica nada
--  13. a política de "segurar mensagem" (0023) não vira porta dos fundos
--  14. isolamento entre contas
--  15. o anônimo não lê nem executa
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0022_cobrancas.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  maria uuid; caio uuid; livre uuid;
  s1 uuid; s2 uuid; s3 uuid; cob uuid; cob2 uuid; mid uuid;
  prop uuid; j jsonb;
  base timestamptz; n int; r text; c record; falhou boolean; msg record;
begin
  -- ---------------------------------------------------------------- preparo
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.propostas_de_cobranca where conta_id in (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
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

  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Maria Reis','5511900000001','em_atendimento') returning id into maria;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Caio Nogueira','5511900000002','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado) values (a_prof,'Livre Silva','5511900000003','em_atendimento') returning id into livre;

  -- Daqui a 3 horas, com política de 24h: cancelar agora é tardio.
  base := now() + interval '3 hours';

  -- ---------------------------------------------------------------- 1
  -- A verificação que mudou de sinal.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,maria,base,base+interval '50 min','avulsa',200.00,24,50) returning id into s1;
  perform public.cancelar_sessao(s1,'paciente');

  select count(*) into n from public.cobrancas where sessao_id=s1;
  if n <> 0 then raise exception '1 FUROU: a cobrança nasceu sozinha — o P4 tirou essa decisão do software'; end if;

  select * into c from public.propostas_de_cobranca where sessao_id=s1;
  if not found then raise exception '1 FUROU: não gerou nem a pergunta'; end if;
  if c.valor_sugerido <> 100.00 then raise exception '1 FUROU: sugeriu %', c.valor_sugerido; end if;
  if c.politica_percentual <> 50 or c.valor_da_sessao <> 200.00 then
    raise exception '1 FUROU: não guardou o retrato da política'; end if;
  prop := c.id;

  -- ---------------------------------------------------------------- 2
  select count(*) into n from public.mensagens
   where conta_id=a_conta and template='aviso_de_cobranca';
  if n <> 0 then raise exception '2 FUROU: % aviso(s) na fila sem decisão nenhuma', n; end if;

  -- ---------------------------------------------------------------- 3
  j := public.decidir_cobranca(prop,'cobrar');
  cob := (j->>'cobranca_id')::uuid;

  select * into c from public.cobrancas where id=cob;
  if c.valor <> 100.00 then raise exception '3 FUROU: valor %', c.valor; end if;
  if c.politica_percentual <> 50 or c.valor_da_sessao <> 200.00 then
    raise exception '3 FUROU: o retrato da política não atravessou a decisão'; end if;
  if c.proposta_id <> prop then raise exception '3 FUROU: a cobrança não aponta para a decisão'; end if;

  -- ---------------------------------------------------------------- 4
  select * into msg from public.mensagens where chave_idem = 'cobranca:'||cob::text;
  if not found then raise exception '4 FUROU: não enfileirou o aviso'; end if;
  if msg.template <> 'aviso_de_cobranca' then raise exception '4 FUROU: template %', msg.template; end if;
  -- A hora de silêncio da B11 sobreviveu ao P4 com razão nova: já não é janela
  -- de perdão — o perdão agora vem antes —, é o tempo de desfazer um clique.
  if msg.agendada_para < now() + interval '50 minutes' then
    raise exception '4 FUROU: o aviso sai em cima da decisão'; end if;
  if (msg.params->>'valor_centavos')::bigint <> 10000 then raise exception '4 FUROU: centavos'; end if;

  -- ---------------------------------------------------------------- 5
  select public.perdoar_cobranca(cob,'primeira vez') into r;
  if r <> 'perdoada' then raise exception '5 FUROU: %', r; end if;
  if (select estado from public.mensagens where chave_idem='cobranca:'||cob::text) <> 'cancelada' then
    raise exception '5 FUROU: o aviso ainda vai sair'; end if;
  if (select perdoada_motivo from public.cobrancas where id=cob) is null then
    raise exception '5 FUROU: o motivo do perdão foi para o lixo (dívida da B11, consertada pela 0058)'; end if;

  -- ---------------------------------------------------------------- 6
  falhou := false;
  begin perform public.perdoar_cobranca(cob);
  exception when others then falhou := true; end;
  if not falhou then raise exception '6 FUROU: perdoou duas vezes'; end if;

  -- ---------------------------------------------------------------- 7
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,caio, now()+interval '5 days', now()+interval '5 days'+interval '50 min','avulsa',200.00,24,50) returning id into s2;
  perform public.cancelar_sessao(s2,'paciente');
  select count(*) into n from public.cobrancas where sessao_id=s2;
  if n <> 0 then raise exception '7 FUROU: cobrou quem avisou no prazo'; end if;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s2;
  if n <> 0 then raise exception '7 FUROU: perguntou sobre quem avisou no prazo'; end if;

  -- ---------------------------------------------------------------- 8
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,valor,politica_horas,politica_percentual)
  values (a_conta,a_prof,livre,base+interval '1 hour',base+interval '1 hour 50 min','avulsa',200.00,24,0) returning id into s3;
  perform public.cancelar_sessao(s3,'paciente');
  select count(*) into n from public.cobrancas where sessao_id=s3;
  if n <> 0 then raise exception '8 FUROU: gerou cobrança zerada'; end if;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s3;
  if n <> 0 then raise exception '8 FUROU: perguntou "quer cobrar R$ 0,00?"'; end if;

  -- ---------------------------------------------------------------- 9
  update public.sessoes set estado='prevista' where id=s2;
  update public.sessoes set inicio = now()-interval '2 hours', fim = now()-interval '1 hour' where id=s2;
  update public.sessoes set estado='falta' where id=s2;

  select id into prop from public.propostas_de_cobranca where sessao_id=s2 and estado='pendente';
  if prop is null then raise exception '9 FUROU: a falta não virou pergunta'; end if;

  j := public.decidir_cobranca(prop,'cobrar');
  cob2 := (j->>'cobranca_id')::uuid;
  select * into c from public.cobrancas where id=cob2;
  if c.valor <> 100.00 then raise exception '9 FUROU: valor %', c.valor; end if;
  if c.motivo <> 'falta' then raise exception '9 FUROU: motivo %', c.motivo; end if;

  -- ---------------------------------------------------------------- 10
  update public.sessoes set estado='realizada' where id=s2;
  if (select estado from public.cobrancas where id=cob2) <> 'cancelada' then
    raise exception '10 FUROU: a cobrança sobreviveu ao desfazer'; end if;
  if (select estado from public.mensagens where chave_idem='cobranca:'||cob2::text) <> 'cancelada' then
    raise exception '10 FUROU: o aviso ainda vai sair depois do desfazer'; end if;

  -- ---------------------------------------------------------------- 11 e 12
  update public.sessoes set estado='falta' where id=s2;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s2;
  if n <> 2 then raise exception '11 FUROU: % perguntas na trilha (esperado 2)', n; end if;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s2 and estado='pendente';
  if n <> 1 then raise exception '11 FUROU: % perguntas vivas', n; end if;

  update public.sessoes set estado='falta' where id=s2;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s2 and estado='pendente';
  if n <> 1 then raise exception '12 FUROU: duplicou'; end if;

  -- ---------------------------------------------------------------- 13
  -- A 0023 abriu **uma** transição para o app: pendente → cancelada. Nem uma
  -- a mais.
  select id into mid from public.mensagens where conta_id=a_conta and estado='cancelada' limit 1;
  update public.mensagens set estado='pendente' where id=mid;
  if (select estado from public.mensagens where id=mid) = 'pendente' then
    raise exception '13 FUROU: ressuscitou mensagem cancelada'; end if;

  select public.enfileirar_mensagem(livre,'lembrete_de_sessao','z9') into mid;
  falhou := false;
  begin
    update public.mensagens set estado='enviada', provedor='forjado' where id=mid;
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception '13 FUROU: o app marcou mensagem como enviada'; end if;

  update public.mensagens set estado='cancelada' where id=mid;
  if (select estado from public.mensagens where id=mid) <> 'cancelada' then
    raise exception '13 FUROU: não deu para segurar o envio'; end if;

  -- ---------------------------------------------------------------- 14
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.cobrancas;
  if n <> 0 then raise exception '14 FUROU: B viu % cobranças de A', n; end if;
  select count(*) into n from public.propostas_de_cobranca;
  if n <> 0 then raise exception '14 FUROU: B viu % decisões pendentes de A', n; end if;

  select id into prop from public.propostas_de_cobranca where estado='pendente' limit 1;
  falhou := false;
  begin perform public.decidir_cobranca(coalesce(prop, gen_random_uuid()),'cobrar');
  exception when others then falhou := true; end;
  if not falhou then raise exception '14 FUROU: B decidiu cobrança de A'; end if;

  -- ---------------------------------------------------------------- 15
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';
  select count(*) into n from public.cobrancas;
  if n <> 0 then raise exception '15 FUROU: anon leu cobranças'; end if;
  select count(*) into n from public.propostas_de_cobranca;
  if n <> 0 then raise exception '15 FUROU: anon leu propostas'; end if;
  falhou := false;
  begin perform public.decidir_cobranca(gen_random_uuid(),'cobrar');
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '15 FUROU: anon decidiu uma cobrança'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.propostas_de_cobranca where conta_id in (a_conta,b_conta);
  delete from public.cobrancas where conta_id in (a_conta,b_conta);
  delete from public.mensagens where conta_id in (a_conta,b_conta);
  delete from public.sessoes where conta_id in (a_conta,b_conta);
  delete from public.pacientes where conta_id in (a_conta,b_conta);
  delete from auth.users where id in (a_auth,b_auth);
  delete from public.contas where id in (a_conta,b_conta);

  raise notice 'B11 + P4 OK — 15 verificações, todas passaram';
end $$;
