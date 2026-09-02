-- Teste do teto de mensagens — depois que ele deixou de ser produto (OP8).
--
-- Esta suíte muda de sinal, e é preciso dizer por quê antes de qualquer linha
-- de SQL, porque metade das verificações que existiam aqui passou a afirmar o
-- contrário do que afirmava.
--
-- A 0060 desfez o teto de mensagens como produto. É o mesmo movimento que o P4
-- fez sobre a suíte 0022: **não por defeito, por decisão.** A 0046 estava certa
-- dentro da própria premissa; o que caiu foi a premissa. A coluna
-- `limite_mensagens_mes` é null em todos os planos, e ela e a máquina ficam de
-- pé, provadas e desligadas — exatamente o que a 0048 fez com
-- `limite_pacientes_ativos`. É `update`, não `drop`.
--
-- **A doutrina antiga não foi abandonada. Ela venceu.**
--
-- O cabeçalho antigo deste arquivo dizia, e continua valendo palavra por
-- palavra: *"um teto de mensagens parece decisão comercial e não é — ele decide
-- quem fica sem aviso"*. O que a 0046 conseguiu foi blindar o essencial contra
-- esse limite. O que a 0060 fez foi mais: **o limite que alcançava o paciente
-- deixou de existir.** Não há mais lembrete a blindar, porque não há mais
-- limite comercial nenhum barrando mensagem. A verificação 1 desta suíte é a
-- forma forte da verificação 1 da suíte anterior.
--
-- E é a mesma família da fronteira 10 do doc 11 ("a fila nunca vira leilão"):
-- o dinheiro não decide quem é atendido, e também não decide quem é avisado.
-- Agora ele não decide nem por engano, porque não há número para estourar.
--
-- ## O teto que sobrou mudou de eixo, e pega o essencial de propósito
--
-- O freio que existe hoje é técnico e mora em `public.limites_tecnicos`, medido
-- por **hora e por dia**, não por mês: um mês cheio nunca estoura um teto
-- horário, um laço estoura em segundos. Ele pega **template essencial também**,
-- e isso não contradiz a verificação 3: o que barra deixou de ser limite
-- comercial e passou a ser **suspeita de laço**. Um laço que manda oitenta
-- lembretes para a mesma pessoa numa noite é pior para ela do que um lembrete
-- que não chega. A verificação 14 prova isso, e a 3 continua provando que
-- nenhum limite de plano a alcança.
--
-- ## Duas cicatrizes de escrita, obedecidas aqui
--
--   · **toda variável leva `v_`.** A 0060 aplicou com sucesso e deixou três
--     funções quebradas porque `fim` é variável e é também coluna de `sessoes`
--     — em plpgsql a variável ganha da coluna (0060b). Nenhuma variável deste
--     arquivo se chama `fim`, `inicio`, `nota`, `plano`, `valor` ou `estado`, e
--     nenhum alias tem uma letra só;
--   · **varredura de corpo de função usa `position(... in ...)`, nunca `like`.**
--     Em `LIKE` o `_` é curinga de um caractere qualquer e casa com espaço: foi
--     assim que a verificação 9 da suíte 0060 acusou código correto, casando
--     `%cabe_no_teto%` com o comentário *"(cabe no teto do plano?) saiu aqui"*
--     (0060d). Foi a quinta varredura desta obra a reprovar código certo.
--
--   parte 1 · a máquina desligada
--     1. nenhum plano tem teto mensal de mensagens                  ← decide
--     2. a coluna e o comentário dela continuam existindo
--
--   parte 2 · o essencial sai, e o catálogo continua íntegro
--     3. template essencial nunca é barrado por limite comercial
--     4. todo template existente continua classificado
--     5. ...e não se cria mensagem com template que não existe
--
--   parte 3 · o não-essencial também sai agora
--     6. oferta de vaga e aviso de cobrança são reservados          ← decide
--     7. `teto_da_conta` responde tem_teto = false nos quatro planos
--
--   parte 4 · a fila não pausa mais
--     8. `avancar_fila` não consulta teto, e a vaga vira oferta     ← decide
--     9. ...e continua chamando `enfileirar_mensagem`               ← decide
--    10. `fila_pausada_no_teto` continua no check de eventos_fila
--
--   parte 5 · o freio que sobrou é técnico
--    11. o freio existe em tabela, com motivo escrito em cada linha
--    12. o freio por conta/hora dispara no número e diz o nome
--    13. o freio por paciente/dia dispara no número e diz o nome
--    14. o freio pega o essencial também — e é de propósito
--    15. a cliente não enxerga `limites_tecnicos`                   ← decide
--    16. a barrada diz qual freio a segurou, no campo `erro`
--
--   parte 6 · as trancas e a reserva
--    17. `cabe_no_teto` não é rota
--    18. `teto_tecnico` também não é rota
--    19. `teto_tecnico` não consulta `public.planos`                ← decide
--    20. a reserva do worker continua atômica
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0046_teto.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare v_conta uuid;
begin
  for v_conta in
    select distinct usr.conta_id from public.usuarios usr
     where usr.email like '%@teste.teto.com.br'
    union
    select ct.id from public.contas ct where ct.nome in ('Ana Teto', 'Bia Teto')
  loop
    delete from public.eventos_fila where conta_id = v_conta;
    delete from public.ofertas      where conta_id = v_conta;
    delete from public.mensagens    where conta_id = v_conta;
    delete from public.fila_encaixe where conta_id = v_conta;
    delete from public.cobrancas    where conta_id = v_conta;
    delete from public.sessoes      where conta_id = v_conta;
    delete from public.enquadres    where conta_id = v_conta;
    delete from public.pacientes    where conta_id = v_conta;
    delete from public.profissionais where conta_id = v_conta;
    delete from public.usuarios     where conta_id = v_conta;
    delete from public.contas       where id = v_conta;
  end loop;
  delete from auth.users where email like '%@teste.teto.com.br';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · a máquina desligada, não apagada

