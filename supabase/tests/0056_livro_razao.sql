-- Teste do livro-razão da sessão (P2, migração 0056).
--
-- A verificação que decide o build é a nº 16: **duas horas de capacidade, uma
-- receita.** Quando o paciente desmarca e consome outra hora com o mesmo
-- dinheiro, a hora antiga fica `reposta` com reconhecido zero e a nova fica
-- `vendida` com o valor. Somar as duas daria receita dobrada; ignorar a antiga
-- esconderia a hora perdida. Nenhum sistema do mercado separa isso, e é
-- exatamente onde a remarcação com crédito esconde perda.
--
-- A segunda é a nº 12: **antecipação não é receita reconhecida.** Pagar hoje
-- uma sessão da semana que vem põe o eixo financeiro em `paga` e deixa o
-- reconhecido **nulo**. Sem isso, a ocupação paga sobe recebendo por hora que
-- ainda não aconteceu — e o número mais importante do produto passa a mentir
-- para cima, que é a direção que ninguém questiona.
--
-- E a nº 11 é a invariante 1 virando teste: **nenhum eixo muda por tela.** A
-- suíte inteira nunca escreve um eixo; ela mexe nos fatos (estado, cobrança,
-- pacote, remarcação, recibo) e confere o que os gatilhos escreveram.
--
--   parte 1 · a estrutura e a dívida declarada
--     1. `estado` continua com os seis valores — nada foi reescrito
--     2. eixo_agenda colapsa prevista/confirmada e cedo/tarde
--     3. o eixo financeiro tem `perdoada` — a divergência do doc 30 é decisão
--     4. reposta e reposta_por andam juntos, ou o check recusa
--     5. receita reconhecida positiva em sessão não realizada é recusada
--     6. nenhuma tela escreve eixo: recalcular_eixos está revogada
--
--   parte 2 · a sessão resolve sozinha
--     7. prevista nasce com capacidade e reconhecido nulos
--     8. realizada vira vendida, com o valor
--     9. falta vira perdida, com reconhecido zero
--    10. cancelada cedo vira perdida
--    11. tudo isso sem ninguém escrever eixo nenhum  ← invariante 1
--
--   parte 3 · a antecipação
--    12. sessão futura paga fica `paga` com reconhecido NULO  ← decide
--    13. e quando ela é realizada, o reconhecido aparece
--
--   parte 4 · a reposta
--    14. remarcar transforma perdida em reposta, apontando para a nova
--    15. a antiga fica com zero e a nova com o valor
--    16. o livro conta duas horas e uma receita  ← decide
--
--   parte 5 · o dinheiro
--    17. aberta → cobrada; paga → paga; perdoada → perdoada
--    18. perdão zera o reconhecido de sessão realizada
--    19. cobrança cancelada devolve a sessão para nao_cobrada
--    20. consumo de pacote vira credito
--
--   parte 6 · o fiscal
--    21. pendência de recibo vira pendente; emitido vira emitida
--
--   parte 7 · o livro-razão
--    22. as sete causas aparecem, e a sétima não tem ação
--    23. hora nunca vendida é calculada da capacidade, e não é linha
--    24. a completude automática passa de 90%
--    25. o livro de outra conta não é legível daqui
--    26. apagar a hora que repôs devolve a antiga para "perdida" — e o
--        esquecimento do titular, que é obrigação legal, não trava (0056b/c)
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0056_livro_razao.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111156';
  b_auth uuid := '22222222-2222-4222-8222-222222222156';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  ana uuid; bia uuid;
  s_ok uuid; s_falta uuid; s_cedo uuid; s_futura uuid; s_desmarcada uuid; s_nova uuid;
  cob uuid; c_falta uuid; s_ancora uuid; tok text; opcao timestamptz;
  hoje date; base date;
  r record; j jsonb; n integer; erro text; v numeric; txt text;
  semana jsonb;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Razao Teste', 'Razao Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'razao@teste.sessoes.com.br', '{"nome":"Razao Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (b_auth, 'razaoviz@teste.sessoes.com.br', '{"nome":"Razao Vizinha"}'::jsonb);

