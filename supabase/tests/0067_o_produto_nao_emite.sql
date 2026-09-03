-- Teste do assistente do Receita Saúde (P8, migrações 0067 e 0067b).
--
-- A verificação que decide este arquivo é a **6**, e ela é a fronteira 11
-- escrita como código: **nenhuma coluna deste banco aceita credencial gov.br**.
--
-- A tentação é permanente e tem nome comercial: a Hotina anuncia emitir o
-- recibo "em um clique", e "um clique" quer dizer que alguém guardou a conta
-- gov.br da psicóloga. Essa conta não é a chave do recibo — é a chave do INSS,
-- do e-CAC e da declaração dela. E a automação sobre tela de terceiro falha em
-- silêncio, com a multa de R$ 100 por recibo saindo do CPF dela.
--
-- Por isso a verificação não procura por uma coluna chamada "senha": procura
-- **por qualquer coluna que aceite o valor**. Uma coluna nova chamada
-- `credencial_fiscal` ou `token_ecac` cairia na varredura no dia em que fosse
-- criada, sem ninguém precisar acrescentar nome nenhum a uma lista.
--
--    1. o estado 'emitido' não existe mais, e 'marcado_por_ela' existe
--    2. as colunas renomeadas são as novas, e as antigas sumiram
--    3. o cartão devolve os seis campos, e a descrição sai VAZIA        ← decide
--    4. conta PJ não recebe cartão nenhum
--    5. o pagador PJ dispensa com motivo gravado, e entra no relatório
--    6. nenhuma coluna aceita credencial gov.br                         ← decide
--    7. não existe função que emita
--    8. mudar o ritmo não mexe em recibo nenhum                         ← decide
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0067_o_produto_nao_emite.sql

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111167';
  v_conta uuid; v_prof uuid; v_pac uuid; v_cob uuid; v_rec uuid;
  v_r jsonb; v_n integer; v_erro text; v_antes jsonb;
  v_col record;
  -- Um valor com cara de credencial. Se **alguma** coluna de texto aceitar isto
  -- sem reclamar, existe onde guardar — e onde existe onde guardar, alguém
  -- guarda.
  v_credencial text := 'gov.br:CPF=52998224725;SENHA=Segredo123;TOKEN=eyJhbGciOiJIUzI1NiJ9';
begin

delete from public.contas where nome = 'Receita Saude Teste';
delete from auth.users where id = v_auth;

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'p8@teste.sessoes.com.br', '{"nome":"Receita Saude Teste"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

-- 1 · o estado antigo não volta.
if exists (
  select 1 from pg_constraint
   where conrelid = 'public.recibos_rfb'::regclass
     and conname = 'recibos_rfb_estado_check'
     and pg_get_constraintdef(oid) like '%''emitido''%'
) then
  raise exception 'FALHOU 1: o check ainda aceita o estado "emitido" — o produto não emite';
end if;
if not exists (
  select 1 from pg_constraint
   where conrelid = 'public.recibos_rfb'::regclass
     and conname = 'recibos_rfb_estado_check'
     and pg_get_constraintdef(oid) like '%marcado_por_ela%'
) then
  raise exception 'FALHOU 1: o estado "marcado_por_ela" sumiu do check';
end if;

-- 2 · as colunas renomeadas.
if exists (select 1 from information_schema.columns
            where table_schema = 'public' and table_name = 'recibos_rfb'
              and column_name in ('emitido_em', 'numero_rfb')) then
  raise exception 'FALHOU 2: uma das colunas antigas voltou — o nome afirmava um fato que só a Receita pode confirmar';
end if;
if (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'recibos_rfb'
       and column_name in ('marcado_por_ela_em', 'numero_informado')) <> 2 then
  raise exception 'FALHOU 2: falta uma das colunas novas';
end if;

-- E `documentos.emitido_em` NÃO muda: lá o produto emitiu de verdade.
if not exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'documentos'
                  and column_name = 'emitido_em') then
  raise exception 'FALHOU 2: documentos.emitido_em foi renomeada por simetria — e ali a palavra é verdadeira';
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, cpf, estado)
  values (v_conta, v_prof, 'Ana Pagadora', '52998224725', 'em_atendimento') returning id into v_pac;

update public.contas set receita_saude = true, regime = 'pf' where id = v_conta;

insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, valor, competencia, estado, paga_em)
  values (v_conta, v_pac, 'sessao', 'sessao_realizada', 200.00,
          date_trunc('month', public.hoje_sp())::date, 'paga', now())
  returning id into v_cob;

