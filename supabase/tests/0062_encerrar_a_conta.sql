-- Teste do encerramento da conta (B41, migração 0062).
--
-- **É a suíte da única operação irreversível do produto**, e por isso metade
-- dela testa a recusa e não o ato. Seis decidem:
--
--   · a **1**, que exige que encerrar sem ter exportado seja impossível pelo
--     banco. A guarda de cinco anos é obrigação **dela** e continua depois que a
--     conta acaba (Res. CFP 001/2009) — o arquivo exportado é a única cópia que
--     sobrevive, e encerrar sem ele transfere para ela um problema sem solução;
--   · a **3**, que recusa exportação de quinze dias atrás. Um arquivo de duas
--     semanas tem a cara de completo e um buraco no fim;
--   · a **4**, que prova que **não dá para forjar a data da exportação**. Foi
--     descoberta aplicando a migração: `trilha_carimba` é `before insert` e faz
--     `new.em := now()`, então uma linha inserida com data antiga nasce com a
--     hora real. Quem quiser burlar a trava precisa exportar de verdade;
--   · a **8**, que exige o papel `dona`. Secretária não encerra a casa de
--     ninguém, e a checagem é do banco e não da tela;
--   · a **9**, que varre o `information_schema` depois de encerrar e reprova se
--     **qualquer** tabela com `conta_id` ainda tiver linha. É a lição da 0059b
--     pelo avesso: lá a lista escrita à mão esqueceu de **levar** dezessete
--     tabelas; aqui ela esqueceria de **apagar** — e dado que sobra depois de
--     alguém pedir para sumir é a pior falha que este produto pode ter;
--   · a **12**, que confere a vizinha inteira depois. Isolamento no ato mais
--     destrutivo do produto é onde ele precisa valer mais.
--
-- **Por que a conta A é de verdade apagada aqui.** Não dá para testar exclusão
-- sem excluir. A conta A nasce nesta suíte, recebe paciente e sessão, e some no
-- meio do arquivo — a limpeza do fim só recolhe a B.
--
-- Cuidados de escrita, cicatriz desta obra: variável leva `v_` (0060b), nada de
-- alias de uma letra (0052c), varredura de corpo de função usa `position()` e
-- nunca `like` porque `_` é curinga (0060d).
--
--   parte 1 · a trava
--     1. sem exportação nenhuma, encerrar é impossível                  ← decide
--     2. ...e a recusa diz por quê, em português
--     3. exportação de quinze dias atrás não serve                      ← decide
--     4. e não dá para forjar a data: a trilha carimba o insert         ← decide
--     5. o nome errado recusa, e a mensagem mostra o nome certo
--     6. espaço em volta do nome não impede
--     7. exportar agora destrava
--     8. só a dona encerra                                             ← decide
--
--   parte 2 · o que sobra depois
--     9. nenhuma tabela com conta_id tem linha da conta encerrada       ← decide
--    10. a conta some de contas
--    11. o login some junto
--    12. a vizinha continua inteira                                    ← decide
--
--   parte 3 · a frase que fica
--    13. nomeia até quando a guarda continua sendo dela
--    14. e não promete apagar o que o backup ainda tem
--
--   parte 4 · as trancas
--    15. exportacao_recente não é sonda de conta alheia
--    16. a trilha continua sem update e sem delete, nem pela dona
--    17. o anônimo não executa nada disto
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0062_encerrar_a_conta.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111162';
  v_b_auth uuid := '22222222-2222-4222-8222-222222222162';
  v_c_auth uuid := '33333333-3333-4333-8333-333333333162';
  v_a_conta uuid; v_a_prof uuid; v_b_conta uuid; v_b_prof uuid; v_c_conta uuid;
  v_a_nome text; v_b_nome text;
  v_pac uuid; v_pac_b uuid;
  v_erro text; v_frase text; v_texto text;
  v_n integer; v_sobrou text := '';
  v_quando timestamptz;
  v_tb text;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.contas where nome in ('Encerrar Teste', 'Encerrar Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'encerrar@teste.sessoes.com.br', '{"nome":"Encerrar Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'encviz@teste.sessoes.com.br', '{"nome":"Encerrar Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;
select nome into v_a_nome from public.contas where id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id into v_b_prof from public.profissionais where conta_id = v_b_conta;
select nome into v_b_nome from public.contas where id = v_b_conta;

-- A conta A recebe conteúdo: sem dado, "apagou tudo" não prova nada.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Encerrar', '5511900000621', 'em_atendimento') returning id into v_pac;
reset role;

set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (v_a_conta, v_a_prof, v_pac,
          now() - interval '2 days',
          now() - interval '2 days' + interval '50 minutes',
          'avulsa', 'realizada', 200.00, 24, 50);
insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, agendada_para)
  values (v_a_conta, v_pac, 'whatsapp', 'lembrete_de_sessao', '5511900000621',
          'enc0062-lem', now());
reset role;

-- A vizinha também tem conteúdo, para a verificação 12 ter o que conferir.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_b_prof, 'Bia Vizinha', '5511900000622', 'em_atendimento') returning id into v_pac_b;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · a trava ---';

