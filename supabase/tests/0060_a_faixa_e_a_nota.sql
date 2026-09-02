-- Teste da faixa de sessões e da nota do produto (OP8, migrações 0060 e 0060b).
--
-- **Metade das verificações prova ausência**, e é a metade que importa: esta
-- build tira uma trava que existia e põe no lugar dela um pedido. O que
-- garante que a trava não volte por engano — numa "otimização de custo" daqui a
-- seis meses — não é a ausência de código, é a presença de verificação.
--
-- Cinco decidem o arquivo:
--
--   · a **2**, que cria a nona sessão de uma conta Grátis de faixa 8 e exige
--     que ela **entre**. A faixa é unidade de preço, não cerca. Barrar a agenda
--     para proteger margem cobra o preço de quem não escolheu plano nenhum: a
--     paciente que já tem hora marcada;
--   · a **11**, que estoura a faixa e depois enfileira uma oferta de vaga, e
--     exige que ela **saia**. É a linha 3 da política do `claude/25` virada em
--     código: nunca parar de avisar a paciente por causa de limite;
--   · a **12**, que varre o corpo de `teto_tecnico` atrás da palavra `planos`.
--     Freio técnico que consulta plano é produto disfarçado, e a diferença
--     entre as duas coisas não sobrevive a seis meses se depender de memória;
--   · a **21**, que dá nota 0 numa conta e nota 10 na outra e exige que faixa,
--     freio e plano respondam **exatamente igual** nas duas. A nota é do
--     produto, e um produto que reage à nota está comprando a nota;
--   · a **24**, que varre `pg_proc` atrás de função que leia `avaliacoes` e
--     escreva em `contas`, `assinaturas`, `planos` ou `faturas`. É a verificação
--     que impede o desconto por nota boa — e ela reprova mesmo que a intenção
--     de quem escrever seja boa.
--
-- **Duas armadilhas de escrita evitadas aqui, e as duas são cicatriz:**
--
--   · **nenhuma variável se chama `fim`, `inicio`, `nota` ou `plano` sem
--     prefixo.** A 0060 aplicou com sucesso e deixou três funções quebradas
--     porque `fim` é variável e é também coluna de `sessoes`. Toda variável
--     deste arquivo leva `v_`;
--   · **as varreduras são estreitas.** Já aconteceu quatro vezes nesta obra uma
--     varredura larga acusar código correto — a última na 0059, com
--     `ocupacao_receita_saude()`. As duas varreduras aqui exigem **duas coisas
--     juntas** no mesmo corpo, e não uma palavra solta.
--
--   parte 1 · a faixa é medida, e não cerca
--     1. a faixa responde numa conta nova: 8, zero usadas
--     2. a nona sessão numa faixa de oito ENTRA                     ← decide
--     3. e aí `acima` é verdade, `restantes` é zero, e nada mais mudou
--     4. `cancelada_cedo` não conta — não foi vendida               ← decide
--     5. falta e cancelamento tardio contam — a hora foi vendida
--     6. a faixa é por profissional que atende
--     7. `pct` passa de 100 e não é elogio nem acusação
--
--   parte 2 · o teto de mensagens saiu do produto
--     8. nenhum plano tem teto mensal de mensagens                  ← decide
--     9. `avancar_fila` não cita mais teto nem plano                ← decide
--    10. o evento `fila_pausada_no_teto` continua existindo no check
--    11. com a faixa estourada, a oferta de vaga SAI                ← decide
--
--   parte 3 · o freio técnico, que é contra o laço
--    12. `teto_tecnico` não lê a tabela de planos                   ← decide
--    13. conta parada não bate em freio nenhum
--    14. o freio por conta/hora existe e diz o nome
--    15. o freio por paciente/dia existe e diz o nome
--    16. o freio pega template essencial também — e é de propósito
--    17. a cliente não enxerga `limites_tecnicos`                   ← decide
--    18. a mensagem barrada diz qual freio a segurou
--
--   parte 4 · a nota é do produto
--    19. nota fora de 0 a 10 é recusada
--    20. os retratos são tirados pela função, não recebidos
--    21. nota 0 e nota 10 não mudam absolutamente nada              ← decide
--    22. momento fora da lista fechada é recusado                   ← decide
--    23. conta nova não é convidada a avaliar
--    24. ninguém lê a nota e escreve em conta, plano ou fatura      ← decide
--    25. a nota não se edita nem se apaga, nem por quem a deu       ← decide
--    26. a nota sai na exportação da conta
--    27. NPS é nulo com menos de cinco respostas
--
--   parte 5 · as trancas
--    28. a vizinha não lê a faixa nem a nota da outra
--    29. quem não é operador não lê o agregado
--    30. o anônimo não executa nada disto
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0060_a_faixa_e_a_nota.sql