do $do$
declare
  v_com_teto   text;
  v_n          integer;
  v_comentario text;
begin
  -- 1 · nenhum plano tem teto mensal de mensagens.  ← decide
  --
  -- Esta é a forma forte da verificação 1 antiga. Lá se provava que o essencial
  -- escapava do limite comercial; aqui se prova que **não há limite comercial
  -- de mensagem para escapar**. A unidade cobrada é a sessão, e ela mora em
  -- `planos.limite_sessoes_mes`, medida e não aplicada (suíte 0060).
  --
  -- Se um plano voltar a ter número aqui, o que volta junto é a fila parada no
  -- mês cheio e o aviso de cobrança que não sai — ou seja, a paciente pagando
  -- por um limite que ela não escolheu.
  select string_agg(pl.codigo, ', ' order by pl.codigo) into v_com_teto
    from public.planos pl
   where pl.limite_mensagens_mes is not null;
  if v_com_teto is not null then
    raise exception '1 · voltaram a vender limite de disparo: % — a unidade cobrada é a sessão, e um teto de mensagem só se conhece depois de estourar, o que não é plano, é surpresa', v_com_teto;
  end if;
  raise notice '1 · nenhum plano tem teto mensal de mensagens: ok';

  -- 2 · e a máquina continua no lugar, desligada.
  --
  -- Mesmo critério da 0048 com `limite_pacientes_ativos`: a coluna está provada
  -- por suíte e nenhum plano a usa. Apagá-la trocaria um `update` por uma
  -- migração no dia em que um plano precisasse de teto mensal outra vez. E o
  -- comentário é o que impede a próxima pessoa achar que a coluna é resto de
  -- código morto e derrubá-la numa faxina.
  select count(*) into v_n
    from pg_attribute pga
   where pga.attrelid = 'public.planos'::regclass
     and pga.attname = 'limite_mensagens_mes'
     and pga.attnum > 0
     and not pga.attisdropped;
  if v_n <> 1 then
    raise exception '2 · a coluna limite_mensagens_mes foi apagada (achei % coluna) — a máquina estava provada e desligada, e apagá-la transforma um update em migração', v_n;
  end if;

  select col_description(pga.attrelid, pga.attnum) into v_comentario
    from pg_attribute pga
   where pga.attrelid = 'public.planos'::regclass
     and pga.attname = 'limite_mensagens_mes';
  if v_comentario is null or length(v_comentario) < 60 then
    raise exception '2 · o comentário da coluna sumiu ou encolheu para % caracteres — sem ele a coluna vira código morto aparente e cai na próxima faxina', coalesce(length(v_comentario), 0);
  end if;
  raise notice '2 · a coluna e o comentário continuam de pé: ok (% caracteres)', length(v_comentario);
end $do$;

-- ==================== parte 2 · o essencial sai, e o catálogo continua íntegro

