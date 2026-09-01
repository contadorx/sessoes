-- Teste da agenda que já existe (critério de pronto da B26).
--
-- A verificação nº 3 é a que decide o build: uma vaga é ofertada, o dentista
-- ocupa aquela hora na Google Agenda, o paciente responde SIM — e o aceite
-- **tem de ser recusado**. É o pior desfecho possível deste produto (marcar por
-- cima de um compromisso dela) e o único motivo pelo qual a `vaga_esta_livre`
-- foi desenhada como função única lá na fase 1.
--
-- Metade das verificações confere o que o sistema **não** faz: não escreve nome
-- de paciente na agenda de terceiro, não guarda o título do que leu, não deixa
-- o token ser lido nem pela dona da conta, não deixa histórico importado virar
-- dinheiro.
--
--   1. sem calendário, a hora está livre (a linha de base)
--   2. ligado, uma ocupação sobreposta tira a hora do ar
--   3. ...e o ACEITE da fila é recusado — a terceira fonte chegou onde importa
--   4. ocupação que encosta mas não sobrepõe não bloqueia
--   5. direção 'escrever' não bloqueia: ela pediu para só mandar
--   6. calendário expirado CONTINUA bloqueando — defasado erra para menos
--   7. revogado não bloqueia, porque desligar apagou as ocupações
--   8. a ocupação de outro profissional não bloqueia esta agenda
--   9. o evento nasce discreto: "Sessão", sem nome nenhum
--  10. modo iniciais devolve "Sessão · M. F." e engole as partículas
--  11. modo completo é o único que diz o nome
--  12. trocar o modo reescreve o futuro e deixa o passado como foi
--  13. a tela não troca o modo por PATCH direto
--  14. criar sessão enfileira 'criar'
--  15. mover a sessão vira 'atualizar', e não uma segunda linha
--  16. cancelar devolve a hora: vira 'remover'
--  17. férias apagam a sessão e o espelho SOBREVIVE para remover lá fora
--  18. sessão que nunca chegou lá fora não deixa lixo na fila
--  19. falhar cinco vezes desiste
--  20. desligar não apaga o que já está na agenda dela
--  21. o que entra não guarda o quê: título, convidado e local são ignorados
--  22. o evento apagado lá fora some daqui
--  23. o token é invisível — nem a dona da conta lê o próprio
--  24. a exportação leva a conexão e não leva a credencial
--  25. o histórico entra com origem 'importada'
--  26. cobrança sobre sessão importada estoura
--  27. o importado não entra no realizado do mês nem em "sem registro"
--  28. histórico no futuro é recusado, e a mesma planilha duas vezes não duplica
--  29. sessão importada não vai para a agenda de ninguém
--  30. isolamento entre contas
--  31. o anônimo não lê nem executa nada
--  32. função de gatilho não é rota: nem logado nem anônimo a executa
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0040_calendario_e_historico.sql

