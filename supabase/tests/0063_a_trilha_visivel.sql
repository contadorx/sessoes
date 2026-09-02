-- Teste da trilha que alguém lê (B33, migração 0063).
--
-- A `trilha_acesso` é gravada desde a B13 e é lida desde hoje. **Esta suíte
-- existe porque a propriedade que importa não é "a trilha existe", é "a trilha
-- chega inteira aos olhos de quem tem direito a ela e não chega a mais
-- ninguém"** — e as duas metades dessa frase falham de formas diferentes.
--
-- Cinco decidem:
--
--   · a **2**, que exige o **nome de quem olhou** e não o `auth_user_id`. Uma
--     tela de auditoria que mostra uuid é uma tela que ninguém lê duas vezes, e
--     uma trilha que ninguém lê é o defeito que a 0060 provou existir: o
--     `insert` de `exportou_conta` sumiu por três horas e só uma suíte notou;
--   · a **8**, que exige **recusa explícita** de quem não tem acesso clínico.
--     A policy da 0049 sozinha devolveria zero linhas em silêncio, e zero linhas
--     numa tela de auditoria é indistinguível de "ninguém acessou nada" — a
--     resposta que tranquiliza exatamente quando não devia;
--   · a **9**, que confere que a vizinha não alcança a trilha da outra. A trilha
--     carrega nome de paciente ao lado de nome de profissional: vazamento aqui é
--     vazamento clínico com outra roupa;
--   · a **10**, que reprova se a trilha aceitar `update` ou `delete` **nem pela
--     dona**. É a propriedade que a página `/seguranca` promete em voz alta, e
--     registro que o próprio interessado edita não é defesa de ninguém;
--   · a **12**, que varre `pg_get_function_arguments` e reprova se aparecer um
--     parâmetro de ação. É a única verificação desta suíte que testa uma
--     **ausência**, e é de propósito: tela de auditoria com filtro por tipo de
--     evento é tela onde o evento inconveniente é o que ninguém marca. Sem esta
--     linha, alguém acrescenta o filtro daqui a dois builds achando que ajuda.
--
-- Cuidados de escrita, cicatriz desta obra: variável leva `v_` (0060b) e nunca
-- se chama `em`, `acao`, `nota` ou `estado`, porque em plpgsql a variável ganha
-- da coluna; nada de alias de uma letra (0052c); varredura de corpo e de
-- assinatura de função usa `position()` e nunca `like`, porque `_` é curinga e
-- já acusou código correto (0060d).
--
-- **E uma cicatriz desta suíte:** envelhecer uma linha da trilha exige `update`
-- depois do `insert`. O gatilho `trilha_carimba` é `before insert` e faz
-- `new.em := now()` — uma linha inserida com data antiga nasce com a hora real.
-- É a mesma descoberta que virou a verificação 4 da suíte 0062.
--
--   parte 1 · a trilha grava e a trilha se lê
--     1. ler uma ficha deixa rastro sozinho
--     2. e a trilha devolve o nome de quem olhou, não um uuid          ← decide
--     3. ...e o nome do paciente
--
--   parte 2 · os recortes
--     4. o recorte por paciente funciona
--     5. o recorte por período exclui o que está fora
--     6. período invertido é recusado
--     7. período de mais de um ano é recusado
--
--   parte 3 · quem lê e quem não lê
--     8. sem acesso clínico a recusa é dita, não são zero linhas       ← decide
--     9. a vizinha não vê a trilha da outra                            ← decide
--    10. a trilha continua sem update e sem delete, nem pela dona      ← decide
--
--   parte 4 · o que a tela precisa saber
--    11. tamanho_da_trilha diz quantas linhas há e de quando começa
--    12. a assinatura não tem filtro por ação                          ← decide
--
--   parte 5 · as trancas
--    13. exportar_paciente continua deixando rastro
--    14. o anônimo não executa nenhuma das duas
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0063_a_trilha_visivel.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111163';
  v_b_auth uuid := '22222222-2222-4222-8222-222222222163';
  v_c_auth uuid := '33333333-3333-4333-8333-333333333163';
  v_a_conta uuid; v_a_prof uuid;
  v_b_conta uuid; v_b_prof uuid;
  v_c_conta uuid;
  v_a_usuario text;
  v_pac_um uuid; v_pac_dois uuid; v_pac_viz uuid;
  v_erro text; v_quem text; v_paciente text;
  v_n integer; v_antes integer;
  v_tamanho jsonb; v_assinatura text;
  v_min_em timestamptz;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.contas where nome in ('Trilha Teste', 'Trilha Vizinha', 'Trilha Secretaria');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'trilha@teste.sessoes.com.br', '{"nome":"Trilha Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'trilhaviz@teste.sessoes.com.br', '{"nome":"Trilha Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;
select nome into v_a_usuario from public.usuarios where auth_user_id = v_a_auth;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id into v_b_prof from public.profissionais where conta_id = v_b_conta;

if v_a_usuario is null then
  raise exception 'FALHOU 0: o usuário de teste nasceu sem nome — a verificação 2 não teria o que comparar';
end if;

-- Duas fichas na conta A: sem duas, o recorte por paciente da 4 não separa nada.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Trilha', '5511900000631', 'em_atendimento') returning id into v_pac_um;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Bruno Trilha', '5511900000632', 'em_atendimento') returning id into v_pac_dois;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_b_prof, 'Carla Vizinha', '5511900000633', 'em_atendimento') returning id into v_pac_viz;
reset role;

