-- Teste do plano terapêutico leve (B31, migração 0072).
--
-- **O objetivo terapêutico é prontuário, e a camada decide quem lê.** É a
-- verificação que decide este arquivo, e ela é irmã do S2 que a mesma build
-- consertou na tela: o painel da agenda oferecia escrita clínica a quem a RLS
-- recusa. Aqui é o outro lado — a RLS tem que recusar de verdade, senão a tela
-- é a única proteção, e tela não é autorização.
--
-- Três decisões de produto viram verificação:
--
--   · a **4**, que exige que a secretária não leia nem escreva objetivo;
--   · a **6**, que recusa data de revisão no passado — uma revisão que nasce
--     vencida só acontece por engano de digitação, e recusar na hora é melhor
--     do que a tela mostrar, no minuto seguinte, um atraso que ela criou;
--   · a **8**, que exige que **concluir não apague**. O objetivo alcançado é
--     parte do que aconteceu no acompanhamento, e o registro guarda o que
--     aconteceu.
--
-- E a **10**, que é sobre o que o banco NÃO faz: ele não classifica atraso.
-- Devolve datas; quem compara com hoje é a tela, em São Paulo. Um booleano
-- "vencido" vindo daqui seria a segunda fonte de verdade sobre uma conta de
-- data — e este projeto já pagou por uma.
--
--    1. a tabela existe, com RLS ligada
--    2. as FKs estão indexadas (lei 2)
--    3. anotar cria, e devolve o id
--    4. a secretária não lê nem escreve                                ← decide
--    5. a vizinha não lê o objetivo da outra
--    6. revisão no passado é recusada                                  ← decide
--    7. remarcar move a data do que está aberto
--    8. concluir marca a data e o objetivo FICA                        ← decide
--    9. concluir duas vezes devolve falso, não erro
--   10. não existe coluna de "vencido" — o banco não julga             ← decide
--   11. não há policy de delete: o que entrou fica pelo prazo
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0072_objetivos_com_data_de_revisao.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111172';
  v_b_auth uuid := '22222222-2222-4222-8222-222222222172';
  v_sec_auth uuid := '33333333-3333-4333-8333-333333333172';
  v_a_conta uuid; v_a_prof uuid; v_b_conta uuid; v_b_prof uuid;
  v_ana uuid; v_bia uuid;
  v_obj uuid; v_erro text; v_n integer; v_ok boolean;
  v_hoje date;
begin

