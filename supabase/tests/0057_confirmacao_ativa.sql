-- Teste da confirmação ativa (P3, migração 0057).
--
-- A verificação que decide o build é a nº 12: **nada nesta migração cancela
-- sessão.** Nem o silêncio, nem a recusa. Erro de agendamento é
-- responsabilidade dela perante o paciente e perante o CRP, e o produto não tem
-- CRP — e cancelar tem consequência em dinheiro, porque a política da B11 nasce
-- da hora que sai. Um cancelamento automático seria o software cobrando alguém
-- por uma decisão que ele tomou sozinho.
--
-- A segunda é a nº 16, e ela é a colisão que ninguém testa: uma pessoa pode ter
-- **uma oferta de vaga viva e uma confirmação pendente ao mesmo tempo**. Um
-- "sim" destinado à confirmação de amanhã não pode aceitar um encaixe que ela
-- nem lembrava ter recebido — senão duas pessoas ficam com o mesmo horário na
-- cabeça.
--
-- E a nº 18 é o defeito que esta migração conserta na anterior: o
-- `recalcular_eixos` da 0056 **apagava a resposta do paciente** no primeiro
-- recálculo que passasse, porque `'confirmada'` não estava na lista dos eixos
-- que ele preserva.
--
--   parte 1 · o padrão, e o que ele protege
--     1. `confirmacao_horas_antes` nasce nulo em todo enquadre que existe
--     2. a faixa é fechada: 2 a 168 horas
--     3. o template existe e é essencial, com motivo escrito
--     4. nem a tela nem o anônimo pedem confirmação — só o cron
--
--   parte 2 · o pedido
--     5. sem confirmação ligada, ninguém é perguntado
--     6. com 24h ligadas, a sessão de amanhã é perguntada e vira `pendente`
--     7. a de depois de amanhã ainda não
--     8. rodar duas vezes não manda duas mensagens
--     9. o pedido não mexe no estado da agenda
--
--   parte 3 · a resposta
--    10. "sim" confirma, carimba a hora e **não** mexe no estado
--    11. "não posso" recusa, carimba, e **não** cancela nada
--    12. não existe nesta build função que cancele sessão  ← decide
--    13. resposta que ninguém entende deixa a confirmação pendente
--    14. quem não tem nada pendente recebe "sem oferta"
--
--   parte 4 · o silêncio
--    15. o que não foi respondido vira `silenciosa` perto da hora
--    16. e continua `prevista`: silêncio não libera nada
--
--   parte 5 · a colisão
--    17. oferta viva e confirmação pendente: ganha a mais recente  ← decide
--
--   parte 6 · o que a 0056 apagava
--    18. a confirmação sobrevive a um recálculo de eixos  ← conserto
--
--   parte 7 · os dois números
--    19. taxa de resposta e antecedência média saem certas
--    20. e o livro de outra conta não é legível daqui
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0057_confirmacao_ativa.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111157';
  b_auth uuid := '22222222-2222-4222-8222-222222222157';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  ana uuid; bia uuid; caio uuid;
  e_ana uuid; e_bia uuid;
  s_amanha uuid; s_depois uuid; s_bia uuid; s_silencio uuid; s_colisao uuid;
  vaga uuid; oferta uuid;
  j jsonb; n integer; erro text; txt text; r record;
  hoje date;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Confirma Teste', 'Confirma Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'confirma@teste.sessoes.com.br', '{"nome":"Confirma Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (b_auth, 'confirmaviz@teste.sessoes.com.br', '{"nome":"Confirma Vizinha"}'::jsonb);

select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
select id into a_prof from public.profissionais where conta_id = a_conta;
select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
select id into b_prof from public.profissionais where conta_id = b_conta;

hoje := public.hoje_sp();

raise notice '--- parte 1 · o padrão ---';

-- 1 · ninguém passa a pedir confirmação porque o software achou bom.
select count(*) into n
  from public.enquadres where confirmacao_horas_antes is not null;
if n > 0 then
  raise exception 'FALHOU 1: % enquadre(s) já nasceram pedindo confirmação — o padrão é não pedir, e ligar é decisão de quem atende', n;
end if;
raise notice 'ok 1 · o padrão é não pedir';

-- 2 · a faixa é fechada dos dois lados.
--
-- Menos de duas horas não dá tempo de reagir a nada; mais de uma semana
-- ninguém lembra do que confirmou.
perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Ana Confirma', '5511900000571', 'em_atendimento') returning id into ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Bia Silencio', '5511900000572', 'em_atendimento') returning id into bia;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Caio Colisao', '5511900000573', 'em_atendimento') returning id into caio;

insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual)
  values (ana, 1, '09:00', 50, 200, 24, 50) returning id into e_ana;
insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual)
  values (bia, 2, '10:00', 50, 200, 24, 50) returning id into e_bia;
reset role;

erro := null;
begin
  set local role postgres;
  update public.enquadres set confirmacao_horas_antes = 1 where id = e_ana;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 2: aceitou pedir confirmação com 1 hora de antecedência — não dá tempo de reagir a nada';
end if;

erro := null;
begin
  set local role postgres;
  update public.enquadres set confirmacao_horas_antes = 400 where id = e_ana;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 2: aceitou pedir confirmação com 400 horas de antecedência';
end if;
raise notice 'ok 2 · a faixa é fechada';

-- 3 · o template é essencial, e o motivo está escrito.
select essencial, motivo into r from public.templates where codigo = 'confirmacao_de_sessao';
if not found then
  raise exception 'FALHOU 3: o template da confirmação não existe — a FK de mensagens recusaria o envio';
end if;
if r.essencial is not true then
  raise exception 'FALHOU 3: a confirmação não é essencial — barrada por teto, a hora apareceria como "não respondeu" sem nunca ter sido perguntada, e ela decidiria sobre um silêncio que o sistema inventou';
end if;
if length(coalesce(r.motivo, '')) < 40 then
  raise exception 'FALHOU 3: o motivo da classificação está vazio ou curto — ele existe para quem for classificar o próximo';
end if;
raise notice 'ok 3 · o template é essencial, com o motivo escrito';

-- 4 · quem pede é o cron, e ninguém mais.
--
-- Uma tela que pudesse "pedir confirmação agora" mandaria a mensagem fora da
-- hora combinada, que é o oposto de confirmar.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname in ('pedir_confirmacoes', 'marcar_silenciosas')
   and (has_function_privilege('authenticated', p.oid, 'execute')
        or has_function_privilege('anon', p.oid, 'execute'));
if n > 0 then
  raise exception 'FALHOU 4: a tela ou o anônimo podem disparar confirmação (% função(ões))', n;
end if;
raise notice 'ok 4 · só o cron pede';

raise notice '--- parte 2 · o pedido ---';

-- Três sessões: amanhã (Ana, com confirmação ligada), depois de amanhã (Ana),
-- e amanhã da Bia (sem confirmação ligada).
set local role postgres;
update public.enquadres set confirmacao_horas_antes = 24 where id = e_ana;
reset role;

-- Como o motor: sessão de recorrência com `enquadre_id` é materializada pelo
-- sistema, não digitada pela tela — a política de INSERT de `sessoes` recusa
-- essa forma vinda de `authenticated`, e está certa.
set local role postgres;
insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, e_ana, now() + interval '20 hours', now() + interval '20 hours 50 minutes',
          'recorrencia', 'prevista', 200, 24, 50) returning id into s_amanha;
insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, e_ana, now() + interval '60 hours', now() + interval '60 hours 50 minutes',
          'recorrencia', 'prevista', 200, 24, 50) returning id into s_depois;
insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, e_bia, now() + interval '21 hours', now() + interval '21 hours 50 minutes',
          'recorrencia', 'prevista', 200, 24, 50) returning id into s_bia;
reset role;

set local role postgres;
select public.pedir_confirmacoes() into n;
reset role;

-- 6 · a de amanhã foi perguntada.
select eixo_confirmacao, confirmacao_pedida_em, estado into r
  from public.sessoes where id = s_amanha;
if r.eixo_confirmacao <> 'pendente' then
  raise exception 'FALHOU 6: a sessão dentro da janela ficou em "%"', r.eixo_confirmacao;
end if;
if r.confirmacao_pedida_em is null then
  raise exception 'FALHOU 6: o pedido não foi carimbado — sem ele, a taxa de resposta seria um palpite sobre a própria feature';
end if;

select count(*) into n from public.mensagens
 where paciente_id = ana and template = 'confirmacao_de_sessao';
if n <> 1 then
  raise exception 'FALHOU 6: saíram % mensagens de confirmação (esperado 1)', n;
end if;

