-- Teste da entrega que se confere (B55, migração 0091).
--
-- A VERIFICAÇÃO QUE DECIDE ESTE ARQUIVO É A 2.
--
-- Toda a garantia depende de o webhook confirmar entrega. Se ele não estiver
-- ligado, nenhuma confirmação chega — e a leitura do sistema fica assim, toda
-- plausível e toda errada: nada confirma → tudo vira perdida → a base inteira é
-- reenviada a cada passada → a taxa de perda dá 100% → o disjuntor abre e
-- desliga o canal **que estava funcionando**.
--
-- Um webhook desconfigurado derrubaria o servidor bom, duplicaria todo e-mail e
-- queimaria a cota do segundo provedor, sem uma linha de erro em lugar nenhum.
-- A trava contra isso é do lado puro (`instrumentoConfiavel`), e é a `2` daqui
-- que prova que o banco não conclui sozinho.
--
--    1. a coluna nasce nula, e enviada sem confirmação é o estado vigiado
--    2. marcar_perdidas só mexe no que passou da janela                ← decide
--    3. confirmar_mensagem carimba entregue e é terminal
--    4. bounce depois de entregue é ruído, não desmentido              ← decide
--    5. o reenvio nasce com chave derivada e aponta para a original
--    6. reenvio confirmado confirma a original junto                   ← decide
--    7. o teto de dois reenvios para, e diz por quê
--    8. a amostra separa silêncio de vazio
--    9. o anônimo não executa nenhuma das funções novas
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0091

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111191';
  v_conta uuid; v_prof uuid; v_pac uuid;
  v_m1 uuid; v_r1 uuid; v_r2 uuid;
  v_res text; n integer; a record;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens where conta_id in (select id from public.contas where nome = 'Entrega Confere');
delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Entrega Confere');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Entrega Confere';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'entrega@teste.sessoes.com.br', '{"nome":"Entrega Confere"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, email, msg_canal, estado)
  values (v_prof, 'Quem Recebe', 'quemrecebe@teste.sessoes.com.br', 'email', 'em_atendimento')
  returning id into v_pac;

reset role;
set local role postgres;

-- Uma mensagem que o provedor **aceitou** há 40 minutos e não confirmou.
--
-- Planta em dois passos, e é o gatilho que manda: `mensagem_confere_retrato`
-- roda **antes do insert** e sobrescreve `estado`, `provedor` e
-- `provedor_msg_id` — *"estado de envio é do worker; ninguém nasce entregue"*.
-- Plantar tudo no insert é a família de defeito que doze suítes deste projeto
-- já tiveram: a suíte pede ao banco algo que o banco recusa com razão, e depois
-- reprova o produto por isso. O gatilho é só de insert, então o `update` vale.
insert into public.mensagens (conta_id, paciente_id, canal, template, params, destino, chave_idem)
values (v_conta, v_pac, 'email', 'lembrete_de_sessao', '{}'::jsonb,
        'quemrecebe@teste.sessoes.com.br', 'entrega:teste:1')
returning id into v_m1;

update public.mensagens
   set estado = 'enviada', enviada_em = now() - interval '40 minutes',
       provedor = 'postal', provedor_msg_id = 'prov-msg-0091-a'
 where id = v_m1;

-- ---------------------------------------------------------------- 1
if (select confirmada_em from public.mensagens where id = v_m1) is not null then
  raise exception '1 FUROU: a confirmação nasceu preenchida';
end if;

-- ---------------------------------------------------------------- 2
-- Uma segunda mensagem, aceita agora: está **dentro** da janela e não pode ser
-- tocada. Se a varredura marcar esta, ela está marcando o que ainda vai chegar.
insert into public.mensagens (conta_id, paciente_id, canal, template, params, destino, chave_idem)
values (v_conta, v_pac, 'email', 'lembrete_de_sessao', '{}'::jsonb,
        'quemrecebe@teste.sessoes.com.br', 'entrega:teste:2');

update public.mensagens
   set estado = 'enviada', enviada_em = now(),
       provedor = 'postal', provedor_msg_id = 'prov-msg-0091-b'
 where chave_idem = 'entrega:teste:2';

select public.marcar_perdidas('email', 20) into n;
if n <> 1 then raise exception '2 FUROU: marcar_perdidas mexeu em % mensagens (esperava 1)', n; end if;
if (select estado from public.mensagens where chave_idem = 'entrega:teste:2') <> 'enviada' then
  raise exception '2 FUROU: marcou como perdida uma mensagem dentro da janela';