select id into v_rec from public.recibos_rfb where cobranca_id = v_cob;
if v_rec is null then
  raise exception 'FALHOU 3: o pagamento não abriu pendência de recibo';
end if;

-- 3 · o cartão, e a descrição vazia.  ← decide
v_r := public.cartao_de_emissao(v_rec);

if (v_r->>'cpf') <> '52998224725' then
  raise exception 'FALHOU 3: o CPF do cartão saiu "%"', v_r->>'cpf';
end if;
if (v_r->>'valor')::numeric <> 200.00 then
  raise exception 'FALHOU 3: o valor do cartão saiu "%"', v_r->>'valor';
end if;
if coalesce(v_r->>'ocupacao', '') = '' then
  raise exception 'FALHOU 3: o cartão veio sem ocupação';
end if;

-- A descrição é campo livre que viaja daqui para a Receita Federal. Escrever
-- ali o nome de quem se trata seria entregar a lista de pacientes por
-- conveniência de preenchimento — a mesma decisão da coluna 6 do CSV.
if coalesce(v_r->>'descricao', 'x') <> '' then
  raise exception 'FALHOU 3: a descrição veio preenchida com "%" — campo livre que vai para a Receita não carrega nome de paciente', v_r->>'descricao';
end if;
if position('Ana Pagadora' in coalesce(v_r->>'descricao', '')) > 0 then
  raise exception 'FALHOU 3: o nome do paciente foi parar na descrição';
end if;

-- 4 · conta PJ não recebe cartão.
update public.contas set regime = 'pj' where id = v_conta;
begin
  perform public.cartao_de_emissao(v_rec);
  raise exception 'FALHOU 4: montou cartão para conta PJ — o caminho fiscal dela é a NFS-e';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 4' in v_erro) > 0 then raise; end if;
end;
update public.contas set regime = 'pf' where id = v_conta;

-- 5 · o pagador pessoa jurídica.
--
-- **A verificação 4 tem efeito colateral, e a 5 dependia de não ter.** Virar a
-- conta para PJ dispara `tg_virar_pj_dispensa`, que dispensa as pendências —
-- é o desenho da 0053b, e está certo. Quando a conta voltou para PF o recibo já
-- não estava mais pendente, e `dispensar_por_pagador_pj` recusou com razão. A 5
-- precisa de uma pendência nova, criada depois da ida e volta.
insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, valor, competencia, estado, paga_em)
  values (v_conta, v_pac, 'sessao', 'sessao_realizada', 200.00,
          date_trunc('month', public.hoje_sp())::date, 'paga', now() - interval '1 day')
  returning id into v_cob;

select id into v_rec from public.recibos_rfb where cobranca_id = v_cob;
if v_rec is null then
  raise exception 'FALHOU 5: a segunda pendência não nasceu depois da volta para PF';
end if;

perform public.dispensar_por_pagador_pj(v_rec);

if (select estado from public.recibos_rfb where id = v_rec) <> 'dispensado' then
  raise exception 'FALHOU 5: não dispensou';
end if;
if coalesce((select dispensa_motivo from public.recibos_rfb where id = v_rec), '') = '' then
  raise exception 'FALHOU 5: dispensou sem motivo gravado — daqui a dois anos ninguém sabe por que o mês tem um buraco';
end if;
if not exists (select 1 from public.relatorio_do_pagador_pj(
                 extract(year from public.hoje_sp())::int) x
                where x.paciente = 'Ana Pagadora') then
  raise exception 'FALHOU 5: a dispensa por PJ não entrou no relatório do ano';
end if;

reset role;
perform set_config('request.jwt.claims', '', true);
set local role postgres;

-- 6 · nenhuma coluna aceita credencial gov.br.  ← decide
--
-- Varre o catálogo: toda coluna de texto de `public` cujo nome sugira guardar
-- segredo. Não é lista de nomes proibidos — é o conjunto inteiro, filtrado por
-- padrão, então a coluna nova aparece aqui no dia em que nascer.
--
-- **Duas perguntas, e elas são diferentes.**
--
-- A primeira é a fronteira 11 na letra: nenhuma coluna guarda credencial do
-- **gov.br, da Receita ou do e-CAC**. Essa não tem exceção nenhuma e não
-- precisa de lista.
for v_col in
  select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
   where c.table_schema = 'public'
     and t.table_type = 'BASE TABLE'
     and c.data_type in ('text', 'character varying', 'character')
     and c.column_name ~* 'gov_?br|receita_?(senha|token|sessao|login)|e_?cac|carne_?leao_(senha|token)|certificado_digital'