do $do$
declare
  v_a_auth uuid := '11111111-1111-4111-8111-111111111160';
  v_b_auth uuid := '22222222-2222-4222-8222-222222222160';
  v_c_auth uuid := '33333333-3333-4333-8333-333333333160';
  v_a_conta uuid; v_a_prof uuid; v_b_conta uuid; v_b_prof uuid;
  v_c_conta uuid; v_prof2 uuid;
  v_ana uuid; v_bia uuid; v_cida uuid;
  v_faixa record; v_faixa_b record;
  v_msg uuid;
  v_j jsonb;
  v_n integer;
  v_erro text;
  v_txt text;
  v_freio text;
  v_hoje date; v_amanha date;
  v_id uuid;
  v_k integer;
begin

-- ============================================================ preâmbulo

delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.contas where nome in ('Faixa Teste', 'Faixa Vizinha', 'Faixa Dupla');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'faixa@teste.sessoes.com.br', '{"nome":"Faixa Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'faixaviz@teste.sessoes.com.br', '{"nome":"Faixa Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id into v_a_prof from public.profissionais where conta_id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id into v_b_prof from public.profissionais where conta_id = v_b_conta;

v_hoje   := public.hoje_sp();
v_amanha := v_hoje + 1;

set local role postgres;
update public.contas set plano = 'gratis' where id in (v_a_conta, v_b_conta);
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Faixa', '5511900000601', 'em_atendimento') returning id into v_ana;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Bia Faixa', '5511900000602', 'em_atendimento') returning id into v_bia;
reset role;

-- A vizinha também precisa de uma paciente: `mensagem_confere_retrato` recusa
-- mensagem sem paciente desde a 0017, e é ela que garante que toda mensagem
-- deste produto tem destinatário conhecido.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_b_prof, 'Cida Vizinha', '5511900000699', 'em_atendimento') returning id into v_cida;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);

raise notice '--- parte 1 · a faixa é medida, e não cerca ---';

-- 1 · A faixa de uma conta nova no Grátis.
set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if not v_faixa.tem_faixa then
  raise exception 'FALHOU 1: conta no Grátis veio sem faixa';
end if;
if v_faixa.limite <> 8 then
  raise exception 'FALHOU 1: limite % (esperado 8, do claude/25)', v_faixa.limite;
end if;
if v_faixa.usadas <> 0 or v_faixa.acima then
  raise exception 'FALHOU 1: conta sem sessão veio com % usadas, acima=%', v_faixa.usadas, v_faixa.acima;
end if;
raise notice 'ok 1 · faixa de 8 e nada gasto';

-- 2 · A nona sessão entra.  ← decide
--
-- Nove sessões numa faixa de oito. Se qualquer gatilho recusar a nona, o
-- produto virou o que a 0046 recusou ser: uma agenda que para no meio para
-- proteger a minha margem. Quem encontraria a porta fechada é a paciente.
set local role postgres;
for v_k in 1..9 loop
  insert into public.sessoes
    (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
     politica_horas, politica_percentual)
    values (v_a_conta, v_a_prof, v_ana,
            (v_hoje + make_interval(days => 0) + time '08:00' + make_interval(hours => v_k))
              at time zone 'America/Sao_Paulo',
            (v_hoje + make_interval(days => 0) + time '08:50' + make_interval(hours => v_k))
              at time zone 'America/Sao_Paulo',
            'avulsa', 'prevista', 200.00, 24, 50);
end loop;
reset role;

select count(*)::integer into v_n from public.sessoes
 where conta_id = v_a_conta and estado = 'prevista';
if v_n <> 9 then
  raise exception 'FALHOU 2: só % sessões entraram numa faixa de 8 — a faixa virou cerca', v_n;
end if;
raise notice 'ok 2 · a nona sessão entrou, e a faixa não é cerca';

-- 3 · E a faixa diz a verdade sobre isso, sem impedir nada.
set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.usadas <> 9 then
  raise exception 'FALHOU 3: usadas % (esperado 9)', v_faixa.usadas;
end if;
if not v_faixa.acima then
  raise exception 'FALHOU 3: 9 sessões numa faixa de 8 não marcou acima';