raise notice '--- parte 1 · a trilha grava e a trilha se lê ---';

-- 1 · Ler uma ficha deixa rastro sozinho.
select count(*)::integer into v_antes
  from public.trilha_acesso where conta_id = v_a_conta and acao = 'leu_ficha';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_acesso(v_pac_um, 'leu_ficha', '{}'::jsonb);
reset role;

select count(*)::integer into v_n
  from public.trilha_acesso
 where conta_id = v_a_conta and acao = 'leu_ficha' and paciente_id = v_pac_um;
if v_n <> v_antes + 1 then
  raise exception 'FALHOU 1: registrar_acesso não gravou linha nenhuma (% na trilha) — registro que não é gravado é promessa de página, não defesa', v_n;
end if;
raise notice 'ok 1 · ler uma ficha deixa rastro';

-- 2 · E a trilha devolve o nome de quem olhou, não um uuid.  ← decide
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select mtr.quem, mtr.paciente into v_quem, v_paciente
  from public.minha_trilha(current_date - 30, current_date + 1) mtr
 where mtr.acao = 'leu_ficha'
 limit 1;
reset role;

if v_quem is null then
  raise exception 'FALHOU 2: minha_trilha não devolveu a linha que a verificação 1 acabou de ver na tabela — a leitura não enxerga o que a escrita gravou';
end if;
if v_quem = v_a_auth::text or v_quem ~ '^[0-9a-f]{8}-[0-9a-f]{4}-' then
  raise exception 'FALHOU 2: a trilha devolveu um uuid em vez do nome de quem olhou ("%") — tela de auditoria com uuid é tela que ninguém lê duas vezes', v_quem;
end if;
if v_quem <> v_a_usuario then
  raise exception 'FALHOU 2: quem olhou saiu como "%" e o nome cadastrado é "%"', v_quem, v_a_usuario;
end if;
raise notice 'ok 2 · a trilha diz o nome de quem olhou';

-- 3 · ...e o nome do paciente.
if v_paciente is distinct from 'Ana Trilha' then
  raise exception 'FALHOU 3: o paciente da linha veio como "%" e devia ser "Ana Trilha" — sem o nome da ficha a trilha não responde "quem abriu a de quem"', coalesce(v_paciente, 'nulo');
end if;
raise notice 'ok 3 · e o nome do paciente junto';

raise notice '--- parte 2 · os recortes ---';

-- 4 · O recorte por paciente funciona.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_acesso(v_pac_dois, 'leu_ficha', '{}'::jsonb);

select count(*)::integer into v_n
  from public.minha_trilha(current_date - 30, current_date + 1, v_pac_dois) mtr
 where mtr.paciente is distinct from 'Bruno Trilha';
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 4: o recorte por paciente trouxe % linha(s) de outra ficha — recorte que não recorta faz a psicóloga desconfiar do que lê', v_n;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n
  from public.minha_trilha(current_date - 30, current_date + 1, v_pac_dois) mtr;
reset role;
if v_n < 1 then
  raise exception 'FALHOU 4: o recorte por paciente devolveu % linhas — o acesso à ficha do Bruno acabou de ser gravado', v_n;
