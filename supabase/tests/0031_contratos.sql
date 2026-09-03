-- Teste do contrato terapêutico com aceite datado (critério de pronto da B19).
--
-- O que este arquivo tenta fazer, linha por linha, é **forjar uma prova**. É a
-- postura certa: o valor inteiro do build está em que a frase "ela aceitou este
-- texto neste instante" seja verdadeira mesmo quando quem afirma tem interesse
-- em que seja. Um contrato que o interessado consegue editar depois não é
-- lastro — é uma captura de tela com aparência de documento.
--
--   1. corpo sem {{politica}} é recusado — o portão do doc 07 como código
--   2. corpo sem {{valor}} é recusado
--   3. o texto sai montado com o valor e a política reais do combinado
--   4. publicar de novo abre a versão 2; a 1 continua lá
--   5. contrato publicado não se edita
--   6. o token não é escolhido pelo cliente
--   7. o texto e o retrato também não são
--   8. token inexistente e token malformado não vazam nada
--   9. o visitante aceita pelo link; origem sai 'link' e a trilha registra
--  10. o link devolve o mínimo — e `anon` não lê a tabela por baixo
--  11. antedatar é impossível: o relógio é do servidor
--  12. quem tem sessão só consegue gravar 'presencial'
--  13. aceite dado não se edita
--  14. link expirado se declara expirado e não aceita
--  15. dois aceites vivos no mesmo combinado: impossível
--  16. revogar preserva a linha e a data
--  17. revogado não volta atrás
--  18. combinado encerrado não aceita — o reajuste perde o lastro de propósito
--  19. a conta B não enxerga, não revoga e não prepara na conta A
--  20. sem aceite, nada é bloqueado: a falta continua cobrando
--  21. reais() bate com o Intl do navegador, inclusive o espaço fino
--  22. anon não publica, não prepara, não revoga, não monta
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0031_contratos.sql

-- ============================================ parte 1 · o modelo e a montagem

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid; enq uuid;
  c1 uuid; c2 uuid; tok text; t text; n numeric; ok boolean;
  corpo text;