select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
select id into a_prof from public.profissionais where conta_id = a_conta;
select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
select id into b_prof from public.profissionais where conta_id = b_conta;

hoje := public.hoje_sp();
-- Uma segunda-feira da semana passada, para o período fechar sem depender do
-- dia em que a suíte roda.
base := hoje - 7;

-- As claims entram aqui, e não só na parte 2. A verificação 4 planta um
-- paciente para sondar um check, e o gatilho de `pacientes` deriva a conta de
-- `conta_atual()` — sem claims ele aborta com "sem conta na sessao", e a sonda
-- mediria a mensagem errada.
perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · a estrutura e a dívida declarada ---';

-- 1 · o estado não foi reescrito. É a decisão central da migração.
select count(*) into n
  from pg_constraint
 where conname = 'sessoes_estado_check'
   and pg_get_constraintdef(oid) like '%cancelada_tarde%'
   and pg_get_constraintdef(oid) like '%prevista%'
   and pg_get_constraintdef(oid) like '%confirmada%';
if n <> 1 then
  raise exception 'FALHOU 1: sessoes.estado foi mexido — a 0056 decidiu explicitamente NÃO reescrevê-lo, porque quinze suítes verdes passariam a testar outra coisa';
end if;
raise notice 'ok 1 · o estado continua sendo o eixo agenda, intacto';

-- 2 · e o cockpit lê pelo mapa, nunca pelo estado cru.
if public.eixo_agenda('prevista') <> 'reservada'
   or public.eixo_agenda('confirmada') <> 'reservada' then
  raise exception 'FALHOU 2: prevista e confirmada não colapsaram em reservada — a diferença entre elas é confirmação, e confirmação tem eixo próprio';
end if;
if public.eixo_agenda('cancelada_cedo') <> 'cancelada'
   or public.eixo_agenda('cancelada_tarde') <> 'cancelada' then
  raise exception 'FALHOU 2: cedo e tarde não colapsaram — a diferença entre elas é política, e política decide cobrança, não ocupação';
end if;
if public.eixo_agenda('realizada') <> 'realizada' or public.eixo_agenda('falta') <> 'ausente' then
  raise exception 'FALHOU 2: o mapa do eixo agenda está errado';
end if;
raise notice 'ok 2 · o eixo agenda colapsa o que não é agenda';

-- 3 · perdoada é valor próprio, e a divergência do doc 30 é deliberada.
select pg_get_constraintdef(oid) into txt
  from pg_constraint where conname = 'sessoes_eixo_financeiro_check';
if txt not like '%perdoada%' then
  raise exception 'FALHOU 3: o eixo financeiro perdeu o valor "perdoada" — chamar perdão de estorno faria a tela dizer a palavra errada sobre uma decisão dela';
end if;
raise notice 'ok 3 · perdão tem nome de perdão';

-- 4 · reposta sem apontar para nada é linha que não conta história nenhuma.
--
-- O paciente da sonda é criado aqui, na conta desta suíte, e **fora** do
-- subbloco — o `exception` desfaz o que estiver dentro dele, e a linha
-- precisa sobreviver para o `delete` do fim achá-la.
--
-- A versão anterior escrevia `(select id from public.pacientes limit 1)`, e
-- isso era uma aposta: enquanto o check recusa, o paciente escolhido não
-- importa. Mas se o check afrouxar um dia, a verificação passa a plantar uma
-- sessão falsa na ficha de quem estiver em primeiro na tabela — que num banco
-- com gente dentro é a ficha de uma pessoa. O teste que existe para reprovar
-- um afrouxamento não pode, ao reprová-lo, escrever na conta de outra pessoa.
set local role authenticated;
insert into public.pacientes (conta_id, profissional_id, nome, estado)
  values (a_conta, a_prof, 'Sonda do Check', 'interessado') returning id into ana;
reset role;