end if;
if v_faixa.restantes <> 0 then
  raise exception 'FALHOU 3: restantes % (esperado 0, e nunca negativo)', v_faixa.restantes;
end if;
raise notice 'ok 3 · acima da faixa, restantes zero, e nada barrado';

-- 4 · `cancelada_cedo` não conta.  ← decide
--
-- Uma sessão desmarcada dentro do prazo não foi vendida. Contá-la faria a
-- paciente que desmarca três vezes empurrar a psicóloga para um plano maior por
-- sessões que nunca aconteceram — o produto acusando alguém pelo comportamento
-- de outra pessoa.
--
-- **As três nascem canceladas**, e não são transicionadas. O gatilho de
-- classificação da 0010 é `before update` e decide `cedo` ou `tarde` pela
-- distância até o início: transicionar uma sessão de hoje nunca produziria
-- `cancelada_cedo`, e a suíte estaria testando o relógio em vez da faixa. É a
-- mesma saída que a 0059 usa para a sessão realizada.
set local role postgres;
for v_k in 1..3 loop
  insert into public.sessoes
    (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
     politica_horas, politica_percentual, cancelada_em, cancelada_por)
    values (v_a_conta, v_a_prof, v_ana,
            (v_hoje + time '18:00' + make_interval(hours => v_k)) at time zone 'America/Sao_Paulo',
            (v_hoje + time '18:50' + make_interval(hours => v_k)) at time zone 'America/Sao_Paulo',
            'avulsa', 'cancelada_cedo', 200.00, 24, 50, now(), 'paciente');
end loop;
reset role;

select count(*)::integer into v_n from public.sessoes where conta_id = v_a_conta;
if v_n <> 12 then
  raise exception 'FALHOU 4: o cenário não montou (% sessões, esperado 12)', v_n;
end if;

set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.usadas <> 9 then
  raise exception 'FALHOU 4: usadas % com 12 sessões, 3 delas desmarcadas no prazo (esperado 9)', v_faixa.usadas;
end if;
raise notice 'ok 4 · desmarcada no prazo não gasta faixa';

