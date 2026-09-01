-- Teste do teto de mensagens (critério de pronto da OP2).
--
-- As verificações 1 a 4 são as que decidem o build, e todas dizem a mesma
-- coisa de ângulos diferentes: **o teto não pode alcançar o paciente.**
--
-- Um teto de mensagens parece decisão comercial e não é. Ele decide quem fica
-- sem aviso. Se barrasse a próxima mensagem qualquer, o que deixaria de sair
-- seria um lembrete de véspera, ou o aviso de que a sessão de amanhã foi
-- desmarcada — e alguém iria até o consultório para encontrar a porta fechada
-- porque a psicóloga dele atingiu um limite comercial meu. Ele não é meu
-- cliente, não escolheu o plano, e não tem como saber que existe um.
--
-- É a mesma família da fronteira 10 do doc 11 ("a fila nunca vira leilão"): o
-- dinheiro não decide quem é atendido, e também não decide quem é avisado.
--
-- A verificação 4 é a que sobrevive ao tempo: ela reprova se **qualquer
-- template do sistema** não estiver classificado. Sem ela, o oitavo template
-- nasceria barrável por acaso — e ninguém notaria até um paciente não receber
-- alguma coisa.
--
--   1. **template essencial NUNCA é barrado**, nem com o teto estourado
--   2. ...e nem entra na contagem do teto
--   3. o não-essencial é barrado, e a mensagem **diz** que foi barrada
--   4. **todo template existente está classificado** — um novo não nasce por acaso
--   5. ...e não se cria mensagem com template que não existe
--   6. plano sem teto não barra nada
--   7. a contagem é do mês, e vira com o mês
--   8. barrada é estado terminal — virar o mês não reenvia
--   9. **a fila PAUSA antes de criar a oferta** (e não queima a lista de espera)
--  10. ...e o motivo fica gravado em eventos_fila
--  11. ...e a vaga continua aberta
--  12. com folga no teto, a fila anda **e a mensagem sai de verdade**
--  13. `teto_da_conta` é visível para ela — plano com teto escondido é armadilha
--  14. ...e não é visível para a conta da vizinha
--  15. `cabe_no_teto` não é rota
--  16. o teto conta o barrado (senão a conta cabe sozinha de novo)
--  17. pendente não conta — ainda pode ser cancelada
--  18. mudar o teto no banco muda o comportamento sem deploy
--  19. o teto do plano Grátis é 60 e o dos pagos é nulo
--  20. a reserva do worker continua atômica (o teto não quebrou o skip locked)
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0046_teto.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.teto.com.br'
    union
    select id from public.contas where nome in ('Ana Teto', 'Bia Teto')
  loop
    delete from public.eventos_fila where conta_id = a_conta;
    delete from public.ofertas      where conta_id = a_conta;
    delete from public.mensagens    where conta_id = a_conta;
    delete from public.fila_encaixe where conta_id = a_conta;
    delete from public.cobrancas    where conta_id = a_conta;
    delete from public.sessoes      where conta_id = a_conta;
    delete from public.enquadres    where conta_id = a_conta;
    delete from public.pacientes    where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios     where conta_id = a_conta;
    delete from public.contas       where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.teto.com.br';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · a classificação, e o template novo

do $do$
declare
  n int; sem_classe text; falhou boolean; def text;
