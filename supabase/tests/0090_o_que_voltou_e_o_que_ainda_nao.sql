-- Teste do que voltou e do que ainda não (migração 0090).
--
-- O DEFEITO QUE ELA EXISTE PARA REPROVAR
--
-- Duas telas respondiam "quanto a fila recuperou neste mês" com números
-- diferentes, e as duas sobre dinheiro:
--
--   `retorno`           (agenda)        contava toda encaixe não cancelada
--   `financeiro_do_mes` (movimentações) conta só `realizada`
--
-- Na conta de demonstração isso era **R$ 750,00 contra R$ 0,00**, com a agenda
-- escrevendo o número em serifa de 26 px embaixo de *"que não teria entrado sem
-- a fila e sem a política"* — sobre quatro sessões que ainda não tinham
-- acontecido. Segunda fonte de verdade sobre dinheiro é S1 automático (§9), e
-- esta era também uma afirmação contrafactual, que é a família do S1-B da B44.
--
-- A verificação que decide o arquivo é a **3**: encaixe `prevista` não entra em
-- `valor_preenchido`.
--
--    1. o preparo é fiel: vaga cancelada, oferta aceita, encaixe criada
--    2. a vaga conta como preenchida desde já — a fila fez o trabalho dela
--    3. encaixe prevista NÃO entra em valor_preenchido                 ← decide
--    4. ela entra em valor_agendado, separada                          ← decide
--    5. realizada move o valor de agendado para preenchido             ← decide
--    6. falta não entra em nenhum dos dois
--    7. as horas seguem o mesmo corte do dinheiro
--    8. `retorno` e `financeiro_do_mes` concordam sobre o que aconteceu
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0090

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111190';
  v_conta uuid; v_prof uuid;
  v_p1 uuid; v_p2 uuid;
  v_vaga uuid; v_of uuid; v_encaixe uuid;
  v_terca timestamptz; v_dia date;
  r record; v_fin jsonb;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens    where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.eventos_fila where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.ofertas      where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.fila_encaixe where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.cobrancas    where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.sessoes      where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.enquadres    where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from public.pacientes    where conta_id in (select id from public.contas where nome = 'Voltou Ou Nao');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Voltou Ou Nao';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'voltououNao@teste.sessoes.com.br', '{"nome":"Voltou Ou Nao"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

set local role postgres;
update public.contas set plano = 'solo' where id = v_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

-- A vaga nasce no **futuro**: `abrir_vaga` recusa hora que já passou, e com
-- razão. O recorte de `retorno` é a data do **cancelamento**, que é agora — daí
-- `v_dia` ser hoje mesmo com a sessão marcada para depois.
v_terca := date_trunc('hour', now()) + interval '2 days';
v_dia   := (now() at time zone 'America/Sao_Paulo')::date;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Quem Desmarcou', '5511900009001', 'em_atendimento') returning id into v_p1;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Quem Pegou A Vaga', '5511900009002', 'em_atendimento') returning id into v_p2;

insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor,
                            politica_horas, politica_percentual)
  values (v_conta, v_prof, v_p1, v_terca, v_terca + interval '50 min', 'avulsa', 300.00, 24, 50)
  returning id into v_vaga;

insert into public.fila_encaixe (paciente_id) values (v_p2);

perform public.cancelar_sessao(v_vaga, 'paciente');
select public.abrir_vaga(v_vaga) into v_of;

-- ---------------------------------------------------------------- 1
if v_of is null then raise exception '1 FUROU: a vaga não gerou oferta'; end if;

perform public.responder_oferta(v_of, 'aceita');

select id into v_encaixe from public.sessoes
 where origem = 'encaixe' and inicio = v_terca and conta_id = v_conta;
if v_encaixe is null then raise exception '1 FUROU: aceitar a oferta não criou a sessão de encaixe'; end if;
if (select estado from public.sessoes where id = v_encaixe) <> 'prevista' then
  raise exception '1 FUROU: a encaixe não nasceu prevista';
end if;

-- ---------------------------------------------------------------- 2 a 4
select * into r from public.retorno(v_dia, v_dia);