-- 9 · e o estado da agenda não mudou.
if r.estado <> 'prevista' then
  raise exception 'FALHOU 9: pedir confirmação mexeu no eixo agenda (ficou "%") — a hora continua reservada, ela só passou a ser reservada COM pergunta', r.estado;
end if;
raise notice 'ok 6 e 9 · perguntou, carimbou, e não mexeu na agenda';

-- 7 · a de depois de amanhã ainda não.
select eixo_confirmacao into txt from public.sessoes where id = s_depois;
if txt <> 'nao_pedida' then
  raise exception 'FALHOU 7: perguntou com 60 horas de antecedência, e o ajuste é 24 (ficou "%")', txt;
end if;
raise notice 'ok 7 · fora da janela, ninguém é perguntado';

-- 5 · e quem não ligou confirmação não é perguntado nunca.
select eixo_confirmacao into txt from public.sessoes where id = s_bia;
if txt <> 'nao_pedida' then
  raise exception 'FALHOU 5: perguntou a quem não pediu confirmação — o padrão é não pedir';
end if;
select count(*) into n from public.mensagens
 where paciente_id = bia and template = 'confirmacao_de_sessao';
if n <> 0 then
  raise exception 'FALHOU 5: mandou mensagem para quem não ligou confirmação';
end if;
raise notice 'ok 5 · quem não ligou não é perguntado';

-- 8 · rodar de novo não manda de novo.
set local role postgres;
perform public.pedir_confirmacoes();
reset role;
select count(*) into n from public.mensagens
 where paciente_id = ana and template = 'confirmacao_de_sessao';
if n <> 1 then
  raise exception 'FALHOU 8: a segunda passada do cron mandou outra mensagem (% no total)', n;
end if;
raise notice 'ok 8 · o cron é idempotente';

raise notice '--- parte 3 · a resposta ---';

-- 10 · "sim" confirma.
set local role postgres;
j := public.responder_do_whatsapp('teste', 'msg-0057-sim', '5511900000571', 'sim');
reset role;

select eixo_confirmacao, confirmacao_respondida_em, estado into r
  from public.sessoes where id = s_amanha;
if r.eixo_confirmacao <> 'confirmada' then
  raise exception 'FALHOU 10: o "sim" deixou o eixo em "%" (resposta: %)', r.eixo_confirmacao, j;
end if;
if r.confirmacao_respondida_em is null then
  raise exception 'FALHOU 10: a resposta não foi carimbada — sem ela não há antecedência média';
end if;
if r.estado <> 'prevista' then
  raise exception 'FALHOU 10: a resposta mexeu no eixo agenda (ficou "%") — invariante 3: quem responde ao paciente é o eixo', r.estado;
end if;
raise notice 'ok 10 · o sim move o eixo, e só o eixo';

-- 11 · "não posso" recusa, e não cancela.
set local role postgres;
update public.sessoes set eixo_confirmacao = 'pendente', confirmacao_respondida_em = null
 where id = s_amanha;
j := public.responder_do_whatsapp('teste', 'msg-0057-nao', '5511900000571', 'nao posso');
reset role;

select eixo_confirmacao, estado, cancelada_em into r from public.sessoes where id = s_amanha;
if r.eixo_confirmacao <> 'recusada' then
  raise exception 'FALHOU 11: o "não posso" deixou o eixo em "%" (resposta: %)', r.eixo_confirmacao, j;
end if;
if r.estado <> 'prevista' or r.cancelada_em is not null then
  raise exception 'FALHOU 11: a recusa CANCELOU a sessão sozinha (estado "%") — cancelar tem consequência em dinheiro, e quem decide é ela, com o custo à vista', r.estado;
end if;
select count(*) into n from public.cobrancas where sessao_id = s_amanha;
if n <> 0 then
  raise exception 'FALHOU 11: a recusa gerou cobrança — o software cobrou alguém por uma decisão que ele tomou sozinho';
end if;
raise notice 'ok 11 · a recusa avisa, e não decide';

-- 12 · e não existe nesta build função que cancele sessão.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and (p.proname like '%liberar_horario%' or p.proname like '%liberar_por_silencio%'
        or p.proname like '%cancelar_por_silencio%' or p.proname like '%auto_cancel%');
if n > 0 then
  raise exception 'FALHOU 12: apareceu função de liberar horário automaticamente (%) — o sistema nunca libera sozinho, e o produto não tem CRP', n;
end if;

select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname in ('pedir_confirmacoes', 'marcar_silenciosas')
   and pg_get_functiondef(p.oid) like '%cancelar_sessao%';