do $do$
declare
  v_a_auth  uuid := '77777777-7777-4777-8777-777777777777';
  v_b_auth  uuid := '88888888-8888-4888-8888-888888888888';
  v_a_conta uuid;
  v_b_conta uuid;
  v_a_prof  uuid;
  v_b_prof  uuid;
  v_a_pac   uuid;
  v_b_pac   uuid;
  v_teto    record;
  v_n       integer;
  v_sem_classe text;
  v_def     text;
  v_situacao text;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'a@teste.teto.com.br', '{"nome":"Ana Teto"}'::jsonb),
         (v_b_auth, 'b@teste.teto.com.br', '{"nome":"Bia Teto"}'::jsonb);

  select usr.conta_id into v_a_conta from public.usuarios usr where usr.auth_user_id = v_a_auth;
  select usr.conta_id into v_b_conta from public.usuarios usr where usr.auth_user_id = v_b_auth;
  select prf.id into v_a_prof from public.profissionais prf where prf.conta_id = v_a_conta limit 1;
  select prf.id into v_b_prof from public.profissionais prf where prf.conta_id = v_b_conta limit 1;

  update public.contas set nome = 'Ana Teto' where id = v_a_conta;
  update public.contas set nome = 'Bia Teto' where id = v_b_conta;

  -- **As contas de teste vão para o Solo, e isto é da migração 0061.**
  --
  -- O gatilho de signup cria conta em `gratis`, e desde a 0061 o Grátis manda à
  -- mão: mensagem de template não-essencial nasce em `na_sua_mao`, o worker não a
  -- reserva, e oferta cuja mensagem está na mão dela não expira. Esta suíte testa
  -- o **motor automático**, que é o do plano pago — o caminho manual tem suíte
  -- própria, a 0061.
  --
  -- Sem esta linha a suíte testaria um plano que não é o que ela descreve, e
  -- falharia dizendo "nada expirou" sobre um sistema que está funcionando.
  set local role postgres;
  update public.contas set plano = 'solo' where id in (v_a_conta, v_b_conta);
  reset role;

  -- Desliga a janela de silêncio nas contas de teste.
  --
  -- **Esta suíte passava de dia e falhava de madrugada**, e demorou a aparecer
  -- porque ninguém roda suíte às quatro da manhã. A janela de silêncio da B7
  -- empurra toda mensagem inserida de madrugada para as 8h — e aí
  -- `agendada_para <= now()` deixa de valer, o `reservar_mensagens` não vê
  -- nada, e a verificação acusa um freio que nunca chegou a olhar a mensagem.
  --
  -- Silêncio é ajuste de conta, então a suíte o desliga na conta dela: uma
  -- janela de **um segundo**, posta uma hora à frente do relógio. Ela nunca
  -- contém o agora, e não depende de que horas a suíte roda.
  --
  -- (Zerar os dois campos não serve: com início igual ao fim, a conta da B7 cai
  -- no ramo `hora >= inicio or hora < fim`, que é sempre verdadeiro — seria
  -- silêncio o dia inteiro.)
  update public.contas
     set silencio_inicio = ((now() at time zone 'America/Sao_Paulo') + interval '1 hour')::time,
         silencio_fim    = ((now() at time zone 'America/Sao_Paulo') + interval '1 hour 1 second')::time
   where id in (v_a_conta, v_b_conta);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_a_auth, 'role', 'authenticated')::text, true);

  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (v_a_conta, v_a_prof, 'Paciente Teto', 'whatsapp', '11988880000')
    returning id into v_a_pac;

  -- A paciente da Bia nasce com as credenciais da Bia: o gatilho
  -- `checa_conta_do_paciente` deriva `conta_id` de `conta_atual()`, e inserir
  -- com a sessão da Ana daria uma paciente da Ana com o nome da Bia.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_b_auth, 'role', 'authenticated')::text, true);
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (v_b_conta, v_b_prof, 'Paciente Freio', 'whatsapp', '11988881111')
    returning id into v_b_pac;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_a_auth, 'role', 'authenticated')::text, true);

  -- 3 · template essencial nunca é barrado por limite comercial.
  --
  -- E não é barrado porque **não existe limite comercial**: a conta da Ana é
  -- Grátis, e o Grátis responde `tem_teto = false`. A verificação antiga
  -- estourava um teto de 8 e exigia que o lembrete passasse por cima dele.
  -- Hoje não há teto para estourar, e a afirmação fica mais simples e mais
  -- forte: o lembrete de véspera e o aviso de desmarque saem, ponto.
  --
  -- O que continua em jogo é o mesmo de sempre: quem ficaria sem o aviso é o
  -- paciente, que não é meu cliente, não escolheu o plano, e não tem como saber
  -- que existe um.
  select * into v_teto from public.teto_da_conta(v_a_conta);
  if v_teto.tem_teto then
    raise exception '3 · a conta Grátis voltou a ter teto de mensagens (limite %) — e com teto volta o lembrete que não sai', v_teto.limite;
  end if;

  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (v_a_conta, v_a_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988880000',
          'teto-essencial', now()),
         (v_a_conta, v_a_pac, 'whatsapp', 'aviso_de_desmarque', '{}', '11988880000',
          'teto-essencial-2', now());

  perform public.reservar_mensagens(200);

  select msg.estado into v_situacao from public.mensagens msg where msg.chave_idem = 'teto-essencial';
  if v_situacao = 'barrada_no_teto' then
    raise exception '3 · O LEMBRETE DE VÉSPERA FOI BARRADO. Um paciente ia ao consultório sem saber, por um limite que ele não escolheu — e desde a 0060 esse limite nem existe mais';
  end if;
  if v_situacao <> 'enviando' then
    raise exception '3 · o lembrete não foi reservado, ficou em "%" — se não sai e não diz por quê, é pior do que barrado', v_situacao;
  end if;

  select msg.estado into v_situacao from public.mensagens msg where msg.chave_idem = 'teto-essencial-2';
  if v_situacao = 'barrada_no_teto' then
    raise exception '3 · o aviso de desmarque foi barrado — alguém vai ao consultório amanhã à toa';
  end if;
  raise notice '3 · o essencial sai, e não há limite comercial que o alcance: ok';

  -- 4 · todo template do sistema está classificado.
  --
  -- Esta é a verificação que sobrevive ao tempo, e ela sobreviveu à mudança de
  -- doutrina inteira: o oitavo template nasce sem linha aqui, a FK o recusa, e
  -- ninguém precisa descobrir pela ausência de uma mensagem que faltava
  -- classificar alguma coisa. O `essencial` continua importando mesmo sem teto
  -- de plano: é ele que a tela usa para dizer o que é aviso de sessão e o que é
  -- conversa nossa.
  select count(*) into v_n from public.templates;
  if v_n < 7 then
    raise exception '4 · só % templates classificados, esperava ao menos 7 — template sem linha aqui nasce sem classe e ninguém nota', v_n;
  end if;

  -- E os três essenciais são exatamente os que o paciente não tem outro jeito
  -- de saber. Se alguém rebaixar um deles, o teste cai.
  select string_agg(lista.codigo, ', ') into v_sem_classe
    from unnest(array['lembrete_de_sessao', 'aviso_de_desmarque', 'encaixe_confirmado'])
         as lista(codigo)
   where not exists (select 1 from public.templates tpl
                      where tpl.codigo = lista.codigo and tpl.essencial);
  if v_sem_classe is not null then
    raise exception '4 · estes deixaram de ser essenciais: % — quem fica sem eles é o paciente, que não escolheu plano nenhum', v_sem_classe;
  end if;

  -- E cada linha traz o motivo escrito. Classificação sem motivo é a próxima
  -- pessoa chutando.
  select count(*) into v_n from public.templates tpl where length(tpl.motivo) < 20;
  if v_n > 0 then
    raise exception '4 · % template(s) sem motivo escrito — classificação sem motivo é a próxima pessoa chutando', v_n;
  end if;
  raise notice '4 · todo template está classificado, com motivo: ok';

  -- 5 · e não se cria mensagem com template que não existe
  select pg_get_constraintdef(pgc.oid) into v_def
    from pg_constraint pgc
   where pgc.conrelid = 'public.mensagens'::regclass
     and pgc.conname = 'mensagens_template_fk';
  if v_def is null then
    raise exception '5 · mensagens.template não é FK para templates — um template novo entraria sem classificação nenhuma';
  end if;
  raise notice '5 · template desconhecido é recusado pela FK: ok';