-- ==================== parte 1 · a terceira fonte da vaga

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  c_auth uuid := '33333333-3333-4333-8333-333333333333';
  a_conta uuid; a_prof uuid; a_prof2 uuid;
  pac uuid; pac2 uuid; sess uuid; cal uuid; ofe uuid;
  d date; ini timestamptz; f timestamptz; n int; falhou boolean;
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
  delete from auth.users where id in (a_auth, c_auth);
  delete from public.contas where nome in ('Ana Solo','Bia Colega');

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  -- Uma segunda profissional na mesma conta: é o cenário de clínica, e é onde
  -- um calendário mal amarrado bloquearia a agenda da colega.
  insert into auth.users (id,email,raw_user_meta_data)
    values (c_auth,'colega@teste.sessoes.com.br','{"nome":"Bia Colega"}'::jsonb);
  delete from public.profissionais p using public.usuarios u
   where p.usuario_id = u.id and u.auth_user_id = c_auth;
  update public.usuarios set conta_id = a_conta where auth_user_id = c_auth;
  delete from public.contas c
   where c.nome = 'Bia Colega' and not exists (select 1 from public.usuarios u where u.conta_id = c.id);
  insert into public.profissionais (conta_id, usuario_id, assina_como)
    select a_conta, u.id, 'Bia Colega' from public.usuarios u where u.auth_user_id = c_auth
    returning id into a_prof2;

  d := public.hoje_sp() + 10;
  ini := (d + time '15:00') at time zone 'America/Sao_Paulo';
  f   := (d + time '15:50') at time zone 'America/Sao_Paulo';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Maria Fernanda de Souza','5511987650001','em_atendimento') returning id into pac;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'João Pedro','5511987650002','em_atendimento') returning id into pac2;

  -- ---------------------------------------------------------------- 1
  if not public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '1 FUROU: sem calendário nenhum a hora já nasce ocupada'; end if;

  cal := public.ligar_calendario(a_prof, 'ana@gmail.com', 'primary');
  if cal is null then raise exception 'PREPARO: o calendário não ligou'; end if;

  reset role;
  perform public.registrar_ocupacoes(
    cal, d, d,
    jsonb_build_array(jsonb_build_object(
      'id','ev-dentista','inicio', ini + interval '10 minutes', 'fim', f + interval '30 minutes')));
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 2
  if public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '2 FUROU: a hora ocupada na agenda dela continua livre aqui — é o bug que a B26 existe para não ter'; end if;

  -- ---------------------------------------------------------------- 3
  -- O caminho inteiro: sessão cancelada abre a vaga, a oferta sai, o paciente
  -- responde SIM. O aceite tem de bater na terceira fonte e voltar.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,cancelada_em,cancelada_por)
    values (a_conta,a_prof,pac,ini,f,'avulsa','cancelada_cedo',200.00, now(), 'paciente')
    returning id into sess;
  insert into public.ofertas (conta_id, sessao_id, paciente_id, expira_em)
    values (a_conta, sess, pac2, now() + interval '30 minutes') returning id into ofe;

  falhou := false;
  begin
    perform public.responder_oferta(ofe, 'aceita');
  exception when others then
    falhou := true;
    if position('deixou de estar livre' in sqlerrm) = 0 then
      raise exception '3 FUROU: recusou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then
    raise exception '3 FUROU: a fila marcou por cima de um compromisso da agenda dela'; end if;
  -- (a resposta é 'aceita'/'recusada'; 'sim'/'nao' é tradução do webhook)

  update public.ofertas set estado='cancelada', respondida_em=now() where id=ofe;

  -- ---------------------------------------------------------------- 4
  -- Termina exatamente às 15:00: encosta e não invade. `[)` é o contrato.
  reset role;
  perform public.registrar_ocupacoes(
    cal, d, d,
    jsonb_build_array(jsonb_build_object(
      'id','ev-encosta','inicio', ini - interval '1 hour', 'fim', ini)));
  execute 'set local role authenticated';

  if not public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '4 FUROU: um compromisso que termina quando a sessão começa bloqueou a hora'; end if;

  -- ---------------------------------------------------------------- 5
  reset role;
  perform public.registrar_ocupacoes(
    cal, d, d,
    jsonb_build_array(jsonb_build_object(
      'id','ev-dentista','inicio', ini + interval '10 minutes', 'fim', f)));
  update public.calendarios set direcao='escrever' where id=cal;
  execute 'set local role authenticated';

  if not public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '5 FUROU: ela pediu para só ESCREVER e o sistema leu assim mesmo'; end if;

  -- ---------------------------------------------------------------- 6
  reset role;
  update public.calendarios set direcao='duas_vias' where id=cal;
  perform public.calendario_falhou(cal, 'token expirado', true);
  execute 'set local role authenticated';

  if (select estado from public.calendarios where id=cal) <> 'expirado' then
    raise exception 'PREPARO: o calendário não ficou expirado'; end if;
  if public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '6 FUROU: calendário defasado liberou a hora — o erro tem de ser para o lado de oferecer menos'; end if;

  -- ---------------------------------------------------------------- 8
  -- (o 7 vem depois, porque desligar é destrutivo e encerra a parte)
  if not public.vaga_esta_livre(a_prof2, ini, f) then
    raise exception '8 FUROU: o calendário de uma bloqueou a agenda da colega'; end if;

  -- ---------------------------------------------------------------- 7
  perform public.desligar_calendario(a_prof);

  select count(*) into n from public.ocupacoes_externas where calendario_id=cal;
  if n <> 0 then raise exception '7 FUROU: desligar deixou % ocupações bloqueando', n; end if;
  if not public.vaga_esta_livre(a_prof, ini, f) then
    raise exception '7 FUROU: calendário revogado ainda bloqueia a hora'; end if;
  if (select count(*) from public.calendarios_segredo where calendario_id=cal) <> 0 then
    raise exception '7 FUROU: o token continuou guardado depois de desligar'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · a terceira fonte da vaga: ok';