end if;
raise notice 'ok 4 · o recorte por paciente separa uma ficha da outra';

-- 5 · O recorte por período exclui o que está fora.
--
-- A linha nasce carimbada com `now()` pelo gatilho `trilha_carimba`, que é
-- `before insert`. Envelhecer exige `update` depois — inserir com data antiga
-- não funciona, e isso é fato observado na suíte 0062.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_acesso(v_pac_um, 'arquivou', '{"marca":"antiga"}'::jsonb);
reset role;

set local role postgres;
update public.trilha_acesso set em = now() - interval '200 days'
 where conta_id = v_a_conta and acao = 'arquivou';
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n
  from public.minha_trilha(current_date - 30, current_date + 1) mtr
 where mtr.acao = 'arquivou';
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 5: uma linha de 200 dias atrás apareceu numa janela de 30 dias (% linha(s)) — período que não recorta faz a tela mentir sobre o que houve na semana', v_n;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n
  from public.minha_trilha(current_date - 365, current_date + 1) mtr
 where mtr.acao = 'arquivou';
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 5: a linha de 200 dias atrás não apareceu na janela de um ano (% linha(s)) — a trilha some quando a pergunta é antiga', v_n;
end if;
raise notice 'ok 5 · o período recorta dos dois lados';

-- 6 · Período invertido é recusado.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  select count(*)::integer into v_n
    from public.minha_trilha(current_date, current_date - 30) mtr;
  reset role;
  raise exception 'FALHOU 6: um período que termina antes de começar foi aceito e devolveu % linha(s) — a resposta vazia pareceria "nada aconteceu"', v_n;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position('termina antes' in v_erro) = 0 then
  raise exception 'FALHOU 6: a recusa do período invertido não diz o que houve — veio "%"', v_erro;
end if;
raise notice 'ok 6 · período invertido é recusado, e a recusa se explica';

-- 7 · Período de mais de um ano é recusado.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  select count(*)::integer into v_n
    from public.minha_trilha(current_date - 3000, current_date) mtr;
  reset role;
  raise exception 'FALHOU 7: um pedido de oito anos foi aceito (% linha(s)) — trilha de conta antiga tem dezenas de milhares de linhas e a tela travaria', v_n;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position('máximo um ano' in v_erro) = 0 then
  raise exception 'FALHOU 7: a recusa do período longo não diz o limite — veio "%"', v_erro;
end if;
raise notice 'ok 7 · período longo demais é recusado com o limite dito';

raise notice '--- parte 3 · quem lê e quem não lê ---';

-- 8 · Sem acesso clínico a recusa é dita, não são zero linhas.  ← decide
--
-- A ordem aqui é a verificação de outra coisa, e é a cicatriz da 0062: o
-- gatilho de signup cria conta própria para o usuário novo e `usuarios.conta_id`
-- é `on delete cascade`. Apagar a conta dele antes de mudá-lo de casa apaga o
-- próprio usuário, e a secretária chegaria em `minha_trilha` sem conta nenhuma —
-- com a recusa certa ('sem conta') pela razão errada. Mover primeiro, apagar
-- depois.
--
-- `acesso_clinico` fica nulo de propósito: a 0049 define nulo como "usa o padrão
-- do papel", e o padrão de 'secretaria' é não. É o caminho que uma conta real
-- percorre, e não uma coluna preenchida à mão só para o teste passar.
set local role postgres;
insert into auth.users (id, email, raw_user_meta_data)
  values (v_c_auth, 'trilhasec@teste.sessoes.com.br', '{"nome":"Trilha Secretaria"}'::jsonb);
select conta_id into v_c_conta from public.usuarios where auth_user_id = v_c_auth;
delete from public.profissionais
 where usuario_id = (select id from public.usuarios where auth_user_id = v_c_auth);
update public.usuarios set conta_id = v_a_conta, papel = 'secretaria', acesso_clinico = null
 where auth_user_id = v_c_auth;
delete from public.contas where id = v_c_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_c_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
if public.conta_atual() is distinct from v_a_conta then
  reset role;
  raise exception 'FALHOU 8: a secretária não ficou na conta da psicóloga — a recusa viria por falta de conta e não por falta de acesso clínico';
end if;
if public.le_clinico() then
  reset role;
  raise exception 'FALHOU 8: a secretária tem acesso clínico — o padrão do papel da 0049 deixou de valer';