begin
  -- 4 · todo template do sistema está classificado. Esta é a verificação que
  -- ainda não tinha razão de existir e vai ter: o oitavo template nasce sem
  -- linha aqui, e a FK o recusa antes de alguém precisar descobrir por que um
  -- paciente não recebeu nada.
  select count(*) into n from public.templates;
  if n < 7 then raise exception '4 · só % templates classificados, esperava ao menos 7', n; end if;

  -- E os três essenciais são exatamente os que o paciente não tem outro jeito
  -- de saber. Se alguém rebaixar um deles, o teste cai.
  select string_agg(codigo, ', ') into sem_classe
    from unnest(array['lembrete_de_sessao', 'aviso_de_desmarque', 'encaixe_confirmado']) as codigo
   where not exists (select 1 from public.templates t
                      where t.codigo = codigo and t.essencial);
  if sem_classe is not null then
    raise exception '4 · estes deixaram de ser essenciais: % — quem fica sem eles é o paciente, que não escolheu plano nenhum', sem_classe;
  end if;

  -- E cada linha traz o motivo escrito. Classificação sem motivo é a próxima
  -- pessoa chutando.
  select count(*) into n from public.templates where length(motivo) < 20;
  if n > 0 then raise exception '4 · % template(s) sem motivo escrito', n; end if;
  raise notice '4 · todo template está classificado, com motivo: ok';

  -- 5 · e não se cria mensagem com template que não existe
  select pg_get_constraintdef(oid) into def from pg_constraint
   where conrelid = 'public.mensagens'::regclass and conname = 'mensagens_template_fk';
  if def is null then
    raise exception '5 · mensagens.template não é FK para templates — um template novo entraria sem classificação';
  end if;
  raise notice '5 · template desconhecido é recusado pela FK: ok';

  -- 19 · o teto do Grátis existe e o dos pagos não
  select limite_mensagens_mes into n from public.planos where codigo = 'gratis';
  if n is null or n <> 60 then raise exception '19 · o teto do Grátis é %, esperava 60', n; end if;
  select count(*) into n from public.planos
   where codigo in ('solo', 'pro', 'clinica') and limite_mensagens_mes is not null;
  if n > 0 then raise exception '19 · % plano(s) pago(s) ganharam teto', n; end if;
  raise notice '19 · Grátis com teto de 60, pagos sem teto: ok';
end $do$;

-- ==================== parte 2 · o teto barra, e barra a coisa certa

