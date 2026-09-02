-- Teste do canal manual do plano Grátis (OP9, migração 0061).
--
-- **A build inteira é uma troca de quem aperta o botão**, e por isso quase todas
-- as verificações são sobre o que *continua* acontecendo. Cinco decidem:
--
--   · a **5**, que exige que template essencial nasça `pendente` **mesmo no
--     Grátis**. Lembrete de véspera, aviso de desmarque, confirmação de encaixe
--     e pedido de confirmação saem sozinhos em qualquer plano, porque quem
--     ficaria sem eles é a paciente, que não escolheu plano nenhum. Se um dia
--     alguém "otimizar" o Grátis apagando esta linha, é aqui que reprova;
--   · a **9**, que confere a **ordem dos gatilhos**. `mensagens_retrato` termina
--     com `new.estado := 'pendente'`, e gatilhos do mesmo evento disparam em
--     ordem alfabética do nome. Um gatilho novo chamado `mensagens_canal` seria
--     apagado em silêncio — sem erro, sem log, com a mensagem saindo sozinha no
--     plano que não devia. O `z` do nome é a ordem de execução;
--   · a **13**, que é o coração: **oferta cuja mensagem ainda está na mão dela
--     não expira.** Sem isso, a vaga seria oferecida a quatro pessoas em duas
--     horas sem nenhuma ter sido convidada, e o rastro diria que ninguém quis —
--     exatamente o modo de falha que o cabeçalho da 0046 descreve;
--   · a **16**, que prova que a trava **destrava**: cancelar a mensagem devolve
--     a oferta ao relógio. Uma trava sem saída seria um defeito com nome bonito;
--   · a **24**, que exige mediana **nula** e não zero quando ela nunca mandou
--     nada. Zero minuto seria a afirmação de que ela é instantânea.
--
-- Cuidados de escrita, todos cicatriz desta obra: toda variável leva `v_`
-- (a 0060b), nenhum alias de uma letra (a 0052c), e varredura de corpo de
-- função usa `position()` e nunca `like`, porque `_` é curinga (a 0060d).
--
--   parte 1 · o canal é do plano
--     1. Grátis é manual; os três pagos, plataforma
--     2. o terceiro degrau não existe no check — plano não anuncia canal que não há  ← decide
--     3. no Grátis, o aviso de cobrança nasce na mão dela
--     4. ...e a oferta de vaga também
--     5. mas o essencial nasce pendente, no Grátis também                            ← decide
--     6. os quatro essenciais, um a um
--     7. em conta paga, nada nasce na mão de ninguém
--     8. o gatilho lê templates.essencial, e não uma lista escrita à mão
--     9. e dispara DEPOIS do mensagens_retrato                                       ← decide
--
--   parte 2 · o worker não toca no que é dela
--    10. reservar_mensagens não reserva o que está na mão dela
--    11. ...e não barra também — não é mensagem barrada, é mensagem dela
--    12. o que está na mão dela não tem enviada_em: não saiu
--
--   parte 3 · o relógio da oferta
--    13. oferta com mensagem na mão dela não expira, mesmo vencida               ← decide
--    14. ...e continua sendo uma oferta só
--    15. quando ela manda, o relógio recomeça agora
--    16. e se ela desistir, a oferta volta a vencer — a trava destrava          ← decide
--    17. em conta paga, a expiração continua exatamente como era
--
--   parte 4 · a caixa dela
--    18. a caixa devolve o que espera, com o nome de quem vai receber
--    19. ...e o id da oferta, extraído da chave
--    20. marcar duas vezes não move o relógio duas vezes
--    21. não se marca mensagem de outra conta
--    22. a policy é estreita: não dá para escrever 'entregue' por este caminho  ← decide
--    23. nem para mexer numa pendente por ele
--
--   parte 5 · a medida, e o que ela recusa medir
--    24. sem envio nenhum, a mediana é NULA e não zero                          ← decide
--    25. em plano pago o resumo diz que não é manual
--    26. a vizinha não lê o resumo da outra, e o anônimo não executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0061_o_dedo_e_dela.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111161';
  v_b_auth uuid := '22222222-2222-4222-8222-222222222161';
  v_a_conta uuid; v_a_prof uuid; v_b_conta uuid; v_b_prof uuid;
  v_ana uuid; v_bia uuid; v_cida uuid;
  v_msg uuid; v_msg2 uuid;
  v_sessao uuid; v_oferta uuid; v_oferta_b uuid; v_sessao_b uuid;
  v_situacao text; v_texto text; v_erro text;
  v_n integer; v_ok boolean; v_j jsonb;
  v_hoje date; v_expira timestamptz; v_expira2 timestamptz;
  v_linha record;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.contas where nome in ('Dedo Teste', 'Dedo Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'dedo@teste.sessoes.com.br', '{"nome":"Dedo Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'dedoviz@teste.sessoes.com.br', '{"nome":"Dedo Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id into v_b_prof from public.profissionais where conta_id = v_b_conta;

v_hoje := public.hoje_sp();

-- A é Grátis (manual). B é Solo (plataforma). É o contraste do arquivo inteiro.
set local role postgres;
update public.contas set plano = 'gratis' where id = v_a_conta;
update public.contas set plano = 'solo'   where id = v_b_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Dedo', '5511900000611', 'em_atendimento') returning id into v_ana;
-- Uma segunda paciente na conta A, e ela existe por causa de um índice: além do
-- `oferta_viva_unica` (parcial, uma oferta viva por sessão), há o
-- `oferta_por_paciente_e_vaga`, que é `unique (sessao_id, paciente_id)` **sem
-- `where`** — a mesma pessoa nunca recebe duas ofertas da mesma vaga, nem
-- depois de a primeira expirar. É invariante de produto, não detalhe de teste:
-- insistir com quem já não quis é exatamente o que a fila não faz.
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Cida Dedo', '5511900000613', 'em_atendimento') returning id into v_cida;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_b_prof, 'Bia Dedo', '5511900000612', 'em_atendimento') returning id into v_bia;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · o canal é do plano ---';

-- 1 · O canal de cada plano.
select count(*)::integer into v_n from public.planos
 where codigo = 'gratis' and canal_saida = 'manual';
if v_n <> 1 then
  raise exception 'FALHOU 1: o Grátis não está em manual';
end if;
select count(*)::integer into v_n from public.planos
 where codigo <> 'gratis' and canal_saida <> 'plataforma';
if v_n <> 0 then
  raise exception 'FALHOU 1: % plano(s) pago(s) fora de plataforma', v_n;
end if;
raise notice 'ok 1 · Grátis manual, pagos plataforma';

-- 2 · O terceiro degrau não existe.  ← decide
--
-- "Automático E do número dela" é o quadrante vazio do mercado (`claude/24`) e
-- depende de BSP com Embedded Signup, que não existe. Um valor `proprio` no
-- check seria um plano anunciando canal inexistente — a mesma classe de erro
-- que a 0045 proibiu com `recursos`.
set local role postgres;
begin
  update public.planos set canal_saida = 'proprio' where codigo = 'pro';
  reset role;
  raise exception 'FALHOU 2: o check aceitou um canal que o produto não tem';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 2 · só existem os dois canais que existem';

-- 3 · No Grátis, o que gera negócio novo nasce na mão dela.
set local role authenticated;
v_msg := public.enfileirar_mensagem(v_ana, 'aviso_de_cobranca', 'dedo0061-cob', '{}'::jsonb);
reset role;

select estado into v_situacao from public.mensagens where id = v_msg;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 3: aviso de cobrança nasceu % no Grátis (esperado na_sua_mao)', v_situacao;
end if;
raise notice 'ok 3 · a cobrança nasce na mão dela';

-- 4 · A oferta de vaga também.
set local role authenticated;
v_msg2 := public.enfileirar_mensagem(v_ana, 'oferta_de_vaga', 'dedo0061-of', '{}'::jsonb);
reset role;

select estado into v_situacao from public.mensagens where id = v_msg2;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 4: oferta de vaga nasceu %', v_situacao;
end if;
raise notice 'ok 4 · a oferta também';

-- 5 · O essencial nasce pendente, no Grátis também.  ← decide
--
-- Quem ficaria sem o lembrete é a paciente. Ela não escolheu o plano, não sabe
-- que existe um, e ir até o consultório para encontrar a porta fechada não é
-- um custo que se transfere para economizar quatro centavos.
set local role authenticated;
perform public.enfileirar_mensagem(v_ana, 'lembrete_de_sessao', 'dedo0061-lem', '{}'::jsonb);
reset role;

select estado into v_situacao from public.mensagens where chave_idem = 'dedo0061-lem';
if v_situacao <> 'pendente' then
  raise exception 'FALHOU 5: o lembrete de véspera nasceu % no Grátis — o limite passou a ser cobrado da paciente', v_situacao;
end if;
raise notice 'ok 5 · o essencial sai sozinho, em qualquer plano';

-- 6 · E os outros essenciais também, um a um.
set local role authenticated;
perform public.enfileirar_mensagem(v_ana, 'aviso_de_desmarque', 'dedo0061-des', '{}'::jsonb);
perform public.enfileirar_mensagem(v_ana, 'encaixe_confirmado', 'dedo0061-enc', '{}'::jsonb);
reset role;

select count(*)::integer into v_n from public.mensagens
 where chave_idem in ('dedo0061-des', 'dedo0061-enc') and estado = 'pendente';
if v_n <> 2 then
  raise exception 'FALHOU 6: só % dos dois essenciais nasceram pendentes', v_n;
end if;
raise notice 'ok 6 · desmarque e encaixe confirmado, idem';

-- 7 · Em conta paga, nada nasce na mão de ninguém.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.enfileirar_mensagem(v_bia, 'aviso_de_cobranca', 'dedo0061-pago', '{}'::jsonb);
reset role;

select estado into v_situacao from public.mensagens where chave_idem = 'dedo0061-pago';
if v_situacao <> 'pendente' then
  raise exception 'FALHOU 7: no Solo a cobrança nasceu % (esperado pendente)', v_situacao;
end if;
raise notice 'ok 7 · o pago manda sozinho, como sempre mandou';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

-- 8 · O gatilho lê a classificação, e não uma lista.
--
-- Uma segunda lista de códigos escrita no corpo seria a que esquece o oitavo
-- template. `templates.essencial` já é obrigatório para todo template novo, e a
-- chave estrangeira recusa mensagem sem linha lá.
v_texto := pg_get_functiondef('public.mensagem_escolhe_o_canal()'::regprocedure);
if position('templates' in v_texto) = 0 or position('essencial' in v_texto) = 0 then
  raise exception 'FALHOU 8: o gatilho não consulta templates.essencial';
end if;
if position('lembrete_de_sessao' in v_texto) > 0
   or position('aviso_de_desmarque' in v_texto) > 0 then
  raise exception 'FALHOU 8: o gatilho tem lista de códigos no corpo — é a lista que esquece o próximo template';
end if;
raise notice 'ok 8 · a classificação é a fonte, e é uma só';

-- 9 · A ordem dos gatilhos.  ← decide
--
-- `mensagens_retrato` termina com `new.estado := 'pendente'`. Gatilhos do mesmo
-- evento disparam em ordem alfabética do nome — um gatilho de canal chamado
-- `mensagens_canal` seria apagado sem erro nenhum, e o sintoma seria a mensagem
-- saindo sozinha no plano que não devia.
select count(*)::integer into v_n
  from pg_trigger tg1
  join pg_class cl1 on cl1.oid = tg1.tgrelid
 where cl1.relname = 'mensagens'
   and not tg1.tgisinternal
   and tg1.tgname = 'mensagens_z_o_canal_do_plano'
   and tg1.tgname > 'mensagens_retrato';
if v_n <> 1 then
  raise exception 'FALHOU 9: o gatilho do canal não vem depois de mensagens_retrato na ordem alfabética — ele seria sobrescrito em silêncio';
end if;
raise notice 'ok 9 · o gatilho do canal dispara por último, e é o nome que garante';

raise notice '--- parte 2 · o worker não toca no que é dela ---';

-- 10 e 11 · A reserva ignora o que é dela, e não a barra.
set local role postgres;
update public.mensagens set agendada_para = now() - interval '5 minutes'
 where id in (v_msg, v_msg2);
perform public.reservar_mensagens(50);
reset role;

select estado into v_situacao from public.mensagens where id = v_msg;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 10: o worker mexeu numa mensagem que é dela (estado %)', v_situacao;
end if;
raise notice 'ok 10 · o worker não reserva o que está na mão dela';
raise notice 'ok 11 · e não barra — não é mensagem barrada, é mensagem dela';

-- 12 · Não saiu, então não tem hora de saída.
select enviada_em into v_expira from public.mensagens where id = v_msg;
if v_expira is not null then
  raise exception 'FALHOU 12: mensagem na mão dela já tem enviada_em — o carimbo diria que saiu algo que não saiu';
end if;
raise notice 'ok 12 · sem enviada_em: não saiu';

raise notice '--- parte 3 · o relógio da oferta ---';

-- O cenário: uma sessão e uma oferta viva, já vencida pelo relógio, com a
-- mensagem dela ainda na caixa.
set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (v_a_conta, v_a_prof, v_ana,
          (v_hoje + 1 + time '10:00') at time zone 'America/Sao_Paulo',
          (v_hoje + 1 + time '10:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'cancelada_tarde', 200.00, 24, 50, now(), 'paciente')
  returning id into v_sessao;

insert into public.ofertas
  (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em, estado)
  values (v_a_conta, v_sessao, v_ana, 1,
          now() - interval '2 hours', now() - interval '1 hour', 'enviada')
  returning id into v_oferta;

insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, agendada_para)
  values (v_a_conta, v_ana, 'whatsapp', 'oferta_de_vaga', '5511900000611',
          'oferta:' || v_oferta::text, now());
reset role;

select estado into v_situacao from public.mensagens
 where chave_idem = 'oferta:' || v_oferta::text;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 13: o cenário não montou — a mensagem da oferta veio %', v_situacao;
end if;

-- 13 · Vencida no relógio, e não expira.  ← decide
set local role postgres;
perform public.expirar_ofertas();
reset role;

select estado into v_situacao from public.ofertas where id = v_oferta;
if v_situacao <> 'enviada' then
  raise exception 'FALHOU 13: a oferta expirou (%) com a mensagem ainda na mão dela — a lista de espera queima em silêncio, e ninguém foi convidado', v_situacao;
end if;
raise notice 'ok 13 · sem convite não há prazo';

-- 14 · E a fila não andou.
select count(*)::integer into v_n from public.ofertas where sessao_id = v_sessao;
if v_n <> 1 then
  raise exception 'FALHOU 14: a fila criou % ofertas para uma vaga que ninguém recebeu', v_n;
end if;
raise notice 'ok 14 · uma vaga, uma oferta, um convite';

-- 15 · Ela manda, e o relógio recomeça agora.
select expira_em into v_expira from public.ofertas where id = v_oferta;

select id into v_msg from public.mensagens
 where chave_idem = 'oferta:' || v_oferta::text;

set local role authenticated;
v_ok := public.marcar_enviada_a_mao(v_msg);
reset role;

if not v_ok then
  raise exception 'FALHOU 15: marcar_enviada_a_mao devolveu falso';
end if;

select expira_em into v_expira2 from public.ofertas where id = v_oferta;
if v_expira2 <= now() then
  raise exception 'FALHOU 15: o prazo continuou no passado depois de ela mandar — o relógio estava contando o tempo dela';
end if;
if v_expira2 <= v_expira then
  raise exception 'FALHOU 15: o prazo não recomeçou (era %, ficou %)', v_expira, v_expira2;
end if;

select estado, enviada_a_mao into v_situacao, v_ok from public.mensagens where id = v_msg;
if v_situacao <> 'enviada' or not v_ok then
  raise exception 'FALHOU 15: a mensagem ficou % com enviada_a_mao=%', v_situacao, v_ok;
end if;
raise notice 'ok 15 · o relógio começa quando a paciente é convidada';

-- 16 · A trava destrava.  ← decide
--
-- Sem isto, uma oferta que ela decidiu não fazer ficaria parada para sempre na
-- caixa **e** segurando a fila, porque a expiração passou a esperar por ela.
--
-- A oferta 1 sai de cena ANTES de a 2 entrar: `oferta_viva_unica` é um índice
-- único parcial por sessão, e ele é o que impede a fila de convidar duas
-- pessoas para a mesma hora. A primeira redação deste bloco inseria antes de
-- expirar e reprovou — pelo índice certo, no lugar certo.
set local role postgres;
update public.ofertas set estado = 'expirada', respondida_em = now() where id = v_oferta;
insert into public.ofertas
  (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em, estado)
  values (v_a_conta, v_sessao, v_cida, 2,
          now() - interval '2 hours', now() - interval '1 hour', 'enviada')
  returning id into v_oferta_b;

insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, agendada_para)
  values (v_a_conta, v_cida, 'whatsapp', 'oferta_de_vaga', '5511900000613',
          'oferta:' || v_oferta_b::text, now())
  returning id into v_msg2;
reset role;

set local role authenticated;
v_ok := public.nao_vou_mandar(v_msg2);
reset role;
if not v_ok then
  raise exception 'FALHOU 16: nao_vou_mandar devolveu falso';
end if;

set local role postgres;
perform public.expirar_ofertas();
reset role;

select estado into v_situacao from public.ofertas where id = v_oferta_b;
if v_situacao <> 'expirada' then
  raise exception 'FALHOU 16: a oferta ficou % depois de ela desistir de mandar — a trava não destrava, e a fila fica parada para sempre', v_situacao;
end if;
raise notice 'ok 16 · desistir devolve a oferta ao relógio';

-- 17 · Em conta paga, a expiração continua exatamente como era.
set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (v_b_conta, v_b_prof, v_bia,
          (v_hoje + 1 + time '11:00') at time zone 'America/Sao_Paulo',
          (v_hoje + 1 + time '11:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'cancelada_tarde', 200.00, 24, 50, now(), 'paciente')
  returning id into v_sessao_b;

insert into public.ofertas
  (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em, estado)
  values (v_b_conta, v_sessao_b, v_bia, 1,
          now() - interval '2 hours', now() - interval '1 hour', 'enviada')
  returning id into v_oferta_b;

perform public.expirar_ofertas();
reset role;

select estado into v_situacao from public.ofertas where id = v_oferta_b;
if v_situacao <> 'expirada' then
  raise exception 'FALHOU 17: a oferta da conta paga ficou % — a condição nova alcançou quem ela não devia alcançar', v_situacao;
end if;
raise notice 'ok 17 · no pago o relógio é o de sempre';

raise notice '--- parte 4 · a caixa dela ---';

-- 18 e 19 · A caixa devolve o que espera, com nome e com o id da oferta.
--
-- Uma sessão nova, e não uma terceira oferta da mesma vaga: `oferta_viva_unica`
-- e `oferta_por_paciente_e_vaga` são invariantes do produto, e um teste que
-- precisasse contorná-las estaria testando outra coisa.
set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (v_a_conta, v_a_prof, v_ana,
          (v_hoje + 2 + time '10:00') at time zone 'America/Sao_Paulo',
          (v_hoje + 2 + time '10:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'cancelada_tarde', 200.00, 24, 50, now(), 'paciente')
  returning id into v_sessao;
insert into public.ofertas
  (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em, estado)
  values (v_a_conta, v_sessao, v_ana, 1, now(), now() + interval '40 minutes', 'enviada')
  returning id into v_oferta;
insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, agendada_para)
  values (v_a_conta, v_ana, 'whatsapp', 'oferta_de_vaga', '5511900000611',
          'oferta:' || v_oferta::text, now())
  returning id into v_msg2;
reset role;

set local role authenticated;
select count(*)::integer into v_n from public.mensagens_na_sua_mao();
if v_n < 2 then
  raise exception 'FALHOU 18: a caixa devolveu % itens (esperado ao menos 2)', v_n;
end if;

select * into v_linha from public.mensagens_na_sua_mao() where id = v_msg2;
reset role;

if v_linha.paciente <> 'Ana Dedo' then
  raise exception 'FALHOU 18: a caixa não diz para quem é (veio %)', coalesce(v_linha.paciente, 'nulo');
end if;
raise notice 'ok 18 · a caixa diz o que é e para quem';

if v_linha.oferta_id is distinct from v_oferta then
  raise exception 'FALHOU 19: o id da oferta veio % (esperado %)', coalesce(v_linha.oferta_id::text, 'nulo'), v_oferta;
end if;
raise notice 'ok 19 · e devolve a oferta, extraída da chave';

-- 20 · Marcar duas vezes não move o relógio duas vezes.
set local role authenticated;
perform public.marcar_enviada_a_mao(v_msg2);
reset role;
select expira_em into v_expira from public.ofertas where id = v_oferta;

set local role authenticated;
v_ok := public.marcar_enviada_a_mao(v_msg2);
reset role;
select expira_em into v_expira2 from public.ofertas where id = v_oferta;

if v_ok then
  raise exception 'FALHOU 20: a segunda marcação devolveu verdadeiro';
end if;
if v_expira2 is distinct from v_expira then
  raise exception 'FALHOU 20: o toque duplicado no celular esticou o prazo da paciente';
end if;
raise notice 'ok 20 · toque duplicado não estica o prazo de ninguém';

-- 21 · Não se marca mensagem de outra conta.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  perform public.marcar_enviada_a_mao(v_msg);
  reset role;
  raise exception 'FALHOU 21: a vizinha marcou mensagem da outra como enviada';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 21 · a mensagem é de quem a tem';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

-- 22 · A policy é estreita.  ← decide
--
-- `entregue` é estado de quem despacha, e ninguém despacha aqui: o produto não
-- tem recibo de leitura do WhatsApp dela. Se a policy deixasse, a tela poderia
-- um dia afirmar entrega que ninguém observou.
set local role postgres;
insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, agendada_para)
  values (v_a_conta, v_ana, 'whatsapp', 'lembrete_de_pagamento', '5511900000611',
          'dedo0061-policy', now())
  returning id into v_msg2;
reset role;

--
-- **E a recusa vem como exceção, não como zero linhas** — é a diferença entre
-- as duas metades de uma policy, e ela vale registrar: `using` *filtra* (a linha
-- some do alcance do update, e o `row_count` é 0), enquanto `with check`
-- *recusa* (o Postgres levanta 42501). Aqui a linha passa pelo `using`, porque
-- ela está mesmo na mão dela, e bate no `with check`. A verificação 23 mostra o
-- outro lado do mesmo mecanismo.
set local role postgres;
update public.mensagens set estado = 'na_sua_mao' where id = v_msg2;
reset role;

set local role authenticated;
begin
  update public.mensagens set estado = 'entregue' where id = v_msg2;
  reset role;
  raise exception 'FALHOU 22: a dona escreveu "entregue" — o produto passaria a afirmar entrega que ninguém observou';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

select estado into v_situacao from public.mensagens where id = v_msg2;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 22: a mensagem ficou % depois da recusa', v_situacao;
end if;
raise notice 'ok 22 · só sai para enviada ou cancelada, e a recusa é exceção'; 

-- 23 · E o caminho novo não alcança uma pendente.
--
-- Aqui o `using` age em vez do `with check`: a linha está `pendente`, então ela
-- nem entra no alcance do update. Zero linhas, sem exceção — a policy não
-- precisa recusar o que ela não vê.
set local role authenticated;
update public.mensagens set estado = 'enviada' where chave_idem = 'dedo0061-lem';
get diagnostics v_n = row_count;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 23: a dona marcou como enviada uma mensagem que o worker ainda vai mandar';
end if;
raise notice 'ok 23 · pendente continua sendo do worker';

raise notice '--- parte 5 · a medida ---';

-- 24 · Sem envio nenhum, a mediana é nula.  ← decide
--
-- Zero minuto seria a afirmação de que ela é instantânea. Mesma distinção que o
-- P5 fez para a ocupação e a 0060 para o NPS: ausência de dado não é elogio nem
-- acusação.
set local role postgres;
update public.mensagens set enviada_a_mao = false, enviada_em = null
 where conta_id = v_a_conta;
reset role;

set local role authenticated;
v_j := public.resumo_do_envio_manual(v_a_conta);
reset role;

if v_j->'mediana_minutos' <> 'null'::jsonb then
  raise exception 'FALHOU 24: mediana veio % sem envio nenhum', v_j->>'mediana_minutos';
end if;
if (v_j->>'manual')::boolean is not true then
  raise exception 'FALHOU 24: o resumo não reconheceu a conta como manual';
end if;
if (v_j->>'na_mao_agora')::integer < 1 then
  raise exception 'FALHOU 24: o resumo não enxergou a caixa (na_mao_agora = %)', v_j->>'na_mao_agora';
end if;
raise notice 'ok 24 · mediana nula, e a caixa contada';

-- 25 · Em plano pago, o resumo diz que não é manual.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_j := public.resumo_do_envio_manual(v_b_conta);
reset role;
if (v_j->>'manual')::boolean is not false then
  raise exception 'FALHOU 25: o Solo veio como manual';
end if;
raise notice 'ok 25 · o pago sabe que não é manual';

-- 26 · As trancas.
set local role authenticated;
begin
  perform public.resumo_do_envio_manual(v_a_conta);
  reset role;
  raise exception 'FALHOU 26: a vizinha leu o resumo da outra';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
begin
  perform * from public.mensagens_na_sua_mao();
  reset role;
  raise exception 'FALHOU 26: o anônimo abriu a caixa dela';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 26 · a caixa e a medida são de quem pergunta';

-- ============================================================ recolher o rastro
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.mensagens where conta_id in (v_a_conta, v_b_conta);
delete from public.eventos_fila where conta_id in (v_a_conta, v_b_conta);
delete from public.ofertas where conta_id in (v_a_conta, v_b_conta);
delete from public.propostas_de_cobranca where conta_id in (v_a_conta, v_b_conta);
delete from public.cobrancas where conta_id in (v_a_conta, v_b_conta);
delete from public.sessoes where conta_id in (v_a_conta, v_b_conta);
delete from public.enquadres where conta_id in (v_a_conta, v_b_conta);
delete from public.pacientes where conta_id in (v_a_conta, v_b_conta);
delete from public.trilha_acesso where conta_id in (v_a_conta, v_b_conta);
delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.profissionais where conta_id in (v_a_conta, v_b_conta);
delete from public.usuarios where conta_id in (v_a_conta, v_b_conta);
delete from public.contas where nome in ('Dedo Teste', 'Dedo Vizinha');
reset role;

raise notice 'SUITE 0061 PASSOU: 26 verificações';
end $do$;