end if;
begin
  select count(*)::integer into v_n
    from public.minha_trilha(current_date - 30, current_date + 1) mtr;
  reset role;
  raise exception 'FALHOU 8: a secretária leu a trilha e recebeu % linha(s) — quem não pode ler prontuário não pode ler a lista de quem leu prontuário', v_n;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position('clínico' in v_erro) = 0 then
  raise exception 'FALHOU 8: a recusa não fala do acesso clínico — veio "%". Zero linhas em silêncio numa tela de auditoria é indistinguível de "ninguém acessou nada"', v_erro;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_c_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  v_tamanho := public.tamanho_da_trilha();
  reset role;
  raise exception 'FALHOU 8: a secretária leu o tamanho da trilha (%) — o número de linhas já conta quanto se olhou prontuário nesta casa', v_tamanho;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position('clínico' in v_erro) = 0 then
  raise exception 'FALHOU 8: tamanho_da_trilha recusou por outra razão — veio "%"', v_erro;
end if;
raise notice 'ok 8 · sem acesso clínico a porta é fechada em voz alta, não em silêncio';

-- 9 · A vizinha não vê a trilha da outra.  ← decide
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_acesso(v_pac_viz, 'leu_ficha', '{}'::jsonb);

select count(*)::integer into v_n
  from public.minha_trilha(current_date - 365, current_date + 1) mtr
 where mtr.paciente in ('Ana Trilha', 'Bruno Trilha') or mtr.quem = v_a_usuario;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 9: a vizinha viu % linha(s) da trilha da outra conta — nome de paciente ao lado de nome de profissional é vazamento clínico com outra roupa', v_n;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n
  from public.minha_trilha(current_date - 365, current_date + 1) mtr
 where mtr.paciente = 'Carla Vizinha';
reset role;
if v_n < 1 then
  raise exception 'FALHOU 9: a vizinha também não vê a própria trilha (% linhas) — o isolamento cortou o lado errado', v_n;
end if;
raise notice 'ok 9 · cada uma lê a própria trilha e só a própria';

-- 10 · A trilha continua sem update e sem delete, nem pela dona.  ← decide
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
update public.trilha_acesso set acao = 'editou_ficha' where conta_id = v_a_conta;
get diagnostics v_n = row_count;
if v_n <> 0 then
  reset role;
  raise exception 'FALHOU 10: a dona editou % linha(s) da própria trilha — agora que ela lê a trilha, poder editá-la é o que transformaria a defesa em anotação', v_n;
end if;
delete from public.trilha_acesso where conta_id = v_a_conta;
get diagnostics v_n = row_count;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 10: a dona apagou % linha(s) da própria trilha — a página /seguranca promete o contrário em voz alta', v_n;
end if;
raise notice 'ok 10 · ler a trilha não abriu porta para editá-la';

raise notice '--- parte 4 · o que a tela precisa saber ---';

-- 11 · tamanho_da_trilha diz quantas linhas há e de quando começa.
--
-- Existe por uma razão só, e ela é sobre confiança: uma tela que mostra as
-- últimas cinquenta linhas sem dizer que há dezoito mil parece uma tela que
-- esconde.
select count(*)::integer, min(em) into v_n, v_min_em
  from public.trilha_acesso where conta_id = v_a_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_tamanho := public.tamanho_da_trilha();
reset role;

if (v_tamanho->>'linhas')::integer is distinct from v_n then
  raise exception 'FALHOU 11: tamanho_da_trilha disse % linhas e a conta tem % — a tela que mostra um recorte precisa dizer o tamanho do todo, senão parece que esconde', v_tamanho->>'linhas', v_n;
end if;
if v_tamanho->>'primeira' is null then
  raise exception 'FALHOU 11: tamanho_da_trilha não diz de quando a trilha começa — sem isso a psicóloga não sabe se o silêncio de março é ausência de acesso ou ausência de registro';
end if;
if (v_tamanho->>'primeira')::timestamptz is distinct from v_min_em then
  raise exception 'FALHOU 11: a primeira linha saiu como % e a mais antiga da conta é % — a data de início está errada', v_tamanho->>'primeira', v_min_em;
end if;
raise notice 'ok 11 · o tamanho e o começo da trilha são ditos: % linhas desde %', v_n, v_min_em;