-- 5 · Falta e cancelamento tardio contam. A hora foi vendida.
set local role postgres;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual)
  values (v_a_conta, v_a_prof, v_bia,
          (v_hoje + time '06:00') at time zone 'America/Sao_Paulo',
          (v_hoje + time '06:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'falta', 200.00, 24, 50);
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
   politica_horas, politica_percentual, cancelada_em, cancelada_por)
  values (v_a_conta, v_a_prof, v_bia,
          (v_hoje + time '07:00') at time zone 'America/Sao_Paulo',
          (v_hoje + time '07:50') at time zone 'America/Sao_Paulo',
          'avulsa', 'cancelada_tarde', 200.00, 24, 50, now(), 'paciente');
reset role;

set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.usadas <> 11 then
  raise exception 'FALHOU 5: usadas % — falta e cancelamento tardio saíram da conta, e a hora foi vendida (esperado 11)', v_faixa.usadas;
end if;
raise notice 'ok 5 · falta e cancelamento tardio continuam gastando faixa';

-- 6 · A faixa multiplica por profissional ATIVO — e só por ele.  ← decide
--
-- Esta verificação achou um defeito da 0060, corrigido pela 0060c: a função
-- contava todos os profissionais, e `profissionais.ativo` existe desde a 0002.
-- Uma clínica que desligou duas continuava com a faixa das quatro — um erro que
-- infla a favor de quem lê, e por isso ninguém corrigiria.
--
-- O segundo profissional precisa de um segundo usuário: a chave é
-- `unique (conta_id, usuario_id)`. Então nasce uma terceira conta pelo gatilho
-- de signup, e o usuário dela é mudado de casa.
set local role postgres;
insert into auth.users (id, email, raw_user_meta_data)
  values (v_c_auth, 'faixadupla@teste.sessoes.com.br', '{"nome":"Faixa Dupla"}'::jsonb);
select conta_id into v_c_conta from public.usuarios where auth_user_id = v_c_auth;
update public.profissionais set conta_id = v_a_conta
 where usuario_id = (select id from public.usuarios where auth_user_id = v_c_auth)
 returning id into v_prof2;
update public.usuarios set conta_id = v_a_conta where auth_user_id = v_c_auth;
delete from public.contas where id = v_c_conta;
reset role;

set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.profissionais <> 2 then
  raise exception 'FALHOU 6: contou % profissionais ativos (esperado 2)', v_faixa.profissionais;
end if;
if v_faixa.limite_total <> 16 then
  raise exception 'FALHOU 6: total % (esperado 8 × 2 = 16) — é assim que a linha da Clínica existe sem segunda coluna', v_faixa.limite_total;
end if;
if v_faixa.acima then
  raise exception 'FALHOU 6: 11 usadas em 16 marcou acima';
end if;

-- E agora a metade que é ausência: desligada, ela para de multiplicar.
set local role postgres;
update public.profissionais set ativo = false where id = v_prof2;
reset role;

set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.profissionais <> 1 then
  raise exception 'FALHOU 6: profissional desligada continuou multiplicando a faixa (% ativos)', v_faixa.profissionais;
end if;
if not v_faixa.acima then
  raise exception 'FALHOU 6: com uma profissional só, 11 usadas em 8 deixou de estar acima — o denominador estava contando quem não atende';
end if;
raise notice 'ok 6 · a faixa multiplica só por quem atende';

-- 7 · `pct` passa de 100, e é fato.
--
-- Mesma recusa do P5: passar do declarado não é elogio nem acusação. A função
-- não estanca em 100 — estancar esconderia a informação de quem precisa dela.
set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;
if v_faixa.pct <> 137 then
  raise exception 'FALHOU 7: pct % (esperado 137 = 11 de 8)', v_faixa.pct;
end if;
raise notice 'ok 7 · pct é fato, passa de 100, e não vem com elogio';

raise notice '--- parte 2 · o teto de mensagens saiu do produto ---';

-- 8 · Nenhum plano tem teto mensal de mensagens.  ← decide
select count(*)::integer into v_n from public.planos
 where limite_mensagens_mes is not null;
if v_n <> 0 then
  raise exception 'FALHOU 8: % plano(s) ainda com teto mensal de mensagens — a unidade cobrada é a sessão', v_n;
end if;
raise notice 'ok 8 · nenhum plano vende limite de disparo';

-- 9 · `avancar_fila` não pergunta mais pelo teto — e continua convidando.  ← decide
--
-- **`position()` e não `like`.** A primeira redação desta verificação usava
-- `like '%cabe_no_teto%'` e reprovou um comentário do corpo que diz "(cabe no
-- teto do plano?)": em `LIKE`, `_` é curinga de um caractere qualquer e casa com
-- espaço. Foi a quinta varredura desta obra a acusar código correto, e a
-- primeira por essa causa.
--
-- **A segunda metade é uma afirmação de PRESENÇA**, e é a primeira do projeto.
-- Ela existe porque `avancar_fila` já perdeu duas vezes a linha que enfileira a
-- mensagem — na 0046 e de novo na 0060 —, sempre por reescrita a partir da
-- migração errada. Sem ela, a oferta nasce, expira em quarenta minutos, a fila
-- avança, e o rastro diz que ninguém quis a vaga: ninguém foi convidado. É o
-- pior modo de falha do produto, e nenhum teste de teto o pega, porque o teto
-- funciona.
v_txt := pg_get_functiondef('public.avancar_fila(uuid)'::regprocedure);
if position('teto_da_conta' in v_txt) > 0 or position('cabe_no_teto' in v_txt) > 0 then
  raise exception 'FALHOU 9: avancar_fila voltou a consultar teto — a fila é o que o produto promete, e pará-la para economizar mensagem é parar a promessa';
end if;
if position('enfileirar_mensagem' in v_txt) = 0 then
  raise exception 'FALHOU 9: avancar_fila cria a oferta e não convida ninguém — é o defeito da 0046d, e já voltou uma vez';
end if;
raise notice 'ok 9 · a fila não pergunta pelo teto, e continua convidando';

-- 10 · O evento antigo continua existindo.
--
-- Não é nostalgia: `fila_pausada_no_teto` está gravado em eventos de agosto,
-- que aconteceram de verdade e explicam vagas que não foram oferecidas. Apagar
-- o valor do check apagaria a leitura da história.
select count(*)::integer into v_n
  from pg_constraint
 where conname = 'eventos_fila_tipo_check'
   and pg_get_constraintdef(oid) like '%fila_pausada_no_teto%';
if v_n <> 1 then
  raise exception 'FALHOU 10: o valor fila_pausada_no_teto sumiu do check — a história dos eventos antigos deixou de ser legível';
end if;
raise notice 'ok 10 · o evento antigo continua legível';

