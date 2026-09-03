-- Teste do cancelamento que enxerga a mão dela (migração 0080).
--
-- **A verificação que decide este arquivo é a 8**, e ela não testa nenhuma das
-- seis funções: varre o `pg_proc`. As seis eu já sei que estavam erradas — foi
-- por isso que a 0080 existiu. O que este arquivo precisa impedir é a
-- **sétima**, escrita daqui a três builds por alguém que copiou o `where` de
-- uma das seis. Foi exatamente assim que a 0061 acrescentou `na_sua_mao` e
-- deixou seis funções para trás.
--
-- A lei 7 diz que checagem por enumeração deixa passar o item novo. Uma suíte
-- que listasse as seis funções à mão seria a própria doença que está tratando.
--
--   1. o Gratuito ainda faz a mensagem nascer na mão dela        ← a premissa
--   2. perdoar cancela o aviso que está na mão dela              ← decide
--   3. esquecer_contato cumpre a frase que devolve               ← decide (LGPD)
--   4. arquivar não deixa mensagem para quem foi encerrado
--   5. PARAR cancela também o que está na mão dela
--   6. o lembrete morre com a sessão desmarcada
--   7. o worker automático NÃO passou a pegar na_sua_mao         ← a contraprova
--   8. nenhuma função cancela mensagem por `estado = 'pendente'` cru ← decide
--   9. barrada_no_teto continua fora, e de propósito
--  10. as concessões das seis sobreviveram ao create or replace
--
-- A **7** é a metade que faltaria numa suíte descuidada: alargar a lista do
-- cancelamento é fácil, e alargar junto a lista do que o motor envia sozinho
-- destruiria a 0061 inteira — no Gratuito o dedo é dela, e o produto passaria a
-- mandar sozinho. Ela prova o oposto das outras, e é por isso que existe.
--
-- **Uma paciente por verificação, e não é economia mal feita.** A primeira
-- escrita deste arquivo reaproveitava a mesma ficha, e o banco recusou duas
-- vezes com razão: `arquivado_nao_muda()` não deixa ficha arquivada voltar a
-- ativa, e `esquecer_contato` apaga o telefone que a verificação seguinte
-- precisava. São as duas guardas funcionando — a suíte é que estava pedindo ao
-- banco para desfazer o que ele existe para não desfazer.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0080_a_pergunta_de_dominio_mora_num_lugar_so.sql

do $do$
declare
  v_ela   uuid := '22222222-2222-4222-8222-222222222280';
  v_conta uuid;
  v_prof  uuid;
  v_pac   uuid;   -- 1, 2 e 3 — termina esquecida
  v_pac2  uuid;   -- 4       — termina arquivada
  v_pac3  uuid;   -- 5       — termina com msg_canal = nao_avisar
  v_pac4  uuid;   -- 6 e 7   — chega intacta, e é a única que podia
  v_ses   uuid;
  v_cob   uuid;
  v_msg   uuid;
  v_estado text;
  v_n     integer;
  v_erro  text;
begin

delete from auth.users where id = v_ela;
delete from public.contas where nome = 'Mao Dela 0080';

-- **A trava, antes de qualquer escrita.** `responder_do_whatsapp` casa por
-- telefone e **sem filtro de conta** — é assim que tem de ser, porque quem
-- manda PARAR não sabe em quantos cadastros está. Só que esta suíte roda como
-- `postgres` contra o banco de verdade, e ali a RLS não protege ninguém. Se um
-- dos números fictícios estiver na ficha de alguém real, a verificação 5
-- desligaria o aviso de uma paciente de verdade. O §11 é claro: nunca a conta
-- do Leandro.
select count(*)::integer into v_n
  from public.pacientes p
 where public.so_digitos(p.telefone) in
       ('11988887777', '11977776666', '11966665555', '11955554444',
        '5511988887777', '5511977776666', '5511966665555', '5511955554444');

if v_n > 0 then
  raise exception 'ABORTADO: % paciente(s) já existem com um dos telefones fictícios desta suíte, e responder_do_whatsapp casa por telefone sem olhar conta — rodar isto desligaria o aviso de alguém de verdade. Troque os números', v_n;
end if;