end $do$;

-- ==================== parte 2 · o que sai não diz quem

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; cal uuid;
  s_futura uuid; s_passada uuid; e_fut uuid; e_pas uuid;
  d date; r record; n int; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta order by criado_em limit 1;
  select id into pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  d := public.hoje_sp() + 10;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 9
  if public.titulo_do_evento('discreto', 'Maria Fernanda de Souza') <> 'Sessão' then
    raise exception '9 FUROU: o título discreto virou "%"',
      public.titulo_do_evento('discreto', 'Maria Fernanda de Souza'); end if;

  -- ---------------------------------------------------------------- 10
  if public.iniciais_do_nome('Maria Fernanda de Souza') <> 'M. F. S.' then
    raise exception '10 FUROU: iniciais deram "%" (as partículas deviam sair)',
      public.iniciais_do_nome('Maria Fernanda de Souza'); end if;
  if public.titulo_do_evento('iniciais', 'Maria Fernanda de Souza') <> 'Sessão · M. F. S.' then
    raise exception '10 FUROU: "%"', public.titulo_do_evento('iniciais','Maria Fernanda de Souza'); end if;
  if public.titulo_do_evento('iniciais', '') <> 'Sessão' then
    raise exception '10 FUROU: sem nome, o título tinha de cair no discreto'; end if;

  -- ---------------------------------------------------------------- 11
  if public.titulo_do_evento('completo', 'Maria Fernanda de Souza') <> 'Sessão · Maria Fernanda de Souza' then
    raise exception '11 FUROU: "%"', public.titulo_do_evento('completo','Maria Fernanda de Souza'); end if;
  if position('Maria' in public.titulo_do_evento('discreto','Maria Fernanda de Souza')
                       || public.titulo_do_evento('iniciais','Maria Fernanda de Souza')) > 0 then
    raise exception '11 FUROU: o nome vazou num modo que não é o completo'; end if;

  -- ---- religa o calendário, agora escrevendo
  cal := public.ligar_calendario(a_prof, 'ana@gmail.com', 'primary');
  perform public.ajustar_calendario(a_prof, 'duas_vias', 'completo');

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d + time '09:00') at time zone 'America/Sao_Paulo',
                               (d + time '09:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00)
    returning id into s_futura;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(public.hoje_sp() - 30 + time '09:00') at time zone 'America/Sao_Paulo',
                               (public.hoje_sp() - 30 + time '09:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s_passada;

  -- Faz de conta que as duas já foram para lá.
  reset role;
  update public.espelhos_calendario set evento_externo='ev-fut', estado='espelhada', enviado_em=now()
   where sessao_id=s_futura returning id into e_fut;
  update public.espelhos_calendario set evento_externo='ev-pas', estado='espelhada', enviado_em=now()
   where sessao_id=s_passada returning id into e_pas;
  execute 'set local role authenticated';

  if e_fut is null or e_pas is null then
    raise exception 'PREPARO: as sessões não geraram espelho'; end if;

  -- O título sai com o nome enquanto o modo é 'completo'.
  select * into r from public.espelhos_a_enviar(50) where id=e_fut;

  -- ---------------------------------------------------------------- 12
  perform public.ajustar_calendario(a_prof, 'duas_vias', 'discreto');

  if (select estado from public.espelhos_calendario where id=e_fut) <> 'pendente' then
    raise exception '12 FUROU: trocar para discreto não reenfileirou a semana que vem'; end if;
  if (select acao from public.espelhos_calendario where id=e_fut) <> 'atualizar' then
    raise exception '12 FUROU: a ação devia ser atualizar'; end if;
  if (select estado from public.espelhos_calendario where id=e_pas) <> 'espelhada' then
    raise exception '12 FUROU: reescreveu o passado — apagar o histórico da agenda dela é decisão dela'; end if;

  select * into r from public.espelhos_a_enviar(50) x where x.id=e_fut;
  if not found then raise exception '12 FUROU: o reenfileirado não aparece na fila de envio'; end if;
  if r.titulo <> 'Sessão' then
    raise exception '12 FUROU: o título já reenfileirado ainda sai como "%"', r.titulo; end if;

  -- ---------------------------------------------------------------- 13
  update public.calendarios set modo_titulo='completo' where id=cal;
  if (select modo_titulo from public.calendarios where id=cal) <> 'discreto' then
    raise exception '13 FUROU: um PATCH direto trocou o modo de título — não existe política de update aqui'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · o que sai não diz quem: ok';
end $do$;

-- ==================== parte 3 · a fila dos espelhos

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid; cal uuid;
  s1 uuid; s2 uuid; esp uuid; esp2 uuid;
  d date; n int; r record; i int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta order by criado_em limit 1;
  select id into pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';
  select id into cal from public.calendarios where profissional_id=a_prof;
  d := public.hoje_sp() + 12;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 14
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d + time '11:00') at time zone 'America/Sao_Paulo',
                               (d + time '11:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00)
    returning id into s1;

  select * into r from public.espelhos_calendario where sessao_id=s1;
  if not found then raise exception '14 FUROU: a sessão nova não entrou na fila do calendário'; end if;
  if r.acao <> 'criar' or r.estado <> 'pendente' then
    raise exception '14 FUROU: nasceu como % / %', r.acao, r.estado; end if;
  esp := r.id;

  -- Finge que foi.
  reset role;
  perform public.marcar_espelho_feito(esp, 'ev-1');
  execute 'set local role authenticated';
  if (select estado from public.espelhos_calendario where id=esp) <> 'espelhada' then
    raise exception '14 FUROU: marcar feito não fechou a linha'; end if;

  -- ---------------------------------------------------------------- 15
  update public.sessoes set inicio = inicio + interval '1 hour', fim = fim + interval '1 hour'
   where id=s1;

  select count(*) into n from public.espelhos_calendario where sessao_id=s1;
  if n <> 1 then raise exception '15 FUROU: mover a sessão criou % linhas na fila', n; end if;
  select * into r from public.espelhos_calendario where sessao_id=s1;
  if r.acao <> 'atualizar' or r.estado <> 'pendente' then
    raise exception '15 FUROU: virou % / %', r.acao, r.estado; end if;
  if r.evento_externo <> 'ev-1' then
    raise exception '15 FUROU: perdeu o id do evento lá fora'; end if;

  -- ---------------------------------------------------------------- 16
  update public.sessoes set estado='cancelada_cedo', cancelada_em=now(), cancelada_por='paciente'
   where id=s1;
  select * into r from public.espelhos_calendario where sessao_id=s1;
  if r.acao <> 'remover' then
    raise exception '16 FUROU: cancelar não devolveu a hora lá fora (ação %)', r.acao; end if;

  -- ---------------------------------------------------------------- 17
  -- Férias apagam a instância prevista. O espelho tem de sobreviver.
  -- Recorrente nasce do motor, não do cliente (a política de insert só deixa
  -- passar encaixe e avulsa) — por isso esta entra com o papel do servidor.
  reset role;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d + 1 + time '11:00') at time zone 'America/Sao_Paulo',
                               (d + 1 + time '11:50') at time zone 'America/Sao_Paulo','recorrencia','prevista',200.00)
    returning id into s2;
  execute 'set local role authenticated';
  select id into esp2 from public.espelhos_calendario where sessao_id=s2;
  reset role;
  perform public.marcar_espelho_feito(esp2, 'ev-2');
  execute 'set local role authenticated';

  -- A tela não apaga sessão (não existe política de delete em `sessoes`): quem
  -- apaga é a materialização, e é com o papel dela que este delete roda.
  reset role;
  delete from public.sessoes where id=s2;
  execute 'set local role authenticated';

  select * into r from public.espelhos_calendario where id=esp2;
  if not found then
    raise exception '17 FUROU: apagar a sessão levou o espelho junto — o evento ficaria órfão na agenda dela para sempre'; end if;
  if r.acao <> 'remover' or r.estado <> 'pendente' then
    raise exception '17 FUROU: ficou % / %', r.acao, r.estado; end if;
  if r.sessao_id is not null then
    raise exception '17 FUROU: o espelho continua apontando para uma sessão que não existe'; end if;
  if r.evento_externo <> 'ev-2' then
    raise exception '17 FUROU: sem o id do evento não há como remover lá fora'; end if;

  -- ---------------------------------------------------------------- 18
  reset role;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,pac,(d + 2 + time '11:00') at time zone 'America/Sao_Paulo',
                               (d + 2 + time '11:50') at time zone 'America/Sao_Paulo','recorrencia','prevista',200.00);
  execute 'set local role authenticated';
  select id into esp2 from public.espelhos_calendario
   where sessao_id = (select id from public.sessoes
                       where paciente_id=pac
                         and inicio=(d + 2 + time '11:00') at time zone 'America/Sao_Paulo');
  reset role;
  delete from public.sessoes where paciente_id=pac
     and inicio=(d + 2 + time '11:00') at time zone 'America/Sao_Paulo';
  execute 'set local role authenticated';
  if exists (select 1 from public.espelhos_calendario where id=esp2) then
    raise exception '18 FUROU: sessão que nunca chegou lá fora deixou um "remover" pendente de nada'; end if;

  -- ---------------------------------------------------------------- 19
  reset role;
  for i in 1..5 loop
    perform public.marcar_espelho_falhou(esp, 'timeout');
  end loop;
  execute 'set local role authenticated';
  select * into r from public.espelhos_calendario where id=esp;
  if r.estado <> 'falhou' then
    raise exception '19 FUROU: insistiu além da quinta (estado %, tentativas %)', r.estado, r.tentativas; end if;
  if r.erro <> 'timeout' then raise exception '19 FUROU: a linha não guardou o que houve'; end if;
  select count(*) into n from public.espelhos_a_enviar(50) x where x.id=esp;
  if n <> 0 then raise exception '19 FUROU: continua na fila depois de desistir'; end if;

  -- ---------------------------------------------------------------- 20
  perform public.desligar_calendario(a_prof);
  select count(*) into n from public.espelhos_calendario
   where calendario_id=cal and evento_externo is not null;
  if n = 0 then
    raise exception '20 FUROU: desligar sumiu com o registro dos eventos que já estão na agenda dela'; end if;
  select count(*) into n from public.espelhos_calendario
   where calendario_id=cal and estado='pendente';
  if n <> 0 then
    raise exception '20 FUROU: ficaram % pendências para sair com um token que não existe mais', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · a fila dos espelhos: ok';