-- 11 · Com a faixa estourada, a mensagem sai.  ← decide
--
-- A conta A está com 11 de 8, ou seja, acima. Enfileiramos uma oferta de vaga —
-- que é justamente o template que a 0046 barrava — e exigimos que ela saia.
set local role postgres;
insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, estado, agendada_para)
  values (v_a_conta, v_ana, 'whatsapp', 'oferta_de_vaga', '5511900000601',
          'teste-0060-oferta', 'pendente', now() - interval '1 minute')
  returning id into v_msg;

perform public.reservar_mensagens(50);
reset role;

set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;
if not v_faixa.acima then
  raise exception 'FALHOU 11: o cenário não estourou a faixa (usadas %, total %)', v_faixa.usadas, v_faixa.limite_total;
end if;

select estado into v_txt from public.mensagens where id = v_msg;
if v_txt = 'barrada_no_teto' then
  raise exception 'FALHOU 11: a oferta de vaga foi barrada com a faixa estourada — quem paga o limite passou a ser a paciente';
end if;
raise notice 'ok 11 · faixa estourada e a oferta saiu assim mesmo (estado %)', v_txt;

raise notice '--- parte 3 · o freio técnico ---';

-- 12 · O freio não consulta plano.  ← decide
v_txt := pg_get_functiondef('public.teto_tecnico(uuid, uuid)'::regprocedure);
if position('public.planos' in v_txt) > 0 or position('limite_mensagens_mes' in v_txt) > 0 then
  raise exception 'FALHOU 12: teto_tecnico consulta plano — freio técnico que olha plano é produto disfarçado';
end if;
if position('limites_tecnicos' in v_txt) = 0 then
  raise exception 'FALHOU 12: teto_tecnico não lê limites_tecnicos — número em constante não se ajusta no dia em que estiver errado';
end if;
raise notice 'ok 12 · o freio é técnico, e não olha plano';

-- 13 · Conta parada não bate em freio.
set local role postgres;
select public.teto_tecnico(v_b_conta, null) into v_freio;
reset role;
if v_freio is not null then
  raise exception 'FALHOU 13: conta sem mensagem nenhuma bateu no freio %', v_freio;
end if;
raise notice 'ok 13 · conta parada não bate em freio nenhum';

-- 14 · O freio por conta/hora.
set local role postgres;
for v_k in 1..60 loop
  insert into public.mensagens
    (conta_id, paciente_id, canal, template, destino, chave_idem, estado,
     agendada_para, enviada_em)
    values (v_b_conta, v_cida, 'whatsapp', 'lembrete_de_sessao', '5511900000699',
            'teste-0060-hora-' || v_k, 'enviada', now(), now() - interval '2 minutes');
end loop;
select public.teto_tecnico(v_b_conta, null) into v_freio;
reset role;

if v_freio is distinct from 'mensagens_por_conta_hora' then
  raise exception 'FALHOU 14: 60 mensagens numa hora e o freio devolveu % (esperado mensagens_por_conta_hora)', coalesce(v_freio, 'nulo');
end if;
raise notice 'ok 14 · sessenta numa hora é laço, e o freio diz o nome';

-- 15 · O freio por paciente/dia, isolado do anterior.
set local role postgres;
delete from public.mensagens where conta_id = v_b_conta;
for v_k in 1..8 loop
  insert into public.mensagens
    (conta_id, paciente_id, canal, template, destino, chave_idem, estado,
     agendada_para, enviada_em)
    values (v_a_conta, v_bia, 'whatsapp', 'lembrete_de_sessao', '5511900000602',
            'teste-0060-dia-' || v_k, 'enviada', now(),
            (v_hoje + time '09:00') at time zone 'America/Sao_Paulo');
end loop;
select public.teto_tecnico(v_a_conta, v_bia) into v_freio;
reset role;

if v_freio is distinct from 'mensagens_por_paciente_dia' then
  raise exception 'FALHOU 15: oito mensagens para o mesmo paciente no dia e o freio devolveu %', coalesce(v_freio, 'nulo');
end if;
raise notice 'ok 15 · oito para a mesma pessoa num dia é defeito nosso, e o freio pega';