-- 1 e 2 · Sem exportação nenhuma, é impossível — e a recusa se explica.  ← decide
set local role authenticated;
begin
  perform public.eliminar_conta(v_a_nome);
  reset role;
  raise exception 'FALHOU 1: encerrou a conta sem exportação nenhuma — a guarda de cinco anos ficaria sem cópia em lugar nenhum do mundo';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

select count(*)::integer into v_n from public.contas where id = v_a_conta;
if v_n <> 1 then
  raise exception 'FALHOU 1: a conta sumiu mesmo com a recusa';
end if;
raise notice 'ok 1 · sem exportar, não encerra';

if position('guarda' in v_erro) = 0 or position('cópia' in v_erro) = 0 then
  raise exception 'FALHOU 2: a recusa não diz por quê — veio "%"', v_erro;
end if;
raise notice 'ok 2 · e a recusa explica a razão, não um código';

-- 3 e 4 · Exportação velha não serve — e não dá para forjar a data.  ← decide
--
-- O `insert` nasce carimbado com `now()` pelo gatilho `trilha_carimba`, então
-- envelhecer exige `update`. Isso **é** a verificação 4: quem quiser burlar a
-- trava precisa exportar de verdade.
set local role postgres;
insert into public.trilha_acesso (conta_id, acao, detalhe, em)
  values (v_a_conta, 'exportou_conta', '{}'::jsonb, now() - interval '15 days');
select em into v_quando from public.trilha_acesso
 where conta_id = v_a_conta and acao = 'exportou_conta';
reset role;

if v_quando < now() - interval '1 hour' then
  raise exception 'FALHOU 4: a trilha aceitou uma data antiga no insert (%) — daria para forjar a exportação e encerrar sem levar nada', v_quando;
end if;
raise notice 'ok 4 · a trilha carimba o insert: não se forja exportação';

set local role postgres;
update public.trilha_acesso set em = now() - interval '15 days'
 where conta_id = v_a_conta and acao = 'exportou_conta';
reset role;

set local role authenticated;
begin
  perform public.eliminar_conta(v_a_nome);
  reset role;
  raise exception 'FALHOU 3: encerrou com exportação de quinze dias — o arquivo dela tem a cara de completo e um buraco no fim';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 3 · exportação velha não destrava';

-- 5 · Nome errado recusa, e a mensagem mostra o nome certo.
set local role authenticated;
begin
  perform public.eliminar_conta('outra coisa qualquer');
  reset role;
  raise exception 'FALHOU 5: encerrou com o nome errado';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position(v_a_nome in v_erro) = 0 then
  raise exception 'FALHOU 5: a recusa não diz qual é o nome esperado — veio "%"', v_erro;
end if;
raise notice 'ok 5 · o nome é digitado, e a recusa mostra qual';