insert into auth.users (id, email, raw_user_meta_data)
  values (v_ela, 'mao.dela@teste.sessoes.com.br', '{"nome":"Mao Dela 0080"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_ela;
update public.contas set nome = 'Mao Dela 0080', plano = 'gratis' where id = v_conta;
select p.id into v_prof from public.profissionais p where p.conta_id = v_conta limit 1;

-- As quatro fichas nascem de dentro da sessão dela: `checa_conta_do_paciente`
-- deriva `conta_id` de `conta_atual()` e exige profissional da mesma conta.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, telefone) values
  (v_conta, v_prof, 'Zebulon Improvável Kryzanowski', '5511988887777') returning id into v_pac;
insert into public.pacientes (conta_id, profissional_id, nome, telefone) values
  (v_conta, v_prof, 'Ondina Quirilov Ferrabrás', '5511977776666') returning id into v_pac2;
insert into public.pacientes (conta_id, profissional_id, nome, telefone) values
  (v_conta, v_prof, 'Teolinda Vasconcelos Ipê', '5511966665555') returning id into v_pac3;
insert into public.pacientes (conta_id, profissional_id, nome, telefone) values
  (v_conta, v_prof, 'Aurélio Bastos Manganês', '5511955554444') returning id into v_pac4;

reset role;

-- ------------------------------------------------------------------------ 1
--
-- A premissa de tudo. Se o Gratuito parasse de nascer `na_sua_mao`, este
-- arquivo inteiro passaria sem provar nada — e é o modo mais comum de uma
-- suíte apodrecer sem reprovar.
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac, 'whatsapp', '5511988887777', 'aviso_de_cobranca', '{}'::jsonb,
   'premissa:' || v_pac::text, 'pendente')
returning id into v_msg;

select estado into v_estado from public.mensagens where id = v_msg;
if v_estado <> 'na_sua_mao' then
  raise exception 'FALHOU 1: no Gratuito a mensagem nasceu % e não na_sua_mao — a 0061 mudou, e o resto desta suíte deixou de provar o que diz provar', v_estado;
end if;

-- ------------------------------------------------------------------------ 2
--
-- O achado que abriu a 0080, pelo caminho de verdade: cobrança aberta, aviso
-- montado com a `chave_idem` que `perdoar_cobranca` procura, e o perdão.
insert into public.cobrancas
  (conta_id, paciente_id, tipo, motivo, valor, competencia, estado)
values
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 200,
   date_trunc('month', public.hoje_sp())::date, 'aberta')
returning id into v_cob;

insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac, 'whatsapp', '5511988887777', 'aviso_de_cobranca', '{}'::jsonb,
   'cobranca:' || v_cob::text, 'pendente');

perform public.perdoar_cobranca(v_cob, 'sem condição este mês');

select estado into v_estado from public.mensagens
 where chave_idem = 'cobranca:' || v_cob::text;

if v_estado <> 'cancelada' then
  raise exception 'FALHOU 2: ela perdoou a cobrança e o aviso ficou % — no Gratuito ele segue na caixa "Na sua mão", pedindo para ela cobrar o que ela acabou de decidir não cobrar', v_estado;
end if;

-- ------------------------------------------------------------------------ 3
--
-- LGPD, e o pior dos seis: a função DEVOLVE a frase "envios cancelados". Aqui
-- a conferência é dupla — o estado no banco e a promessa na frase.
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac, 'whatsapp', '5511988887777', 'aviso_de_cobranca', '{}'::jsonb,
   'lgpd:' || v_pac::text, 'pendente');

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select public.esquecer_contato(v_pac) into v_erro;
reset role;

if v_erro not like '%envios cancelados%' then
  raise exception 'FALHOU 3: a frase de retorno mudou (%) — se ela não promete mais cancelar envio, esta verificação precisa mudar junto', v_erro;
end if;

select count(*)::integer into v_n from public.mensagens
 where paciente_id = v_pac
   and estado = any(public.estados_de_mensagem_por_sair());

if v_n > 0 then
  raise exception 'FALHOU 3: sobrou % mensagem por sair para quem pediu para ser esquecido, e a função devolveu "envios cancelados" — o telefone saiu da ficha mas mensagens.destino guarda o número, então o texto está montado e endereçado', v_n;
end if;

-- ------------------------------------------------------------------------ 4
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac2, 'whatsapp', '5511977776666', 'aviso_de_cobranca', '{}'::jsonb,
   'arquivo:' || v_pac2::text, 'pendente');

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.arquivar_paciente(v_pac2, 'Encerramos combinado, com alta.', 'alta');
reset role;

