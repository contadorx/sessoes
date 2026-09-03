-- Teste da linha do mês (B54, migração 0095).
--
-- A VERIFICAÇÃO QUE DECIDE ESTE ARQUIVO É A 1: **a tela dela e a página dele
-- somam o mesmo mês.** É a única razão de `linhas_do_mes` existir como função
-- separada em vez de duas consultas parecidas. O antipadrão nº 1 deste projeto
-- é a segunda fonte de verdade, e sobre dinheiro ele é S1 automático — foi
-- exatamente isso que a 0090 acabou de consertar entre `retorno` e
-- `financeiro_do_mes`, com R$ 750,00 contra R$ 0,00 na mesma conta.
--
--    1. a soma é uma só: `meses_do_paciente` == `pagina_do_paciente`   ← decide
--    2. cancelada não cria mês, e mês com sobra não é mês pago
--    3. o recibo casa por sobreposição de período, e o cancelado some
--    4. `recibo_na_janela` concorda com `documento_do_link`, e a página do
--       paciente não carrega o id do documento fora da janela (0096)
--    5. o recorte é doze, e são os doze mais recentes
--    6. avisar recusa sem link vivo, e enfileira uma vez só
--    7. emitir **não** avisa: o default não decide por ela
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0095

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111195';
  v_conta uuid; v_prof uuid; v_pac uuid;
  v_token text; v_doc uuid; v_doc_velho uuid;
  v_msg uuid; v_msg2 uuid;
  r jsonb; p jsonb; linha jsonb; n integer; falhou boolean; i integer;
  v_num integer;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.trilha_acesso where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.documentos where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.cobrancas where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.links_do_paciente where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.sessoes where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Meses Teste');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Meses Teste';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'mesesteste@teste.sessoes.com.br', '{"nome":"Meses Teste"}'::jsonb);
select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

-- `abrir_link_do_paciente` e `revogar_link_do_paciente` são `security definer`
-- e passam por `conta_atual()`, que lê o JWT. Sem a claim elas levantariam
-- "sem conta" — e o papel continua `postgres` de propósito: quem escreve nesta
-- base é o servidor de escrita, e trocar de papel no meio da suíte esconderia
-- defeito atrás da RLS.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);

insert into public.pacientes (conta_id, profissional_id, nome, telefone, msg_canal, estado)
  values (v_conta, v_prof, 'Marta Dos Meses', '5511900009502', 'whatsapp', 'em_atendimento')
  returning id into v_pac;

-- Três meses com formatos diferentes de propósito:
--   julho    · dois pagamentos, mês fechado
--   agosto   · um pago e um em aberto — o mês que não pode dizer "pago"
--   setembro · um perdoado, e um cancelado que não pode criar mês nenhum
insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, valor, estado, competencia, paga_em)
values
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 200, 'paga',     date '2026-07-01', timestamptz '2026-07-10 12:00-03'),
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 200, 'paga',     date '2026-07-01', timestamptz '2026-07-24 12:00-03'),
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 300, 'paga',     date '2026-08-01', timestamptz '2026-08-12 12:00-03'),
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 100, 'aberta',   date '2026-08-01', null),
  (v_conta, v_pac, 'falta',  'falta',            150, 'perdoada', date '2026-09-01', null),
  (v_conta, v_pac, 'sessao', 'sessao_realizada', 999, 'cancelada',date '2026-10-01', null);

-- Duas sessões realizadas em julho: é o que `emitir_documento` exige.
insert into public.sessoes (conta_id, paciente_id, profissional_id, inicio, fim, estado, valor, origem)
values
  (v_conta, v_pac, v_prof, timestamptz '2026-07-07 14:00-03', timestamptz '2026-07-07 14:50-03', 'realizada', 200, 'recorrencia'),
  (v_conta, v_pac, v_prof, timestamptz '2026-07-21 14:00-03', timestamptz '2026-07-21 14:50-03', 'realizada', 200, 'recorrencia');

perform public.abrir_link_do_paciente(v_pac);
select token into v_token from public.links_do_paciente
 where paciente_id = v_pac and revogado_em is null order by criado_em desc limit 1;