-- 8 · Só a dona.  ← decide
--
-- Vem antes da 7 de propósito: depois que a conta for encerrada não há mais
-- papel nenhum para testar.
--
-- **A ordem aqui é a verificação de outra coisa**, e custou uma reprovação: o
-- gatilho de signup cria conta própria para o usuário novo, e `usuarios.conta_id`
-- é `on delete cascade`. Apagar a conta dele antes de mudá-lo de casa apaga o
-- próprio usuário — a primeira redação fazia isso, e a secretária chegava em
-- `eliminar_conta` sem conta nenhuma, com a recusa certa pela razão errada.
-- Mover primeiro, apagar depois.
set local role postgres;
insert into auth.users (id, email, raw_user_meta_data)
  values (v_c_auth, 'secretaria@teste.sessoes.com.br', '{"nome":"Secretaria Enc"}'::jsonb);
select conta_id into v_c_conta from public.usuarios where auth_user_id = v_c_auth;
delete from public.profissionais
 where usuario_id = (select id from public.usuarios where auth_user_id = v_c_auth);
update public.usuarios set conta_id = v_a_conta, papel = 'secretaria'
 where auth_user_id = v_c_auth;
delete from public.contas where id = v_c_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_c_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  perform public.eliminar_conta(v_a_nome);
  reset role;
  raise exception 'FALHOU 8: a secretária encerrou a conta da psicóloga';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
if position('dona' in v_erro) = 0 then
  raise exception 'FALHOU 8: a recusa não fala do papel — veio "%"', v_erro;
end if;
raise notice 'ok 8 · secretária não encerra a casa de ninguém';

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

-- 6 e 7 · Exportar agora destrava, e espaço em volta não atrapalha.
set local role authenticated;
perform public.exportar_conta();
reset role;

select public.exportacao_recente(v_a_conta) into v_quando;
if v_quando is null or v_quando < now() - interval '5 minutes' then
  raise exception 'FALHOU 7: a exportação não ficou registrada na trilha (%) — é o defeito que a 0060e consertou', coalesce(v_quando::text, 'nulo');
end if;
raise notice 'ok 7 · exportar registra, e a trava lê da trilha';

set local role authenticated;
v_frase := public.eliminar_conta('  ' || v_a_nome || '  ');
reset role;
raise notice 'ok 6 · espaço em volta do nome não impede quem digitou certo';

raise notice '--- parte 2 · o que sobra depois ---';

-- 9 · Nenhuma tabela com conta_id tem linha da conta encerrada.  ← decide
--
-- A varredura é a mesma que a função usa para apagar, e é de propósito: as duas
-- leem o catálogo. Uma tabela criada daqui a três builds entra nas duas sozinha.
for v_tb in
  select co.table_name::text
    from information_schema.columns co
    join information_schema.tables ta
      on ta.table_schema = co.table_schema and ta.table_name = co.table_name
   where co.table_schema = 'public'
     and co.column_name = 'conta_id'
     and ta.table_type = 'BASE TABLE'
     and co.table_name <> 'contas'
loop
  execute format('select count(*) from public.%I where conta_id = $1', v_tb)
    into v_n using v_a_conta;
  if v_n > 0 then
    v_sobrou := v_sobrou || v_tb || '(' || v_n || ') ';
  end if;
end loop;

if v_sobrou <> '' then
  raise exception 'FALHOU 9: sobrou dado da conta encerrada em: % — dado que fica depois de alguém pedir para sumir é a pior falha deste produto', v_sobrou;
end if;
raise notice 'ok 9 · o catálogo inteiro varrido, e nada sobrou';

-- 10 · A conta some.
select count(*)::integer into v_n from public.contas where id = v_a_conta;
if v_n <> 0 then
  raise exception 'FALHOU 10: a conta continua em contas';
end if;
raise notice 'ok 10 · a conta some';

-- 11 · E o login junto.
select count(*)::integer into v_n from auth.users where id in (v_a_auth, v_c_auth);
if v_n <> 0 then
  raise exception 'FALHOU 11: % login(s) continuam de pé — quem entrasse encontraria um produto vazio sem entender o que houve', v_n;
end if;
raise notice 'ok 11 · o login some junto';

-- 12 · A vizinha continua inteira.  ← decide
select count(*)::integer into v_n from public.contas where id = v_b_conta;
if v_n <> 1 then
  raise exception 'FALHOU 12: a conta da vizinha sumiu junto';