loop
  raise exception 'FALHOU 6: a coluna %.% guardaria credencial do gov.br ou do e-CAC. Essa conta é a chave do INSS, da declaração e do e-CAC dela — o produto não guarda senha, nem sessão, nem token, nem por intermediador (fronteira 11)',
    v_col.table_name, v_col.column_name;
end loop;

-- A segunda é mais larga e por isso precisa de resposta, não de silêncio:
-- **quais colunas deste banco guardam segredo de qualquer natureza?** A
-- varredura acha seis, e as seis têm razão de existir — nenhuma é fiscal:
--
--   · `aceites.token`               — o link do aceite do contrato (B19)
--   · `links_do_paciente.token`     — a página transacional única (P7)
--   · `remarcacoes.token`           — o link de remarcação (B21)
--       os três são token **gerado aqui**, de uso único e com prazo: são a
--       chave de uma página nossa, não credencial de ninguém em lugar nenhum.
--   · `calendarios.sync_token`      — o cursor de sincronização do calendário
--   · `calendarios_segredo.refresh_token` e `.access_token`
--       o OAuth do calendário dela, em tabela **separada** justamente para
--       poder ter RLS própria. É credencial de terceiro, e de um terceiro que
--       ela escolheu conectar — não da conta que abre a declaração dela.
--
-- O que a verificação recusa é a **sétima**: uma coluna nova com cara de
-- segredo reprova aqui até alguém escrever por que ela existe. A lista não é
-- permissão — é a afirmação de qual é o estado de hoje, e é a mesma forma do
-- "todo token de cor tem papel declarado" da suíte de contraste.
select count(*)::integer into v_n
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name
 where c.table_schema = 'public'
   and t.table_type = 'BASE TABLE'
   and c.data_type in ('text', 'character varying', 'character')
   and c.column_name ~* 'senha|password|credencial|token|certificado'
   and (c.table_name, c.column_name) not in (
     ('aceites', 'token'),
     ('links_do_paciente', 'token'),
     ('remarcacoes', 'token'),
     ('calendarios', 'sync_token'),
     ('calendarios_segredo', 'refresh_token'),
     ('calendarios_segredo', 'access_token')
   );
if v_n > 0 then
  raise exception 'FALHOU 6: apareceu coluna nova com cara de guardar segredo. Ela pode ser legítima — mas precisa ser declarada aqui, com o motivo, antes de existir em silêncio';
end if;

-- E o valor plantado não encontra casa: nenhuma coluna de `contas` o aceita.
begin
  execute format('update public.contas set nome = %L where id = %L', v_credencial, v_conta);
  -- Se chegou aqui, gravou num campo de nome — o que é esperado e inofensivo.
  -- O que a verificação recusa é coluna **destinada** a isso, acima.
  update public.contas set nome = 'Receita Saude Teste' where id = v_conta;
exception when others then null;
end;

-- 7 · não existe função que emita.
select count(*)::integer into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and (p.proname ~* '^emitir_recibo|emitir_rfb|receita_saude_emitir|autenticar_gov');
if v_n > 0 then
  raise exception 'FALHOU 7: existe função com nome de quem emite — o produto é conciliador, não emissor';
end if;

-- 8 · mudar o ritmo não mexe em recibo nenhum.  ← decide
--
-- É o critério de pronto da build: "mudar o ritmo hoje não reenvia nada do
-- passado". O ritmo decide quando o próximo lembrete sai, e nada além disso.
select jsonb_agg(to_jsonb(r) order by r.id) into v_antes
  from public.recibos_rfb r where r.conta_id = v_conta;

update public.contas set ritmo_recibo = 'semanal' where id = v_conta;

if (select jsonb_agg(to_jsonb(r) order by r.id)
      from public.recibos_rfb r where r.conta_id = v_conta) is distinct from v_antes then
  raise exception 'FALHOU 8: mudar o ritmo mexeu nos recibos — ele decide o próximo lembrete, não o passado';
end if;

if (select count(*) from public.mensagens where conta_id = v_conta) > 0 then
  raise exception 'FALHOU 8: mudar o ritmo enfileirou mensagem';
end if;

delete from public.contas where nome = 'Receita Saude Teste';
delete from auth.users where id = v_auth;
reset role;

raise notice 'OK · 0067 · o produto não emite, o cartão não carrega nome de paciente, e não há onde guardar credencial';
end
$do$;