-- ---------------------------------------------------------------- 1 ← decide
r := public.linhas_do_mes(v_pac, 12);
p := public.pagina_do_paciente(v_token);

if p->>'estado' <> 'aberta' then
  raise exception '1 FUROU: a página não abriu (%)', p->>'estado';
end if;
if (p->'meses') is null then
  raise exception '1 FUROU: a página do paciente não traz a linha do mês';
end if;
if (p->'meses') <> r then
  raise exception '1 FUROU: a tela dela e a página dele discordam sobre o mesmo mês';
end if;
if public.meses_do_paciente(v_pac) <> public.linhas_do_mes(v_pac, 12, false) then
  raise exception '1 FUROU: meses_do_paciente não é linhas_do_mes — há duas somas';
end if;

-- As duas leituras diferem em **uma** coisa desde a 0096: o id do recibo fora
-- da janela, que a página do paciente não carrega. O dinheiro tem de ser
-- idêntico, e é isso que se cobra aqui — comparar os objetos inteiros deixaria
-- passar uma divergência de valor no dia em que houvesse documento antigo.
if (select jsonb_agg(x - 'recibo' - 'recibo_numero' order by x->>'competencia')
      from jsonb_array_elements(public.linhas_do_mes(v_pac, 12, false)) x)
   is distinct from
   (select jsonb_agg(x - 'recibo' - 'recibo_numero' order by x->>'competencia')
      from jsonb_array_elements(public.linhas_do_mes(v_pac, 12, true)) x) then
  raise exception '1 FUROU: os dois lados discordam sobre o dinheiro do mês, e não só sobre o id do papel';
end if;

-- ---------------------------------------------------------------- 2
-- A cobrança cancelada é de outubro e é a única de outubro: se ela criasse mês,
-- outubro apareceria. Um mês que só tem cancelamento não aconteceu.
if exists (select 1 from jsonb_array_elements(r) x where x->>'competencia' = '2026-10-01') then
  raise exception '2 FUROU: cobrança cancelada criou um mês';
end if;
if jsonb_array_length(r) <> 3 then
  raise exception '2 FUROU: esperava três meses, vieram %', jsonb_array_length(r);
end if;

select x into linha from jsonb_array_elements(r) x where x->>'competencia' = '2026-08-01';
if (linha->>'combinado')::numeric <> 400 then
  raise exception '2 FUROU: agosto combinou %, esperava 400', linha->>'combinado';
end if;
if (linha->>'aberto')::numeric <> 100 then
  raise exception '2 FUROU: agosto tem % em aberto, esperava 100', linha->>'aberto';
end if;
-- `pago_em` vem preenchido mesmo com sobra — é fato, e o fato é que houve
-- pagamento. Quem decide que o mês **não está pago** é `marcaDoPago`, em
-- lib/meses.ts, e é lá que o teste unitário cobra isso. O que esta verificação
-- garante é que o banco entrega as duas coisas para a decisão ser possível.
if (linha->>'pago_em') is null then
  raise exception '2 FUROU: agosto perdeu a data do pagamento parcial';
end if;

select x into linha from jsonb_array_elements(r) x where x->>'competencia' = '2026-09-01';
if (linha->>'perdoado')::numeric <> 150 or (linha->>'pago')::numeric <> 0 then
  raise exception '2 FUROU: setembro devia ser só perdoado';
end if;

-- ---------------------------------------------------------------- 3
-- Um recibo de 01/07 a 30/09 cobre os três meses. Igualdade de competência não
-- resolveria: quem cobra por sessão e emite recibo por trimestre teria três
-- meses sem papel nenhum.
select coalesce(max(numero), 0) + 1 into v_num from public.documentos where conta_id = v_conta;
insert into public.documentos (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
                               valor_total, quantidade, retrato)
values (v_conta, v_pac, v_num, 'recibo', date '2026-07-01', date '2026-09-30',
        700, 4, '{"base":"teste"}'::jsonb)
returning id into v_doc;

r := public.linhas_do_mes(v_pac, 12);
select count(*) into n from jsonb_array_elements(r) x where x->>'recibo' = v_doc::text;
if n <> 3 then
  raise exception '3 FUROU: o recibo trimestral apareceu em % meses, esperava 3', n;