delete from auth.users where id in (v_a_auth, v_b_auth, v_sec_auth);
delete from public.contas where nome in ('Objetivo Teste', 'Objetivo Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'obj@teste.sessoes.com.br', '{"nome":"Objetivo Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'objviz@teste.sessoes.com.br', '{"nome":"Objetivo Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id into v_b_prof from public.profissionais where conta_id = v_b_conta;

v_hoje := public.hoje_sp();

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Objetivo', '5511900000721', 'em_atendimento') returning id into v_ana;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_b_prof, 'Bia Objetivo', '5511900000722', 'em_atendimento') returning id into v_bia;
reset role;

-- 1 · a tabela existe, com RLS ligada.
select count(*)::integer into v_n from pg_class
 where relname = 'objetivos' and relnamespace = 'public'::regnamespace and relrowsecurity;
if v_n <> 1 then raise exception 'FALHOU 1: objetivos sem RLS'; end if;

-- 2 · as FKs indexadas. A lei 2 — e a checagem varre o catálogo, não uma lista.
select count(*)::integer into v_n
  from pg_constraint co
 where co.conrelid = 'public.objetivos'::regclass and co.contype = 'f'
   and not exists (
     select 1 from pg_index ix
      where ix.indrelid = co.conrelid
        and (ix.indkey::smallint[])[0] = co.conkey[1]);
if v_n > 0 then raise exception 'FALHOU 2: % chave(s) estrangeira(s) sem índice', v_n; end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

-- 3 · anotar cria.
v_obj := public.anotar_objetivo(v_ana, 'Retomar o trabalho sem crise', v_hoje + 60);
if v_obj is null then raise exception 'FALHOU 3: anotar não devolveu id'; end if;
select count(*)::integer into v_n from public.objetivos_do_paciente(v_ana);
if v_n <> 1 then raise exception 'FALHOU 3: a lista devolveu %', v_n; end if;

-- 6 · revisão no passado é recusada.  ← decide
begin
  perform public.anotar_objetivo(v_ana, 'objetivo com data velha', v_hoje - 1);
  raise exception 'FALHOU 6: aceitou revisão no passado';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 6' in v_erro) > 0 then raise; end if;
  if position('já passou' in v_erro) = 0 then raise exception 'FALHOU 6: %', v_erro; end if;
end;

-- 7 · remarcar move a data.
if public.remarcar_revisao(v_obj, v_hoje + 120) is not true then
  raise exception 'FALHOU 7: não remarcou';
end if;
select count(*)::integer into v_n from public.objetivos
 where id = v_obj and revisar_em = v_hoje + 120;
if v_n <> 1 then raise exception 'FALHOU 7: a data não mudou'; end if;

-- 8 · concluir marca a data e o objetivo FICA.  ← decide
if public.concluir_objetivo(v_obj) is not true then raise exception 'FALHOU 8: não concluiu'; end if;
select count(*)::integer into v_n from public.objetivos
 where id = v_obj and concluido_em is not null;
if v_n <> 1 then
  raise exception 'FALHOU 8: concluir apagou o objetivo — ele é parte do que aconteceu no acompanhamento, e o registro guarda o que aconteceu';
end if;
select count(*)::integer into v_n from public.objetivos_do_paciente(v_ana);
if v_n <> 1 then raise exception 'FALHOU 8: o concluído sumiu da lista'; end if;

-- 9 · concluir duas vezes devolve falso.
if public.concluir_objetivo(v_obj) is not false then
  raise exception 'FALHOU 9: concluiu o que já estava concluído';
end if;
reset role;

-- 5 · a vizinha não lê o objetivo da outra.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*)::integer into v_n from public.objetivos;
if v_n <> 0 then raise exception 'FALHOU 5: a vizinha leu % objetivo(s) da outra conta', v_n; end if;
reset role;

-- 4 · a secretária não lê nem escreve.  ← decide
--
-- Objetivo terapêutico é conteúdo do prontuário, e a camada clínica não vem
-- junto com o cargo administrativo. Quem marca a agenda não precisa saber o que
-- está sendo trabalhado na terapia.
set local role postgres;
insert into auth.users (id, email, raw_user_meta_data)
  values (v_sec_auth, 'secobj@teste.sessoes.com.br', '{"nome":"Sec Objetivo"}'::jsonb);
delete from public.contas ct where ct.id = (
  select u.conta_id from public.usuarios u where u.auth_user_id = v_sec_auth);
update public.usuarios set conta_id = v_a_conta, papel = 'secretaria'
 where auth_user_id = v_sec_auth;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_sec_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

select count(*)::integer into v_n from public.objetivos;
if v_n <> 0 then
  raise exception 'FALHOU 4: a secretária leu % objetivo(s) — objetivo terapêutico é prontuário, e acesso clínico não vem junto com o cargo administrativo', v_n;
end if;

begin
  perform public.anotar_objetivo(v_ana, 'a secretária escrevendo no prontuário', null);
  raise exception 'FALHOU 4: a secretária escreveu um objetivo';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 4' in v_erro) > 0 then raise; end if;
end;
reset role;

-- 10 · o banco não classifica atraso.  ← decide
select count(*)::integer into v_n from information_schema.columns
 where table_schema = 'public' and table_name = 'objetivos'
   and column_name ~* 'vencid|atrasad|pendente';
if v_n > 0 then
  raise exception 'FALHOU 10: o banco ganhou coluna de juízo sobre a data — ele devolve datas, e quem compara com hoje é a tela, em São Paulo';
end if;

-- 11 · não há policy de delete.
select count(*)::integer into v_n from pg_policies
 where schemaname = 'public' and tablename = 'objetivos' and cmd = 'DELETE';
if v_n > 0 then
  raise exception 'FALHOU 11: existe policy de delete — o que entrou no prontuário fica pelo prazo de guarda';
end if;

set local role postgres;
delete from auth.users where id in (v_a_auth, v_b_auth, v_sec_auth);
delete from public.contas where nome in ('Objetivo Teste', 'Objetivo Vizinha');
reset role;

raise notice 'OK · 0072 · o plano leve é clínico, não julga a data, e concluir não apaga';
end
$do$;