if n > 0 then
  raise exception 'FALHOU 12: a máquina de confirmação chama cancelar_sessao';
end if;
raise notice 'ok 12 · nada aqui cancela sessão';

-- 13 · frase inteira deixa pendente, e o robô não insiste.
set local role postgres;
update public.sessoes set eixo_confirmacao = 'pendente', confirmacao_respondida_em = null
 where id = s_amanha;
j := public.responder_do_whatsapp('teste', 'msg-0057-frase', '5511900000571',
       'oi, acho que consigo mas vou confirmar com meu chefe');
reset role;

select eixo_confirmacao into txt from public.sessoes where id = s_amanha;
if txt <> 'pendente' then
  raise exception 'FALHOU 13: uma frase inteira virou "%" — o robô adivinhou', txt;
end if;
if j->>'estado' <> 'nao_entendi' then
  raise exception 'FALHOU 13: devolveu "%"', j->>'estado';
end if;
raise notice 'ok 13 · o que não se entende fica pendente, sem robô insistindo';

-- 14 · quem não tem nada pendente.
set local role postgres;
j := public.responder_do_whatsapp('teste', 'msg-0057-orfa', '5511999999999', 'sim');
reset role;
if j->>'estado' <> 'sem_oferta' then
  raise exception 'FALHOU 14: resposta sem dono devolveu "%"', j->>'estado';
end if;
raise notice 'ok 14 · resposta sem dono é registrada, não adivinhada';

raise notice '--- parte 4 · o silêncio ---';

-- 15 e 16 · perto da hora, o não respondido vira sinal — e só isso.
set local role postgres;
insert into public.sessoes (conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, e_bia, now() + interval '90 minutes', now() + interval '140 minutes',
          'recorrencia', 'prevista', 200, 24, 50) returning id into s_silencio;
reset role;

set local role postgres;
update public.sessoes
   set eixo_confirmacao = 'pendente', confirmacao_pedida_em = now() - interval '20 hours'
 where id = s_silencio;
select public.marcar_silenciosas() into n;
reset role;

select eixo_confirmacao, estado, cancelada_em into r from public.sessoes where id = s_silencio;
if r.eixo_confirmacao <> 'silenciosa' then
  raise exception 'FALHOU 15: perto da hora e sem resposta, o eixo ficou "%"', r.eixo_confirmacao;
end if;
if r.estado <> 'prevista' or r.cancelada_em is not null then
  raise exception 'FALHOU 16: o silêncio liberou o horário (estado "%") — quem não respondeu pode estar sem bateria, e ela nunca liberou por silêncio', r.estado;
end if;

-- E a sessão de amanhã, que ainda está longe, não virou silenciosa.
select eixo_confirmacao into txt from public.sessoes where id = s_amanha;
if txt = 'silenciosa' then
  raise exception 'FALHOU 15: marcou como silenciosa uma sessão que ainda tem tempo de responder';
end if;
raise notice 'ok 15 e 16 · silêncio é sinal, e sinal não tem botão';

raise notice '--- parte 5 · a colisão ---';

-- 17 · oferta viva e confirmação pendente no mesmo telefone.
--
-- O Caio entra na fila, recebe uma oferta, e **depois** recebe o pedido de
-- confirmação de uma sessão dele. Um "sim" tem de resolver a confirmação, que
-- é a última mensagem que ele viu — e não aceitar um encaixe que ele nem
-- lembrava ter recebido.
set local role authenticated;
insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual, confirmacao_horas_antes)
  values (caio, 3, '15:00', 50, 200, 24, 50, 24);
reset role;

set local role postgres;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, caio, now() + interval '30 hours', now() + interval '30 hours 50 minutes',
          'avulsa', 'prevista', 200, 24, 50) returning id into s_colisao;

-- Uma vaga cancelada para gerar oferta de verdade.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (a_conta, a_prof, ana, now() + interval '40 hours', now() + interval '40 hours 50 minutes',
          'avulsa', 'cancelada_cedo', 200, 240, 0, now(), 'paciente') returning id into vaga;
reset role;

set local role postgres;
insert into public.ofertas (conta_id, sessao_id, paciente_id, estado, enviar_em, expira_em)
  values (a_conta, vaga, caio, 'enviada', now() - interval '3 hours', now() + interval '3 hours')
  returning id into oferta;