begin
  corpo :=
    'Combinado de atendimento entre {{profissional}} (CRP {{crp}}) e {{nome}}. ' ||
    'Os encontros acontecem {{horario}}, com duração de {{duracao}}. ' ||
    'O valor de cada encontro é {{valor}}. Sobre desmarcar: {{politica}}. ' ||
    'Este combinado vale a partir de {{data}}, em {{cidade}}, e pode ser ' ||
    'revisto por qualquer uma das partes a qualquer momento.';

  delete from public.aceites where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.contratos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data)
    values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  update public.profissionais set assina_como='Ana Ferreira', crp='06/123456' where id=a_prof;
  update public.contas set cidade='São Paulo' where id=a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Maria Reis Alcântara','5511900000001','em_atendimento') returning id into maria;

  -- terça (2) às 15h, R$ 1.234,50, política 24h/50%
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (maria,2,'15:00',50,1234.50,24,50) returning id into enq;

  -- ---------------------------------------------------------------- 1
  ok := false;
  begin
    perform public.publicar_contrato('Sem a regra', replace(corpo, '{{politica}}', 'o que combinarmos'));
  exception when others then ok := true;
  end;
  if not ok then raise exception '1 · publicou um contrato sem a política de falta — o portão do doc 07 não existe'; end if;

  -- ---------------------------------------------------------------- 2
  ok := false;
  begin
    perform public.publicar_contrato('Sem o dinheiro', replace(corpo, '{{valor}}', 'o combinado'));
  exception when others then ok := true;
  end;
  if not ok then raise exception '2 · publicou um contrato sem o valor'; end if;

  c1 := public.publicar_contrato('Combinado de atendimento', corpo);

  -- ---------------------------------------------------------------- 3
  tok := public.preparar_aceite(enq);
  select a.texto into t from public.aceites a where a.enquadre_id=enq;

  if position('R$' || chr(160) || '1.234,50' in t) = 0 then raise exception '3 · o valor não saiu no texto: %', t; end if;
  if position('desmarcar com menos de 24 horas cobra 50%' in t) = 0 then raise exception '3 · a política não saiu: %', t; end if;
  if position('terça, 15h' in t) = 0 then raise exception '3 · o horário não saiu: %', t; end if;
  if position('Ana Ferreira' in t) = 0 or position('06/123456' in t) = 0 then raise exception '3 · a assinatura não saiu: %', t; end if;
  if position('{{' in t) > 0 then raise exception '3 · sobrou marcador no texto congelado: %', t; end if;

  -- ---------------------------------------------------------------- 4
  c2 := public.publicar_contrato('Combinado de atendimento', corpo || ' Versão nova.');
  select count(*) into n from public.contratos where conta_id=a_conta;
  if n <> 2 then raise exception '4 · esperava duas versões, achei %', n; end if;
  select versao into n from public.contratos where id=c2;
  if n <> 2 then raise exception '4 · a segunda versão não é a 2, é %', n; end if;

  -- ---------------------------------------------------------------- 5
  ok := false;
  begin
    update public.contratos set corpo = corpo || ' emenda' where id=c1;
  exception when others then ok := true;
  end;
  if not ok then raise exception '5 · editou um contrato publicado — o aceite passa a apontar para um texto que ninguém leu'; end if;

  -- ---------------------------------------------------------------- 6 e 7
  -- Um PATCH direto no PostgREST tentando plantar token, texto e retrato.
  update public.aceites set revogado_em = now(), motivo_revogacao='teste' where enquadre_id=enq;
  insert into public.aceites (enquadre_id, conta_id, paciente_id, contrato_id,
                              token, texto, retrato, expira_em, criado_em)
  values (enq, a_conta, maria, c1,
          'deadbeefdeadbeefdeadbeefdeadbeef',
          'Concordo em pagar o dobro e abro mão de tudo.',
          '{"valor": 99999}'::jsonb,
          now() + interval '10 years', now());

  select a.token, a.texto into tok, t from public.aceites a where a.enquadre_id=enq and a.revogado_em is null;

  if tok = 'deadbeefdeadbeefdeadbeefdeadbeef' then
    raise exception '6 · o cliente escolheu o token — quem escolhe o endereço da prova, forja a prova';
  end if;
  if position('abro mão de tudo' in t) > 0 then raise exception '7 · o cliente escreveu o texto do contrato pelo PostgREST'; end if;
  if position('R$' || chr(160) || '1.234,50' in t) = 0 then raise exception '7 · o gatilho não remontou o texto a partir do combinado'; end if;

  select (a.retrato->>'valor')::numeric into n from public.aceites a where a.enquadre_id=enq and a.revogado_em is null;
  if n <> 1234.50 then raise exception '7 · o retrato veio do cliente, não do combinado: %', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · o modelo e a montagem: ok';
end $do$;