end $do$;

-- ==================== parte 3 · o não-essencial também sai agora

do $do$
declare
  v_a_auth  uuid := '77777777-7777-4777-8777-777777777777';
  v_a_conta uuid;
  v_a_pac   uuid;
  v_teto    record;
  v_situacao text;
  v_codigo  text;
begin
  select usr.conta_id into v_a_conta from public.usuarios usr where usr.auth_user_id = v_a_auth;
  select pac.id into v_a_pac from public.pacientes pac
   where pac.conta_id = v_a_conta and pac.nome = 'Paciente Teto' limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_a_auth, 'role', 'authenticated')::text, true);

  -- 6 · o não-essencial também sai.  ← decide
  --
  -- **Esta verificação afirma o contrário da verificação 3 antiga**, e é a que
  -- carrega a decisão da 0060 inteira. Antes, o não-essencial era barrado e a
  -- suíte exigia que fosse. Só que "não-essencial" queria dizer **oferta de
  -- vaga e aviso de cobrança** — e essas duas são exatamente o que o produto
  -- promete fazer: a oferta que não sai é uma vaga que ninguém soube que abriu,
  -- e o aviso de cobrança que não sai é um dinheiro que atrasa.
  --
  -- Sessenta mensagens custavam cerca de R$ 3,70. O limite não protegia margem;
  -- produzia experiência ruim para economizar três reais e setenta.
  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (v_a_conta, v_a_pac, 'whatsapp', 'oferta_de_vaga', '{}', '11988880000',
          'teto-oferta', now()),
         (v_a_conta, v_a_pac, 'whatsapp', 'aviso_de_cobranca', '{}', '11988880000',
          'teto-barravel', now());

  perform public.reservar_mensagens(200);

  select msg.estado into v_situacao from public.mensagens msg where msg.chave_idem = 'teto-oferta';
  if v_situacao = 'barrada_no_teto' then
    raise exception '6 · a oferta de vaga foi barrada — uma vaga que ninguém soube que abriu, para economizar centavos';
  end if;
  if v_situacao <> 'enviando' then
    raise exception '6 · a oferta de vaga não foi reservada, ficou em "%"', v_situacao;
  end if;

  select msg.estado into v_situacao from public.mensagens msg where msg.chave_idem = 'teto-barravel';
  if v_situacao = 'barrada_no_teto' then
    raise exception '6 · o aviso de cobrança foi barrado — o limite virou atraso no dinheiro dela';
  end if;
  if v_situacao <> 'enviando' then
    raise exception '6 · o aviso de cobrança não foi reservado, ficou em "%"', v_situacao;
  end if;
  raise notice '6 · o não-essencial também sai: ok';

  -- 7 · e `teto_da_conta` diz `tem_teto = false` nos quatro planos.
  --
  -- A função continua existindo — é parte da máquina desligada da verificação 2
  -- — e é ela que a tela consulta. Se um plano voltasse a ter número, a tela
  -- voltaria a mostrar barra de consumo de mensagem, que é a língua errada.
  -- A conta da Ana passeia pelos quatro planos e volta ao Solo.
  foreach v_codigo in array array['gratis', 'solo', 'pro', 'clinica'] loop
    update public.contas set plano = v_codigo where id = v_a_conta;
    select * into v_teto from public.teto_da_conta(v_a_conta);
    if v_teto.tem_teto then
      raise exception '7 · o plano % voltou a ter teto de mensagens (limite %) — quem paga esse limite é quem não escolheu o plano', v_codigo, v_teto.limite;
    end if;
    if v_teto.estourou then
      raise exception '7 · o plano % respondeu "estourou" sem ter teto nenhum', v_codigo;
    end if;
  end loop;
  -- Volta ao Solo, e não ao Grátis: é o plano que esta suíte fixou no preâmbulo
  -- da parte 2, pela razão da 0061 escrita lá. As partes seguintes ainda usam
  -- esta conta para exercitar o motor automático.
  update public.contas set plano = 'solo' where id = v_a_conta;
  raise notice '7 · os quatro planos respondem tem_teto = false: ok';
end $do$;

-- ==================== parte 4 · a fila não pausa mais

do $do$
declare
  v_a_auth  uuid := '77777777-7777-4777-8777-777777777777';
  v_a_conta uuid;
  v_a_prof  uuid;
  v_a_pac   uuid;
  v_pac_dois uuid;
  v_pac_tres uuid;
  v_sessao  uuid;
  v_oferta  uuid;
  v_n       integer;
  v_corpo   text;
  v_dia     date;
