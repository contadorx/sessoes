-- Teste da receita em risco por causa (P5, migração 0059).
--
-- Quatro verificações decidem o arquivo, e três delas são ausências:
--
--   · a **1**, que é o denominador vazio: quem não declarou janela nenhuma tem
--     ocupação **nula**, e não 0%. Ausência de declaração e capacidade zero são
--     coisas diferentes, e confundi-las é acusar alguém de não ter trabalhado
--     num mês em que ela só não preencheu um formulário;
--   · a **6**, que separa antecipado de atendido: pagamento adiantado de sessão
--     futura **não** entra na ocupação paga. É o caminho pelo qual o número mais
--     importante do produto mentiria para cima;
--   · a **9**, que varre `pg_proc` atrás de função que devolva ocupação sozinha.
--     Os quatro números vêm de um objeto só, e é a estrutura — não a tela — que
--     garante isso;
--   · a **22**, que exige que `hora_nunca_vendida` **nunca** apareça como alerta
--     candidato a sumir. Um alerta sem botão jamais acumula clique, e sem essa
--     exclusão a leitura recomendaria, todo mês, apagar exatamente a linha que o
--     roadmap decidiu não ter botão.
--
-- **Por que tudo acontece amanhã.** A janela de capacidade não pode começar no
-- passado (0055), e a sessão realizada não pode ser marcada no futuro por
-- `update` (0009). O par tornaria a suíte dependente da hora do dia — o defeito
-- que a 0046 escondeu por semanas e só aparecia de madrugada. A saída é que o
-- gatilho de transição é `before update`, e não `before insert`: a sessão nasce
-- já realizada, num dia inteiro à frente, e a suíte deixa de olhar para o
-- relógio.
--
--   parte 1 · o denominador, e o silêncio dele
--     1. sem janela declarada, os três percentuais são NULOS        ← decide
--     2. e o cockpit responde mesmo assim, dizendo que não há janela
--     3. com janela e sem sessão, a ocupação é 0 — aí zero é a verdade
--
--   parte 2 · os quatro números
--     4. ocupação realizada, com o número exato
--     5. ocupação paga conta hora prestada com receita reconhecida
--     6. e antecipação NÃO entra na ocupação paga                   ← decide
--     7. receita por hora disponível, com o número exato
--     8. as sete causas vêm na mesma resposta
--     9. não existe função que devolva ocupação sozinha             ← decide
--    10. o tempo protegido vem junto com a ocupação
--
--   parte 3 · o que a estrutura recusa
--    11. nenhuma chave de meta, objetivo, alvo ou ideal
--    12. nenhuma coluna de meta nas tabelas do P1 e do P5
--    13. passar de 100% é fato, e é só um booleano
--    14. nenhuma função do P5 sugere preencher, oferecer ou convidar
--    15. a sétima causa continua sem ação
--
--   parte 4 · o instrumento
--    16. registrar uso conta, e a segunda vez soma
--    17. causa sem ação é recusada pelo banco
--    18. o uso é da conta de quem clicou, e não de um parâmetro
--    19. não existe política de delete: a contagem não se apaga
--
--   parte 5 · o alerta que ninguém clicou
--    20. causa com peso e sem clique vira candidata
--    21. clicar tira da lista
--    22. `hora_nunca_vendida` nunca é candidata                     ← decide
--    23. `falta_com_cobranca` também não
--    24. causa sem peso nenhum não vira candidata
--
--   parte 6 · as trancas
--    25. a vizinha não lê os usos nem o cockpit da outra
--    26. o anônimo não executa nada disto
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0059_receita_em_risco.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111159';
  b_auth uuid := '22222222-2222-4222-8222-222222222159';
  a_conta uuid; a_prof uuid; b_conta uuid; b_prof uuid;
  ana uuid; bia uuid;
  s_feita uuid; s_cobrada uuid; s_antecipada uuid; s_falta uuid; s_passada uuid;
  cob uuid;
  j jsonb; c jsonb; n integer; erro text; txt text; v numeric;
  hoje date; amanha date; dow smallint; extra timestamptz;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Risco Teste', 'Risco Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'risco@teste.sessoes.com.br', '{"nome":"Risco Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (b_auth, 'riscoviz@teste.sessoes.com.br', '{"nome":"Risco Vizinha"}'::jsonb);