-- 16 · O freio pega template essencial também — e é a diferença doutrinária.
--
-- A 0046 protegia o essencial porque o que barrava era um limite COMERCIAL, e
-- deixar a paciente sem lembrete para proteger margem cobra de quem não
-- escolheu plano. Aqui o que barra é suspeita de laço, e oitenta lembretes
-- numa noite são piores para ela do que um lembrete que não chega.
set local role postgres;
insert into public.mensagens
  (conta_id, paciente_id, canal, template, destino, chave_idem, estado, agendada_para)
  values (v_a_conta, v_bia, 'whatsapp', 'lembrete_de_sessao', '5511900000602',
          'teste-0060-essencial', 'pendente', now() - interval '1 minute')
  returning id into v_msg;
perform public.reservar_mensagens(50);
select estado, erro into v_txt, v_erro from public.mensagens where id = v_msg;
reset role;

if v_txt <> 'barrada_no_teto' then
  raise exception 'FALHOU 16: lembrete passou pelo freio de oito por paciente/dia (estado %) — o freio é contra laço, e laço não distingue template', v_txt;
end if;
raise notice 'ok 16 · o freio pega o essencial também, porque laço não escolhe template';

-- 17 · A cliente não enxerga a tabela de freios.  ← decide
set local role authenticated;
select count(*)::integer into v_n from public.limites_tecnicos;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 17: a cliente leu % linha(s) de limites_tecnicos — freio é proteção contra bug, não cardápio', v_n;
end if;
raise notice 'ok 17 · o freio é invisível, como manda a linha 5 da política';

-- 18 · A barrada diz qual freio a segurou.
if v_erro is null or v_erro not like '%mensagens_por_paciente_dia%' then
  raise exception 'FALHOU 18: o erro da barrada foi "%" e não nomeia o freio — sem o nome eu abro o banco para descobrir no dia em que importa', coalesce(v_erro, 'nulo');
end if;
raise notice 'ok 18 · a mensagem barrada diz qual freio, pelo nome';

set local role postgres;
delete from public.mensagens where conta_id in (v_a_conta, v_b_conta);
reset role;

raise notice '--- parte 4 · a nota é do produto ---';

-- 19 · Nota fora da escala é recusada.
set local role authenticated;
begin
  perform public.registrar_avaliacao(11::smallint, null, 'perfil');
  raise exception 'FALHOU 19: aceitou nota 11';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 19 · nota fora de 0 a 10 é recusada (%)', left(v_erro, 60);

-- 20 · Os retratos são tirados pela função, e não recebidos.
--
-- Se o plano viesse por parâmetro, um cliente poderia informar outro — e a
-- leitura por plano viraria ficção.
set local role authenticated;
v_id := public.registrar_avaliacao(9::smallint, 'a fila salvou meu mês', 'perfil');
reset role;

select plano, sessoes_no_mes into v_txt, v_n from public.avaliacoes where id = v_id;
if v_txt <> 'gratis' then
  raise exception 'FALHOU 20: plano gravado % (esperado gratis)', v_txt;
end if;
if v_n <> 11 then
  raise exception 'FALHOU 20: sessões do mês gravadas % (esperado 11, com as 3 desmarcadas no prazo fora)', v_n;
end if;
raise notice 'ok 20 · a função tira os retratos sozinha';

-- 21 · Nota 0 e nota 10 não mudam nada.  ← decide
--
-- Duas contas no mesmo plano. Uma dá 0, a outra dá 10. Faixa, freio e plano têm
-- de responder exatamente igual — um produto que reage à nota está comprando a
-- nota, e a partir daí ela mede a reação e não o produto.
set local role postgres;
update public.contas set plano = 'gratis' where id in (v_a_conta, v_b_conta);
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_avaliacao(0::smallint, 'não serviu', 'perfil');
select * into v_faixa_b from public.faixa_da_conta(v_b_conta);
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
perform public.registrar_avaliacao(10::smallint, 'perfeito', 'perfil');
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;

if v_faixa.limite is distinct from v_faixa_b.limite then
  raise exception 'FALHOU 21: quem deu 10 tem limite % e quem deu 0 tem % — a nota comprou faixa', v_faixa.limite, v_faixa_b.limite;
end if;
if v_faixa.e_fair_use is distinct from v_faixa_b.e_fair_use then
  raise exception 'FALHOU 21: a nota mudou o regime da faixa';
end if;

set local role postgres;
select public.teto_tecnico(v_a_conta, null) into v_freio;
select public.teto_tecnico(v_b_conta, null) into v_txt;
select count(*)::integer into v_n from public.contas
 where id in (v_a_conta, v_b_conta) and plano = 'gratis';
reset role;

if v_freio is distinct from v_txt then
  raise exception 'FALHOU 21: o freio respondeu diferente para quem deu 0 e para quem deu 10';