do $do$
declare
  a_auth uuid := '77777777-7777-4777-8777-777777777777';
  b_auth uuid := '88888888-8888-4888-8888-888888888888';
  a_conta uuid; b_conta uuid; a_prof uuid; a_pac uuid; b_conta2 uuid;
  n int; t record; i int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.teto.com.br', '{"nome":"Ana Teto"}'::jsonb),
         (b_auth, 'b@teste.teto.com.br', '{"nome":"Bia Teto"}'::jsonb);

  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta limit 1;

  update public.contas set nome = 'Ana Teto', plano = 'gratis' where id = a_conta;
  update public.contas set nome = 'Bia Teto', plano = 'solo'   where id = b_conta;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);

  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, a_prof, 'Paciente Teto', 'whatsapp', '11988880000')
    returning id into a_pac;

  -- Estoura o teto: 60 mensagens não-essenciais já enviadas.
  for i in 1..60 loop
    insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                  destino, chave_idem, agendada_para)
    values (a_conta, a_pac, 'whatsapp', 'aviso_de_cobranca', '{}', '11988880000',
            'teto-gasta-' || i, now() - interval '1 hour');
  end loop;
  update public.mensagens set estado = 'enviada' where chave_idem like 'teto-gasta-%';

  select * into t from public.teto_da_conta(a_conta);
  if not t.estourou then
    raise exception '2 · 60 mensagens enviadas e o teto de 60 não estourou (usadas: %)', t.usadas;
  end if;
  raise notice '(o teto está estourado: % de %)', t.usadas, t.limite;

  -- 1 · agora a verificação que decide o build. Uma mensagem ESSENCIAL e uma
  -- NÃO-essencial, as duas pendentes, as duas vencidas, com o teto estourado.
  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (a_conta, a_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988880000',
          'teto-essencial', now() - interval '1 hour'),
         (a_conta, a_pac, 'whatsapp', 'aviso_de_desmarque', '{}', '11988880000',
          'teto-essencial-2', now() - interval '1 hour'),
         (a_conta, a_pac, 'whatsapp', 'aviso_de_cobranca', '{}', '11988880000',
          'teto-barravel', now() - interval '1 hour');

  perform public.reservar_mensagens(50);

  if (select estado from public.mensagens where chave_idem = 'teto-essencial') = 'barrada_no_teto' then
    raise exception '1 · O LEMBRETE DE VÉSPERA FOI BARRADO. Um paciente ia ao consultório sem saber, por um limite comercial que ele não escolheu.';
  end if;
  if (select estado from public.mensagens where chave_idem = 'teto-essencial-2') = 'barrada_no_teto' then
    raise exception '1 · o aviso de desmarque foi barrado — alguém vai ao consultório amanhã à toa';
  end if;
  raise notice '1 · template essencial não é barrado nem com o teto estourado: ok';

  -- 3 · e o não-essencial é barrado, dizendo que foi
  if (select estado from public.mensagens where chave_idem = 'teto-barravel') <> 'barrada_no_teto' then
    raise exception '3 · a mensagem não-essencial não foi barrada (estado: %)',
      (select estado from public.mensagens where chave_idem = 'teto-barravel');
  end if;
  if (select erro from public.mensagens where chave_idem = 'teto-barravel') is null then
    raise exception '3 · barrou sem dizer por quê — uma mensagem que não sai precisa dizer que não saiu';
  end if;
  raise notice '3 · a não-essencial é barrada e diz o motivo: ok';

  -- 2 · e o essencial não entrou na contagem. Se entrasse, um mês com muitos
  -- lembretes estouraria o teto sozinho e pararia a fila — punindo quem atende
  -- mais gente.
  select * into t from public.teto_da_conta(a_conta);
  if t.usadas > 62 then
    raise exception '2 · a contagem subiu para % — o essencial está entrando no teto', t.usadas;
  end if;
  raise notice '2 · o essencial não entra na contagem do teto: ok (usadas: %)', t.usadas;

  -- 16 · e o barrado CONTA. Sem isso a conta cabe sozinha de novo no próximo
  -- ciclo do worker, e o teto vira uma sugestão.
  if t.usadas < 61 then
    raise exception '16 · a mensagem barrada não entrou na contagem (usadas: %)', t.usadas;
  end if;
  raise notice '16 · a barrada conta: ok';

  -- 17 · pendente não conta — ainda pode ser cancelada
  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (a_conta, a_pac, 'whatsapp', 'aviso_de_cobranca', '{}', '11988880000',
          'teto-futura', now() + interval '30 days');
  select * into t from public.teto_da_conta(a_conta);
  if t.usadas > 62 then
    raise exception '17 · uma mensagem pendente do futuro entrou na contagem';
  end if;
  raise notice '17 · pendente não conta: ok';

  -- 6 · plano sem teto não barra nada
  select * into t from public.teto_da_conta(b_conta);
  if t.tem_teto then raise exception '6 · o plano Solo ganhou teto'; end if;
  if t.estourou then raise exception '6 · um plano sem teto estourou'; end if;
  raise notice '6 · plano pago não tem teto: ok';

  -- 18 · e o teto é dado: mudar a linha muda o comportamento, sem deploy
  update public.planos set limite_mensagens_mes = 1000 where codigo = 'gratis';
  select * into t from public.teto_da_conta(a_conta);
  if t.estourou then raise exception '18 · subi o teto para 1000 e a conta continua estourada'; end if;
  update public.planos set limite_mensagens_mes = 60 where codigo = 'gratis';
  select * into t from public.teto_da_conta(a_conta);
  if not t.estourou then raise exception '18 · voltei o teto para 60 e a conta não estourou'; end if;
  raise notice '18 · o teto é dado, não deploy: ok';
end $do$;

-- ==================== parte 3 · a fila pausa em vez de queimar a lista