end if;

update public.documentos set cancelado_em = now(), motivo_cancelamento = 'teste' where id = v_doc;
r := public.linhas_do_mes(v_pac, 12);
if exists (select 1 from jsonb_array_elements(r) x where x->>'recibo' is not null) then
  raise exception '3 FUROU: recibo cancelado continuou aparecendo na linha do mês';
end if;

-- ---------------------------------------------------------------- 4
-- A tela não pode oferecer "abrir" para o que `documento_do_link` recusa. As
-- duas leituras são de lugares diferentes e têm de concordar sempre.
select coalesce(max(numero), 0) + 1 into v_num from public.documentos where conta_id = v_conta;
insert into public.documentos (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
                               valor_total, quantidade, retrato, emitido_em)
values (v_conta, v_pac, v_num, 'recibo', date '2026-08-01', date '2026-08-31',
        400, 2, '{"base":"teste"}'::jsonb, now() - interval '200 days')
returning id into v_doc_velho;

-- Do lado dela (`p_so_na_janela => false`) o recibo antigo tem id: ela abre
-- pela ficha, com a RLS da conta.
r := public.linhas_do_mes(v_pac, 12, false);
select x into linha from jsonb_array_elements(r) x where x->>'competencia' = '2026-08-01';

if linha->>'recibo' <> v_doc_velho::text then
  raise exception '4 FUROU: agosto não achou o recibo de agosto na leitura dela';
end if;
if (linha->>'recibo_na_janela')::boolean then
  raise exception '4 FUROU: recibo de 200 dias atrás veio como dentro da janela';
end if;
if (public.documento_do_link(v_token, v_doc_velho)->>'estado') <> 'inexistente' then
  raise exception '4 FUROU: a porta serviu o documento que a lista disse estar fora da janela';
end if;

-- **E do lado dele o id não sai.** Este é o achado que a suíte 0066 acusou
-- contra a 0095, e a razão de a 0096 existir: um id numa página de portador é
-- metade de uma URL, e a outra metade é pública. A defesa passaria a ser só a
-- checagem de data dentro de `documento_do_link`; são duas, e a segunda é não
-- ter o número.
r := public.linhas_do_mes(v_pac, 12);
select x into linha from jsonb_array_elements(r) x where x->>'competencia' = '2026-08-01';
if linha->>'recibo' is not null or linha->>'recibo_numero' is not null then
  raise exception '4 FUROU: a página do paciente carrega o id do recibo fora da janela';
end if;
if linha->>'recibo_em' is null then
  raise exception '4 FUROU: sumiu também a data — a pessoa passaria a achar que o recibo nunca foi emitido, e cobraria dela um papel que ela já fez';
end if;
p := public.pagina_do_paciente(v_token);
if position(v_doc_velho::text in (p->'meses')::text) > 0 then
  raise exception '4 FUROU: o id do recibo antigo saiu na página do paciente';
end if;

-- O documento emitido não se edita (`documento_nao_muda`), então o recibo novo
-- de agosto é outro documento — e é assim na vida real: recibo com erro se
-- cancela e se reemite. De quebra, isto prova que a lista pega o **mais
-- recente** quando há dois cobrindo o mesmo mês.
select coalesce(max(numero), 0) + 1 into v_num from public.documentos where conta_id = v_conta;
insert into public.documentos (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
                               valor_total, quantidade, retrato)
values (v_conta, v_pac, v_num, 'recibo', date '2026-08-01', date '2026-08-31',
        400, 2, '{"base":"teste"}'::jsonb)
returning id into v_doc;

-- Leitura da página (a segura), e agora o id sai: o documento está na janela.
r := public.linhas_do_mes(v_pac, 12);
select x into linha from jsonb_array_elements(r) x where x->>'competencia' = '2026-08-01';
if linha->>'recibo' <> v_doc::text then
  raise exception '4 FUROU: com dois recibos de agosto, a lista não trouxe o mais recente';
end if;
if not (linha->>'recibo_na_janela')::boolean then
  raise exception '4 FUROU: recibo de hoje veio como fora da janela';
end if;
if (public.documento_do_link(v_token, v_doc)->>'estado') <> 'aberta' then
  raise exception '4 FUROU: a porta recusou o documento que a lista ofereceu';