-- A confirmação é MAIS RECENTE que a oferta.
update public.sessoes
   set eixo_confirmacao = 'pendente', confirmacao_pedida_em = now() - interval '10 minutes'
 where id = s_colisao;

j := public.responder_do_whatsapp('teste', 'msg-0057-colisao', '5511900000573', 'sim');
reset role;

select eixo_confirmacao into txt from public.sessoes where id = s_colisao;
if txt <> 'confirmada' then
  raise exception 'FALHOU 17: o "sim" não resolveu a confirmação mais recente (eixo "%", resposta: %)', txt, j;
end if;

select estado into txt from public.ofertas where id = oferta;
if txt <> 'enviada' then
  raise exception 'FALHOU 17: o "sim" da confirmação aceitou uma vaga de encaixe (oferta ficou "%") — duas pessoas ficariam com o mesmo horário na cabeça', txt;
end if;
raise notice 'ok 17 · na colisão, ganha a mensagem mais recente';

raise notice '--- parte 6 · o que a 0056 apagava ---';

-- 18 · a confirmação sobrevive a um recálculo de eixos.
--
-- O `case` da 0056 caía em 'nao_pedida' sempre que o eixo estivesse
-- 'confirmada' e o estado não fosse 'confirmada' — e a partir da 0057 é
-- exatamente o que acontece com quem responde "sim". A primeira cobrança
-- gravada depois disso apagava a confirmação em silêncio.
set local role authenticated;
insert into public.cobrancas (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao, competencia, estado)
  values (a_conta, caio, s_colisao, 'sessao', 'avulsa', 200, 200, date_trunc('month', hoje)::date, 'aberta');
reset role;

select eixo_confirmacao, eixo_financeiro into r from public.sessoes where id = s_colisao;
if r.eixo_confirmacao <> 'confirmada' then
  raise exception 'FALHOU 18: gravar uma cobrança apagou a confirmação do paciente (eixo virou "%")', r.eixo_confirmacao;
end if;
if r.eixo_financeiro <> 'cobrada' then
  raise exception 'FALHOU 18: o eixo financeiro parou de seguir a cobrança (ficou "%")', r.eixo_financeiro;
end if;
raise notice 'ok 18 · a resposta do paciente não se apaga sozinha';

raise notice '--- parte 7 · os dois números ---';

-- 19 · a taxa e a antecedência.
set local role authenticated;
j := public.resposta_das_confirmacoes(hoje - 1, hoje + 7);
reset role;

if (j->>'pedidas')::int < 3 then
  raise exception 'FALHOU 19: contou % pedidas (esperado ao menos 3)', j->>'pedidas';
end if;
if (j->>'confirmadas')::int < 1 then
  raise exception 'FALHOU 19: nenhuma confirmada';
end if;
if (j->>'silenciosas')::int < 1 then
  raise exception 'FALHOU 19: nenhuma silenciosa';
end if;
if j->>'antecedencia_media_h' is null then
  raise exception 'FALHOU 19: sem antecedência média — é metade do que decide se o bloco se paga';
end if;
if (j->>'antecedencia_media_h')::numeric <= 0 then
  raise exception 'FALHOU 19: antecedência média de % horas — negativa ou zero significa resposta depois da sessão', j->>'antecedencia_media_h';
end if;
raise notice 'ok 19 · os dois números existem desde o primeiro dia';

-- 20 · e são da conta.
perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
j := public.resposta_das_confirmacoes(hoje - 1, hoje + 7);
reset role;
if (j->>'pedidas')::int <> 0 then
  raise exception 'FALHOU 20: a vizinha leu % confirmações da outra conta', j->>'pedidas';
end if;
raise notice 'ok 20 · os números são da conta';

-- ============================================================ recolher o rastro
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.mensagens_recebidas where provedor_msg_id like 'msg-0057-%';
delete from public.mensagens where conta_id in (a_conta, b_conta);
delete from public.eventos_fila where conta_id in (a_conta, b_conta);
delete from public.ofertas where conta_id in (a_conta, b_conta);
delete from public.fila_encaixe where conta_id in (a_conta, b_conta);
delete from public.cobrancas where conta_id in (a_conta, b_conta);
delete from public.sessoes where conta_id in (a_conta, b_conta);
delete from public.enquadres where conta_id in (a_conta, b_conta);
delete from public.pacientes where conta_id in (a_conta, b_conta);
delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Confirma Teste', 'Confirma Vizinha');
reset role;

raise notice 'SUITE 0057 PASSOU: 20 verificações';
end $do$;
