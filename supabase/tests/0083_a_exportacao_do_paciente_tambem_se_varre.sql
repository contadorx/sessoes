-- Teste da varredura que faltava do lado clínico (migração 0083).
--
-- A verificação 15 da `0024_lgpd.sql` varre `information_schema` e cobra que
-- toda tabela com `conta_id` saia em `exportar_conta`. Foi ela que achou o
-- `objetivos` esquecido. **`exportar_paciente` não tinha irmã**: a cópia que a
-- psicóloga entrega quando o Conselho pede não tinha quem a cobrasse.
--
-- Este arquivo escreve a irmã.
--
--   1. o plano terapêutico sai na cópia do paciente              ← decide
--   2. toda tabela com le_clinico() sai em exportar_paciente     ← decide (lei 7)
--   3. e continua saindo na exportação da conta (a 0082 viva)
--   4. a trilha NÃO sai na cópia do paciente, e é decisão
--   5. a assimetria com eliminar_conta não pode voltar
--
-- A **5** é a que explica por que isto foi S1 e não S3: `eliminar_conta` varre
-- o catálogo e apaga tudo; a exportação enumerava e deixava para trás. O
-- produto obrigava a tirar a cópia, prometia que ela responde ao Conselho, e
-- apagava o que não estava nela.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0083_a_exportacao_do_paciente_tambem_se_varre.sql

do $do$
declare
  v_ela   uuid := '22222222-2222-4222-8222-222222222283';
  v_conta uuid; v_prof uuid; v_pac uuid;
  v_j jsonb; v_erro text; v_n integer;
begin

delete from auth.users where id = v_ela;
delete from public.contas where nome = 'Copia 0083';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_ela, 'copia@teste.sessoes.com.br', '{"nome":"Copia 0083"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_ela;
update public.contas set nome = 'Copia 0083' where id = v_conta;
select p.id into v_prof from public.profissionais p where p.conta_id = v_conta limit 1;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome)
  values (v_conta, v_prof, 'Gumercindo Alcântara Vilalobos') returning id into v_pac;

-- Pelo caminho de verdade, e não por insert cru: quem escreve objetivo é a
-- função da 0072.
perform public.anotar_objetivo(v_pac,
  'Reduzir a frequência das crises de ansiedade antes de reuniões de trabalho.',
  (public.hoje_sp() + 90)::date);

-- ------------------------------------------------------------------------ 1
v_j := public.exportar_paciente(v_pac);

if not (v_j ? 'objetivos') then
  raise exception 'FALHOU 1: a cópia do paciente não tem a chave objetivos — e eliminar_conta apaga a tabela, porque ela varre o catálogo em vez de enumerar';
end if;

if jsonb_array_length(v_j -> 'objetivos') <> 1 then
  raise exception 'FALHOU 1: a chave existe e veio com % objetivo(s)', jsonb_array_length(v_j -> 'objetivos');
end if;

if (v_j -> 'objetivos' -> 0) ? 'conta_id' then
  raise exception 'FALHOU 1: o objetivo vazou conta_id na cópia do paciente';
end if;

-- ------------------------------------------------------------------------ 4
--
-- E a trilha continua fora, de propósito: é o registro de QUEM LEU, é da
-- conta e não do paciente, e sai em `exportar_conta`. Pôr a trilha aqui
-- entregaria à paciente o histórico de acessos da psicóloga.
if v_j ? 'trilha_acesso' then
  raise exception 'FALHOU 4: a cópia do paciente levou a trilha de acesso — ela é o registro de quem leu, e é da conta';
end if;

-- ------------------------------------------------------------------------ 3
v_j := public.exportar_conta();
if not (v_j ? 'objetivos') then
  raise exception 'FALHOU 3: a 0082 se perdeu — objetivos saiu da exportação da conta';
end if;

reset role;

-- ------------------------------------------------------------------------ 2
--
-- A varredura. Enumerar as seis tabelas clínicas aqui seria repetir o erro que
-- este arquivo existe para impedir: a sétima entraria sem ninguém notar, que é
-- exatamente como `objetivos` entrou na 0072.
select string_agg(t.tabela, ', ' order by t.tabela), count(*)::integer
  into v_erro, v_n
  from (
    select distinct c.relname as tabela
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
     where pg_get_expr(pol.polqual, pol.polrelid) like '%le_clinico%'
        or pg_get_expr(pol.polwithcheck, pol.polrelid) like '%le_clinico%'
  ) t
 where t.tabela <> 'trilha_acesso'
   and pg_get_functiondef('public.exportar_paciente(uuid,boolean)'::regprocedure)
       not like '%public.' || t.tabela || ' %';

if v_n > 0 then
  raise exception 'FALHOU 2: tabela(s) clínica(s) fora da cópia do paciente: %. Quem põe le_clinico() numa tabela acrescenta a exportação na mesma build — e eliminar_conta já varre o catálogo, então o que não sai aqui some sem cópia', v_erro;
end if;

-- ------------------------------------------------------------------------ 5
--
-- A assimetria, dita como invariante: `eliminar_conta` não pode voltar a ter
-- lista, porque é a metade que apaga. Se um dia ela enumerar, o par
-- "varre e apaga / enumera e exporta" inverte para o lado que perde dado.
if pg_get_functiondef('public.eliminar_conta(text)'::regprocedure) !~ 'information_schema|pg_class|pg_tables' then
  raise exception 'FALHOU 5: eliminar_conta deixou de varrer o catálogo — se ela passar a enumerar, a tabela nova fica viva depois de "apagar minha conta", e é a lei 7 na direção oposta';
end if;

-- ------------------------------------------------------------------------ fim
delete from public.contas where id = v_conta;
delete from auth.users where id = v_ela;

raise notice 'OK · 0083 · a cópia que responde ao Conselho leva o plano terapêutico, e agora tem quem a cobre';
end
$do$;