end $do$;

-- ==================== parte 4 · o que entra, e o que nunca sai daqui

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; cal uuid;
  d date; n int; r record; exp jsonb; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta order by criado_em limit 1;
  d := public.hoje_sp() + 15;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  cal := public.ligar_calendario(a_prof, 'ana@gmail.com', 'primary');
  reset role;

  perform public.guardar_segredo_do_calendario(cal, '1//refresh-super-secreto', 'ya29.acesso', now() + interval '1 hour');

  -- ---------------------------------------------------------------- 21
  perform public.registrar_ocupacoes(
    cal, d, d,
    jsonb_build_array(jsonb_build_object(
      'id','ev-terapia-da-ana',
      'inicio', (d + time '08:00') at time zone 'America/Sao_Paulo',
      'fim',    (d + time '09:00') at time zone 'America/Sao_Paulo',
      'titulo', 'Minha análise com o Dr. Ferreira',
      'descricao', 'levar o sonho anotado',
      'local', 'Rua Tal, 400',
      'convidados', jsonb_build_array('dr.ferreira@exemplo.com'))));

  select * into r from public.ocupacoes_externas where evento_externo='ev-terapia-da-ana';
  if not found then raise exception '21 FUROU: a ocupação não foi gravada'; end if;
  if position('análise' in to_jsonb(r)::text) > 0
     or position('Ferreira' in to_jsonb(r)::text) > 0
     or position('sonho' in to_jsonb(r)::text) > 0
     or position('Rua Tal' in to_jsonb(r)::text) > 0 then
    raise exception '21 FUROU: guardamos o QUÊ do compromisso dela — só precisávamos do QUANDO: %', to_jsonb(r)::text; end if;

  -- ---------------------------------------------------------------- 22
  -- A mesma janela, sem aquele evento: ele foi apagado lá fora.
  perform public.registrar_ocupacoes(
    cal, d, d,
    jsonb_build_array(jsonb_build_object(
      'id','ev-outro',
      'inicio', (d + time '14:00') at time zone 'America/Sao_Paulo',
      'fim',    (d + time '15:00') at time zone 'America/Sao_Paulo')));

  if exists (select 1 from public.ocupacoes_externas where evento_externo='ev-terapia-da-ana') then
    raise exception '22 FUROU: o compromisso apagado lá fora continua bloqueando a hora aqui'; end if;
  if not exists (select 1 from public.ocupacoes_externas where evento_externo='ev-outro') then
    raise exception '22 FUROU: o evento novo não entrou'; end if;

  -- ---------------------------------------------------------------- 23
  execute 'set local role authenticated';
  select count(*) into n from public.calendarios_segredo;
  if n <> 0 then
    raise exception '23 FUROU: a dona da conta lê o próprio refresh token pelo PostgREST (% linhas)', n; end if;

  falhou := false;
  begin
    perform public.guardar_segredo_do_calendario(cal, 'forjado');
  exception when others then falhou := true;
  end;
  if not falhou then
    raise exception '23 FUROU: quem está logado consegue gravar token'; end if;

  falhou := false;
  begin
    perform public.calendarios_a_ler(10);
  exception when others then falhou := true;
  end;
  if not falhou then
    raise exception '23 FUROU: a lista com os tokens de TODAS as contas é executável por quem está logado'; end if;

  -- ---------------------------------------------------------------- 24
  exp := public.exportar_conta();
  if not (exp ? 'calendarios') then
    raise exception '24 FUROU: a exportação não leva a conexão'; end if;
  if not (exp ? 'ocupacoes_externas') or not (exp ? 'espelhos_calendario') then
    raise exception '24 FUROU: faltou ocupações ou espelhos na exportação'; end if;
  if position('refresh-super-secreto' in exp::text) > 0 then
    raise exception '24 FUROU: o refresh token saiu na exportação — portabilidade é direito ao dado, não à credencial'; end if;
  if position('ya29.acesso' in exp::text) > 0 then
    raise exception '24 FUROU: o access token saiu na exportação'; end if;
  if exp ? 'calendarios_segredo' then
    raise exception '24 FUROU: existe uma seção de segredos na exportação'; end if;
  if (exp->'calendarios'->0) ? 'sync_token' then
    raise exception '24 FUROU: o cursor de sincronização saiu na exportação'; end if;
  if jsonb_array_length(exp->'calendarios') = 0 then
    raise exception '24 FUROU: a seção de calendários veio vazia'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 4 · o que entra, e o que nunca sai daqui: ok';
