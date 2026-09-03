-- Teste da política que exige assinatura no envio manual (migração 0081).
--
-- **A verificação que decide este arquivo é a 2**, e ela é a que quase não se
-- escreve: apertar uma política é fácil, e apertar demais quebra o caminho
-- honesto sem que ninguém perceba até a psicóloga tentar usar. A 1 prova que a
-- forja parou; a 2 prova que `marcar_enviada_a_mao()` continua funcionando, e
-- sem ela esta migração seria uma regressão com cara de conserto.
--
--   1. o `update` cru que nomeia provedor é recusado           ← decide
--   2. `marcar_enviada_a_mao()` continua passando              ← decide
--   3. dizer "enviada" sem a marca da mão é recusado
--   4. `nao_vou_mandar()` continua passando
--   5. `enviando` e `entregue` seguem fora do alcance dela      (a 0061 viva)
--   6. o que ela mandou aparece na medida do canal manual      ← o porquê
--   7. mensagem de outra conta continua fora de alcance
--
-- A **6** é a razão de a 0081 existir e não é sobre permissão: é sobre a
-- `resumo_do_envio_manual` da 0061, que conta `enviada_a_mao`. Uma mensagem
-- que chegasse a `enviada` sem essa coluna sumiria da conta do que ela mandou
-- à mão e viraria despacho do motor — num plano que não tem motor.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0081_a_mao_dela_assina_o_que_mandou.sql

do $do$
declare
  v_ela    uuid := '22222222-2222-4222-8222-222222222281';
  v_outra  uuid := '33333333-3333-4333-8333-333333333381';
  v_conta  uuid; v_c_outra uuid;
  v_prof   uuid; v_prof_o uuid;
  v_pac    uuid; v_pac_o uuid;
  v_m1 uuid; v_m2 uuid; v_m3 uuid; v_m4 uuid; v_alheia uuid;
  v_estado text; v_n integer; v_ok boolean; v_r jsonb;
  v_falhou boolean;
begin

delete from auth.users where id in (v_ela, v_outra);
delete from public.contas where nome in ('Assina 0081', 'Alheia 0081');

insert into auth.users (id, email, raw_user_meta_data) values
  (v_ela,   'assina@teste.sessoes.com.br', '{"nome":"Assina 0081"}'::jsonb),
  (v_outra, 'alheia@teste.sessoes.com.br', '{"nome":"Alheia 0081"}'::jsonb);

select conta_id into v_conta   from public.usuarios where auth_user_id = v_ela;
select conta_id into v_c_outra from public.usuarios where auth_user_id = v_outra;

update public.contas set nome = 'Assina 0081', plano = 'gratis' where id = v_conta;
update public.contas set nome = 'Alheia 0081', plano = 'gratis' where id = v_c_outra;

select p.id into v_prof   from public.profissionais p where p.conta_id = v_conta   limit 1;
select p.id into v_prof_o from public.profissionais p where p.conta_id = v_c_outra limit 1;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (conta_id, profissional_id, nome, telefone)
  values (v_conta, v_prof, 'Belarmina Tchaikovsky Odalisca', '5511944443333')
  returning id into v_pac;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_outra::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (conta_id, profissional_id, nome, telefone)
  values (v_c_outra, v_prof_o, 'Ninguém Da Outra Conta', '5511933332222')
  returning id into v_pac_o;
reset role;

-- Quatro mensagens dela e uma da vizinha. No Gratuito todas nascem na mão dela
-- (0061), e é essa a premissa de tudo o que vem abaixo.
insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_conta, v_pac, 'whatsapp', '5511944443333', 'aviso_de_cobranca', '{}'::jsonb, 'a81:1', 'pendente'),
  (v_conta, v_pac, 'whatsapp', '5511944443333', 'aviso_de_cobranca', '{}'::jsonb, 'a81:2', 'pendente'),
  (v_conta, v_pac, 'whatsapp', '5511944443333', 'aviso_de_cobranca', '{}'::jsonb, 'a81:3', 'pendente'),
  (v_conta, v_pac, 'whatsapp', '5511944443333', 'aviso_de_cobranca', '{}'::jsonb, 'a81:4', 'pendente');

insert into public.mensagens
  (conta_id, paciente_id, canal, destino, template, params, chave_idem, estado)
values
  (v_c_outra, v_pac_o, 'whatsapp', '5511933332222', 'aviso_de_cobranca', '{}'::jsonb, 'a81:alheia', 'pendente')
returning id into v_alheia;

select id into v_m1 from public.mensagens where chave_idem = 'a81:1';
select id into v_m2 from public.mensagens where chave_idem = 'a81:2';
select id into v_m3 from public.mensagens where chave_idem = 'a81:3';
select id into v_m4 from public.mensagens where chave_idem = 'a81:4';

select estado into v_estado from public.mensagens where id = v_m1;
if v_estado <> 'na_sua_mao' then
  raise exception 'FALHOU 0: a premissa caiu — no Gratuito a mensagem nasceu % e não na_sua_mao', v_estado;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