begin
  select usr.conta_id into v_a_conta from public.usuarios usr where usr.auth_user_id = v_a_auth;
  select prf.id into v_a_prof from public.profissionais prf where prf.conta_id = v_a_conta limit 1;
  select pac.id into v_a_pac  from public.pacientes pac
   where pac.conta_id = v_a_conta and pac.nome = 'Paciente Teto' limit 1;
  v_dia := public.hoje_sp();

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_a_auth, 'role', 'authenticated')::text, true);

  -- Duas pessoas na fila de espera. É a lista que a versão antiga protegia
  -- pausando a fila — e que agora é servida em vez de protegida.
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (v_a_conta, v_a_prof, 'Fila Dois', 'whatsapp', '11988880002')
    returning id into v_pac_dois;
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (v_a_conta, v_a_prof, 'Fila Três', 'whatsapp', '11988880003')
    returning id into v_pac_tres;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, estado, origem, valor)
  values (v_a_conta, v_a_prof, v_a_pac,
          (v_dia + 3 || ' 14:00')::timestamp at time zone 'America/Sao_Paulo',
          (v_dia + 3 || ' 15:00')::timestamp at time zone 'America/Sao_Paulo',
          'prevista', 'avulsa', 200)
    returning id into v_sessao;

  -- A fila é por conta e paciente, não por profissional: quem amarra o
  -- profissional é a sessão cancelada que `avancar_fila` recebe. E `conta_id`
  -- é derivado por gatilho (0012) — passar à mão seria testar o próprio insert.
  insert into public.fila_encaixe (paciente_id) values (v_pac_dois), (v_pac_tres);

  update public.sessoes set estado = 'cancelada_cedo', cancelada_em = now(),
                            cancelada_por = 'paciente'
   where id = v_sessao;

  -- 8 · `avancar_fila` não consulta teto nenhum, e a vaga vira oferta.  ← decide
  --
  -- **Esta verificação afirma o contrário da 9 antiga.** Lá, a fila pausava
  -- antes de criar a oferta e a suíte exigia a pausa, porque a alternativa era
  -- queimar a lista de espera criando ofertas que ninguém receberia. Com o teto
  -- fora do caminho não há mais o que pausar: a fila é o que o produto promete,
  -- e pará-la para economizar mensagem é parar a promessa no mês em que ela
  -- mais precisou.
  --
  -- **`position()` e não `like`.** Em `LIKE`, `_` é curinga de um caractere
  -- qualquer e casa com espaço — foi assim que `%cabe_no_teto%` reprovou o
  -- comentário "(cabe no teto do plano?) saiu aqui" e acusou código correto
  -- (0060d).
  v_corpo := pg_get_functiondef('public.avancar_fila(uuid)'::regprocedure);
  if position('teto_da_conta' in v_corpo) > 0 then
    raise exception '8 · avancar_fila voltou a consultar teto_da_conta — a fila é o que o produto promete, e pará-la para economizar mensagem é parar a promessa';
  end if;
  if position('cabe_no_teto' in v_corpo) > 0 then
    raise exception '8 · avancar_fila voltou a consultar cabe_no_teto — o freio que sobrou é técnico e mora no envio, não aqui';
  end if;

  v_oferta := public.avancar_fila(v_sessao);
  if v_oferta is null then
    raise exception '8 · a fila não criou oferta nenhuma com a vaga aberta e duas pessoas esperando — a pausa por teto saiu na 0060 e não pode ter voltado por outro caminho';
  end if;

  select count(*) into v_n from public.ofertas ofr where ofr.sessao_id = v_sessao;
  if v_n <> 1 then
    raise exception '8 · esperava 1 oferta para a vaga, achei %', v_n;
  end if;

  select count(*) into v_n from public.eventos_fila evt
   where evt.sessao_id = v_sessao and evt.tipo = 'fila_pausada_no_teto';
  if v_n <> 0 then
    raise exception '8 · a fila gravou % evento(s) de pausa no teto — a pausa por plano deixou de existir na 0060', v_n;
  end if;
  raise notice '8 · a fila não pergunta pelo teto e a vaga virou oferta: ok';

  -- 9 · ...e a oferta convida alguém de verdade.  ← decide
  --
  -- **Afirmação de PRESENÇA**, e é a primeira do projeto. Ela existe porque a
  -- linha que enfileira a mensagem já se perdeu **duas vezes** em
  -- `avancar_fila`: na 0046, corrigida pela 0046d, e de novo na 0060, corrigida
  -- pela 0060d — as duas por reescrita a partir da migração errada, porque
  -- `create or replace function` é `drop` + `create` disfarçado.
  --
  -- Sem essa linha a oferta nasce, expira em quarenta minutos, a fila avança, e
  -- o rastro diz que ninguém quis a vaga. Ninguém foi convidado. Conferir a
  -- oferta sem conferir a mensagem é conferir o registro de que alguém foi
  -- convidado, e não o convite.
  if position('enfileirar_mensagem' in v_corpo) = 0 then
    raise exception '9 · avancar_fila cria a oferta e não convida ninguém — é o defeito da 0046d, e já voltou uma vez (0060d)';
  end if;

  select count(*) into v_n from public.mensagens msg
   where msg.chave_idem = 'oferta:' || v_oferta::text;
  if v_n <> 1 then
    raise exception '9 · a oferta foi criada mas achei % mensagem enfileirada — a oferta seria o registro de um convite que ninguém recebeu', v_n;
  end if;
  if (select msg.template from public.mensagens msg
       where msg.chave_idem = 'oferta:' || v_oferta::text) <> 'oferta_de_vaga' then
    raise exception '9 · a mensagem da oferta não é oferta_de_vaga';
  end if;
  raise notice '9 · avancar_fila continua chamando enfileirar_mensagem, e a mensagem existe: ok';

  -- 10 · o evento antigo continua legível.
  --
  -- Não é nostalgia. `fila_pausada_no_teto` está gravado em eventos de agosto,
  -- que aconteceram de verdade e explicam vagas que não foram oferecidas.
  -- Apagar o valor do check apagaria a leitura da história — e sobraria um
  -- pedaço de agosto sem explicação nenhuma.
  select count(*) into v_n
    from pg_constraint pgc
   where pgc.conname = 'eventos_fila_tipo_check'
     and position('fila_pausada_no_teto' in pg_get_constraintdef(pgc.oid)) > 0;
  if v_n <> 1 then
    raise exception '10 · o valor fila_pausada_no_teto sumiu do check de eventos_fila — os eventos de agosto deixaram de ser legíveis';
  end if;
  raise notice '10 · fila_pausada_no_teto continua no check: ok';