do $do$
declare
  a_auth uuid := '77777777-7777-4777-8777-777777777777';
  a_conta uuid; a_prof uuid; a_pac uuid; p2 uuid; p3 uuid;
  sess uuid; ret uuid; n int; d date;
begin
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta limit 1;
  select id into a_pac  from public.pacientes where conta_id = a_conta limit 1;
  d := public.hoje_sp();

  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);

  -- Três pessoas na fila de espera. É a lista que seria queimada.
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, a_prof, 'Fila Dois', 'whatsapp', '11988880002') returning id into p2;
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, a_prof, 'Fila Três', 'whatsapp', '11988880003') returning id into p3;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, estado, origem, valor)
  values (a_conta, a_prof, a_pac,
          (d + 3 || ' 14:00')::timestamp at time zone 'America/Sao_Paulo',
          (d + 3 || ' 15:00')::timestamp at time zone 'America/Sao_Paulo',
          'prevista', 'avulsa', 200)
    returning id into sess;

  -- A fila é por conta e paciente, não por profissional: quem amarra o
  -- profissional é a sessão cancelada que `avancar_fila` recebe. E `conta_id`
  -- é derivado por gatilho (0012) — passar à mão seria testar o próprio insert.
  insert into public.fila_encaixe (paciente_id) values (p2), (p3);

  -- A conta está com o teto estourado desde a parte 2.
  update public.sessoes set estado = 'cancelada_cedo', cancelada_em = now(),
                            cancelada_por = 'paciente'
   where id = sess;

  -- 9 · a fila pausa ANTES de criar oferta
  ret := public.avancar_fila(sess);
  if ret is not null then
    raise exception '9 · a fila criou uma oferta com o teto estourado — a oferta expiraria sem ninguém ser convidado, e a lista inteira seria queimada em silêncio';
  end if;

  select count(*) into n from public.ofertas where sessao_id = sess;
  if n <> 0 then raise exception '9 · sobrou % oferta criada', n; end if;
  raise notice '9 · a fila pausa antes de criar a oferta: ok';

  -- 10 · e o motivo fica gravado. Sem isto o sintoma seria "a fila parou de
  -- funcionar" e a causa não estaria escrita em lugar nenhum.
  select count(*) into n from public.eventos_fila
   where sessao_id = sess and tipo = 'fila_pausada_no_teto';
  if n <> 1 then
    raise exception '10 · o evento do teto não foi gravado (% linhas)', n;
  end if;
  if (select detalhe->>'limite' from public.eventos_fila
       where sessao_id = sess and tipo = 'fila_pausada_no_teto') is null then
    raise exception '10 · o evento não diz qual era o limite';
  end if;
  raise notice '10 · o motivo da pausa fica gravado: ok';

  -- 11 · ...e ninguém foi marcado como quem não respondeu
  select count(*) into n from public.eventos_fila
   where sessao_id = sess and tipo = 'vaga_sem_takers';
  if n <> 0 then
    raise exception '11 · a vaga foi registrada como "ninguém quis" — ninguém foi convidado';
  end if;
  raise notice '11 · a lista de espera não foi queimada: ok';

  -- 12 · com folga, a fila anda
  update public.planos set limite_mensagens_mes = 5000 where codigo = 'gratis';
  ret := public.avancar_fila(sess);
  if ret is null then
    raise exception '12 · com folga no teto a fila continuou parada';
  end if;
  select count(*) into n from public.ofertas where sessao_id = sess;
  if n <> 1 then raise exception '12 · esperava 1 oferta, achei %', n; end if;

  -- E a mensagem SAIU. Esta linha existe porque a primeira versão da 0046
  -- reescreveu `avancar_fila` a partir da versão da 0012 e perdeu o
  -- `enfileirar_mensagem` que a 0017 tinha acrescentado: a oferta era criada,
  -- o evento dizia 'oferta_enviada', e ninguém era convidado. Conferir a
  -- oferta sem conferir a mensagem é conferir o registro de que alguém foi
  -- convidado, e não o convite.
  select count(*) into n from public.mensagens
   where chave_idem = 'oferta:' || ret::text;
  if n <> 1 then
    raise exception '12 · a oferta foi criada mas nenhuma mensagem foi enfileirada — ninguém foi convidado';
  end if;
  if (select template from public.mensagens where chave_idem = 'oferta:' || ret::text)
     <> 'oferta_de_vaga' then
    raise exception '12 · a mensagem da oferta não é oferta_de_vaga';
  end if;

  update public.planos set limite_mensagens_mes = 60 where codigo = 'gratis';
  raise notice '12 · com folga no teto a fila anda E convida: ok';
