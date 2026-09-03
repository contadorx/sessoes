-- Teste do roteamento por classe e da cascata (B52, migração 0092).
--
-- A VERIFICAÇÃO QUE DECIDE ESTE ARQUIVO É A 6: template de classe `documento`
-- **não desce para canal não oficial**, nem por cascata, nem por urgência. É a
-- fronteira 8 escrita em código, e não num comentário de tela — e é a metade da
-- decisão de 03/09 que o documento do canal **não** afrouxa.
--
--    1. a urgente fura a fila, e o lote SAI na ordem                    ← decide
--    2. a mensagem nasce no canal da paciente
--    3. o degrau da cascata nasce no canal pedido, com o destino certo ← decide
--    4. o mesmo canal duas vezes é recusado — a chave de entrega
--    5. sem contato para o canal, o degrau não nasce sem destino
--    6. documento NASCE no e-mail, mesmo para paciente de WhatsApp     ← decide
--    6b. e sem e-mail cadastrado ele não nasce — não desce para o WhatsApp
--    7. `nao_avisar` continua recusando: a cascata não atravessa a decisão dela
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0092

do $do$
declare
  v_auth uuid := '11111111-1111-4111-8111-111111111192';
  v_conta uuid; v_prof uuid;
  v_pac uuid; v_semEmail uuid; v_calado uuid;
  v_m uuid; v_novo uuid; v_ordem text[]; v_so_uma text[]; falhou boolean;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens where conta_id in (select id from public.contas where nome = 'Cascata B52');
delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Cascata B52');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Cascata B52';
delete from public.templates where codigo = 'teste_documento_0092';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'cascata@teste.sessoes.com.br', '{"nome":"Cascata B52"}'::jsonb);
select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

-- Plano pago: no Grátis a não-essencial nasce `na_sua_mao` e a fila não é
-- reservada — a suíte testaria o caminho manual achando que testa o motor.
set local role postgres;
update public.contas set plano = 'solo' where id = v_conta;
insert into public.templates (codigo, descricao, motivo, essencial, classe)
values ('teste_documento_0092', 'Documento de teste',
        'Existe só para provar que documento não desce para canal não oficial.',
        false, 'documento');
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, email, msg_canal, estado)
  values (v_prof, 'Tem Os Dois', '5511900009301', 'temosdois@teste.sessoes.com.br',
          'whatsapp', 'em_atendimento')
  returning id into v_pac;
insert into public.pacientes (profissional_id, nome, telefone, msg_canal, estado)
  values (v_prof, 'So Telefone', '5511900009302', 'whatsapp', 'em_atendimento')
  returning id into v_semEmail;
insert into public.pacientes (profissional_id, nome, telefone, msg_canal, estado)
  values (v_prof, 'Nao Quer Aviso', '5511900009303', 'nao_avisar', 'em_atendimento')
  returning id into v_calado;

-- ---------------------------------------------------------------- 1
-- A rotina entra PRIMEIRO, a urgente depois. Em FIFO a rotina sairia antes — e
-- uma oferta que expira em 40 minutos atrás de duzentos lembretes fecha a vaga
-- vazia sem nenhum erro aparecer.
perform public.enfileirar_mensagem(v_pac, 'aviso_de_cobranca', 'casc:rotina',
                                   '{}'::jsonb, now() - interval '2 hours');
perform public.enfileirar_mensagem(v_pac, 'oferta_de_vaga', 'casc:urgente',
                                   '{}'::jsonb, now() - interval '1 hour');

reset role;
set local role postgres;

-- 1a · com o lote apertado, quem entra é a urgente.
select array_agg(template) into v_so_uma from public.reservar_mensagens(1);
if v_so_uma <> array['oferta_de_vaga'] then
  raise exception '1 FUROU: com lote de 1 a fila escolheu % — a urgente ficou de fora', v_so_uma;
end if;
update public.mensagens set estado = 'pendente' where conta_id = v_conta;

-- 1b · e o lote inteiro **sai** na ordem.
--
-- Esta metade não estava aqui, e a suíte a exigiu: o `order by` de dentro do
-- `where id in (…)` escolhe **quais** linhas entram no lote, e a ordem do
-- `RETURNING` é arbitrária. Sem o `order by` de fora, o worker mandava a rotina
-- antes da urgente dentro do mesmo lote — a fila "certa", na ordem errada.
select array_agg(template order by ord) into v_ordem
  from (select template, row_number() over () as ord from public.reservar_mensagens(10)) x;
if v_ordem[1] <> 'oferta_de_vaga' then
  raise exception '1 FUROU: a fila devolveu % — a urgente esperou a rotina dentro do lote', v_ordem;