if r.preenchidas <> 1 then
  raise exception '2 FUROU: a vaga preenchida não contou (% preenchidas)', r.preenchidas;
end if;

if r.valor_preenchido <> 0 then
  raise exception '3 FUROU: encaixe prevista entrou em valor_preenchido (%) — é dinheiro de sessão que não aconteceu', r.valor_preenchido;
end if;

if r.valor_agendado <> 300.00 then
  raise exception '4 FUROU: valor_agendado deu % (esperava 300,00)', r.valor_agendado;
end if;

if r.horas_recuperadas <> 0 then
  raise exception '7 FUROU: horas de sessão que não aconteceu contaram como recuperadas (%)', r.horas_recuperadas;
end if;

-- ---------------------------------------------------------------- 5
--
-- O relógio anda. A suíte move a vaga **e** a encaixe pelo mesmo tanto, porque
-- `retorno` casa as duas por `inicio`: mover só uma desfaria o par e a
-- verificação passaria a medir outra coisa.
set local role postgres;
update public.sessoes
   set inicio = now() - interval '2 hours',
       fim    = now() - interval '2 hours' + interval '50 min'
 where id in (v_vaga, v_encaixe);
reset role;

-- Não existe `marcar_sessao` no banco: a tela faz `update` direto, e quem
-- guarda a transição é o gatilho `checa_transicao_sessao`. A suíte faz o
-- mesmo caminho da tela, como `authenticated`.
update public.sessoes set estado = 'realizada' where id = v_encaixe;
select * into r from public.retorno(v_dia, v_dia);

if r.valor_preenchido <> 300.00 then
  raise exception '5 FUROU: depois de realizada, valor_preenchido deu % (esperava 300,00)', r.valor_preenchido;
end if;
if r.valor_agendado <> 0 then
  raise exception '5 FUROU: realizada continuou contando como agendada (%)', r.valor_agendado;
end if;
if r.horas_recuperadas <= 0 then
  raise exception '7 FUROU: realizada não trouxe as horas (%)', r.horas_recuperadas;
end if;

-- ---------------------------------------------------------------- 8
-- As duas telas concordam sobre o que aconteceu. `financeiro_do_mes` recorta
-- pelo mês da sessão; aqui a vaga e a encaixe estão no mesmo dia, então os dois
-- recortes coincidem e a comparação é legítima.
select public.financeiro_do_mes(date_trunc('month', v_dia)::date,
                                (date_trunc('month', v_dia) + interval '1 month - 1 day')::date)
  into v_fin;

if (v_fin -> 'recuperado' ->> 'valor_encaixes')::numeric <> r.valor_preenchido then
  raise exception '8 FUROU: financeiro diz % e retorno diz % sobre a mesma hora',
    v_fin -> 'recuperado' ->> 'valor_encaixes', r.valor_preenchido;
end if;

-- ---------------------------------------------------------------- 6
update public.sessoes set estado = 'falta' where id = v_encaixe;
select * into r from public.retorno(v_dia, v_dia);

if r.valor_preenchido <> 0 or r.valor_agendado <> 0 then
  raise exception '6 FUROU: encaixe que virou falta contou como % preenchido e % agendado — não aconteceu e não vai acontecer',
    r.valor_preenchido, r.valor_agendado;
end if;
if r.preenchidas <> 1 then
  raise exception '6 FUROU: a falta apagou o trabalho da fila (% preenchidas)', r.preenchidas;
end if;

-- ------------------------------------------------------------------ recolhe
reset role;
set local role postgres;

delete from public.mensagens    where conta_id = v_conta;
delete from public.eventos_fila where conta_id = v_conta;
delete from public.ofertas      where conta_id = v_conta;
delete from public.fila_encaixe where conta_id = v_conta;
delete from public.cobrancas    where conta_id = v_conta;
delete from public.propostas_de_cobranca where conta_id = v_conta;
delete from public.sessoes      where conta_id = v_conta;
delete from public.enquadres    where conta_id = v_conta;
delete from public.pacientes    where conta_id = v_conta;
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'S2 OK — 8 verificações, todas passaram';
end $do$;