end $do$;

-- ==================== parte 5 · o freio que sobrou é técnico

do $do$
declare
  v_b_auth  uuid := '88888888-8888-4888-8888-888888888888';
  v_b_conta uuid;
  v_b_pac   uuid;
  v_lim_hora integer;
  v_lim_dia  integer;
  v_freio   text;
  v_n       integer;
  v_i       integer;
  v_situacao text;
  v_texto_erro text;
  v_rls     boolean;
begin
  select usr.conta_id into v_b_conta from public.usuarios usr where usr.auth_user_id = v_b_auth;
  select pac.id into v_b_pac from public.pacientes pac
   where pac.conta_id = v_b_conta and pac.nome = 'Paciente Freio' limit 1;

  -- 11 · o freio existe em tabela, com motivo escrito em cada linha.
  --
  -- Em tabela e não em constante no corpo da função, pelo mesmo motivo que os
  -- planos estão em tabela desde a 0045: um número que só muda com deploy não é
  -- ajustável no dia em que ele estiver errado. E com motivo obrigatório, pela
  -- mesma razão de `templates.motivo` — quem for mexer no número precisa
  -- encontrar escrito por que ele é aquele.
  select count(*) into v_n from public.limites_tecnicos
   where codigo in ('mensagens_por_conta_hora', 'mensagens_por_paciente_dia');
  if v_n <> 2 then
    raise exception '11 · achei % dos dois freios técnicos — sem freio nenhum, um laço de código vira fatura e queima o número no WhatsApp', v_n;
  end if;

  select count(*) into v_n from public.limites_tecnicos lmt where length(lmt.motivo) < 40;
  if v_n > 0 then
    raise exception '11 · % freio(s) sem motivo escrito — número sem motivo é a próxima pessoa chutando se pode mexer', v_n;
  end if;

  select lmt.valor into v_lim_hora from public.limites_tecnicos lmt
   where lmt.codigo = 'mensagens_por_conta_hora';
  select lmt.valor into v_lim_dia from public.limites_tecnicos lmt
   where lmt.codigo = 'mensagens_por_paciente_dia';
  raise notice '11 · os dois freios existem, com motivo: ok (conta/hora %, paciente/dia %)', v_lim_hora, v_lim_dia;

  -- 12 · o freio por conta/hora dispara no número da tabela, e diz o nome.
  --
  -- A suíte **lê o número da tabela** em vez de escrever 60 aqui: a lição da
  -- OP3 é que teste que afirma o literal testa o número e não a regra, e ficou
  -- vermelho no dia em que o número mudou de propósito. O que se afirma é a
  -- fronteira: com um a menos não dispara, com o número exato dispara — e
  -- devolve o próprio código, e não um booleano.
  delete from public.mensagens where conta_id = v_b_conta;

  for v_i in 1..(v_lim_hora - 1) loop
    insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                  destino, chave_idem, agendada_para)
    values (v_b_conta, v_b_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988881111',
            'freio-hora-' || v_i, now());
  end loop;
  update public.mensagens set estado = 'enviada', enviada_em = now() - interval '2 minutes'
   where conta_id = v_b_conta and chave_idem like 'freio-hora-%';

  v_freio := public.teto_tecnico(v_b_conta, null);
  if v_freio is not null then
    raise exception '12 · com % mensagens numa hora o freio já disparou (%) — um a menos que o limite tem de passar, senão o freio corta trabalho legítimo', v_lim_hora - 1, v_freio;
  end if;

  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (v_b_conta, v_b_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988881111',
          'freio-hora-limite', now());
  update public.mensagens set estado = 'enviada', enviada_em = now() - interval '2 minutes'
   where chave_idem = 'freio-hora-limite';

  v_freio := public.teto_tecnico(v_b_conta, null);
  if v_freio is distinct from 'mensagens_por_conta_hora' then
    raise exception '12 · % mensagens numa hora e o freio devolveu "%" (esperava mensagens_por_conta_hora) — uma conta real não manda isso numa hora, é laço', v_lim_hora, coalesce(v_freio, 'nulo');
  end if;
  raise notice '12 · o freio por conta/hora dispara em % e diz o próprio nome: ok', v_lim_hora;

  -- 13 · o freio por paciente/dia, isolado do anterior.
  --
  -- Apaga tudo da conta primeiro: `teto_tecnico` confere a hora antes do dia e
  -- devolveria o freio errado, e a suíte estaria provando o freio de cima duas
  -- vezes sem saber.
  delete from public.mensagens where conta_id = v_b_conta;

  for v_i in 1..(v_lim_dia - 1) loop
    insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                  destino, chave_idem, agendada_para)
    values (v_b_conta, v_b_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988881111',
            'freio-dia-' || v_i, now());
  end loop;
  update public.mensagens set estado = 'enviada', enviada_em = now() - interval '2 minutes'
   where conta_id = v_b_conta and chave_idem like 'freio-dia-%';

  v_freio := public.teto_tecnico(v_b_conta, v_b_pac);
  if v_freio is not null then
    raise exception '13 · com % mensagens no dia para a mesma pessoa o freio já disparou (%) — o pior dia legítimo tem quatro, e o limite é o dobro dele', v_lim_dia - 1, v_freio;
  end if;

  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (v_b_conta, v_b_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988881111',
          'freio-dia-limite', now());
  update public.mensagens set estado = 'enviada', enviada_em = now() - interval '2 minutes'
   where chave_idem = 'freio-dia-limite';

  v_freio := public.teto_tecnico(v_b_conta, v_b_pac);
  if v_freio is distinct from 'mensagens_por_paciente_dia' then
    raise exception '13 · % mensagens num dia para a mesma pessoa e o freio devolveu "%" (esperava mensagens_por_paciente_dia) — acima disso alguém está sendo incomodado por defeito nosso', v_lim_dia, coalesce(v_freio, 'nulo');
  end if;
  raise notice '13 · o freio por paciente/dia dispara em % e diz o próprio nome: ok', v_lim_dia;

  -- 14 · o freio pega o essencial também — e é de propósito.
  --
  -- **Isto parece contradizer a verificação 3, e não contradiz.** Lá o que
  -- barrava era um limite comercial: deixar a paciente sem lembrete para
  -- proteger a minha margem é cobrar de quem não escolheu plano nenhum. Aqui o
  -- que barra é **suspeita de laço** — e um laço que manda oitenta lembretes
  -- para a mesma pessoa numa noite é pior para ela do que um lembrete que não
  -- chega. As duas verificações dizem a mesma coisa dos dois lados: quem decide
  -- é o cuidado com ela, nunca o meu custo.
  --
  -- A paciente da Bia está no limite do dia. Um lembrete de sessão — o mais
  -- essencial de todos — tem de ser barrado aqui.
  insert into public.mensagens (conta_id, paciente_id, canal, template, params,
                                destino, chave_idem, agendada_para)
  values (v_b_conta, v_b_pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11988881111',
          'freio-essencial', now());

  perform public.reservar_mensagens(200);

  select msg.estado, msg.erro into v_situacao, v_texto_erro
    from public.mensagens msg where msg.chave_idem = 'freio-essencial';
  if v_situacao <> 'barrada_no_teto' then
    raise exception '14 · o lembrete passou pelo freio de % por paciente/dia (estado "%") — o freio é contra laço, e laço não escolhe template', v_lim_dia, v_situacao;
  end if;
  raise notice '14 · o freio pega o essencial também, porque laço não escolhe template: ok';

  -- 15 · a cliente não enxerga a tabela de freios.  ← decide
  --
  -- Freio técnico é proteção contra bug, não cardápio. Se ele aparecesse para
  -- ela, viraria produto de novo pela porta dos fundos: alguém leria "60 por
  -- hora" como promessa, e a próxima conversa seria sobre subir o número.
  -- RLS ligada e **zero policy** — as funções que precisam são `definer`.
  select pgc.relrowsecurity into v_rls
    from pg_class pgc where pgc.oid = 'public.limites_tecnicos'::regclass;
  if not coalesce(v_rls, false) then
    raise exception '15 · limites_tecnicos está com RLS desligada — a tabela do freio ficou aberta para quem tem chave de cliente';
  end if;

  select count(*) into v_n from pg_policies pol
   where pol.schemaname = 'public' and pol.tablename = 'limites_tecnicos';
  if v_n <> 0 then
    raise exception '15 · apareceram % policy(s) em limites_tecnicos — freio é proteção contra bug, não cardápio', v_n;
  end if;

  set local role authenticated;
  select count(*) into v_n from public.limites_tecnicos;
  reset role;
  if v_n <> 0 then
    raise exception '15 · a cliente leu % linha(s) de limites_tecnicos — o número viraria promessa, e a conversa seguinte seria sobre subi-lo', v_n;
  end if;
  raise notice '15 · o freio é invisível para a cliente: ok';

  -- 16 · e a barrada diz QUAL freio a segurou.
  --
  -- `teto_tecnico` devolve o código em vez de um booleano justamente por isto:
  -- um booleano me faria abrir o banco para descobrir qual freio pegou, no dia
  -- em que isso importasse. E a palavra na tela é "trava de segurança", que é o
  -- que a coisa virou — não "limite do seu plano", que é o que ela não é mais.
  if v_texto_erro is null then
    raise exception '16 · barrou sem dizer por quê — uma mensagem que não sai precisa dizer que não saiu, e por qual freio';
  end if;
  if position('mensagens_por_paciente_dia' in v_texto_erro) = 0 then
    raise exception '16 · o erro da barrada foi "%" e não nomeia o freio — sem o nome eu abro o banco para descobrir no dia em que importa', v_texto_erro;
  end if;
  if position('trava de segurança' in v_texto_erro) = 0 then
    raise exception '16 · o erro da barrada foi "%" e não diz que é trava de segurança — chamar isso de limite de plano seria mentir sobre o que sobrou', v_texto_erro;
  end if;
  raise notice '16 · a barrada diz qual freio a segurou: ok (%)', v_texto_erro;

  delete from public.mensagens where conta_id = v_b_conta;
