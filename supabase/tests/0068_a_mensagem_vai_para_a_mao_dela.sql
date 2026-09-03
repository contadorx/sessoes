-- Teste da porta de entrada da caixa "Na sua mão" (B43, migração 0068).
--
-- **A migração é uma função de dezoito linhas, e quase tudo o que importa nela
-- é o que ela recusa.** O worker chama `passar_para_a_sua_mao` quando não há
-- provedor de mensagem configurado; antes disso ele chamava `marcar_enviada`
-- com um id inventado, e a tela afirmava à psicóloga que a paciente tinha sido
-- avisada. Colhido em produção em 02/09:
--
--   template            estado    provedor    provedor_msg_id
--   lembrete_de_sessao  enviada   registro    registro:1788346982148
--
-- Quatro verificações decidem:
--
--   · a **3**, que exige que o estado final seja `na_sua_mao` e que
--     `enviada_em` continue **nulo**. Uma data de envio numa mensagem que
--     ninguém entregou é a mesma mentira por outro campo;
--   · a **5**, que recusa mover o que já foi enviado. É a razão de a porta ser
--     estreita: se um provedor de verdade aceitou a mensagem, mandá-la para a
--     mão dela faria a paciente receber duas vezes — e a segunda sairia do
--     número pessoal dela;
--   · a **7**, que amarra esta migração à 0061: oferta cuja mensagem está na
--     mão dela **não expira**. É o que impede a vaga de queimar enquanto espera
--     o dedo dela, e vale igual para quem chegou aqui por falta de provedor;
--   · a **9**, que exige que a função esteja **fora** de /rest/v1/rpc. Ela muda
--     estado de mensagem sem perguntar de quem é a conta — quem a chama é o
--     worker, com a chave de serviço, e mais ninguém.
--
-- Cuidados de escrita, herdados: toda variável leva `v_`, nenhum alias de uma
-- letra, e varredura de corpo de função usa `position()` e nunca `like`, porque
-- `_` é curinga.
--
--   parte 1 · a porta
--     1. a função existe, e é security invoker
--     2. mensagem pendente vai para a mão dela
--     3. ...com o motivo escrito e sem enviada_em                          ← decide
--     4. mensagem reservada (enviando) também vai
--     5. o que já foi enviado NÃO volta                                    ← decide
--     6. nem o cancelado, nem o que já está na mão dela
--
--   parte 2 · o que a caixa e o relógio fazem com ela
--     7. oferta com mensagem posta aqui não expira                         ← decide
--     8. a caixa dela devolve a mensagem, com nome e id da oferta
--
--   parte 3 · quem pode chamar
--     9. anon e authenticated não executam                                 ← decide
--    10. mensagem inexistente levanta exceção, não devolve falso em silêncio
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0068_a_mensagem_vai_para_a_mao_dela.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111167';
  v_a_conta uuid; v_a_prof uuid;
  v_ana uuid;
  v_msg uuid; v_msg2 uuid; v_msg3 uuid;
  v_sessao uuid; v_oferta uuid;
  v_situacao text; v_erro text; v_motivo text;
  v_n integer; v_ok boolean;
  v_enviada timestamptz;
  v_hoje date;
  v_linha record;
begin

-- ============================================================ preâmbulo

delete from auth.users where id = v_a_auth;
delete from public.contas where nome = 'Mao Teste';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'mao@teste.sessoes.com.br', '{"nome":"Mao Teste"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;

v_hoje := public.hoje_sp();

-- A conta é **paga**, de propósito. O caminho de 0061 (plano manual) já tem
-- suíte; o que se testa aqui é o outro caminho — o que não depende de plano
-- nenhum, porque falta de provedor não é escolha comercial dela.
set local role postgres;
update public.contas set plano = 'solo' where id = v_a_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Mao', '5511900000671', 'em_atendimento') returning id into v_ana;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · a porta ---';

