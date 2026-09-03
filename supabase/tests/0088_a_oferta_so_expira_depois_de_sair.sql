-- Teste da expiração que espera a mensagem sair (B50, migrações 0088 e 0089).
--
-- O DEFEITO QUE ESTA SUÍTE EXISTE PARA REPROVAR
--
-- `expirar_ofertas` pulava oferta cuja mensagem estivesse `na_sua_mao` — e só
-- esse estado. Com a mensagem `pendente`, `enviando`, `falhou` ou
-- `barrada_no_teto`, no minuto do `expira_em` a oferta expirava, `avancar_fila`
-- chamava a próxima, que também não saía, e **a fila queimava inteira sem uma
-- única mensagem ter saído** — com a tela mostrando "expirada" para gente que
-- nunca foi convidada.
--
-- A verificação que decide o arquivo é a **2**: mensagem `pendente` vencida
-- **não** expira, e a fila **não** anda. Se ela passar a expirar, esta linha
-- reprova antes de a próxima psicóloga descobrir pelo WhatsApp de uma paciente
-- que não foi convidada para nada.
--
--    1. o preparo é fiel: oferta viva, mensagem criada, prazo vencido
--    2. mensagem pendente segura a oferta, e a fila não anda           ← decide
--    3. enviando também segura
--    4. na_sua_mao continua segurando (a decisão da OP9, sem regressão)
--    5. falhou segura — ninguém foi convidado
--    6. barrada_no_teto segura — é o caminho normal de quem bateu a cota
--    7. cancelada expira: é ela dizendo "não vou mandar"
--    8. enviada expira, grava o evento e a fila anda                   ← decide
--    9. entregue expira igual
--   10. oferta sem mensagem nenhuma segura (o rastro da 0046d/0060d)
--   11. avancar_fila grava oferta_preparada, e não oferta_enviada      ← decide
--   12. marcar_enviada grava oferta_enviada uma vez só (idempotente)
--   13. marcar_enviada_a_mao também grava — ela mandou, saiu de verdade
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0088

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111188';
  v_conta uuid; v_prof uuid;
  v_p1 uuid; v_p2 uuid;
  v_vaga uuid; v_of1 uuid; v_of2 uuid;
  v_msg uuid; v_estado text;
  v_terca timestamptz;
  n integer; v_txt text;
begin

-- ------------------------------------------------------------------ preparo
--
-- A ordem é de dependência: o que aponta para `pacientes` com `restrict` sai
-- antes. `mensagens` entra nesta lista porque esta suíte cria mensagem — a
-- lição da 0012 é que tabela nova some da limpeza e some do radar.
delete from public.mensagens    where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.eventos_fila where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.ofertas      where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.fila_encaixe where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.sessoes      where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.enquadres    where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from public.pacientes    where conta_id in (select id from public.contas where nome = 'Fila Que Espera');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Fila Que Espera';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'filaqueespera@teste.sessoes.com.br', '{"nome":"Fila Que Espera"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

-- Plano pago, pelo mesmo motivo da 0012: no Grátis a mensagem nasce
-- `na_sua_mao` e a oferta já era segurada — a suíte testaria o caminho manual
-- achando que testava o automático.
set local role postgres;
update public.contas set plano = 'solo' where id = v_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

-- Terça 15h de uma semana futura, com o `::timestamp` que a 0013 ensinou.
v_terca := ((date_trunc('week', ((now() at time zone 'America/Sao_Paulo')::date + 8)::timestamp)
             + interval '1 day' + interval '15 hours')::timestamp) at time zone 'America/Sao_Paulo';

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Primeira Da Fila', '5511900008801', 'em_atendimento') returning id into v_p1;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Segunda Da Fila', '5511900008802', 'em_atendimento') returning id into v_p2;

insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca, v_terca + interval '50 min', 'avulsa', 200.00, 24, 50)
  returning id into v_vaga;

-- As duas na fila, sem janela: qualquer hora serve, e a ordem sai da regra.
insert into public.fila_encaixe (paciente_id) values (v_p1);
insert into public.fila_encaixe (paciente_id) values (v_p2);

perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of1;

-- ---------------------------------------------------------------- 1
if v_of1 is null then raise exception '1 FUROU: não nasceu oferta nenhuma'; end if;