end $do$;

-- ==================== parte 6 · as trancas e a reserva

do $do$
declare
  v_a_auth  uuid := '77777777-7777-4777-8777-777777777777';
  v_a_conta uuid;
  v_corpo   text;
  v_n       integer;
begin
  select usr.conta_id into v_a_conta from public.usuarios usr where usr.auth_user_id = v_a_auth;

  -- 17 · `cabe_no_teto` não é rota.
  --
  -- Ela mudou de significado sem mudar de nome — era "cabe no teto do plano" e
  -- passou a ser "não bateu num freio técnico" —, e o que não muda é que ela é
  -- máquina de dentro. Publicada em /rest/v1/rpc, viraria sonda: qualquer um
  -- descobriria se a conta da vizinha está travada agora.
  if has_function_privilege('anon', 'public.cabe_no_teto(uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.cabe_no_teto(uuid)'::regprocedure, 'execute') then
    raise exception '17 · cabe_no_teto está publicada em /rest/v1/rpc — máquina de dentro exposta vira sonda da conta alheia';
  end if;
  raise notice '17 · cabe_no_teto não é rota: ok';

  -- 18 · e `teto_tecnico` também não.
  --
  -- Ela é a função nova, e função nova é exatamente onde o grant se esquece.
  -- Exposta, ela responde "esta conta está travada agora" para quem perguntar,
  -- e o freio interno vira informação de fora.
  if has_function_privilege('anon', 'public.teto_tecnico(uuid, uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.teto_tecnico(uuid, uuid)'::regprocedure, 'execute') then
    raise exception '18 · teto_tecnico está publicada em /rest/v1/rpc — ela responde "esta conta está travada agora" para quem perguntar';
  end if;
  raise notice '18 · teto_tecnico não é rota: ok';

  -- 19 · `teto_tecnico` não consulta a tabela de planos.  ← decide
  --
  -- É a verificação que mantém a fronteira desta build inteira de pé: freio
  -- técnico que olha plano é **produto disfarçado**, e a diferença entre as
  -- duas coisas não sobrevive a seis meses se depender de memória. No dia em
  -- que alguém escrever "e se o Pro tivesse um freio mais folgado", esta linha
  -- reprova antes de a ideia virar comportamento.
  --
  -- E a metade de presença: o freio tem de ler `limites_tecnicos`. Número em
  -- constante no corpo não se ajusta no dia em que ele estiver errado.
  --
  -- `position()`, nunca `like`: em LIKE o `_` é curinga e já acusou código
  -- correto (0060d).
  v_corpo := pg_get_functiondef('public.teto_tecnico(uuid, uuid)'::regprocedure);
  if position('public.planos' in v_corpo) > 0 then
    raise exception '19 · teto_tecnico consulta public.planos — freio técnico que olha plano é produto disfarçado, e a fronteira some';
  end if;
  if position('limite_mensagens_mes' in v_corpo) > 0 then
    raise exception '19 · teto_tecnico lê limite_mensagens_mes — o teto de plano voltou pela porta do freio';
  end if;
  if position('limites_tecnicos' in v_corpo) = 0 then
    raise exception '19 · teto_tecnico não lê limites_tecnicos — número em constante não se ajusta no dia em que estiver errado';
  end if;
  raise notice '19 · o freio é técnico e não olha plano: ok';

  -- 20 · e a reserva continua atômica.
  --
  -- A 0060 pôs um UPDATE novo antes do `for update skip locked` — o passo que
  -- barra o que bateu num freio. Se esse UPDATE tivesse comido o skip locked,
  -- dois workers reservariam a mesma linha e o paciente receberia em dobro. É o
  -- tipo de defeito que só aparece com dois processos, ou seja, nunca em teste
  -- — então o que se afirma é a presença da cláusula, e que a reserva roda sem
  -- explodir.
  v_corpo := pg_get_functiondef('public.reservar_mensagens(integer)'::regprocedure);
  if position('for update skip locked' in lower(v_corpo)) = 0 then
    raise exception '20 · o for update skip locked sumiu de reservar_mensagens — dois workers reservariam a mesma linha, e o paciente receberia a mesma mensagem duas vezes';
  end if;

  perform public.reservar_mensagens(200);
  select count(*) into v_n from public.mensagens msg
   where msg.conta_id = v_a_conta and msg.tentativas > 1;
  raise notice '20 · a reserva do worker continua atômica: ok (% linha(s) com mais de uma tentativa)', v_n;