end if;

-- ---------------------------------------------------------------- 3
select public.confirmar_mensagem('prov-msg-0091-b', 'entregue') into v_res;
if v_res <> 'entregue' then raise exception '3 FUROU: confirmar devolveu "%"', v_res; end if;
if (select confirmada_em from public.mensagens where chave_idem = 'entrega:teste:2') is null then
  raise exception '3 FUROU: entregue sem carimbo de confirmação';
end if;

-- ---------------------------------------------------------------- 4
select public.confirmar_mensagem('prov-msg-0091-b', 'falhou') into v_res;
if v_res <> 'ja_entregue' then
  raise exception '4 FUROU: bounce depois de entregue devolveu "%" — e desmentiu a entrega', v_res;
end if;
if (select estado from public.mensagens where chave_idem = 'entrega:teste:2') <> 'entregue' then
  raise exception '4 FUROU: a entrega foi desfeita por um evento posterior';
end if;

-- ---------------------------------------------------------------- 5
select public.reenfileirar_mensagem(v_m1) into v_r1;
if v_r1 is null then raise exception '5 FUROU: a perdida não voltou para a fila'; end if;
if (select estado from public.mensagens where id = v_m1) <> 'reenviada' then
  raise exception '5 FUROU: a original não ficou como reenviada';
end if;
if (select chave_idem from public.mensagens where id = v_r1) <> 'entrega:teste:1#r1' then
  raise exception '5 FUROU: a chave do reenvio é "%"',
    (select chave_idem from public.mensagens where id = v_r1);
end if;
if (select reenvio_de from public.mensagens where id = v_r1) <> v_m1 then
  raise exception '5 FUROU: o reenvio não aponta para a original';
end if;

-- ---------------------------------------------------------------- 6
-- Quem recebeu foi a paciente, não a linha do banco. Sem isto a original ficaria
-- para sempre sem confirmação e a taxa de perda nunca fecharia.
update public.mensagens
   set estado = 'enviada', enviada_em = now(), provedor_msg_id = 'prov-msg-0091-r1'
 where id = v_r1;

select public.confirmar_mensagem('prov-msg-0091-r1', 'entregue') into v_res;
if v_res <> 'entregue' then raise exception '6 FUROU: o reenvio não confirmou'; end if;
if (select confirmada_em from public.mensagens where id = v_m1) is null then
  raise exception '6 FUROU: o reenvio confirmou e a original ficou sem confirmação';
end if;

-- ---------------------------------------------------------------- 7
update public.mensagens set estado = 'perdida' where id = v_r1;
select public.reenfileirar_mensagem(v_r1) into v_r2;
if v_r2 is null then raise exception '7 FUROU: o segundo reenvio foi recusado cedo demais'; end if;

update public.mensagens set estado = 'perdida' where id = v_r2;
if public.reenfileirar_mensagem(v_r2) is not null then
  raise exception '7 FUROU: reenviou uma terceira vez — reenvio em laço é problema de reputação';
end if;
if (select estado from public.mensagens where id = v_r2) <> 'falhou' then
  raise exception '7 FUROU: esgotado o teto, a mensagem não ficou visível como falhou';
end if;
if (select erro from public.mensagens where id = v_r2) not like '%reenvios%' then
  raise exception '7 FUROU: desistiu sem dizer por quê';
end if;

-- ---------------------------------------------------------------- 8
select * into a from public.amostra_do_canal('email', 20);
if a.total < 1 then raise exception '8 FUROU: a amostra não viu as mensagens da janela'; end if;
if a.confirmadas < 1 then raise exception '8 FUROU: a amostra não contou as confirmadas'; end if;

-- ---------------------------------------------------------------- 9
-- Nada disto é caminho de paciente: o anônimo não executa nenhuma.
if exists (
  select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('confirmar_mensagem', 'marcar_perdidas', 'amostra_do_canal',
                       'registrar_varredura', 'reenfileirar_mensagem')
     and has_function_privilege('anon', p.oid, 'execute')
) then
  raise exception '9 FUROU: o anônimo executa uma das funções da entrega';
end if;

-- ------------------------------------------------------------------ recolhe
delete from public.mensagens where conta_id = v_conta;
delete from public.pacientes where conta_id = v_conta;
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B55 OK — 9 verificações, todas passaram';
end $do$;