-- ============================================= parte 2 · o aceite e a fraude

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; maria uuid; enq uuid; ace uuid; ace2 uuid;
  tok text; j jsonb; n int; ok boolean; quando timestamptz; t text;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into maria from public.pacientes where conta_id=a_conta and nome='Maria Reis Alcântara';
  select id into enq from public.enquadres where paciente_id=maria and vigencia_fim is null;
  select a.id, a.token into ace, tok from public.aceites a where a.enquadre_id=enq and a.revogado_em is null;

  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  -- ---------------------------------------------------------------- 8
  j := public.contrato_por_token('00000000000000000000000000000000');
  if j->>'estado' <> 'inexistente' then raise exception '8 · token inexistente devolveu %', j; end if;
  j := public.contrato_por_token('nao-e-um-token');
  if j->>'estado' <> 'inexistente' then raise exception '8 · token malformado devolveu %', j; end if;

  -- ---------------------------------------------------------------- 10
  j := public.contrato_por_token(tok);
  if j->>'estado' <> 'pendente' then raise exception '10 · o estado do link pendente é %', j->>'estado'; end if;
  if j->>'nome' <> 'Maria' then
    raise exception '10 · o link mostra o nome inteiro (%) — a tela é lida por quem passa', j->>'nome';
  end if;
  if j ? 'telefone' or j ? 'cpf' or j ? 'paciente_id' or j ? 'conta_id' then
    raise exception '10 · o link do visitante vaza campo de cadastro: %', j;
  end if;

  select count(*) into n from public.aceites;
  if n <> 0 then raise exception '10 · anon enxerga % aceites direto na tabela', n; end if;

  -- ---------------------------------------------------------------- 9
  j := public.aceitar_contrato(tok, 'Maria Reis Alcântara', null, '203.0.113.7', 'Mozilla/5.0');
  if (j->>'ok')::boolean is not true then raise exception '9 · o visitante não conseguiu aceitar: %', j; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  select a.origem, a.aceito_em into t, quando from public.aceites a where a.id=ace;
  if t <> 'link' then raise exception '9 · a origem do aceite pelo link saiu como %', t; end if;
  if quando < now() - interval '1 minute' then raise exception '9 · o aceite não foi carimbado agora'; end if;

  select count(*) into n from public.trilha_acesso where paciente_id=maria and acao='contrato_aceito';
  if n <> 1 then raise exception '9 · o aceite pelo link não entrou na trilha (%)', n; end if;

  -- ---------------------------------------------------------------- 13
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  ok := false;
  begin update public.aceites set texto = 'Outro texto, mais conveniente.' where id=ace;
  exception when others then ok := true; end;
  if not ok then raise exception '13 · ela reescreveu o texto de um aceite já dado'; end if;

  ok := false;
  begin update public.aceites set aceito_por = 'Outra pessoa' where id=ace;
  exception when others then ok := true; end;
  if not ok then raise exception '13 · ela trocou quem aceitou'; end if;

  -- ---------------------------------------------------------------- 16
  perform public.revogar_aceite(ace, 'teste de revogação');
  select revogado_em into quando from public.aceites where id=ace;
  if quando is null then raise exception '16 · revogar não gravou'; end if;

  select count(*) into n from public.aceites where id=ace;
  if n <> 1 then raise exception '16 · revogar apagou a linha — some o lastro das cobranças que já saíram'; end if;

  select a.aceito_em into quando from public.aceites a where a.id=ace;
  if quando is null then raise exception '16 · revogar apagou a data do aceite'; end if;

  -- ---------------------------------------------------------------- 17
  reset role; perform set_config('request.jwt.claims','',true);
  ok := false;
  begin update public.aceites set revogado_em = null where id=ace;
  exception when others then ok := true; end;
  if not ok then raise exception '17 · aceite revogado voltou atrás'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 15
  tok := public.preparar_aceite(enq);
  select a.id into ace2 from public.aceites a where a.enquadre_id=enq and a.revogado_em is null;

  ok := false;
  begin
    insert into public.aceites (enquadre_id, conta_id, paciente_id, contrato_id, token, texto, retrato, expira_em)
    select enq, a_conta, maria, a.contrato_id, 'x', 'x', '{}'::jsonb, now() from public.aceites a where a.id=ace2;
  exception when others then ok := true; end;
  if not ok then
    raise exception '15 · dois aceites vivos no mesmo combinado — "tem lastro?" deixou de ter uma resposta só';
  end if;

  -- ------------------------------------------------------------- 11 e 12
  -- Antedatar para dar lastro a uma cobrança que já saiu.
  update public.aceites set aceito_em = now() - interval '90 days', aceito_por = 'Maria Reis Alcântara' where id=ace2;
  select a.aceito_em, a.origem into quando, t from public.aceites a where a.id=ace2;

  if quando < now() - interval '1 minute' then
    raise exception '11 · antedatou o aceite para % — o relógio não é do servidor', quando;
  end if;
  if t <> 'presencial' then
    raise exception '12 · sessão autenticada gravou origem % — a procedência foi digitada, não deduzida', t;
  end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · o aceite e a fraude: ok';