select count(*)::integer into v_n from public.mensagens
 where paciente_id = v_pac2
   and estado = any(public.estados_de_mensagem_por_sair());

if v_n > 0 then
  raise exception 'FALHOU 4: a ficha foi arquivada e sobrou % mensagem por sair', v_n;
end if;

-- ------------------------------------------------------------------------ 5
--
-- O opt-out. A paciente escreveu PARAR: o que já estava montado não pode
-- continuar esperando o dedo dela.
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac3, 'whatsapp', '5511966665555', 'aviso_de_cobranca', '{}'::jsonb,
   'parar:' || v_pac3::text, 'pendente');

perform public.responder_do_whatsapp('teste', 'msg-0080-parar', '5511966665555', 'PARAR');

select estado into v_estado from public.mensagens
 where chave_idem = 'parar:' || v_pac3::text;

if v_estado <> 'cancelada' then
  raise exception 'FALHOU 5: ela pediu para parar e a mensagem ficou % — mandar à mão para quem pediu para parar é a mesma quebra, com a assinatura da psicóloga em cima', v_estado;
end if;

-- ------------------------------------------------------------------------ 6
--
-- O lembrete de véspera de uma sessão que foi desmarcada. Pela porta de
-- verdade: quem cancela é o gatilho `sessoes_cancelam_lembrete`, e o que este
-- teste faz é só desmarcar a sessão.
insert into public.sessoes
  (conta_id, paciente_id, profissional_id, inicio, fim, valor, estado)
values
  (v_conta, v_pac4, v_prof,
   (public.hoje_sp() + 3)::timestamptz + interval '14 hours',
   (public.hoje_sp() + 3)::timestamptz + interval '14 hours 50 minutes',
   200, 'prevista')
returning id into v_ses;

insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac4, 'whatsapp', '5511955554444', 'lembrete_de_sessao', '{}'::jsonb,
   'lembrete:' || v_ses::text, 'pendente');

-- `cancelada_cedo` é valor de estado, não coluna: quem carimba a hora é
-- `cancelada_em`, e `sessoes_check1` amarra as duas.
update public.sessoes
   set estado = 'cancelada_cedo', cancelada_em = now()
 where id = v_ses;

select estado into v_estado from public.mensagens
 where chave_idem = 'lembrete:' || v_ses::text;

if v_estado <> 'cancelada' then
  raise exception 'FALHOU 6: a sessão foi desmarcada e o lembrete de véspera ficou % — ela mandaria à mão um lembrete de uma sessão que não vai acontecer', v_estado;
end if;

-- ------------------------------------------------------------------------ 7
--
-- A CONTRAPROVA, e a razão de a função nova não se chamar `estados_vivos`.
-- Alargar a lista do cancelamento é fácil; alargar junto a lista do que o
-- motor manda sozinho destruiria a 0061 inteira — no Gratuito o dedo é dela.
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado,
   agendada_para)
values
  (v_conta, v_pac4, 'whatsapp', '5511955554444', 'aviso_de_cobranca', '{}'::jsonb,
   'motor:' || v_pac4::text, 'pendente', now() - interval '1 hour')
returning id into v_msg;

select count(*)::integer into v_n
  from public.reservar_mensagens(200) r where r.id = v_msg;

if v_n > 0 then
  raise exception 'FALHOU 7: o worker automático reservou uma mensagem na_sua_mao — a 0080 alargou a pergunta errada, e o produto passou a mandar sozinho no plano em que o dedo é dela';
end if;

select estado into v_estado from public.mensagens where id = v_msg;
if v_estado <> 'na_sua_mao' then
  raise exception 'FALHOU 7: o motor mexeu na mensagem da mão dela (virou %)', v_estado;
end if;