select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
select id into a_prof from public.profissionais where conta_id = a_conta;
select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
select id into b_prof from public.profissionais where conta_id = b_conta;

hoje   := public.hoje_sp();
amanha := hoje + 1;
dow    := extract(dow from amanha)::smallint;

perform set_config('request.jwt.claims',
  json_build_object('sub', a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Ana Risco', '5511900000591', 'em_atendimento') returning id into ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (a_prof, 'Bia Risco', '5511900000592', 'em_atendimento') returning id into bia;
reset role;

raise notice '--- parte 1 · o denominador e o silêncio dele ---';

-- 1 · Nenhuma janela ainda.  ← decide
--
-- Zero por cento é uma afirmação sobre o trabalho de alguém. Nulo é a ausência
-- de uma declaração. O produto não tem o direito de trocar a segunda pela
-- primeira.
set local role authenticated;
j := public.cockpit_do_mes(a_prof, amanha, amanha);
reset role;

if j->'ocupacao_realizada' <> 'null'::jsonb then
  raise exception 'FALHOU 1: ocupação realizada veio % sem janela declarada — zero é acusação, nulo é ausência', j->>'ocupacao_realizada';
end if;
if j->'ocupacao_paga' <> 'null'::jsonb then
  raise exception 'FALHOU 1: ocupação paga veio %', j->>'ocupacao_paga';
end if;
if j->'receita_por_hora' <> 'null'::jsonb then
  raise exception 'FALHOU 1: receita por hora veio %', j->>'receita_por_hora';
end if;
raise notice 'ok 1 · sem declaração, os três são nulos';

-- 2 · E a tela ainda assim tem o que dizer.
if (j->'capacidade'->>'sem_janela')::boolean is not true then
  raise exception 'FALHOU 2: não disse que não há janela';
end if;
if jsonb_array_length(j->'causas') <> 7 then
  raise exception 'FALHOU 2: % causas (esperado 7)', jsonb_array_length(j->'causas');
end if;
raise notice 'ok 2 · o cockpit responde mesmo vazio';

-- 3 · Agora a semana declarada: 5 horas vendáveis e 1 hora protegida.
set local role postgres;
insert into public.janelas_atendimento
  (conta_id, profissional_id, dia_semana, inicio, fim, destino, vigencia_de)
  values (a_conta, a_prof, dow, '08:00', '13:00', 'atendimento', hoje);
insert into public.janelas_atendimento
  (conta_id, profissional_id, dia_semana, inicio, fim, destino, vigencia_de)
  values (a_conta, a_prof, dow, '13:00', '14:00', 'registro', hoje);
reset role;

set local role authenticated;
j := public.cockpit_do_mes(a_prof, amanha + 7, amanha + 7);
reset role;
if (j->'minutos'->>'vendavel')::integer <> 300 then
  raise exception 'FALHOU 3: vendável % (esperado 300)', j->'minutos'->>'vendavel';
end if;
if (j->>'ocupacao_realizada')::numeric <> 0 then
  raise exception 'FALHOU 3: ocupação % numa semana declarada e sem sessão — aqui zero é a verdade', j->>'ocupacao_realizada';
end if;
raise notice 'ok 3 · declarou e não atendeu: zero é a verdade';

raise notice '--- parte 2 · os quatro números ---';

-- As quatro sessões de amanhã. Nascem já no estado final, e por isso a suíte
-- não olha para o relógio — ver o cabeçalho.
set local role postgres;

-- prestada e paga
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, ana,
          (amanha + time '08:00') at time zone 'America/Sao_Paulo',
          (amanha + time '08:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'realizada', 200.00, 24, 50)
  returning id into s_feita;
insert into public.cobrancas
  (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao,
   competencia, estado, paga_em)
  values (a_conta, ana, s_feita, 'sessao', 'sessao_realizada', 200.00, 200.00,
          date_trunc('month', amanha)::date, 'paga', now());

-- prestada e em aberto
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, bia,
          (amanha + time '09:00') at time zone 'America/Sao_Paulo',
          (amanha + time '09:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'realizada', 200.00, 24, 50)
  returning id into s_cobrada;
insert into public.cobrancas
  (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao,
   competencia, estado)
  values (a_conta, bia, s_cobrada, 'sessao', 'sessao_realizada', 200.00, 200.00,
          date_trunc('month', amanha)::date, 'aberta');

-- paga adiantado, e ainda não aconteceu
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, ana,
          (amanha + time '10:00') at time zone 'America/Sao_Paulo',
          (amanha + time '10:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'prevista', 200.00, 24, 50)
  returning id into s_antecipada;
insert into public.cobrancas
  (conta_id, paciente_id, sessao_id, tipo, motivo, valor, valor_da_sessao,
   competencia, estado, paga_em)
  values (a_conta, ana, s_antecipada, 'sessao', 'avulsa', 200.00, 200.00,
          date_trunc('month', amanha)::date, 'paga', now());

-- não veio, e ninguém cobrou
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (a_conta, a_prof, bia,
          (amanha + time '11:00') at time zone 'America/Sao_Paulo',
          (amanha + time '11:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'falta', 200.00, 24, 50)
  returning id into s_falta;
reset role;

set local role authenticated;
j := public.cockpit_do_mes(a_prof, amanha, amanha);
reset role;

-- 4 · 100 minutos atendidos sobre 300 vendáveis.
if (j->'minutos'->>'realizada')::integer <> 100 then
  raise exception 'FALHOU 4: % minutos realizados (esperado 100)', j->'minutos'->>'realizada';
end if;
if (j->>'ocupacao_realizada')::numeric <> 33.3 then
  raise exception 'FALHOU 4: ocupação realizada % (esperado 33,3)', j->>'ocupacao_realizada';
end if;
raise notice 'ok 4 · ocupação realizada';

-- 5 e 6 · A paga conta uma só: a prestada **com receita reconhecida**.
--
-- A prestada em aberto tem reconhecido e não tem pagamento; a antecipada tem
-- pagamento e não tem reconhecido. As duas ficam de fora, por motivos opostos.
if (j->'minutos'->>'paga')::integer <> 50 then
  raise exception 'FALHOU 5: % minutos pagos (esperado 50)', j->'minutos'->>'paga';
end if;
if (j->>'ocupacao_paga')::numeric <> 16.7 then
  raise exception 'FALHOU 5: ocupação paga % (esperado 16,7)', j->>'ocupacao_paga';
end if;

select valor_reconhecido into v from public.sessoes where id = s_antecipada;
if v is not null then
  raise exception 'FALHOU 6: a sessão paga adiantado reconheceu % de receita antes de acontecer', v;
end if;
if (j->'minutos'->>'paga')::integer > 50 then
  raise exception 'FALHOU 6: a antecipação entrou na ocupação paga — o número passaria a mentir para cima';
end if;
raise notice 'ok 5 e 6 · pago é hora prestada, e antecipação não conta';

-- 7 · Receita reconhecida 400 sobre 5 horas vendáveis.
if (j->>'receita_reconhecida')::numeric <> 400 then
  raise exception 'FALHOU 7: receita reconhecida % (esperado 400)', j->>'receita_reconhecida';
end if;
if (j->>'receita_por_hora')::numeric <> 80.00 then
  raise exception 'FALHOU 7: receita por hora % (esperado 80)', j->>'receita_por_hora';
end if;
raise notice 'ok 7 · receita por hora disponível';

-- 8 · E as causas vêm na mesma resposta, não numa segunda ida ao banco.
select x into c from jsonb_array_elements(j->'causas') x
 where x->>'causa' = 'falta_sem_cobranca';
if (c->>'n')::integer <> 1 or (c->>'valor')::numeric <> 200 then
  raise exception 'FALHOU 8: falta sem cobrança veio %', c;
end if;
select x into c from jsonb_array_elements(j->'causas') x
 where x->>'causa' = 'atendida_nao_recebida';
if (c->>'n')::integer <> 1 then
  raise exception 'FALHOU 8: atendida e não recebida veio %', c;
end if;
raise notice 'ok 8 · os quatro números e as causas, numa resposta só';

-- 9 · Nenhuma função devolve ocupação sozinha.  ← decide
--
-- Se um dia existir `taxa_de_ocupacao(prof, de, ate) returns numeric`, alguém
-- vai pô-la sozinha numa tela — e um número solitário de ocupação, num produto
-- para psicólogas, empurra contra o descanso.
--
-- A primeira versão desta varredura procurava só pelo nome, e reprovou um banco
-- correto: a 0053 tem `ocupacao_receita_saude()`, que devolve o **código de
-- ocupação profissional** da Receita Federal — 255, para psicólogo. Mesma
-- palavra, outro assunto. É a lição da 0044 e da 0051 de novo: asserção larga
-- acusa o código certo, e o preço não é o falso positivo, é aprender a ignorar
-- o alarme.
--
-- O perigo real tem forma: **um escalar numérico com nome de ocupação**. É esse
-- que alguém põe sozinho numa tela.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.prokind = 'f'
   and p.proname ~ 'ocupacao'
   and p.proname <> 'cockpit_do_mes'
   and pg_get_function_result(p.oid)
       in ('numeric', 'double precision', 'real', 'integer', 'bigint', 'smallint');
if n <> 0 then
  raise exception 'FALHOU 9: % função(ões) de ocupação fora do cockpit — os quatro números vêm juntos ou não vêm', n;
end if;

for txt in select unnest(array['ocupacao_realizada','ocupacao_paga','receita_por_hora','causas'])
loop
  if not (j ? txt) then
    raise exception 'FALHOU 9: o cockpit voltou sem "%"', txt;
  end if;
end loop;
raise notice 'ok 9 · os quatro moram no mesmo objeto';

-- 10 · E o tempo protegido vai junto, sempre.
--
-- Sem ele, ocupação se lê como espaço vazio a ocupar — e tempo de prontuário e
-- de descanso são capacidade declarada, não ociosidade.
if (j->'minutos'->>'protegido')::integer <> 60 then
  raise exception 'FALHOU 10: protegido % (esperado 60)', j->'minutos'->>'protegido';
end if;
raise notice 'ok 10 · o protegido aparece ao lado da ocupação';

raise notice '--- parte 3 · o que a estrutura recusa ---';

-- 11 · Nenhuma meta na resposta.
if j::text ~* '"(meta|objetivo|alvo|ideal|esperado)[^"]*"\s*:' then
  raise exception 'FALHOU 11: o cockpit devolveu uma meta — barra de progresso rumo a 100%% de ocupação é empurrão para eliminar o descanso';
end if;
raise notice 'ok 11 · não existe meta na resposta';

-- 12 · Nem nas tabelas.
select count(*) into n
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('janelas_atendimento', 'usos_do_alerta')
   and column_name ~* 'meta|objetivo|alvo|ideal';
if n <> 0 then
  raise exception 'FALHOU 12: % coluna(s) de meta nas tabelas de capacidade', n;
end if;
raise notice 'ok 12 · não existe meta no banco';

-- 13 · Passar de 100% é fato, e é só um booleano.
set local role postgres;
extra := (amanha + time '14:00') at time zone 'America/Sao_Paulo';
for n in 1..5 loop
  insert into public.sessoes
    (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
     politica_horas, politica_percentual)
    values (a_conta, a_prof, ana,
            extra + make_interval(hours => n),
            extra + make_interval(hours => n, mins => 50),
            'avulsa', 'realizada', 200.00, 24, 50);
end loop;
reset role;

set local role authenticated;
j := public.cockpit_do_mes(a_prof, amanha, amanha);
reset role;
if (j->>'ocupacao_realizada')::numeric <= 100 then
  raise exception 'FALHOU 13: ocupação % com 350 minutos sobre 300', j->>'ocupacao_realizada';
end if;
if (j->>'alem_do_declarado')::boolean is not true then
  raise exception 'FALHOU 13: não marcou que passou do declarado';
end if;
if j::text ~* 'parab|otim|excelente|meta atingida|super' then
  raise exception 'FALHOU 13: o banco elogiou alguém por trabalhar além do que declarou';
end if;
raise notice 'ok 13 · além do declarado é fato, e não elogio';

-- 14 · Nenhuma função do P5 sugere contato.
--
-- Comentário sai da varredura de propósito: ele é a memória de **por que** a
-- frase é proibida, e apagá-lo para o teste passar seria apagar o motivo. É a
-- lição da 0044 e da 0051.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.prokind = 'f'
   and p.proname in ('cockpit_do_mes', 'alertas_a_rever', 'registrar_uso_do_alerta')
   and regexp_replace(pg_get_functiondef(p.oid), '--[^\n]*', '', 'g')
       ~* 'preench|ofere[cç]|divulg|convid|captar|prospect';
if n <> 0 then
  raise exception 'FALHOU 14: % função(ões) do P5 sugerindo contato — o Código de Ética veda induzir alguém a recorrer aos serviços', n;
end if;
raise notice 'ok 14 · nenhuma função sugere preencher hora';

-- 15 · E a sétima causa continua sem ação.
select x into c from jsonb_array_elements(j->'causas') x
 where x->>'causa' = 'hora_nunca_vendida';
if c is null then
  raise exception 'FALHOU 15: a hora nunca vendida sumiu da lista — ela é fato e tem de aparecer';
end if;
if c->>'acao' is not null then
  raise exception 'FALHOU 15: a hora nunca vendida ganhou a ação "%"', c->>'acao';
end if;
raise notice 'ok 15 · a sétima linha aparece, e não tem botão';

raise notice '--- parte 4 · o instrumento ---';

-- 16 · Contar, e somar na segunda vez.
set local role authenticated;
n := public.registrar_uso_do_alerta('falta_sem_cobranca');
if n <> 1 then raise exception 'FALHOU 16: primeira vez contou %', n; end if;
n := public.registrar_uso_do_alerta('falta_sem_cobranca');
if n <> 2 then raise exception 'FALHOU 16: segunda vez contou %', n; end if;
reset role;
raise notice 'ok 16 · o uso se conta';

-- 17 · Causa sem ação não entra. Ver o cabeçalho da 0059.
erro := null;
begin
  set local role authenticated;
  perform public.registrar_uso_do_alerta('hora_nunca_vendida');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 17: contou clique numa causa que não tem botão';
end if;

erro := null;
begin
  set local role authenticated;
  perform public.registrar_uso_do_alerta('falta_com_cobranca');
  reset role;
exception when others then erro := sqlerrm;
end;
reset role;
if erro is null then
  raise exception 'FALHOU 17: contou clique na causa que não é problema';
end if;
raise notice 'ok 17 · só as cinco causas com ação';

-- 18 · O uso é de quem clicou. Sem parâmetro de conta, não há sonda.
select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'registrar_uso_do_alerta'
   and pg_get_function_identity_arguments(p.oid) ~* 'conta';
if n <> 0 then
  raise exception 'FALHOU 18: registrar uso aceita conta por parâmetro — é a assinatura de uma sonda';
end if;
select conta_id into a_conta from public.usos_do_alerta where causa = 'falta_sem_cobranca' limit 1;
if a_conta is null then raise exception 'FALHOU 18: não gravou em conta nenhuma'; end if;
raise notice 'ok 18 · o uso é da conta de quem clicou';

-- 19 · E a contagem não se apaga: zerar seria apagar a prova de que o alerta
--      não serve para nada.
select count(*) into n from pg_policies
 where schemaname = 'public' and tablename = 'usos_do_alerta' and cmd = 'DELETE';
if n <> 0 then
  raise exception 'FALHOU 19: existe política de delete em usos_do_alerta';
end if;
raise notice 'ok 19 · a contagem não se apaga';

raise notice '--- parte 5 · o alerta que ninguém clicou ---';

-- Uma falta de dez dias atrás, para haver peso dentro da janela de 90 dias que
-- a leitura olha. As sessões de amanhã estão fora dela de propósito.
select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (a_conta, a_prof, bia,
          ((hoje - 10) + time '15:00') at time zone 'America/Sao_Paulo',
          ((hoje - 10) + time '15:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'cancelada_tarde', 200.00, 24, 50,
          -- O estado e o registro do cancelamento são a mesma coisa e não se
          -- separam nem num teste: é o `check` da 0006, e a suíte tem de montar
          -- o cenário como o produto monta.
          ((hoje - 10) + time '14:00') at time zone 'America/Sao_Paulo', 'paciente')
  returning id into s_passada;
reset role;

-- 20 · A causa "cancelada e não reocupada" tem peso e nunca foi clicada.
set local role authenticated;
j := public.alertas_a_rever(a_prof);
reset role;

select x into c from jsonb_array_elements(j->'alertas') x
 where x->>'causa' = 'cancelada_nao_revendida';
if c is null then
  raise exception 'FALHOU 20: a causa com peso e sem clique não virou candidata: %', j;
end if;
if (c->>'nunca_usado')::boolean is not true then
  raise exception 'FALHOU 20: disse que já tinha sido usada';
end if;
raise notice 'ok 20 · o alerta que ninguém usou aparece';

-- 21 · Clicar tira da lista.
set local role authenticated;
perform public.registrar_uso_do_alerta('cancelada_nao_revendida');
j := public.alertas_a_rever(a_prof);
reset role;
select count(*) into n from jsonb_array_elements(j->'alertas') x
 where x->>'causa' = 'cancelada_nao_revendida';
if n <> 0 then
  raise exception 'FALHOU 21: continuou candidata depois de usada';
end if;
raise notice 'ok 21 · usar tira da lista';

-- 22 e 23 · As duas sem ação nunca aparecem.  ← decide
select count(*) into n from jsonb_array_elements(j->'alertas') x
 where x->>'causa' = 'hora_nunca_vendida';
if n <> 0 then
  raise exception 'FALHOU 22: a hora nunca vendida virou candidata a sumir — ela não tem botão por decisão, e não por falta de uso';
end if;
select count(*) into n from jsonb_array_elements(j->'alertas') x
 where x->>'causa' = 'falta_com_cobranca';
if n <> 0 then
  raise exception 'FALHOU 23: a falta com cobrança virou candidata — ela não é problema, é a política funcionando';
end if;
raise notice 'ok 22 e 23 · as duas sem ação ficam de fora';

-- 24 · E causa sem peso nenhum não vira candidata: conselho sobre nada.
select count(*) into n from jsonb_array_elements(j->'alertas') x
 where x->>'causa' = 'abaixo_do_valor';
if n <> 0 then
  raise exception 'FALHOU 24: recomendou rever um alerta que nunca teve o que mostrar';
end if;
raise notice 'ok 24 · sem peso, sem recomendação';

raise notice '--- parte 6 · as trancas ---';

-- 25 · A vizinha não lê nada disto.
perform set_config('request.jwt.claims',
  json_build_object('sub', b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select count(*) into n from public.usos_do_alerta;
if n <> 0 then raise exception 'FALHOU 25: a vizinha viu % usos da outra conta', n; end if;

j := public.cockpit_do_mes(a_prof, amanha, amanha);
reset role;
if (j->'minutos'->>'realizada')::integer <> 0 then
  raise exception 'FALHOU 25: a vizinha leu % minutos atendidos da outra conta', j->'minutos'->>'realizada';
end if;
if (j->>'receita_reconhecida')::numeric <> 0 then
  raise exception 'FALHOU 25: a vizinha leu a receita da outra conta';
end if;
raise notice 'ok 25 · o cockpit é da conta';

-- 26 · E o anônimo não passa da porta.
perform set_config('request.jwt.claims', null, true);
set local role anon;
erro := null;
begin perform public.cockpit_do_mes(a_prof, amanha, amanha);
exception when others then erro := sqlerrm; end;
if erro is null then raise exception 'FALHOU 26: anon leu o cockpit'; end if;

erro := null;
begin perform public.registrar_uso_do_alerta('reposta');
exception when others then erro := sqlerrm; end;
if erro is null then raise exception 'FALHOU 26: anon registrou uso de alerta'; end if;

erro := null;
begin perform public.alertas_a_rever(a_prof);
exception when others then erro := sqlerrm; end;
reset role;
if erro is null then raise exception 'FALHOU 26: anon leu os alertas'; end if;
raise notice 'ok 26 · o anônimo não lê nada disto';

-- ============================================================ recolher o rastro
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.usos_do_alerta where conta_id in (a_conta, b_conta);
delete from public.mensagens where conta_id in (a_conta, b_conta);
delete from public.recibos_rfb where conta_id in (a_conta, b_conta);
delete from public.propostas_de_cobranca where conta_id in (a_conta, b_conta);
delete from public.cobrancas where conta_id in (a_conta, b_conta);
delete from public.sessoes where conta_id in (a_conta, b_conta);
delete from public.janelas_atendimento where conta_id in (a_conta, b_conta);
delete from public.enquadres where conta_id in (a_conta, b_conta);
delete from public.pacientes where conta_id in (a_conta, b_conta);
delete from auth.users where id in (a_auth, b_auth);
delete from public.contas where nome in ('Risco Teste', 'Risco Vizinha');
reset role;

raise notice 'SUITE 0059 PASSOU: 26 verificações';
end $do$;