erro := null;
begin
  set local role postgres;
  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, eixo_capacidade)
  values (a_conta, a_prof, ana,
          (base + time '07:00') at time zone 'America/Sao_Paulo',
          (base + time '07:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'falta', 100, 'reposta');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 4: entrou uma sessão "reposta" sem apontar para a hora que a repôs';
end if;
-- E recusou pelo motivo certo: sem esta linha, um erro de coluna nula (ou
-- qualquer outro) contaria como aprovação, e o check poderia já não existir.
if erro not ilike '%sessoes_reposta_aponta%' then
  raise exception 'FALHOU 4: recusou com "%" — esperava o check sessoes_reposta_aponta', erro;
end if;

-- A sonda sai: ela existiu para uma linha que o banco recusou.
set local role postgres;
delete from public.pacientes where id = ana;
reset role;
ana := null;
raise notice 'ok 4 · reposta e reposta_por andam juntos';

-- 6 · nenhuma tela escreve eixo.
select count(*) into n
  from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'recalcular_eixos'
   and has_function_privilege('authenticated', p.oid, 'execute');
if n > 0 then
  raise exception 'FALHOU 6: a tela pode chamar recalcular_eixos — eixo que se escreve por fora é eixo que discorda dos fatos';
end if;
raise notice 'ok 6 · o cálculo dos eixos é da máquina';

raise notice '--- parte 2 · a sessão resolve sozinha ---';

perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Ana do Livro', '5511900000561', 'em_atendimento') returning id into ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Bia do Livro', '5511900000562', 'em_atendimento') returning id into bia;

-- Quatro horas do mesmo dia, sem encavalar (a restrição de exclusão da 0006).
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, (base + time '09:00') at time zone 'America/Sao_Paulo',
                                (base + time '09:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 200, 24, 50)
  returning id into s_ok;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, (base + time '10:00') at time zone 'America/Sao_Paulo',
                                (base + time '10:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 200, 24, 50)
  returning id into s_falta;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, (base + time '11:00') at time zone 'America/Sao_Paulo',
                                (base + time '11:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 200, 240, 0)
  returning id into s_cedo;
reset role;

-- 7 · nasce sem capacidade e sem reconhecido: ainda não resolveu.
select eixo_capacidade, valor_reconhecido, eixo_financeiro into r
  from public.sessoes where id = s_ok;
if r.eixo_capacidade is not null then
  raise exception 'FALHOU 7: sessão prevista já nasceu classificada como "%" — o banco não adivinha o futuro', r.eixo_capacidade;
end if;
if r.valor_reconhecido is not null then
  raise exception 'FALHOU 7: sessão prevista já nasceu com receita reconhecida (%)', r.valor_reconhecido;
end if;
if r.eixo_financeiro <> 'nao_cobrada' then
  raise exception 'FALHOU 7: sessão prevista nasceu em "%"', r.eixo_financeiro;
end if;
raise notice 'ok 7 · prevista nasce sem resolução, e é o certo';

-- 8, 9, 10 e 11 · os fatos mudam, os eixos seguem — sem ninguém escrever eixo.
set local role authenticated;
update public.sessoes set estado = 'realizada' where id = s_ok;
update public.sessoes set estado = 'falta' where id = s_falta;
perform public.cancelar_sessao(s_cedo, 'paciente');
reset role;

select eixo_capacidade, valor_reconhecido into r from public.sessoes where id = s_ok;
if r.eixo_capacidade <> 'vendida' then
  raise exception 'FALHOU 8: hora entregue ficou "%" — invariante 4: hora entregue é hora vendida', r.eixo_capacidade;
end if;
if r.valor_reconhecido <> 200 then
  raise exception 'FALHOU 8: reconhecido = % (esperado 200)', r.valor_reconhecido;
end if;

select eixo_capacidade, valor_reconhecido into r from public.sessoes where id = s_falta;
if r.eixo_capacidade <> 'perdida' or r.valor_reconhecido <> 0 then
  raise exception 'FALHOU 9: falta ficou % com reconhecido % (esperado perdida / 0)', r.eixo_capacidade, r.valor_reconhecido;
end if;

select eixo_capacidade, estado into r from public.sessoes where id = s_cedo;
if r.eixo_capacidade <> 'perdida' then
  raise exception 'FALHOU 10: cancelada (%) ficou "%"', r.estado, r.eixo_capacidade;
end if;
raise notice 'ok 8, 9, 10 e 11 · os eixos seguiram os fatos, sem ninguém escrever eixo';

raise notice '--- parte 3 · a antecipação ---';

-- 12 · pagar hoje uma sessão da semana que vem.
set local role authenticated;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, (hoje + 3 + time '15:00') at time zone 'America/Sao_Paulo',
                                (hoje + 3 + time '15:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 300, 24, 50)
  returning id into s_futura;

insert into public.cobrancas (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao, competencia, estado, paga_em)
  values (a_conta, bia, s_futura, 'sessao', 'avulsa', 300, 300,
          date_trunc('month', hoje)::date, 'paga', now())
  returning id into cob;
reset role;

select eixo_financeiro, valor_reconhecido, eixo_capacidade into r
  from public.sessoes where id = s_futura;
if r.eixo_financeiro <> 'paga' then
  raise exception 'FALHOU 12: a antecipação não marcou o eixo financeiro (ficou "%")', r.eixo_financeiro;
end if;
if r.valor_reconhecido is not null then
  raise exception 'FALHOU 12: antecipação virou receita reconhecida (%) — a ocupação paga passaria a subir recebendo por hora que ainda não aconteceu, e o número mentiria PARA CIMA', r.valor_reconhecido;
end if;
if r.eixo_capacidade is not null then
  raise exception 'FALHOU 12: a hora futura já foi classificada como "%"', r.eixo_capacidade;
end if;
raise notice 'ok 12 · dinheiro recebido não é hora prestada';

-- 5 · e nem por update direto ela vira receita.
erro := null;
begin
  set local role postgres;
  update public.sessoes set valor_reconhecido = 300 where id = s_futura;
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 5: um update direto reconheceu receita de hora que ainda não aconteceu — a invariante 2 tem de estar no banco, não na convenção';
end if;
raise notice 'ok 5 · receita reconhecida só existe para hora prestada';

-- 13 · e quando a hora acontece, aí sim.
--
-- O relógio anda antes do estado mudar: `checa_transicao_sessao` (0009) recusa
-- marcar como realizada uma hora que ainda não começou, e está certíssima. A
-- suíte move a sessão para o passado — que é o que o tempo faria — em vez de
-- inventar uma transição que o produto não permite.
set local role postgres;
update public.sessoes
   set inicio = (base + time '14:00') at time zone 'America/Sao_Paulo',
       fim    = (base + time '14:50') at time zone 'America/Sao_Paulo'
 where id = s_futura;
reset role;

set local role authenticated;
update public.sessoes set estado = 'realizada' where id = s_futura;
reset role;

select valor_reconhecido, eixo_capacidade into r from public.sessoes where id = s_futura;
if r.valor_reconhecido <> 300 or r.eixo_capacidade <> 'vendida' then
  raise exception 'FALHOU 13: prestada a hora, reconhecido = % e capacidade = %', r.valor_reconhecido, r.eixo_capacidade;
end if;
raise notice 'ok 13 · prestada a hora, a receita é reconhecida';

raise notice '--- parte 4 · a reposta ---';

-- 14, 15 · a hora se perde e o paciente consome outra com o mesmo dinheiro.
set local role authenticated;
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, ana, (hoje + 4 + time '09:00') at time zone 'America/Sao_Paulo',
                                (hoje + 4 + time '09:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 200, 240, 0)
  returning id into s_desmarcada;

-- A remarcação da B21 só oferece hora em **dia que já é dela**: as opções saem
-- dos buracos, da grade e das bordas dos dias em que ela já vem trabalhar. Uma
-- agenda vazia não tem para onde remarcar, e isso está certo — então a suíte
-- cria a âncora do dia em vez de inventar um horário que a função recusaria.
insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, bia, (hoje + 5 + time '11:00') at time zone 'America/Sao_Paulo',
                                (hoje + 5 + time '11:50') at time zone 'America/Sao_Paulo', 'avulsa', 'prevista', 200, 24, 50)
  returning id into s_ancora;

tok := public.abrir_remarcacao(s_desmarcada);

-- A escolha só aceita o que está congelado nas opções — é a defesa que impede
-- o link de virar porta para marcar qualquer hora na agenda dela. Então a
-- suíte escolhe a primeira das opções que a própria função ofereceu.
-- `rm` e não `r`: em plpgsql uma variável declarada e um alias de tabela
-- dividem o mesmo espaço de nomes, e a variável ganha. Aqui existe um `r
-- record` declarado no bloco, e `r.opcoes` viraria "record has no field". É a
-- lição da 0052c, cobrada de novo — desta vez na suíte.
select (o->>'inicio')::timestamptz into opcao
  from public.remarcacoes rm, jsonb_array_elements(rm.opcoes) o
 where rm.token = tok
 limit 1;

if opcao is null then
  raise exception 'FALHOU no preâmbulo da 14: a remarcação não ofereceu nenhuma hora';
end if;

j := public.escolher_remarcacao(tok, opcao);
reset role;

if (j->>'ok')::boolean is not true then
  raise exception 'FALHOU no preâmbulo da 14: a remarcação não aconteceu (%)', j->>'motivo';
end if;
s_nova := (j->>'sessao')::uuid;

-- A remarcação exige hora futura (e é o certo). Para o livro-razão fechar um
-- período, o par inteiro é movido para um dia que já passou — de novo, é o que
-- o tempo faria, e não uma transição inventada.
set local role postgres;
update public.sessoes
   set inicio = (base + 1 + time '09:00') at time zone 'America/Sao_Paulo',
       fim    = (base + 1 + time '09:50') at time zone 'America/Sao_Paulo'
 where id = s_desmarcada;
update public.sessoes
   set inicio = (base + 1 + time '10:00') at time zone 'America/Sao_Paulo',
       fim    = (base + 1 + time '10:50') at time zone 'America/Sao_Paulo'
 where id = s_nova;
-- A âncora sai do caminho: ela existiu para a remarcação ter onde encaixar, e
-- deixá-la no período faria o livro-razão do teste contar uma hora a mais.
delete from public.sessoes where id = s_ancora;
reset role;

select eixo_capacidade, reposta_por, valor_reconhecido into r
  from public.sessoes where id = s_desmarcada;
if r.eixo_capacidade <> 'reposta' then
  raise exception 'FALHOU 14: a hora desmarcada ficou "%" — remarcar com crédito é exatamente onde o mercado esconde a hora perdida', r.eixo_capacidade;
end if;
if r.reposta_por is distinct from s_nova then
  raise exception 'FALHOU 14: reposta_por não aponta para a hora que a repôs';
end if;
if r.valor_reconhecido <> 0 then
  raise exception 'FALHOU 15: a hora reposta reconheceu % de receita — somar as duas daria receita dobrada', r.valor_reconhecido;
end if;

set local role authenticated;
update public.sessoes set estado = 'realizada' where id = s_nova;
reset role;

select eixo_capacidade, valor_reconhecido into r from public.sessoes where id = s_nova;
if r.eixo_capacidade <> 'vendida' or r.valor_reconhecido <> 200 then
  raise exception 'FALHOU 15: a hora nova ficou % com reconhecido % (esperado vendida / 200)', r.eixo_capacidade, r.valor_reconhecido;
end if;
raise notice 'ok 14 e 15 · duas horas de capacidade, uma receita';

raise notice '--- parte 5 · o dinheiro ---';

-- 17 · aberta, paga, perdoada.
set local role authenticated;
select id into c_falta from public.cobrancas where sessao_id = s_falta and estado <> 'cancelada' limit 1;
reset role;

if c_falta is null then
  -- **Mudou com o P4 (0058).** A falta não gera mais cobrança: gera pergunta.
  -- O caminho de produção passou a ser decidir, e é por ele que a cobrança tem
  -- de nascer aqui — um `insert` cru de multa o banco recusa desde a 0058, e
  -- recusa de propósito.
  set local role authenticated;
  select id into c_falta from public.propostas_de_cobranca
   where sessao_id = s_falta and estado = 'pendente';

  if c_falta is null then
    raise exception 'FALHOU 17: a falta não gerou nem cobrança nem pergunta';
  end if;

  select (public.decidir_cobranca(c_falta, 'cobrar')->>'cobranca_id')::uuid into c_falta;
  reset role;
end if;

select eixo_financeiro into txt from public.sessoes where id = s_falta;
if txt <> 'cobrada' then
  raise exception 'FALHOU 17: cobrança aberta deixou a sessão em "%"', txt;
end if;

set local role authenticated;
update public.cobrancas set estado = 'paga', paga_em = now() where id = c_falta;
reset role;
select eixo_financeiro into txt from public.sessoes where id = s_falta;
if txt <> 'paga' then
  raise exception 'FALHOU 17: cobrança paga deixou a sessão em "%"', txt;
end if;

set local role authenticated;
update public.cobrancas set estado = 'perdoada', paga_em = null, perdoada_em = now() where id = c_falta;
reset role;
select eixo_financeiro into txt from public.sessoes where id = s_falta;
if txt <> 'perdoada' then
  raise exception 'FALHOU 17: perdão deixou a sessão em "%" — perdoar é decisão dela, com motivo, e tem nome próprio', txt;
end if;
raise notice 'ok 17 · o eixo financeiro segue a cobrança, com o nome certo';

-- 18 · perdão zera o reconhecido de sessão realizada.
set local role authenticated;
insert into public.cobrancas (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao, competencia, estado, perdoada_em)
  values (a_conta, ana, s_ok, 'sessao', 'sessao_realizada', 200, 200, date_trunc('month', base)::date, 'perdoada', now())
  returning id into cob;
reset role;

select valor_reconhecido, eixo_capacidade into r from public.sessoes where id = s_ok;
if r.valor_reconhecido <> 0 then
  raise exception 'FALHOU 18: sessão perdoada reconheceu % — o dinheiro não ficou', r.valor_reconhecido;
end if;
if r.eixo_capacidade <> 'vendida' then
  raise exception 'FALHOU 18: o perdão mudou o eixo CAPACIDADE para "%" — invariante 4: a hora foi entregue, e o dinheiro é assunto do outro eixo. Misturar contaria o mesmo problema duas vezes na tabela de perdas', r.eixo_capacidade;
end if;
raise notice 'ok 18 · perdão zera a receita e não mexe na hora entregue';

-- 19 · cobrança cancelada devolve a sessão para nao_cobrada.
set local role authenticated;
update public.cobrancas set estado = 'cancelada' where id = cob;
reset role;
select eixo_financeiro, valor_reconhecido into r from public.sessoes where id = s_ok;
if r.eixo_financeiro <> 'nao_cobrada' then
  raise exception 'FALHOU 19: cobrança cancelada deixou a sessão em "%" — a tabela de perdas mostraria uma dívida que não existe mais', r.eixo_financeiro;
end if;
if r.valor_reconhecido <> 200 then
  raise exception 'FALHOU 19: cancelado o perdão, a receita da hora entregue não voltou (%)', r.valor_reconhecido;
end if;
raise notice 'ok 19 · cobrança cancelada some do eixo, e a hora entregue volta a valer';

raise notice '--- parte 6 · o fiscal ---';

-- 21 · o recibo move o eixo fiscal.
set local role authenticated;
update public.contas set receita_saude = true where id = a_conta;
update public.pacientes set cpf = '39053344705' where id = ana;
select public.registrar_recebimento(s_ok, hoje - 1) into cob;
reset role;

select eixo_fiscal, eixo_financeiro into r from public.sessoes where id = s_ok;
if r.eixo_financeiro <> 'paga' then
  raise exception 'FALHOU 21: o recebimento não marcou o eixo financeiro (ficou "%")', r.eixo_financeiro;
end if;
if r.eixo_fiscal <> 'pendente' then
  raise exception 'FALHOU 21: nasceu pendência de recibo e o eixo fiscal ficou "%"', r.eixo_fiscal;
end if;

set local role authenticated;
perform public.marcar_recibo_rfb((select id from public.recibos_rfb where cobranca_id = cob), 'RS-0056');
reset role;
select eixo_fiscal into txt from public.sessoes where id = s_ok;
if txt <> 'emitida' then
  raise exception 'FALHOU 21: recibo emitido e o eixo fiscal ficou "%"', txt;
end if;
raise notice 'ok 21 · o eixo fiscal segue o recibo';

raise notice '--- parte 7 · o livro-razão ---';

-- Declara uma semana, para a capacidade existir e a sétima causa ter conta.
select jsonb_agg(jsonb_build_object('dia', d, 'inicio', '09:00', 'fim', '12:00', 'destino', 'atendimento'))
  into semana from generate_series(0, 6) d;

set local role authenticated;
perform public.definir_semana(a_prof, semana);
j := public.livro_razao(a_prof, hoje, hoje + 6);
reset role;

-- 22 · as sete causas, e a sétima sem ação.
if jsonb_array_length(j->'causas') <> 7 then
  raise exception 'FALHOU 22: o livro trouxe % causas (esperado 7)', jsonb_array_length(j->'causas');
end if;

select c->>'acao' into txt
  from jsonb_array_elements(j->'causas') c
 where c->>'causa' = 'hora_nunca_vendida';
if txt is not null then
  raise exception 'FALHOU 22: a hora nunca vendida ganhou a ação "%" — ela aparece como fato e NÃO gera sugestão de contato com ninguém. O Código de Ética veda induzir pessoa a recorrer a serviços', txt;
end if;

select count(*) into n from jsonb_array_elements(j->'causas') c
 where c->>'causa' in ('falta_sem_cobranca','falta_com_cobranca','cancelada_nao_revendida',
                       'reposta','atendida_nao_recebida','abaixo_do_valor','hora_nunca_vendida');
if n <> 7 then
  raise exception 'FALHOU 22: as sete causas do doc 30 não estão todas presentes (% reconhecidas)', n;
end if;
raise notice 'ok 22 · as sete causas, e a sétima sem botão';

-- 23 · a hora nunca vendida vem da capacidade, e não de linha nenhuma.
select (c->>'minutos')::integer into n
  from jsonb_array_elements(j->'causas') c where c->>'causa' = 'hora_nunca_vendida';
if n is null then
  raise exception 'FALHOU 23: a hora nunca vendida não foi calculada';
end if;
if n <> greatest(0, (j->'capacidade'->>'vendavel_min')::integer - (j->>'minutos_usados')::integer) then
  raise exception 'FALHOU 23: a hora nunca vendida (%) não é capacidade menos horas usadas', n;
end if;

select count(*) into n
  from information_schema.tables
 where table_schema = 'public' and table_type = 'BASE TABLE'
   and (table_name like '%hora_vaga%' or table_name like '%horas_vagas%');
if n > 0 then
  raise exception 'FALHOU 23: apareceu tabela de hora vazia — vaga continua sendo cálculo';
end if;
raise notice 'ok 23 · a hora nunca vendida é cálculo, não estoque';

-- 16 · a conta que decide o build: duas horas, uma receita.
set local role authenticated;
j := public.livro_razao(a_prof, base + 1, base + 1);
reset role;

select (c->>'n')::integer, (c->>'valor')::numeric into n, v
  from jsonb_array_elements(j->'causas') c where c->>'causa' = 'reposta';
if n <> 1 or v <> 200 then
  raise exception 'FALHOU 16: a causa reposta veio com n=% valor=% (esperado 1 e 200)', n, v;
end if;
if (j->>'receita_reconhecida')::numeric <> 200 then
  raise exception 'FALHOU 16: duas horas de capacidade produziram % de receita — a soma tem de ser UMA receita, senão a remarcação com crédito vira lucro imaginário', j->>'receita_reconhecida';
end if;
if (j->'horas'->>'cancelada')::integer <> 1 or (j->'horas'->>'realizada')::integer <> 1 then
  raise exception 'FALHOU 16: as duas horas não apareceram separadas nos eixos (%)', j->'horas';
end if;
raise notice 'ok 16 · duas horas de capacidade, uma receita';

-- 24 · a completude automática.
set local role authenticated;
j := public.completude_dos_eixos(base - 30, hoje + 30);
reset role;
if (j->>'sessoes')::integer = 0 then
  raise exception 'FALHOU 24: a completude mediu zero sessão';
end if;
if (j->>'completas')::integer * 100 < (j->>'sessoes')::integer * 90 then
  raise exception 'FALHOU 24: completude de % em % sessões — o critério de pronto do P2 é 90%%, e eixo que se preenche por tela é eixo que fica vazio',
    j->>'completas', j->>'sessoes';
end if;
raise notice 'ok 24 · a completude automática passa de 90%%';

-- 25 · e o livro é da conta.
perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
j := public.livro_razao(a_prof, hoje, hoje + 6);
reset role;
if (j->>'receita_reconhecida')::numeric <> 0 then
  raise exception 'FALHOU 25: a vizinha leu % de receita da outra conta — `security definer` aqui teria entregado o livro inteiro para quem passasse o uuid', j->>'receita_reconhecida';
end if;
raise notice 'ok 25 · o livro é da conta';

-- 26 · apagar a hora que repôs não pode travar nada.
--
-- Esta verificação existe porque a limpeza da própria suíte a encontrou, e o
-- defeito era de produção: `reposta_por` é `on delete set null` e o check exige
-- que `reposta` aponte para alguém. Apagar a sessão que repôs zerava o ponteiro
-- e o check recusava a linha — o `delete` inteiro estourava.
--
-- E `sessoes.paciente_id` é `on delete cascade`. Ou seja: apagar um paciente
-- que um dia remarcou faria a **exclusão de dados do titular** falhar com
-- "violates check constraint". Obrigação legal (LGPD art. 18, doc 18) quebrando
-- por contradição de modelagem é o pior lugar possível para descobrir isso.
--
-- A 0056b responde a pergunta em vez de afrouxar o check: sumindo a hora que
-- repôs, a antiga volta a ser **hora perdida** — que é a única resposta
-- honesta, porque a reposição era exatamente o fato de outra hora ter sido
-- consumida com o mesmo dinheiro.
-- De volta à sessão da conta A: a verificação 25 trocou as claims para a
-- vizinha, e `esquecer_contato` é da dona.
perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);
set local role postgres;
delete from public.sessoes where id = s_nova;
reset role;

select eixo_capacidade, reposta_por, valor_reconhecido into r
  from public.sessoes where id = s_desmarcada;
if r.eixo_capacidade <> 'perdida' then
  raise exception 'FALHOU 26: sumida a hora que repôs, a antiga ficou "%" — sem a outra hora, o que sobra é a perda', r.eixo_capacidade;
end if;
if r.reposta_por is not null then
  raise exception 'FALHOU 26: reposta_por continuou apontando para uma sessão que não existe mais';
end if;
if r.valor_reconhecido <> 0 then
  raise exception 'FALHOU 26: sobrou receita (%) pendurada numa hora que ninguém prestou', r.valor_reconhecido;
end if;

-- E o caminho de esquecimento do produto — que é anonimização, e não `delete`
-- — passa inteiro num paciente que remarcou.
--
-- A distinção importa e a suíte a aprendeu na marra: um `delete from pacientes`
-- cru esbarra na FK de `recibos_rfb`, e **isso está certo**. Registro fiscal não
-- se apaga (invariante da B24), e é exatamente por isso que o direito de
-- eliminação do titular é atendido por `esquecer_contato` — que apaga o que
-- identifica e preserva o que a Receita exige. Testar o `delete` cru era testar
-- um caminho que o produto não oferece.
set local role authenticated;
perform public.esquecer_contato(ana);
reset role;

select telefone, nome into r from public.pacientes where id = ana;
if r.telefone is not null then
  raise exception 'FALHOU 26: esquecer_contato deixou o telefone de quem remarcou';
end if;
raise notice 'ok 26 · a reposição que some vira perda, e o esquecimento não trava';

-- ============================================================ recolher o rastro
set local role postgres;
delete from public.recibos_rfb where conta_id in (a_conta, b_conta);
delete from public.remarcacoes where conta_id in (a_conta, b_conta);
delete from public.cobrancas where conta_id in (a_conta, b_conta);
delete from public.sessoes where conta_id in (a_conta, b_conta);
delete from public.janelas_atendimento where conta_id in (a_conta, b_conta);
delete from public.pacientes where conta_id in (a_conta, b_conta);
delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Razao Teste', 'Razao Vizinha');
reset role;

raise notice 'SUITE 0056 PASSOU: 26 verificações';
end $do$;