end if;
if v_n <> 2 then
  raise exception 'FALHOU 21: a nota mexeu no plano de alguém — % das 2 contas continuam no gratis', v_n;
end if;
raise notice 'ok 21 · nota 0 e nota 10 não mudam nada do que o sistema faz';

-- 22 · Momento fora da lista fechada é recusado.  ← decide
--
-- É a lista de `momento` que impede pedir nota dentro de um cancelamento ou de
-- uma cobrança. Se ela aceitar texto livre, a regra vira convenção de tela, e
-- convenção de tela não sobrevive a seis meses.
set local role authenticated;
begin
  perform public.registrar_avaliacao(8::smallint, null, 'depois_de_cobrar');
  raise exception 'FALHOU 22: aceitou momento livre — a regra do momento de dor virou convenção';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 22 · momento é lista fechada, e momento novo é migração';

-- 23 · Conta nova não é convidada.
set local role authenticated;
v_j := public.avaliacao_pendente();
reset role;
if (v_j->>'pedir')::boolean then
  raise exception 'FALHOU 23: convidou uma conta de hoje a avaliar — a nota mediria o cadastro';
end if;
if v_j->>'motivo' <> 'conta nova' then
  raise exception 'FALHOU 23: motivo % (esperado "conta nova")', v_j->>'motivo';
end if;
raise notice 'ok 23 · conta nova não é convidada, e o motivo é dito';

-- 24 · Ninguém lê a nota e escreve na relação comercial.  ← decide
--
-- Varredura estreita: exige `avaliacoes` **e** uma escrita numa das quatro
-- tabelas juntas no mesmo corpo. `exportar_conta` cita `avaliacoes` e não
-- escreve; `nota_do_produto` cita `avaliacoes` e `contas` e só lê. Nenhuma das
-- duas pode ser acusada por esta redação.
select count(*)::integer into v_n
  from pg_proc pr
  join pg_namespace ns on ns.oid = pr.pronamespace
 where ns.nspname = 'public'
   and pg_get_functiondef(pr.oid) like '%avaliacoes%'
   and (pg_get_functiondef(pr.oid) like '%update public.contas%'
     or pg_get_functiondef(pr.oid) like '%update public.assinaturas%'
     or pg_get_functiondef(pr.oid) like '%update public.planos%'
     or pg_get_functiondef(pr.oid) like '%update public.faturas%'
     or pg_get_functiondef(pr.oid) like '%insert into public.faturas%');
if v_n <> 0 then
  raise exception 'FALHOU 24: % função(ões) leem a nota e escrevem na relação comercial — é o desconto por nota boa entrando pela porta dos fundos', v_n;
end if;
raise notice 'ok 24 · a nota não compra nada e não custa nada';

-- 25 · A nota não se edita nem se apaga.  ← decide
--
-- A nota de agosto é o que ela achava em agosto. Sem `update` e sem `delete` na
-- RLS: mudar de opinião registra uma nota nova, e as duas ficam.
set local role authenticated;
update public.avaliacoes set nota = 10 where conta_id = v_a_conta;
get diagnostics v_n = row_count;
if v_n <> 0 then
  raise exception 'FALHOU 25: editou % avaliação(ões) — a nota virou opinião reescrita', v_n;
end if;
delete from public.avaliacoes where conta_id = v_a_conta;
get diagnostics v_n = row_count;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 25: apagou % avaliação(ões)', v_n;
end if;
raise notice 'ok 25 · a nota não se reescreve nem se apaga';

-- 26 · A nota sai na exportação.
set local role authenticated;
v_j := public.exportar_conta();
reset role;
if v_j->'avaliacoes' is null then
  raise exception 'FALHOU 26: a exportação não tem a chave avaliacoes — coletar sobre alguém e não devolver é o que esse arquivo existe para não ser';
end if;
if jsonb_array_length(v_j->'avaliacoes') <> 2 then
  raise exception 'FALHOU 26: exportou % avaliações (esperado 2)', jsonb_array_length(v_j->'avaliacoes');
end if;
if (v_j->'avaliacoes'->0) ? 'conta_id' then
  raise exception 'FALHOU 26: a exportação carregou conta_id junto';
end if;
raise notice 'ok 26 · a nota e o texto dela saem na exportação';