end if;

-- ---------------------------------------------------------------- 2
set local role authenticated;
select public.enfileirar_mensagem(v_pac, 'oferta_de_vaga', 'casc:1', '{}'::jsonb, now()) into v_m;
if (select canal from public.mensagens where id = v_m) <> 'whatsapp' then
  raise exception '2 FUROU: nasceu em canal diferente do da paciente';
end if;

reset role;
set local role postgres;

-- ---------------------------------------------------------------- 3
select public.reencaminhar_mensagem(v_m, 'email') into v_novo;
if v_novo is null then raise exception '3 FUROU: a cascata não desceu'; end if;
if (select canal from public.mensagens where id = v_novo) <> 'email' then
  raise exception '3 FUROU: o degrau não ficou no canal pedido — o gatilho reescreveu';
end if;
if (select destino from public.mensagens where id = v_novo) <> 'temosdois@teste.sessoes.com.br' then
  raise exception '3 FUROU: o destino do degrau não é o e-mail dela';
end if;
if (select estado from public.mensagens where id = v_m) <> 'reenviada' then
  raise exception '3 FUROU: a original não ficou como reenviada';
end if;

-- ---------------------------------------------------------------- 4
if public.reencaminhar_mensagem(v_m, 'email') is not null then
  raise exception '4 FUROU: mandou a mesma mensagem duas vezes pelo mesmo canal';
end if;

-- ---------------------------------------------------------------- 5
set local role authenticated;
select public.enfileirar_mensagem(v_semEmail, 'oferta_de_vaga', 'casc:2', '{}'::jsonb, now()) into v_m;
reset role;
set local role postgres;

select public.reencaminhar_mensagem(v_m, 'email') into v_novo;
if v_novo is not null and (select canal from public.mensagens where id = v_novo) = 'email' then
  raise exception '5 FUROU: criou degrau de e-mail para quem não tem e-mail';
end if;

-- ---------------------------------------------------------------- 6
--
-- **A verificação que mudou o produto.** A primeira versão só olhava a cascata,
-- e passou — porque a cascata nunca era chamada: a mensagem nasce com o canal
-- da paciente, então um documento para quem escolheu WhatsApp **nascia no
-- WhatsApp**, e o caminho principal passava por fora da fronteira. A trava foi
-- para a porta, que é `mensagem_confere_retrato`.
set local role authenticated;
select public.enfileirar_mensagem(v_pac, 'teste_documento_0092', 'casc:doc', '{}'::jsonb, now()) into v_m;

if (select canal from public.mensagens where id = v_m) <> 'email' then
  raise exception '6 FUROU: documento nasceu em "%" para paciente de WhatsApp — a fronteira 8 é só comentário',
    (select canal from public.mensagens where id = v_m);
end if;

-- 6b · e para quem não tem e-mail ele **não nasce**. Recusa dura de propósito:
-- a alternativa seria mandar o recibo por WhatsApp.
falhou := false;
begin
  perform public.enfileirar_mensagem(v_semEmail, 'teste_documento_0092', 'casc:doc2', '{}'::jsonb, now());
  falhou := true;
exception when others then
  if sqlerrm not like '%documento só sai por e-mail%' then raise; end if;
end;
if falhou then
  raise exception '6 FUROU: documento nasceu para paciente sem e-mail — e sairia por WhatsApp';
end if;

reset role;
set local role postgres;

-- ---------------------------------------------------------------- 7
set local role authenticated;

-- A porta **devolve null** em vez de estourar, e é decisão escrita na 0017:
-- *"silêncio pedido pelo paciente não é erro de quem chama — a cascata segue
-- para o próximo da fila em vez de estourar"*. O que a suíte exige é que
-- ninguém entre na fila; o `raise` do gatilho é a segunda linha de defesa, para
-- quem insere direto.
if public.enfileirar_mensagem(v_calado, 'oferta_de_vaga', 'casc:calado', '{}'::jsonb, now()) is not null then
  raise exception '7 FUROU: enfileirou para quem pediu para não ser avisado';
end if;
if exists (select 1 from public.mensagens where paciente_id = v_calado) then
  raise exception '7 FUROU: nasceu mensagem para quem pediu para não ser avisado';
end if;

-- ------------------------------------------------------------------ recolhe
reset role;
set local role postgres;

delete from public.mensagens where conta_id = v_conta;
delete from public.pacientes where conta_id = v_conta;
delete from public.templates where codigo = 'teste_documento_0092';
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B52 OK — 7 verificações, todas passaram';
end $do$;