end $do$;

-- ==================== parte 7 · recolher o rastro

do $do$
declare
  v_conta uuid;
  v_n     integer;
  v_com_teto text;
begin
  for v_conta in
    select distinct usr.conta_id from public.usuarios usr
     where usr.email like '%@teste.teto.com.br'
    union
    select ct.id from public.contas ct where ct.nome in ('Ana Teto', 'Bia Teto')
  loop
    delete from public.eventos_fila where conta_id = v_conta;
    delete from public.ofertas      where conta_id = v_conta;
    delete from public.mensagens    where conta_id = v_conta;
    delete from public.fila_encaixe where conta_id = v_conta;
    delete from public.cobrancas    where conta_id = v_conta;
    delete from public.sessoes      where conta_id = v_conta;
    delete from public.enquadres    where conta_id = v_conta;
    delete from public.pacientes    where conta_id = v_conta;
    delete from public.profissionais where conta_id = v_conta;
    delete from public.usuarios     where conta_id = v_conta;
    delete from public.contas       where id = v_conta;
  end loop;
  delete from auth.users where email like '%@teste.teto.com.br';

  select count(*) into v_n from public.contas ct where ct.nome like '%Teto';
  if v_n <> 0 then
    raise exception 'parte 7 · sobraram % contas de teste', v_n;
  end if;

  -- A regra que ficou da OP3: **suíte nunca escreve valor de produção de volta.**
  -- Esta versão não precisa devolver nada, porque não aperta teto nenhum — a
  -- máquina que ela testa está desligada e a suíte não a liga. Esta conferência
  -- existe para provar que não ligou por acidente: se um plano saiu daqui com
  -- número, a suíte deixou produto novo em produção sem ninguém ter decidido.
  select string_agg(pl.codigo, ', ' order by pl.codigo) into v_com_teto
    from public.planos pl where pl.limite_mensagens_mes is not null;
  if v_com_teto is not null then
    raise exception 'parte 7 · a suíte deixou teto mensal nos planos % — nenhuma verificação daqui escreve nessa coluna, então alguma escreveu por engano', v_com_teto;
  end if;

  raise notice 'parte 7 · rastro recolhido: ok';
  raise notice 'SUITE 0046 PASSOU: 20 verificações';
end $do$;