-- 12 · A assinatura não tem filtro por ação.  ← decide
--
-- É a única verificação desta suíte que testa uma **ausência**, e é de
-- propósito: uma tela de auditoria com filtro por tipo de evento é uma tela onde
-- o evento inconveniente é o que ninguém marca. Sem esta linha alguém
-- acrescenta o filtro daqui a dois builds achando que ajuda.
--
-- `position()` e não `like`: `_` é curinga e já acusou código correto (0060d).
select pg_get_function_arguments(pr.oid) into v_assinatura
  from pg_proc pr
  join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public' and pr.proname = 'minha_trilha';

if v_assinatura is null then
  raise exception 'FALHOU 12: minha_trilha não existe no catálogo';
end if;
if position('acao' in v_assinatura) > 0
   or position('ação' in v_assinatura) > 0
   or position('evento' in v_assinatura) > 0 then
  raise exception 'FALHOU 12: a assinatura ganhou filtro por ação — "%". Tela de auditoria com filtro por tipo de evento é tela onde o evento inconveniente é o que ninguém marca', v_assinatura;
end if;
if position('p_de' in v_assinatura) = 0 or position('p_ate' in v_assinatura) = 0
   or position('p_paciente' in v_assinatura) = 0 then
  raise exception 'FALHOU 12: a assinatura perdeu período ou paciente — "%". São as duas perguntas que alguém faz quando desconfia de alguma coisa', v_assinatura;
end if;
raise notice 'ok 12 · o recorte é por período e por paciente, e por nada mais';

raise notice '--- parte 5 · as trancas ---';

-- 13 · exportar_paciente continua deixando rastro.
--
-- É a lição da 0060 pelo avesso: lá o `insert` de `exportou_conta` sumiu de uma
-- função sem que nada quebrasse. Aqui a suíte olha o efeito e não o corpo.
select count(*)::integer into v_antes
  from public.trilha_acesso
 where conta_id = v_a_conta and acao = 'exportou_paciente';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.exportar_paciente(v_pac_um);
reset role;

select count(*)::integer into v_n
  from public.trilha_acesso
 where conta_id = v_a_conta and acao = 'exportou_paciente' and paciente_id = v_pac_um;
if v_n <> v_antes + 1 then
  raise exception 'FALHOU 13: exportar uma ficha não deixou rastro (% linhas de exportou_paciente) — foi exatamente esse insert que a 0060 apagou sem querer da exportação da conta', v_n;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n
  from public.minha_trilha(current_date - 30, current_date + 1) mtr
 where mtr.acao = 'exportou_paciente';
reset role;
if v_n < 1 then
  raise exception 'FALHOU 13: o rastro da exportação está na tabela mas não chega à tela — a psicóloga não veria a cópia que saiu da casa dela';
end if;
raise notice 'ok 13 · a exportação da ficha deixa rastro, e o rastro é lido';

-- 14 · O anônimo não executa nenhuma das duas.
perform set_config('request.jwt.claims', null, true);
set local role anon;
begin
  select count(*)::integer into v_n
    from public.minha_trilha(current_date - 30, current_date) mtr;
  reset role;
  raise exception 'FALHOU 14: o anônimo chamou minha_trilha e recebeu % linha(s)', v_n;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

set local role anon;
begin
  v_tamanho := public.tamanho_da_trilha();
  reset role;
  raise exception 'FALHOU 14: o anônimo leu o tamanho da trilha (%)', v_tamanho;
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 14 · o anônimo não alcança nenhuma das duas';

-- ============================================================ recolher o rastro

perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.trilha_acesso where conta_id in (v_a_conta, v_b_conta);
delete from public.mensagens where conta_id in (v_a_conta, v_b_conta);
delete from public.sessoes where conta_id in (v_a_conta, v_b_conta);
delete from public.enquadres where conta_id in (v_a_conta, v_b_conta);
delete from public.pacientes where conta_id in (v_a_conta, v_b_conta);
delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.profissionais where conta_id in (v_a_conta, v_b_conta);
delete from public.usuarios where conta_id in (v_a_conta, v_b_conta);
delete from public.contas where nome in ('Trilha Teste', 'Trilha Vizinha', 'Trilha Secretaria');
reset role;

raise notice 'SUITE 0063 PASSOU: 14 verificações';
end $do$;