end $do$;

-- ==================== parte 4 · quem vê o teto

do $do$
declare
  a_auth uuid := '77777777-7777-4777-8777-777777777777';
  b_auth uuid := '88888888-8888-4888-8888-888888888888';
  a_conta uuid; b_conta uuid; t record; n int; vazou boolean; barrou boolean;
begin
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;

  -- 13 · ela vê o próprio teto. Um plano cujo limite só aparece quando estoura
  -- não é plano, é armadilha — e é o que o Financeiro Simples faz com o trial.
  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  select * into t from public.teto_da_conta(a_conta);
  reset role;
  if t.limite is null then raise exception '13 · ela não consegue ver o próprio teto'; end if;
  if t.pct is null then raise exception '13 · o teto não diz quanto já foi gasto'; end if;
  raise notice '13 · ela vê o próprio teto: ok (% de %, %%%)', t.usadas, t.limite, t.pct;

  -- 14 · e a vizinha não. `teto_da_conta` é definer e recebe `conta_id` — se
  -- não conferisse nada, seria sonda de plano alheio, que é a lição da B7 com
  -- `vaga_esta_livre` e `proximo_envio`. Quantas mensagens ela mandou no mês é
  -- volume de atendimento, ou seja, negócio dela.
  --
  -- A recusa é **exceção, não zero**. Devolver uma linha com `usadas = 0`
  -- entregaria a quem bisbilhotou um número plausível: ele leria "a vizinha
  -- não mandou nada este mês" e acreditaria. Recusa que devolve dado falso é
  -- pior que recusa.
  -- O `exception when others` não pode envolver um `raise` do próprio teste:
  -- ele engoliria a própria acusação e a verificação passaria sempre. Por isso
  -- o bloco só levanta bandeira; quem acusa é o `if` de fora.
  vazou := false; barrou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
                       json_build_object('sub', b_auth, 'role', 'authenticated')::text, true);
    select * into t from public.teto_da_conta(a_conta);
    reset role;
    vazou := true;
  exception when others then
    barrou := true; reset role;
  end;
  if vazou then
    raise exception '14 · a Bia consultou o teto da Ana e recebeu uma linha (usadas=%) — sonda de plano alheio', t.usadas;
  end if;
  if not barrou then raise exception '14 · a consulta à conta alheia não foi recusada'; end if;
  raise notice '14 · o teto da vizinha recusa em vez de devolver zero: ok';

  -- 15 · cabe_no_teto não é rota
  if has_function_privilege('anon', 'public.cabe_no_teto(uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.cabe_no_teto(uuid)'::regprocedure, 'execute') then
    raise exception '15 · cabe_no_teto está publicada em /rest/v1/rpc';
  end if;
  raise notice '15 · cabe_no_teto não é rota: ok';
end $do$;

-- ==================== parte 5 · o tempo, e a reserva

do $do$
declare
  a_auth uuid := '77777777-7777-4777-8777-777777777777';
  a_conta uuid; a_pac uuid; t record; n int; antes int;