select id, estado into v_msg, v_estado
  from public.mensagens where chave_idem = 'oferta:' || v_of1::text;
if v_msg is null then
  raise exception '1 FUROU: a oferta nasceu sem mensagem — é o defeito da 0046d/0060d de volta';
end if;

-- Vence o prazo. É o que o relógio faria; aqui é a suíte que faz, para não
-- esperar o timeout da conta. Os **dois** relógios andam junto: `ofertas_check`
-- exige `expira_em > enviar_em`, e mexer só no de trás é violação de constraint
-- — a primeira coisa que esta suíte aprendeu rodando.
set local role postgres;
update public.ofertas set enviar_em = now() - interval '2 minutes',
                          expira_em = now() - interval '1 minute' where id = v_of1;
reset role;

-- ------------------------------------------------- 2 a 6 · o que segura a oferta
--
-- Um laço, e não cinco blocos: os estados são os do `check` de
-- `mensagens.estado` que significam "ninguém foi convidado ainda". Escrever os
-- cinco à mão deixaria o sexto de fora no dia em que ele nascer.
for v_txt in select unnest(array['pendente', 'enviando', 'na_sua_mao', 'falhou', 'barrada_no_teto'])
loop
  set local role postgres;
  update public.mensagens set estado = v_txt where id = v_msg;
  reset role;

  select public.expirar_ofertas() into n;
  if n <> 0 then
    raise exception '2-6 FUROU: com a mensagem em "%" a oferta expirou (% expiradas) — a fila queima sem ninguém ser convidado', v_txt, n;
  end if;

  select estado into v_estado from public.ofertas where id = v_of1;
  if v_estado <> 'enviada' then
    raise exception '2-6 FUROU: com a mensagem em "%" a oferta saiu de enviada para "%"', v_txt, v_estado;
  end if;

  select count(*) into n from public.ofertas where sessao_id = v_vaga;
  if n <> 1 then
    raise exception '2-6 FUROU: com a mensagem em "%" a fila andou — % ofertas nesta vaga', v_txt, n;
  end if;
end loop;

-- ---------------------------------------------------------------- 7
-- `nao_vou_mandar` grava `cancelada`, e desistir devolve a vaga ao relógio:
-- este é o único estado "não saiu" que **precisa** deixar expirar, senão a
-- decisão dela de não mandar segura a fila para sempre.
set local role postgres;
update public.mensagens set estado = 'cancelada' where id = v_msg;
reset role;

select public.expirar_ofertas() into n;
if n <> 1 then raise exception '7 FUROU: ela desistiu de mandar e a oferta não expirou (%)', n; end if;

-- A fila andou: nasceu oferta para a segunda.
select id into v_of2 from public.ofertas where sessao_id = v_vaga and estado = 'enviada';
if v_of2 is null then raise exception '7 FUROU: expirou e não chamou a próxima'; end if;
if (select paciente_id from public.ofertas where id = v_of2) = v_p1 then
  raise exception '7 FUROU: chamou a mesma pessoa de novo';
end if;

-- ---------------------------------------------------------------- 8
select id into v_msg from public.mensagens where chave_idem = 'oferta:' || v_of2::text;
if v_msg is null then raise exception '8 FUROU: a segunda oferta nasceu sem mensagem'; end if;

set local role postgres;
update public.mensagens set estado = 'enviada' where id = v_msg;
update public.ofertas set enviar_em = now() - interval '2 minutes',
                          expira_em = now() - interval '1 minute' where id = v_of2;
reset role;

select public.expirar_ofertas() into n;
if n <> 1 then raise exception '8 FUROU: mensagem enviada e vencida não expirou (%)', n; end if;
if (select estado from public.ofertas where id = v_of2) <> 'expirada' then
  raise exception '8 FUROU: a oferta não ficou expirada';
end if;
select count(*) into n from public.eventos_fila
 where oferta_id = v_of2 and tipo = 'oferta_expirada';
if n <> 1 then raise exception '8 FUROU: % eventos de expiração', n; end if;

-- ---------------------------------------------------------------- 9
-- `entregue` é o outro estado que significa que saiu. Vaga nova, porque as
-- duas da fila já foram chamadas nesta.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca + interval '1 day', v_terca + interval '1 day' + interval '50 min',
          'avulsa', 200.00, 24, 50)
  returning id into v_vaga;
perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of1;
if v_of1 is null then raise exception '9 FUROU: não ofertou na segunda vaga'; end if;

select id into v_msg from public.mensagens where chave_idem = 'oferta:' || v_of1::text;
set local role postgres;
update public.mensagens set estado = 'entregue' where id = v_msg;
update public.ofertas set enviar_em = now() - interval '2 minutes',
                          expira_em = now() - interval '1 minute' where id = v_of1;
reset role;

select public.expirar_ofertas() into n;
if n < 1 then raise exception '9 FUROU: mensagem entregue e vencida não expirou'; end if;

-- ---------------------------------------------------------------- 10
-- Oferta sem mensagem nenhuma: é o rastro que `avancar_fila` deixa quando
-- perde a linha que enfileira — e este projeto perdeu duas vezes (0046d,
-- 0060d). Segurando, a terceira trava a fila à vista em vez de queimá-la.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca + interval '2 days', v_terca + interval '2 days' + interval '50 min',
          'avulsa', 200.00, 24, 50)
  returning id into v_vaga;
perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of1;

set local role postgres;
delete from public.mensagens where chave_idem = 'oferta:' || v_of1::text;
update public.ofertas set enviar_em = now() - interval '2 minutes',
                          expira_em = now() - interval '1 minute' where id = v_of1;
reset role;

select public.expirar_ofertas() into n;
if n <> 0 then raise exception '10 FUROU: oferta sem mensagem expirou — ninguém foi convidado e a fila andou'; end if;

-- ---------------------------------------------------------------- 11
-- A 0089: o evento da criação não pode dizer "enviada".
select count(*) into n from public.eventos_fila
 where oferta_id = v_of1 and tipo = 'oferta_preparada';
if n <> 1 then raise exception '11 FUROU: % eventos oferta_preparada na criação', n; end if;

select count(*) into n from public.eventos_fila
 where oferta_id = v_of1 and tipo = 'oferta_enviada';
if n <> 0 then
  raise exception '11 FUROU: a trilha diz "oferta enviada" e nenhuma mensagem saiu — era o defeito das onze linhas';
end if;

-- ---------------------------------------------------------------- 12
-- Quem viu sair é quem grava, e grava uma vez só.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca + interval '3 days', v_terca + interval '3 days' + interval '50 min',
          'avulsa', 200.00, 24, 50)
  returning id into v_vaga;
perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of1;
select id into v_msg from public.mensagens where chave_idem = 'oferta:' || v_of1::text;

set local role postgres;
perform public.marcar_enviada(v_msg, 'teste', null);
perform public.marcar_enviada(v_msg, 'teste', null);
reset role;

select count(*) into n from public.eventos_fila
 where oferta_id = v_of1 and tipo = 'oferta_enviada';
if n <> 1 then raise exception '12 FUROU: % eventos oferta_enviada depois de duas chamadas', n; end if;

-- ---------------------------------------------------------------- 13
-- Ela mandou pelo WhatsApp dela: saiu de verdade, e o evento nasce igual.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca + interval '4 days', v_terca + interval '4 days' + interval '50 min',
          'avulsa', 200.00, 24, 50)
  returning id into v_vaga;
perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of1;
select id into v_msg from public.mensagens where chave_idem = 'oferta:' || v_of1::text;

set local role postgres;
update public.mensagens set estado = 'na_sua_mao' where id = v_msg;
reset role;

if public.marcar_enviada_a_mao(v_msg) <> true then
  raise exception '13 FUROU: marcar_enviada_a_mao recusou uma mensagem na mão dela';
end if;

select count(*) into n from public.eventos_fila
 where oferta_id = v_of1 and tipo = 'oferta_enviada';
if n <> 1 then raise exception '13 FUROU: ela mandou e a trilha não registrou (% eventos)', n; end if;

-- ------------------------------------------------------------------ recolhe
reset role;
set local role postgres;

delete from public.mensagens    where conta_id = v_conta;
delete from public.eventos_fila where conta_id = v_conta;
delete from public.ofertas      where conta_id = v_conta;
delete from public.fila_encaixe where conta_id = v_conta;
delete from public.sessoes      where conta_id = v_conta;
delete from public.enquadres    where conta_id = v_conta;
delete from public.pacientes    where conta_id = v_conta;
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B50 OK — 13 verificações, todas passaram';
end $do$;