end $do$;

-- ==================== parte 5 · memória, não dinheiro

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; pac uuid;
  antiga timestamptz; s_imp uuid; res jsonb; painel jsonb;
  de date; ate date; n int; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta order by criado_em limit 1;
  select id into pac from public.pacientes where conta_id=a_conta and nome like 'Maria%';

  de  := date_trunc('month', public.hoje_sp())::date;
  ate := (date_trunc('month', public.hoje_sp()) + interval '1 month - 1 day')::date;
  antiga := (public.hoje_sp() - 2 + time '10:00') at time zone 'America/Sao_Paulo';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 25
  res := public.importar_historico(jsonb_build_array(
    jsonb_build_object('paciente_id', pac, 'inicio', antiga, 'estado','realizada','valor', 190.00)));

  if (res->>'importadas')::int <> 1 then
    raise exception '25 FUROU: importou % linhas (%)', res->>'importadas', res; end if;
  select id into s_imp from public.sessoes where paciente_id=pac and inicio=antiga;
  if (select origem from public.sessoes where id=s_imp) <> 'importada' then
    raise exception '25 FUROU: a sessão não ficou marcada como importada'; end if;

  -- ---------------------------------------------------------------- 26
  falhou := false;
  begin
    insert into public.cobrancas (conta_id, paciente_id, sessao_id, tipo, motivo, valor, competencia)
    values (a_conta, pac, s_imp, 'sessao', 'avulsa', 190.00, de);
  exception when others then
    falhou := true;
    if position('memória, não dinheiro' in sqlerrm) = 0 then
      raise exception '26 FUROU: estourou por outro motivo (%)', sqlerrm; end if;
  end;
  if not falhou then
    raise exception '26 FUROU: dinheiro de outro sistema entrou no caixa deste'; end if;

  -- ---------------------------------------------------------------- 27
  painel := public.financeiro_do_mes(de, ate);
  if position('190' in (painel->'realizado'->>'valor')) > 0 then
    raise exception '27 FUROU: a planilha importada virou faturamento do mês (%)',
      painel->'realizado'->>'valor'; end if;
  select count(*) into n from public.sessoes_sem_registro(de, ate) x where x.sessao_id = s_imp;
  if n <> 0 then
    raise exception '27 FUROU: o sistema vai perguntar "recebi?" por uma sessão de outro sistema'; end if;

  -- ---------------------------------------------------------------- 28
  res := public.importar_historico(jsonb_build_array(
    jsonb_build_object('paciente_id', pac,
                       'inicio', (public.hoje_sp() + 5 + time '10:00') at time zone 'America/Sao_Paulo',
                       'estado','realizada','valor', 190.00)));
  if (res->>'importadas')::int <> 0 then
    raise exception '28 FUROU: aceitou histórico com data no futuro'; end if;
  if position('passado' in res::text) = 0 then
    raise exception '28 FUROU: recusou sem dizer por quê (%)', res; end if;

  res := public.importar_historico(jsonb_build_array(
    jsonb_build_object('paciente_id', pac, 'inicio', antiga, 'estado','realizada','valor', 190.00)));
  if (res->>'importadas')::int <> 0 or (res->>'repetidas')::int <> 1 then
    raise exception '28 FUROU: colar a mesma planilha duas vezes duplicou o passado (%)', res; end if;

  res := public.importar_historico(jsonb_build_array(
    jsonb_build_object('paciente_id', pac, 'inicio', antiga - interval '1 day',
                       'estado','prevista','valor', 190.00)));
  if (res->>'importadas')::int <> 0 then
    raise exception '28 FUROU: aceitou estado que não é desfecho'; end if;

  -- ---------------------------------------------------------------- 29
  if exists (select 1 from public.espelhos_calendario where sessao_id=s_imp) then
    raise exception '29 FUROU: uma sessão de 2024 foi parar na agenda Google dela'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 5 · memória, não dinheiro: ok';