end $do$;

-- ========================================== parte 3 · fronteiras e vizinhas

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_conta uuid;
  maria uuid; enq uuid; nova uuid; ace uuid; s uuid;
  tok text; j jsonb; n int; ok boolean; t text; antes timestamptz;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into maria from public.pacientes where conta_id=a_conta and nome='Maria Reis Alcântara';
  select id into enq from public.enquadres where paciente_id=maria and vigencia_fim is null;

  reset role; perform set_config('request.jwt.claims','',true);
  update public.aceites set revogado_em=now() where enquadre_id=enq and revogado_em is null;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  tok := public.preparar_aceite(enq);
  select a.id into ace from public.aceites a where a.enquadre_id=enq and a.revogado_em is null;

  -- ---------------------------------------------------------------- 14
  reset role; perform set_config('request.jwt.claims','',true);
  update public.aceites set expira_em = now() - interval '1 day' where id=ace;

  execute 'set local role anon';
  j := public.contrato_por_token(tok);
  if j->>'estado' <> 'expirado' then raise exception '14 · o link vencido não se declara vencido: %', j->>'estado'; end if;
  j := public.aceitar_contrato(tok, 'Maria Reis Alcântara');
  if (j->>'ok')::boolean is not false or j->>'motivo' <> 'expirado' then raise exception '14 · aceitou por um link vencido: %', j; end if;

  -- ---------------------------------------------------------------- 18
  reset role; perform set_config('request.jwt.claims','',true);
  update public.aceites set revogado_em=now() where enquadre_id=enq and revogado_em is null;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- O reajuste da D14: fecha o combinado e abre outro.
  update public.enquadres set vigencia_fim = public.hoje_sp(), motivo_fim='reajuste' where id=enq;
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual)
    values (maria,2,'15:00',50,1400.00,24,50) returning id into nova;

  ok := false;
  begin perform public.preparar_aceite(enq); exception when others then ok := true; end;
  if not ok then
    raise exception '18 · preparou aceite de um combinado encerrado — o reajuste manteria o lastro velho';
  end if;

  tok := public.preparar_aceite(nova);
  select a.texto into t from public.aceites a where a.enquadre_id=nova;
  if position('R$' || chr(160) || '1.400,00' in t) = 0 then raise exception '18 · o combinado novo não trouxe o valor novo: %', t; end if;

  -- ---------------------------------------------------------------- 20
  -- Sem aceite não se bloqueia nada: a falta continua cobrando.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
    values (a_conta,a_prof,maria,now()-interval '2 hours',now()-interval '70 minutes','avulsa','prevista',1400.00,24,50)
    returning id into s;
  update public.sessoes set estado='falta' where id=s;
  -- **Reescrita em 03/09, e é a suíte provando o contrário porque a decisão
  -- mudou.** O que esta verificação defende é a fronteira: *o contrato não é
  -- porteiro da relação* — a ausência de aceite vivo não pode travar o que
  -- vem depois da falta. Isso continua valendo inteiro.
  --
  -- O que mudou foi o que vem depois da falta. O **P4** tirou a cobrança
  -- automática do software: a falta gera a **pergunta**, e quem decide é ela.
  -- A 0022 foi reescrita na época e esta ficou para trás, exigindo o
  -- comportamento revogado. É o mesmo caso que o `CLAUDE.md` §8 descreve pelo
  -- nome, e a resposta dele é esta: a suíte passa a provar o oposto.
  select count(*) into n from public.cobrancas where sessao_id=s;
  if n <> 0 then
    raise exception '20 · a cobrança da falta nasceu sozinha (%) — o P4 tirou essa decisão do software', n;
  end if;
  select count(*) into n from public.propostas_de_cobranca where sessao_id=s;
  if n <> 1 then
    raise exception '20 · a falta não virou pergunta por causa do contrato — o sistema virou porteiro da relação (%)', n;
  end if;

  -- ---------------------------------------------------------------- 19
  select a.id into ace from public.aceites a where a.enquadre_id=nova and a.revogado_em is null;

  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.aceites where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.contratos where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Solo';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  select criado_em into antes from public.aceites where id=ace;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.aceites;
  if n <> 0 then raise exception '19 · a Bia enxerga % aceites da Ana', n; end if;
  select count(*) into n from public.contratos;
  if n <> 0 then raise exception '19 · a Bia enxerga % contratos da Ana', n; end if;

  update public.aceites set revogado_em = now() where id=ace;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '19 · a Bia revogou % aceites da Ana pelo PostgREST', n; end if;

  ok := false;
  begin perform public.revogar_aceite(ace, 'não é meu'); exception when others then ok := true; end;
  if not ok then raise exception '19 · a Bia revogou um aceite da Ana pela função'; end if;

  ok := false;
  begin perform public.preparar_aceite(nova); exception when others then ok := true; end;
  if not ok then raise exception '19 · a Bia preparou um aceite no combinado da Ana'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  if (select revogado_em from public.aceites where id=ace) is not null then
    raise exception '19 · o aceite da Ana ficou revogado depois da visita da Bia';
  end if;

  -- ---------------------------------------------------------------- 21
  -- Os mesmos casos estão em lib/contrato.test.ts com as mesmas strings.
  if public.reais(1234.50) <> 'R$' || chr(160) || '1.234,50' then raise exception '21 · reais(1234.50) = %', public.reais(1234.50); end if;
  if public.reais(200) <> 'R$' || chr(160) || '200,00' then raise exception '21 · reais(200) = %', public.reais(200); end if;
  if public.reais(0) <> 'R$' || chr(160) || '0,00' then raise exception '21 · reais(0) = %', public.reais(0); end if;
  if public.reais(1000000) <> 'R$' || chr(160) || '1.000.000,00' then raise exception '21 · reais(1000000) = %', public.reais(1000000); end if;

  -- ---------------------------------------------------------------- 22
  execute 'set local role anon';
  ok := false; begin perform public.publicar_contrato('x','y'); exception when others then ok := true; end;
  if not ok then raise exception '22 · anon publicou contrato'; end if;
  ok := false; begin perform public.preparar_aceite(nova); exception when others then ok := true; end;
  if not ok then raise exception '22 · anon preparou aceite'; end if;
  ok := false; begin perform public.revogar_aceite(ace); exception when others then ok := true; end;
  if not ok then raise exception '22 · anon revogou aceite'; end if;
  ok := false; begin perform public.montar_contrato('x', nova); exception when others then ok := true; end;
  if not ok then raise exception '22 · anon montou contrato'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  -- ------------------------------------------------------------------- fim
  -- A 0031 não recolhia o próprio rastro: 'Ana Solo' e 'Bia Solo' ficavam de pé
  -- depois dela, e foi assim que uma 'Bia Solo' órfã apareceu no banco. A conta
  -- primeiro, que `pacientes.profissional_id` e `registros.*` são RESTRICT.
  delete from public.aceites       where conta_id in (a_conta, b_conta);
  delete from public.contratos     where conta_id in (a_conta, b_conta);
  delete from public.propostas_de_cobranca where conta_id in (a_conta, b_conta);
  delete from public.cobrancas     where conta_id in (a_conta, b_conta);
  delete from public.mensagens     where conta_id in (a_conta, b_conta);
  delete from public.trilha_acesso where conta_id in (a_conta, b_conta);
  delete from public.sessoes       where conta_id in (a_conta, b_conta);
  delete from public.enquadres     where conta_id in (a_conta, b_conta);
  delete from public.pacientes     where conta_id in (a_conta, b_conta);
  delete from public.contas        where id in (a_conta, b_conta);
  delete from auth.users           where id in (a_auth, b_auth);

  raise notice 'parte 3 · fronteiras e vizinhas: ok';
  raise notice '0031 · 22 verificações passaram.';
end $do$;