end if;

-- ---------------------------------------------------------------- 5
-- Catorze competências entram, doze saem, e são as mais recentes. O recorte é
-- do produto, não do acaso: a página é aberta num celular que outra pessoa pode
-- estar segurando, e um extrato sem fim é a fronteira D3 com outra roupa.
for i in 1..14 loop
  insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, valor, estado, competencia)
  values (v_conta, v_pac, 'sessao', 'sessao_realizada', 50, 'aberta',
          (date '2025-01-01' + ((i - 1) || ' months')::interval)::date);
end loop;

r := public.linhas_do_mes(v_pac, 12);
if jsonb_array_length(r) <> 12 then
  raise exception '5 FUROU: vieram % meses, o recorte é 12', jsonb_array_length(r);
end if;
if (r->0->>'competencia') < (r->11->>'competencia') then
  raise exception '5 FUROU: a lista não está do mais novo para o mais velho';
end if;
if (r->11->>'competencia') <= '2025-01-01' then
  raise exception '5 FUROU: o corte guardou os mais velhos e jogou fora os recentes';
end if;

-- ---------------------------------------------------------------- 6
-- Sem link vivo o aviso apontaria para uma página que não abre: recusa, não
-- finge (lei 8).
perform public.revogar_link_do_paciente(v_pac);
falhou := false;
begin
  perform public.avisar_documento_disponivel(v_doc_velho);
  falhou := true;
exception when others then
  if sqlerrm not like '%link vivo%' then raise; end if;
end;
if falhou then
  raise exception '6 FUROU: avisou sobre uma página que não abre';
end if;

perform public.abrir_link_do_paciente(v_pac);
select public.avisar_documento_disponivel(v_doc_velho) into v_msg;
if v_msg is null then
  raise exception '6 FUROU: com link vivo, o aviso não foi enfileirado';
end if;

-- O aviso é `rotina`, e não `documento`: se fosse `documento`, o gatilho
-- exigiria e-mail e esta paciente — que só tem WhatsApp — nunca seria avisada.
-- É a razão de o §5.2 existir: a mensagem carrega o aviso, não o papel.
if (select canal from public.mensagens where id = v_msg) <> 'whatsapp' then
  raise exception '6 FUROU: o aviso não saiu pelo canal da paciente (%)',
    (select canal from public.mensagens where id = v_msg);
end if;
if (select template from public.mensagens where id = v_msg) <> 'documento_disponivel' then
  raise exception '6 FUROU: o aviso saiu com outro template';
end if;

-- Dois toques no botão, uma mensagem só: a chave de idempotência é o documento.
select public.avisar_documento_disponivel(v_doc_velho) into v_msg2;
if v_msg2 is not null then
  raise exception '6 FUROU: o segundo toque enfileirou uma segunda mensagem';
end if;
select count(*) into n from public.mensagens
 where paciente_id = v_pac and template = 'documento_disponivel';
if n <> 1 then
  raise exception '6 FUROU: há % avisos do mesmo documento na fila', n;
end if;

-- ---------------------------------------------------------------- 7
-- Emitir não avisa. "O default que decide por ela" é antipadrão nomeado do §9,
-- e há emissão que é só contabilidade dela, em lote, no fechamento do mês.
delete from public.mensagens where paciente_id = v_pac;
select public.emitir_documento(v_pac, 'recibo', date '2026-07-01', date '2026-07-31') into v_doc;
select count(*) into n from public.mensagens where paciente_id = v_pac;
if n <> 0 then
  raise exception '7 FUROU: emitir documento mandou mensagem sozinho (% na fila)', n;
end if;

-- ------------------------------------------------------------------ recolhe
delete from public.mensagens where conta_id = v_conta;
delete from public.trilha_acesso where conta_id = v_conta;
delete from public.documentos where conta_id = v_conta;
delete from public.cobrancas where conta_id = v_conta;
delete from public.links_do_paciente where conta_id = v_conta;
delete from public.sessoes where conta_id = v_conta;
delete from public.pacientes where conta_id = v_conta;
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B54 OK — 7 verificações, todas passaram';
end $do$;