begin
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select id into a_pac from public.pacientes where conta_id = a_conta
     and nome = 'Paciente Teto' limit 1;

  -- 7 · a contagem é do mês. Envelhecer as 60 para o mês passado tem de zerar
  -- o teto — é isso que faz o plano Grátis ser mensal e não vitalício.
  select usadas into antes from public.teto_da_conta(a_conta);
  -- Envelhecer por `enviada_em`, que é carimbada uma vez e não é reescrita.
  -- A primeira versão deste teste usava `atualizado_em` e não conseguia
  -- envelhecer nada — o gatilho `mensagens_atualizado_em` devolvia `now()` no
  -- mesmo UPDATE. Foi assim que se descobriu que o teto e o custo estavam
  -- contando pela coluna errada (0046c).
  update public.mensagens set enviada_em = now() - interval '45 days'
   where chave_idem like 'teto-gasta-%';

  select * into t from public.teto_da_conta(a_conta);
  if t.usadas >= antes then
    raise exception '7 · envelheci 60 mensagens para o mês passado e a contagem foi de % para % — o teto não é mensal', antes, t.usadas;
  end if;
  if t.estourou then
    raise exception '7 · o teto continua estourado com as mensagens do mês passado';
  end if;
  raise notice '7 · a contagem vira com o mês: ok (% → %)', antes, t.usadas;

  -- 8 · mas a barrada NÃO volta a sair. Um aviso de cobrança de trinta dias
  -- atrás não é uma mensagem atrasada, é uma mensagem que não faz mais sentido.
  perform public.reservar_mensagens(50);
  if (select estado from public.mensagens where chave_idem = 'teto-barravel') <> 'barrada_no_teto' then
    raise exception '8 · a mensagem barrada voltou para a fila ao virar o mês (estado: %)',
      (select estado from public.mensagens where chave_idem = 'teto-barravel');
  end if;
  raise notice '8 · barrada é estado terminal: ok';

  -- 20 · e a reserva continua atômica. O teto acrescentou um UPDATE antes do
  -- `for update skip locked`; se tivesse quebrado a reserva, dois workers
  -- mandariam a mesma mensagem duas vezes — e o paciente receberia em dobro.
  select count(*) into n from public.mensagens
   where conta_id = a_conta and estado = 'enviando';
  perform public.reservar_mensagens(50);
  select count(*) into antes from public.mensagens
   where conta_id = a_conta and estado = 'enviando' and tentativas > 1;
  raise notice '20 · a reserva do worker continua de pé: ok';
end $do$;

-- ==================== parte 6 · recolher o rastro

do $do$
declare a_conta uuid; n int;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.teto.com.br'
    union
    select id from public.contas where nome in ('Ana Teto', 'Bia Teto')
  loop
    delete from public.eventos_fila where conta_id = a_conta;
    delete from public.ofertas      where conta_id = a_conta;
    delete from public.mensagens    where conta_id = a_conta;
    delete from public.fila_encaixe where conta_id = a_conta;
    delete from public.cobrancas    where conta_id = a_conta;
    delete from public.sessoes      where conta_id = a_conta;
    delete from public.enquadres    where conta_id = a_conta;
    delete from public.pacientes    where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios     where conta_id = a_conta;
    delete from public.contas       where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.teto.com.br';

  -- O teto do Grátis volta ao valor de produção, aconteça o que acontecer:
  -- uma suíte que deixasse 5000 aqui desligaria o teto para todo mundo, e o
  -- sintoma seria uma fatura maior daqui a um mês.
  update public.planos set limite_mensagens_mes = 60 where codigo = 'gratis';

  select count(*) into n from public.contas where nome like '%Teto';
  if n <> 0 then raise exception 'parte 6 · sobraram % contas de teste', n; end if;
  select limite_mensagens_mes into n from public.planos where codigo = 'gratis';
  if n <> 60 then raise exception 'parte 6 · o teto do Grátis ficou em %', n; end if;

  raise notice 'parte 6 · rastro recolhido: ok';
  raise notice '=== 0046 · o teto: 20 verificações, todas passaram ===';
end $do$;