-- 27 · NPS é nulo com amostra pequena.
--
-- Com três respostas o NPS anda 66 pontos por pessoa. Um número que se move
-- assim vira decisão errada com cara de medida — e o portão 1→2 do doc 04 pede
-- cinco justamente por isso.
-- `set local role postgres` **não** torna ninguém operador: `e_operador()` lê
-- `usuarios.operador` pelo `auth.uid()` do JWT, e o JWT aqui ainda é o da conta
-- A. É o porteiro funcionando — então a suíte veste o crachá de propósito, e o
-- devolve antes da verificação 29, que prova que sem ele não se lê nada.
set local role postgres;
update public.contas set is_teste = false where id in (v_a_conta, v_b_conta);
update public.usuarios set operador = true where auth_user_id = v_a_auth;
reset role;

set local role authenticated;
select public.nota_do_produto(v_hoje - 1, v_hoje + 1) into v_j;
reset role;

set local role postgres;
update public.usuarios set operador = false where auth_user_id = v_a_auth;
reset role;
if v_j->'nps' <> 'null'::jsonb then
  raise exception 'FALHOU 27: NPS veio % com % respostas — abaixo de cinco ele é ruído com cara de medida', v_j->>'nps', v_j->>'n';
end if;
if (v_j->>'n')::integer < 3 then
  raise exception 'FALHOU 27: a leitura não enxergou as notas (n = %)', v_j->>'n';
end if;
if v_j->'distribuicao' = '{}'::jsonb then
  raise exception 'FALHOU 27: a distribuição veio vazia — média sem distribuição esconde dois produtos diferentes';
end if;
raise notice 'ok 27 · NPS nulo com amostra pequena, e a distribuição inteira aparece';

raise notice '--- parte 5 · as trancas ---';

-- 28 · A vizinha não lê a faixa nem a nota da outra.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
begin
  perform * from public.faixa_da_conta(v_a_conta);
  reset role;
  raise exception 'FALHOU 28: a vizinha leu a faixa da outra';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

set local role authenticated;
select count(*)::integer into v_n from public.avaliacoes where conta_id = v_a_conta;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 28: a vizinha leu % avaliação(ões) da outra', v_n;
end if;
raise notice 'ok 28 · faixa e nota são de quem pergunta';

-- 29 · Quem não é operador não lê o agregado.
set local role authenticated;
begin
  perform public.nota_do_produto(v_hoje - 30, v_hoje);
  reset role;
  raise exception 'FALHOU 29: uma cliente leu a nota agregada de todas';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

set local role authenticated;
begin
  perform * from public.contas_acima_da_faixa();
  reset role;
  raise exception 'FALHOU 29: uma cliente leu a lista de contas acima da faixa';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 29 · o agregado é do operador';

-- 30 · O anônimo não executa nada.
perform set_config('request.jwt.claims', null, true);
set local role anon;
begin
  perform public.avaliacao_pendente();
  reset role;
  raise exception 'FALHOU 30: o anônimo executou avaliacao_pendente';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;

set local role anon;
begin
  perform * from public.faixa_da_conta(v_a_conta);
  reset role;
  raise exception 'FALHOU 30: o anônimo leu a faixa';
exception when others then
  v_erro := sqlerrm;
  if v_erro like 'FALHOU%' then raise; end if;
end;
reset role;
raise notice 'ok 30 · o anônimo não executa nada disto';

-- ============================================================ recolher o rastro
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.avaliacoes where conta_id in (v_a_conta, v_b_conta);
delete from public.mensagens where conta_id in (v_a_conta, v_b_conta);
delete from public.eventos_fila where conta_id in (v_a_conta, v_b_conta);
delete from public.ofertas where conta_id in (v_a_conta, v_b_conta);
delete from public.propostas_de_cobranca where conta_id in (v_a_conta, v_b_conta);
delete from public.cobrancas where conta_id in (v_a_conta, v_b_conta);
delete from public.sessoes where conta_id in (v_a_conta, v_b_conta);
delete from public.enquadres where conta_id in (v_a_conta, v_b_conta);
delete from public.pacientes where conta_id in (v_a_conta, v_b_conta);
delete from public.profissionais where conta_id in (v_a_conta, v_b_conta);
delete from public.usuarios where conta_id in (v_a_conta, v_b_conta);
delete from auth.users where id in (v_a_auth, v_b_auth, v_c_auth);
delete from public.contas where nome in ('Faixa Teste', 'Faixa Vizinha', 'Faixa Dupla');
reset role;

raise notice 'SUITE 0060 PASSOU: 30 verificações';
end $do$;