end $do$;

-- ==================== parte 6 · isolamento e o anônimo

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; a_prof uuid; b_prof uuid; n int; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta order by criado_em limit 1;

  delete from public.espelhos_calendario where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.ocupacoes_externas where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.calendarios where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Outra');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Outra';
  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Outra"}'::jsonb);
  select id into b_prof from public.profissionais
   where conta_id=(select conta_id from public.usuarios where auth_user_id=b_auth);

  -- ---------------------------------------------------------------- 30
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.calendarios;
  if n <> 0 then raise exception '30 FUROU: a Bia vê % calendários da Ana', n; end if;
  select count(*) into n from public.ocupacoes_externas;
  if n <> 0 then raise exception '30 FUROU: a Bia vê a agenda pessoal da Ana'; end if;
  select count(*) into n from public.espelhos_calendario;
  if n <> 0 then raise exception '30 FUROU: a Bia vê os espelhos da Ana'; end if;

  -- A sonda da 0015, agora com a terceira fonte: perguntar sobre a agenda
  -- alheia continua não sendo proibido — é inútil, e responde sobre o vazio.
  if not public.vaga_esta_livre(a_prof, now() + interval '15 days', now() + interval '15 days 1 hour') then
    raise exception '30 FUROU: a resposta da sonda revelou a ocupação de outra conta'; end if;

  falhou := false;
  begin
    perform public.ligar_calendario(a_prof, 'invasora@gmail.com', 'primary');
  exception when others then falhou := true;
  end;
  if not falhou then
    raise exception '30 FUROU: a Bia ligou um calendário no profissional da Ana'; end if;

  falhou := false;
  begin
    perform public.desligar_calendario(a_prof);
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '30 FUROU: a Bia desligou o calendário da Ana'; end if;

  -- ---------------------------------------------------------------- 31
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.calendarios;
  if n <> 0 then raise exception '31 FUROU: o anônimo lê calendários'; end if;
  select count(*) into n from public.ocupacoes_externas;
  if n <> 0 then raise exception '31 FUROU: o anônimo lê ocupações'; end if;
  select count(*) into n from public.calendarios_segredo;
  if n <> 0 then raise exception '31 FUROU: o anônimo lê tokens'; end if;

  falhou := false;
  begin perform public.titulo_do_evento('completo','Maria'); exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executa titulo_do_evento'; end if;

  falhou := false;
  begin perform public.importar_historico('[]'::jsonb); exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executa importar_historico'; end if;

  falhou := false;
  begin perform public.calendario_do_profissional(null); exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: o anônimo executa calendario_do_profissional'; end if;

  -- ---------------------------------------------------------------- 32
  -- `create function` concede execute ao PUBLIC, e o PostgREST publica tudo o
  -- que é executável. Gatilho `definer` exposto em /rest/v1/rpc é superfície
  -- que não precisa existir — é o mesmo revoke que faltou na 0018.
  falhou := false;
  begin perform public.sessao_espelha(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '32 FUROU: o anônimo alcança sessao_espelha'; end if;

  falhou := false;
  begin perform public.sessao_apagada_espelha(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '32 FUROU: o anônimo alcança sessao_apagada_espelha'; end if;

  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  falhou := false;
  begin perform public.modo_reescreve_o_futuro(); exception when insufficient_privilege then null;
  when others then falhou := true; end;
  if falhou then raise exception '32 FUROU: quem está logado alcança modo_reescreve_o_futuro'; end if;

  reset role;
  raise notice 'parte 6 · isolamento e o anônimo: ok';
  raise notice '=== 0040 · calendário e histórico: 32 verificações, todas passaram ===';
end $do$;
