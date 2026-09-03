-- Teste da medida do Receita Saúde (P8, migração 0079).
--
-- A verificação que decide este arquivo é a **3**: a conta de teste não entra
-- na conta. Não é higiene de dado, é o que separa medir de se enganar — hoje a
-- conta de demonstração tem 72 recibos e as reais têm seis no total, e uma
-- mediana que somasse as duas me diria que a P8 funciona com base em dado que
-- eu mesmo plantei. O número existiria, pareceria medida, e responderia à
-- pergunta errada.
--
-- E a **1** é a que impede o resto de importar: se qualquer autenticada
-- alcançasse a função, o painel do negócio teria vazado quantas contas existem
-- e quanto elas usam o produto para dentro da conta de uma psicóloga.
--
--    1. quem não é operador leva exceção                              ← decide
--    2. sem ninguém marcado, a mediana volta nula e não zero           ← decide
--    3. conta de teste não entra na conta                             ← decide
--    4. conta PJ não entra: o cartão não existe para ela
--    5. a mediana é dos dias entre pagamento e baixa
--    6. nenhum paciente e nenhuma sessão saem daqui
--    7. `anon` não alcança a função
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0079_a_medida_e_do_produto_nao_da_pessoa.sql

do $do$
declare
  v_op    uuid := '11111111-1111-4111-8111-111111111179';
  v_ela   uuid := '22222222-2222-4222-8222-222222222279';
  v_c_op  uuid; v_c_ela uuid; v_c_teste uuid; v_c_pj uuid;
  v_pac   uuid; v_cob uuid; v_prof uuid;
  v_r     jsonb; v_r_id uuid; v_erro text; v_n integer;
begin

delete from auth.users where id in (v_op, v_ela);
delete from public.contas where nome in ('Medida Operador', 'Medida Ela', 'Medida Teste', 'Medida PJ');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_op,  'medida.op@teste.sessoes.com.br',  '{"nome":"Medida Operador"}'::jsonb),
         (v_ela, 'medida.ela@teste.sessoes.com.br', '{"nome":"Medida Ela"}'::jsonb);

select conta_id into v_c_op  from public.usuarios where auth_user_id = v_op;
select conta_id into v_c_ela from public.usuarios where auth_user_id = v_ela;

update public.contas set nome = 'Medida Operador' where id = v_c_op;
update public.contas set nome = 'Medida Ela', regime = 'pf', receita_saude = true
 where id = v_c_ela;

-- ------------------------------------------------------------------------ 1
--
-- A conta dela é uma conta comum: sem a marca de operador, a função tem de
-- recusar. A porta em `page.tsx` devolve 404 antes disso; esta é a fechadura.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

begin
  perform public.receita_saude_do_painel();
  raise exception 'FALHOU 1: uma conta comum leu a medida do painel — ela diz quantas contas existem e quanto elas usam o produto';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
  if v_erro not like '%operador%' then
    raise exception 'FALHOU 1: recusou, mas por outro motivo: %', v_erro;
  end if;
end;

reset role;

-- Daqui para baixo eu sou o operador.
update public.usuarios set operador = true where auth_user_id = v_op;

-- ------------------------------------------------------------------------ 2
--
-- Nenhum recibo marcado em conta nenhuma nova: o que a função devolver aqui
-- vale contra o banco inteiro, então a verificação é sobre a FORMA, não sobre
-- o valor — `dias_ate_a_baixa` é uma chave que existe e pode ser nula.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_op::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_r := public.receita_saude_do_painel();

if not (v_r ? 'dias_ate_a_baixa') then
  raise exception 'FALHOU 2: a medida não devolve dias_ate_a_baixa';
end if;

select string_agg(k, ', ') into v_erro
  from unnest(array['contas','contas_com_recibo','contas_que_marcaram',
                    'marcados','pendentes','pendentes_de_anos_anteriores']) k
 where jsonb_typeof(v_r -> k) is distinct from 'number';

if v_erro is not null then
  raise exception 'FALHOU 2: % não voltou como número — contagem ausente viraria travessão numa tela que precisa de zero', v_erro;
end if;

v_n := (v_r ->> 'contas')::int;
reset role;

-- ------------------------------------------------------------------------ 3
--
-- A conta de teste some da conta. Crio uma conta PF com o modo ligado e
-- marcada como teste: `contas` não pode mudar.
insert into public.contas (nome, regime, receita_saude, is_teste)
  values ('Medida Teste', 'pf', true, true) returning id into v_c_teste;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_op::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_r := public.receita_saude_do_painel();
if (v_r ->> 'contas')::int <> v_n then
  raise exception 'FALHOU 3: a conta de teste entrou na conta (% → %) — a de demonstração sozinha tem mais recibos que todas as reais, e a mediana viraria medida do meu próprio dado', v_n, (v_r ->> 'contas')::int;