-- ------------------------------------------------------------------------ 1
--
-- A forja que a suíte 0022 pega desde a B11: dizer que saiu, e por qual
-- provedor. Quem nomeia provedor é quem despachou, e não foi ela.
v_falhou := false;
begin
  update public.mensagens set estado = 'enviada', provedor = 'forjado' where id = v_m1;
exception when insufficient_privilege then v_falhou := true;
end;

if not v_falhou then
  raise exception 'FALHOU 1: o app marcou mensagem como enviada nomeando um provedor — a ficha diz que o motor despachou, e no Gratuito motor não existe';
end if;

-- ------------------------------------------------------------------------ 2
--
-- E a metade que uma política apertada demais quebraria em silêncio.
select public.marcar_enviada_a_mao(v_m1) into v_ok;
if not v_ok then
  raise exception 'FALHOU 2: marcar_enviada_a_mao devolveu falso — a 0081 apertou a política a ponto de fechar o caminho honesto';
end if;

select estado into v_estado from public.mensagens where id = v_m1;
if v_estado <> 'enviada' then
  raise exception 'FALHOU 2: depois de marcar à mão a mensagem ficou %', v_estado;
end if;

-- ------------------------------------------------------------------------ 3
--
-- Sem nomear provedor, mas sem a marca da mão: continua sendo a ficha de um
-- envio que ninguém assina.
v_falhou := false;
begin
  update public.mensagens set estado = 'enviada' where id = v_m2;
exception when insufficient_privilege then v_falhou := true;
end;

if not v_falhou then
  raise exception 'FALHOU 3: dizer "enviada" sem enviada_a_mao passou — e é exatamente a linha que some da medida do canal manual';
end if;

-- ------------------------------------------------------------------------ 4
select public.nao_vou_mandar(v_m3) into v_ok;
if not v_ok then
  raise exception 'FALHOU 4: nao_vou_mandar devolveu falso — decidir não mandar não assina nada e tinha de continuar livre';
end if;

select estado into v_estado from public.mensagens where id = v_m3;
if v_estado <> 'cancelada' then
  raise exception 'FALHOU 4: depois de nao_vou_mandar a mensagem ficou %', v_estado;
end if;

-- ------------------------------------------------------------------------ 5
--
-- A 0061 viva: `enviando` e `entregue` são estados de quem despacha, e a
-- 0081 não podia tê-los aberto de passagem.
v_falhou := false;
begin
  update public.mensagens set estado = 'enviando' where id = v_m4;
exception when insufficient_privilege then v_falhou := true;
end;
if not v_falhou then
  raise exception 'FALHOU 5: ela alcançou o estado enviando, que é de quem despacha';
end if;

v_falhou := false;
begin
  update public.mensagens set estado = 'entregue', enviada_a_mao = true where id = v_m4;
exception when insufficient_privilege then v_falhou := true;
end;
if not v_falhou then
  raise exception 'FALHOU 5: ela alcançou o estado entregue — entrega é o provedor que confirma, e ela não tem como saber';
end if;

-- ------------------------------------------------------------------------ 6
--
-- O porquê da 0081, conferido onde dói: a medida do canal manual da 0061.
v_r := public.resumo_do_envio_manual(v_conta);

if (v_r ->> 'enviadas_no_mes')::int < 1 then
  raise exception 'FALHOU 6: a mensagem que ela mandou à mão não entrou na medida do canal manual (enviadas_no_mes = %) — é a segunda fonte de verdade do §9 sobre o que saiu', v_r ->> 'enviadas_no_mes';
end if;

if not (v_r ->> 'manual')::boolean then
  raise exception 'FALHOU 6: a conta do Gratuito não se reconhece como canal manual';
end if;

-- ------------------------------------------------------------------------ 7
--
-- E o isolamento não pode ter afrouxado junto: a política nova continua
-- presa a `conta_atual()`.
v_falhou := false;
begin
  update public.mensagens set estado = 'cancelada' where id = v_alheia;
  if not found then v_falhou := true; end if;
exception when others then v_falhou := true;
end;

if not v_falhou then
  raise exception 'FALHOU 7: ela cancelou mensagem da conta vizinha';
end if;

reset role;

-- A conferência do estado só vale fora da sessão dela: de dentro, a policy de
-- `select` esconderia a linha e `v_estado` voltaria nulo — a suíte passaria
-- sem ver nada, que é pior do que reprovar.
select estado into v_estado from public.mensagens where id = v_alheia;
if v_estado <> 'na_sua_mao' then
  raise exception 'FALHOU 7: a mensagem da vizinha ficou % — o isolamento caiu junto com o aperto', v_estado;
end if;

-- ------------------------------------------------------------------------ fim
--
-- A conta sai primeiro: `pacientes.profissional_id` e `registros.*` são
-- RESTRICT de propósito.
delete from public.contas where id in (v_conta, v_c_outra);
delete from auth.users where id in (v_ela, v_outra);

raise notice 'OK · 0081 · a mão dela assina o que mandou — e o caminho honesto continua aberto';
end
$do$;