-- 1 · A função existe, e é security invoker.
select count(*)::integer into v_n
  from pg_proc pr
  join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public'
   and pr.proname = 'passar_para_a_sua_mao'
   and pr.prosecdef = false;
if v_n <> 1 then
  raise exception 'FALHOU 1: passar_para_a_sua_mao não existe como security invoker';
end if;

-- Uma mensagem pendente, do jeito que o produto a cria.
set local role postgres;
insert into public.mensagens (conta_id, paciente_id, template, canal, destino, params, estado)
  values (v_a_conta, v_ana, 'lembrete_de_sessao', 'whatsapp', '5511900000671',
          '{"nome":"Ana","modo":"discreto"}'::jsonb, 'pendente')
  returning id into v_msg;

-- 2 · Pendente vai para a mão dela.
select public.passar_para_a_sua_mao(v_msg, 'sem provedor de mensagem configurado') into v_ok;
if v_ok is not true then
  raise exception 'FALHOU 2: a mensagem pendente não foi para a mão dela';
end if;

-- 3 · ...com o motivo escrito e SEM enviada_em.  ← decide
select estado, erro, enviada_em into v_situacao, v_motivo, v_enviada
  from public.mensagens where id = v_msg;
if v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 3: o estado ficou % e não na_sua_mao', v_situacao;
end if;
if v_motivo is null or position('provedor' in v_motivo) = 0 then
  raise exception 'FALHOU 3: o motivo não chegou à linha (erro = %)', v_motivo;
end if;
if v_enviada is not null then
  raise exception 'FALHOU 3: enviada_em foi carimbada (%) numa mensagem que ninguém entregou — é a mesma afirmação sem lastro que a B43 veio consertar', v_enviada;
end if;

-- 4 · Reservada (`enviando`) também vai. É o caso real: o worker reserva o lote
--     antes de perguntar ao adaptador.
insert into public.mensagens (conta_id, paciente_id, template, canal, destino, params, estado)
  values (v_a_conta, v_ana, 'lembrete_de_sessao', 'whatsapp', '5511900000671',
          '{"nome":"Ana","modo":"discreto"}'::jsonb, 'enviando')
  returning id into v_msg2;

select public.passar_para_a_sua_mao(v_msg2, 'sem provedor de mensagem configurado') into v_ok;
select estado into v_situacao from public.mensagens where id = v_msg2;
if v_ok is not true or v_situacao <> 'na_sua_mao' then
  raise exception 'FALHOU 4: a mensagem reservada não foi para a mão dela (estado %)', v_situacao;
end if;

-- 5 · O que já saiu NÃO volta.  ← decide
insert into public.mensagens (conta_id, paciente_id, template, canal, destino, params, estado)
  values (v_a_conta, v_ana, 'lembrete_de_sessao', 'whatsapp', '5511900000671',
          '{"nome":"Ana","modo":"discreto"}'::jsonb, 'enviada')
  returning id into v_msg3;

select public.passar_para_a_sua_mao(v_msg3, 'sem provedor') into v_ok;
select estado into v_situacao from public.mensagens where id = v_msg3;
if v_ok is not false or v_situacao <> 'enviada' then
  raise exception 'FALHOU 5: mensagem já enviada foi mandada para a mão dela — a paciente receberia duas vezes, e a segunda pelo número pessoal dela';
end if;

-- 6 · Nem o cancelado, nem o que já está lá.
update public.mensagens set estado = 'cancelada' where id = v_msg3;
select public.passar_para_a_sua_mao(v_msg3, 'sem provedor') into v_ok;
if v_ok is not false then
  raise exception 'FALHOU 6: mensagem cancelada voltou para a fila da mão dela';
end if;

select public.passar_para_a_sua_mao(v_msg, 'sem provedor') into v_ok;
if v_ok is not false then
  raise exception 'FALHOU 6: mensagem que já estava na mão dela foi movida de novo';
end if;

raise notice '--- parte 2 · a caixa e o relógio ---';