end if;

reset role;

-- ------------------------------------------------------------------------ 4
--
-- A conta PJ também não entra: para ela o cartão não existe, e
-- `ao_pagar_gera_recibo_rfb` volta antes de criar pendência.
insert into public.contas (nome, regime, receita_saude, is_teste)
  values ('Medida PJ', 'pj', true, false) returning id into v_c_pj;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_op::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_r := public.receita_saude_do_painel();
if (v_r ->> 'contas')::int <> v_n then
  raise exception 'FALHOU 4: a conta PJ entrou no escopo — o cartão do Receita Saúde não existe para ela';
end if;

reset role;

-- ------------------------------------------------------------------------ 5
--
-- Dois recibos marcados com atrasos conhecidos, na conta dela (PF, não-teste):
-- a mediana tem de sair deles e não de outra diferença de datas.
-- `checa_conta_do_paciente` deriva `conta_id` de `conta_atual()` e exige um
-- profissional da mesma conta. Ou seja: paciente não se cria como `postgres`,
-- cria-se **de dentro da sessão dela** — foi o que este teste tentou fazer na
-- primeira execução e o banco recusou, com razão.
select p.id into v_prof from public.profissionais p where p.conta_id = v_c_ela limit 1;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_ela::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome)
  values (v_c_ela, v_prof, 'Paciente da Medida') returning id into v_pac;

-- Pelo caminho de verdade, e não por `insert` direto em `recibos_rfb`: quem
-- cria a pendência é `ao_pagar_gera_recibo_rfb`, e quem carimba a baixa é
-- `marcar_recibo_rfb`. Um teste que plantasse as duas colunas à mão provaria a
-- aritmética da mediana e não provaria que ela lê o que o produto escreve.
for v_n in select unnest(array[10, 20]) loop
  insert into public.cobrancas
    (conta_id, paciente_id, tipo, motivo, valor, competencia, estado, paga_em)
  values
    (v_c_ela, v_pac, 'sessao', 'sessao_realizada', 200,
     date_trunc('month', public.hoje_sp())::date, 'paga',
     (public.hoje_sp() - v_n)::timestamptz)
  returning id into v_cob;

  select r.id into v_r_id from public.recibos_rfb r where r.cobranca_id = v_cob;
  if v_r_id is null then
    raise exception 'FALHOU 5: o gatilho não gerou a pendência do recibo';
  end if;
  perform public.marcar_recibo_rfb(v_r_id);
end loop;

reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_op::text, 'role', 'authenticated')::text, true);
set local role authenticated;

v_r := public.receita_saude_do_painel();

-- Dez e vinte dias entre o pagamento e a baixa. Se outra conta real do banco
-- tiver recibo marcado a mediana muda, então a conferência não é do valor
-- exato: ela tem de existir e não pode ser negativa.
if v_r ->> 'dias_ate_a_baixa' is null then
  raise exception 'FALHOU 5: com dois recibos marcados a mediana continuou nula';
end if;
if (v_r ->> 'dias_ate_a_baixa')::numeric < 0 then
  raise exception 'FALHOU 5: mediana negativa — a subtração está invertida, e a tela diria que a baixa acontece antes do pagamento';
end if;

-- ------------------------------------------------------------------------ 6
--
-- A fronteira 9 conferida no lugar certo: nenhuma chave da saída pode carregar
-- paciente, sessão ou nome de conta.
select string_agg(k, ', ') into v_erro
  from jsonb_object_keys(v_r) k
 where k ~* 'paciente|sessao|sessão|nome|email|cpf|telefone|evolucao|anamnese';

if v_erro is not null then
  raise exception 'FALHOU 6: a medida do painel carrega %', v_erro;
end if;

reset role;

-- ------------------------------------------------------------------------ 7
if has_function_privilege('anon', 'public.receita_saude_do_painel()', 'execute') then
  raise exception 'FALHOU 7: anon alcança a medida do painel';
end if;

-- E a que ela substituiu não pode ter ficado para trás: duas funções medindo a
-- mesma coisa em escopos diferentes é a segunda fonte de verdade do §9.
if exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'telemetria_do_receita_saude'
) then
  raise exception 'FALHOU 7: telemetria_do_receita_saude() voltou — ela mede a mesma coisa presa a conta_atual()';
end if;

-- ------------------------------------------------------------------------ fim
delete from public.recibos_rfb where conta_id = v_c_ela;
delete from public.cobrancas where conta_id = v_c_ela;
delete from public.pacientes where conta_id = v_c_ela;
delete from public.contas where id in (v_c_teste, v_c_pj);
delete from auth.users where id in (v_op, v_ela);
delete from public.contas where nome in ('Medida Operador', 'Medida Ela');

raise notice 'OK · 0079 · a medida é do produto, não da pessoa — e a conta de teste não entra nela';
end
$do$;