-- ------------------------------------------------------------------------ 8
--
-- A varredura, e a única verificação deste arquivo que ainda serve depois que
-- as seis funções acima forem reescritas por outro motivo.
--
-- Regra: se o corpo de uma função **cancela** mensagem (`update
-- public.mensagens ... set estado = 'cancelada'`), ele não pode filtrar por
-- `estado = 'pendente'` cru — tem de perguntar a
-- `estados_de_mensagem_por_sair()`. A lei 7 em forma executável.
select string_agg(p.proname, ', ' order by p.proname), count(*)::integer
  into v_erro, v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and exists (
     select 1 from regexp_matches(
       pg_get_functiondef(p.oid),
       'update\s+public\.mensagens[\s\S]{0,255}?set\s+estado\s*=\s*''cancelada''[\s\S]{0,255}?estado\s*=\s*''pendente''',
       'g')
   );

if v_n > 0 then
  raise exception 'FALHOU 8: % cancela(m) mensagem filtrando por estado = ''pendente'' cru, e não enxerga(m) a caixa "Na sua mão": %. A pergunta "esta mensagem ainda vai sair?" mora em estados_de_mensagem_por_sair(), e é a lição que a 0052d já tinha escrito', v_n, v_erro;
end if;

-- ------------------------------------------------------------------------ 9
--
-- `barrada_no_teto` fica de fora, e é decisão: `lib/teto.ts` a trata como
-- terminal e a frase dela diz "não saiu". Cancelar o que já está morto só
-- apagaria o histórico de que a trava de segurança atuou.
if 'barrada_no_teto' = any(public.estados_de_mensagem_por_sair()) then
  raise exception 'FALHOU 9: barrada_no_teto entrou na lista do que ainda sai — ela é terminal em lib/teto.ts, e cancelá-la apaga o registro de que a trava agiu';
end if;

if 'enviada' = any(public.estados_de_mensagem_por_sair())
   or 'entregue' = any(public.estados_de_mensagem_por_sair())
   or 'enviando' = any(public.estados_de_mensagem_por_sair()) then
  raise exception 'FALHOU 9: a lista do que ainda vai sair inclui algo que já saiu ou está em voo — cancelar depois do envio é reescrever o passado';
end if;

-- E todo estado da lista tem de ser um estado que a tabela aceita: uma lista
-- com valor que o `check` recusa é uma lista que nunca casa com linha nenhuma,
-- e o cancelamento voltaria a falhar em silêncio.
select count(*)::integer into v_n
  from unnest(public.estados_de_mensagem_por_sair()) e
 where not exists (
   select 1 from pg_constraint c
    where c.conrelid = 'public.mensagens'::regclass
      and c.conname = 'mensagens_estado_check'
      and pg_get_constraintdef(c.oid) like '%''' || e || '''%'
 );

if v_n > 0 then
  raise exception 'FALHOU 9: % estado(s) da lista não existem no check de mensagens — o filtro não casaria com linha nenhuma e o cancelamento falharia calado', v_n;
end if;

-- ----------------------------------------------------------------------- 10
--
-- `create or replace` preserva a ACL, mas isso é conhecimento meu sobre o
-- Postgres e não prova nada sobre este banco. A 0066c e a 0075 são as duas
-- vezes em que uma concessão se perdeu sem ninguém ver.
if not has_function_privilege('authenticated', 'public.estados_de_mensagem_por_sair()', 'execute') then
  raise exception 'FALHOU 10: authenticated não alcança a lista — arquivar_paciente e perdoar_cobranca não são security definer e rodam como ela';
end if;

if has_function_privilege('anon', 'public.estados_de_mensagem_por_sair()', 'execute') then
  raise exception 'FALHOU 10: anon alcança a lista';
end if;

select string_agg(p.proname, ', ' order by p.proname), count(*)::integer
  into v_erro, v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('arquivar_paciente', 'esquecer_contato', 'perdoar_cobranca')
   and not has_function_privilege('authenticated', p.oid, 'execute');

if v_n > 0 then
  raise exception 'FALHOU 10: % função(ões) perderam a concessão de authenticated no create or replace da 0080: %', v_n, v_erro;
end if;

-- ------------------------------------------------------------------------ fim
--
-- A conta sai primeiro: `pacientes.profissional_id` e `registros.*` são
-- RESTRICT de propósito, e apagar `auth.users` antes esbarra neles. Lição das
-- sete suítes consertadas em 03/09.
delete from public.contas where id = v_conta;
delete from auth.users where id = v_ela;
delete from public.mensagens_recebidas where provedor_msg_id = 'msg-0080-parar';

raise notice 'OK · 0080 · o que está na mão dela também se cancela — e o motor continua sem tocar nela';
end
$do$;