end if;
select count(*)::integer into v_n from public.pacientes where conta_id = v_b_conta;
if v_n <> 1 then
  raise exception 'FALHOU 12: a vizinha perdeu paciente (% restantes)', v_n;
end if;
select count(*)::integer into v_n from auth.users where id = v_b_auth;
if v_n <> 1 then
  raise exception 'FALHOU 12: o login da vizinha sumiu junto';
end if;
raise notice 'ok 12 · o isolamento vale no ato mais destrutivo do produto';

raise notice '--- parte 3 · a frase que fica ---';

-- 13 · A frase nomeia até quando a guarda continua sendo dela.
if position('guarda' in v_frase) = 0 then
  raise exception 'FALHOU 13: a frase de encerramento não fala da guarda — veio "%"', v_frase;
end if;
if v_frase !~ '\d{2}/\d{2}/\d{4}' then
  raise exception 'FALHOU 13: a frase não traz a data até quando ela responde — veio "%"', v_frase;
end if;
raise notice 'ok 13 · a frase diz até quando ela continua responsável';

-- 14 · E não promete o que o backup ainda tem.
if position('7 dias' in v_frase) = 0 then
  raise exception 'FALHOU 14: a frase não menciona os sete dias do backup — prometer sumiço definitivo seria mentir ou operar sem cópia';
end if;
if v_frase ~* '(definitiv|para sempre|irrecuper|sem qualquer)' then
  raise exception 'FALHOU 14: a frase promete apagamento definitivo — veio "%"', v_frase;
end if;
raise notice 'ok 14 · sete dias ditos, nenhum "para sempre" prometido';

raise notice '--- parte 4 · as trancas ---';

-- 15 · `exportacao_recente` não é sonda de conta alheia.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  perform public.exportacao_recente(v_b_conta);
exception when others then
  reset role;
  raise exception 'FALHOU 15: a dona não lê a própria exportação — %', sqlerrm;
end;
reset role;

set local role authenticated;
begin
  perform public.exportacao_recente('00000000-0000-4000-8000-000000000000'::uuid);
  reset role;
  raise exception 'FALHOU 15: leu a exportação de uma conta alheia';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 15 · a exportação é da conta de quem pergunta';

-- 16 · A trilha continua sem update e sem delete, nem pela dona.
set local role authenticated;
update public.trilha_acesso set acao = 'leu_ficha' where conta_id = v_b_conta;
get diagnostics v_n = row_count;
if v_n <> 0 then
  reset role;
  raise exception 'FALHOU 16: a dona editou % linha(s) da própria trilha — trilha que se edita não é defesa de ninguém', v_n;
end if;
delete from public.trilha_acesso where conta_id = v_b_conta;
get diagnostics v_n = row_count;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 16: a dona apagou % linha(s) da própria trilha', v_n;
end if;
raise notice 'ok 16 · a trilha não se edita nem se apaga';

-- 17 · O anônimo não executa nada disto.
perform set_config('request.jwt.claims', null, true);
set local role anon;
begin
  perform public.eliminar_conta('qualquer');
  reset role;
  raise exception 'FALHOU 17: o anônimo chamou eliminar_conta';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

set local role anon;
begin
  perform public.exportacao_recente(v_b_conta);
  reset role;
  raise exception 'FALHOU 17: o anônimo leu a exportação';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 17 · o anônimo não alcança nada disto';

-- ============================================================ recolher o rastro
--
-- Só a vizinha: a conta A foi encerrada de verdade no meio do arquivo, que é o
-- que esta suíte existe para provar.
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.mensagens where conta_id = v_b_conta;
delete from public.trilha_acesso where conta_id = v_b_conta;
delete from public.sessoes where conta_id = v_b_conta;
delete from public.enquadres where conta_id = v_b_conta;
delete from public.pacientes where conta_id = v_b_conta;
delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.profissionais where conta_id = v_b_conta;
delete from public.usuarios where conta_id = v_b_conta;
delete from public.contas where nome in ('Encerrar Teste', 'Encerrar Vizinha');
reset role;

raise notice 'SUITE 0062 PASSOU: 17 verificações';
end $do$;