-- Uma vaga com oferta enviada e vencida, e a mensagem daquela oferta posta na
-- mão dela pelo caminho novo.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, estado, origem, valor)
  values (v_a_conta, v_a_prof, v_ana,
          (v_hoje + 1)::timestamptz + interval '15 hours',
          (v_hoje + 1)::timestamptz + interval '15 hours 50 minutes',
          'cancelada_cedo', 'enquadre', '200.00')
  returning id into v_sessao;

insert into public.ofertas (conta_id, sessao_id, paciente_id, estado, enviar_em, expira_em)
  values (v_a_conta, v_sessao, v_ana, 'enviada', now() - interval '2 hours',
          now() - interval '1 hour')
  returning id into v_oferta;

insert into public.mensagens (conta_id, paciente_id, template, canal, destino, params,
                              estado, chave_idem)
  values (v_a_conta, v_ana, 'oferta_de_vaga', 'whatsapp', '5511900000671',
          '{"nome":"Ana","modo":"discreto"}'::jsonb, 'enviando',
          'oferta:' || v_oferta::text);

update public.mensagens set estado = 'pendente' where chave_idem = 'oferta:' || v_oferta::text;
select id into v_msg from public.mensagens where chave_idem = 'oferta:' || v_oferta::text;
select public.passar_para_a_sua_mao(v_msg, 'sem provedor de mensagem configurado') into v_ok;

-- 7 · A oferta vencida NÃO expira enquanto a mensagem está na mão dela.  ← decide
select public.expirar_ofertas() into v_n;
select estado into v_situacao from public.ofertas where id = v_oferta;
if v_situacao <> 'enviada' then
  raise exception 'FALHOU 7: a oferta expirou (%) com a mensagem ainda na mão dela — a vaga seria oferecida à próxima sem ninguém ter sido convidado', v_situacao;
end if;

-- 8 · A caixa dela devolve a mensagem, com nome e id da oferta.
set local role authenticated;
select count(*)::integer into v_n from public.mensagens_na_sua_mao();
if v_n < 3 then
  raise exception 'FALHOU 8: a caixa devolveu % mensagens; as postas aqui não apareceram', v_n;
end if;

select * into v_linha from public.mensagens_na_sua_mao() where id = v_msg;
if v_linha.paciente is distinct from 'Ana Mao' then
  raise exception 'FALHOU 8: a caixa não trouxe o nome de quem vai receber (%)', v_linha.paciente;
end if;
if v_linha.oferta_id is distinct from v_oferta then
  raise exception 'FALHOU 8: a caixa não extraiu o id da oferta da chave';
end if;
reset role;

raise notice '--- parte 3 · quem pode chamar ---';

-- 9 · Fora de /rest/v1/rpc.  ← decide
select count(*)::integer into v_n
  from pg_proc pr
  join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public'
   and pr.proname = 'passar_para_a_sua_mao'
   and (has_function_privilege('anon', pr.oid, 'execute')
        or has_function_privilege('authenticated', pr.oid, 'execute'));
if v_n <> 0 then
  raise exception 'FALHOU 9: passar_para_a_sua_mao está executável por anon/authenticated — ela muda estado de mensagem sem perguntar de quem é a conta';
end if;

-- 10 · Mensagem inexistente levanta, não devolve falso em silêncio. Falso ali
--      diria "não precisava mover", e o worker seguiria adiante achando que
--      tratou a linha.
begin
  select public.passar_para_a_sua_mao(gen_random_uuid(), 'sem provedor') into v_ok;
  raise exception 'FALHOU 10: mensagem inexistente não levantou exceção';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 10' in v_erro) > 0 then raise; end if;
  if position('não encontrada' in v_erro) = 0 then
    raise exception 'FALHOU 10: levantou por outro motivo — %', v_erro;
  end if;
end;

-- ============================================================ limpeza

set local role postgres;
delete from auth.users where id = v_a_auth;
delete from public.contas where nome = 'Mao Teste';
reset role;

raise notice 'OK · 0068 · a mensagem vai para a mão dela, e o que já saiu não volta';
end
$do$;
