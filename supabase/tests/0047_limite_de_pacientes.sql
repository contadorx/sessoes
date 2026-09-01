-- Teste do limite de pacientes (critério de pronto da OP3).
--
-- **Desde a 0048 nenhum plano usa este limite.** O Grátis dá tudo o que é
-- registro — agenda, prontuário, livro-razão — e cobra só o que economiza
-- tempo, que é a mensageria; um teto de pacientes limitaria justamente a parte
-- que devia ser livre.
--
-- A suíte fica, e o mecanismo fica, por um motivo: ele está provado, custa
-- nada em repouso (o gatilho sai na primeira linha quando o limite é nulo), e
-- se um plano precisar de teto de pacientes um dia, é um `update` que vale na
-- hora. Uma máquina testada e desligada é barata; reconstruí-la em seis meses,
-- não.
--
-- Por isso a suíte **configura o próprio limite** e devolve `null` no fim —
-- ela não depende mais do que está em produção, que é a lição que a 0046
-- custou caro para aprender: suíte que sabe um número de produção de cor é
-- suíte que pode reverter um deploy.
--
-- A verificação que decide o build é a **3**, e ela existe porque todo limite
-- por contagem tem uma porta dos fundos de uma linha: arquivar cinco, criar
-- cinco, desarquivar os cinco primeiros. Sem o gatilho do UPDATE o limite é
-- decorativo, e ninguém descobre — nem eu, porque a conta continua parecendo
-- certa em toda tela.
--
-- A **10** é a outra que não pode faltar: o limite não pode impedir arquivar.
-- Se impedisse, a conta lotada ficaria sem saída — e a saída é justamente o
-- que faz o limite ser aceitável.
--
--   1. o sexto paciente é recusado
--   2. ...com mensagem que se explica sozinha e diz o que fazer
--   3. **desarquivar também consome vaga** — a porta dos fundos está fechada
--   4. arquivar libera vaga
--   5. plano pago não tem limite nenhum
--   6. o limite é dado: mudar a linha muda o comportamento, sem deploy
--   7. paciente que nasce arquivado não consome vaga
--   8. `pacientes_da_conta` não é sonda de conta alheia
--   9. ...e não é rota para o anônimo
--  10. **arquivar continua possível com a conta lotada** — a saída não se fecha
--  11. **nenhum plano limita pacientes** — o único limite é o de mensagens
--  12. ...mas a máquina da OP2 continua de pé: o essencial nunca é barrado
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0047_limite_de_pacientes.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.limite.com.br'
    union
    select id from public.contas where nome in ('Ana Limite', 'Bia Limite')
  loop
    delete from public.mensagens     where conta_id = a_conta;
    delete from public.sessoes       where conta_id = a_conta;
    delete from public.enquadres     where conta_id = a_conta;
    delete from public.pacientes     where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios      where conta_id = a_conta;
    delete from public.contas        where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.limite.com.br';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · o limite, e a porta dos fundos

do $do$
declare
  a_auth uuid := 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  b_auth uuid := 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  a_conta uuid; b_conta uuid; a_prof uuid; p1 uuid; p6 uuid;
  i int; n int; falhou boolean; msg text; t record;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.limite.com.br', '{"nome":"Ana Limite"}'::jsonb),
         (b_auth, 'b@teste.limite.com.br', '{"nome":"Bia Limite"}'::jsonb);

  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta limit 1;

  update public.contas set nome = 'Ana Limite', plano = 'gratis' where id = a_conta;
  update public.contas set nome = 'Bia Limite', plano = 'solo'   where id = b_conta;

  -- A suíte liga o limite para si mesma. Em produção ele é nulo desde a 0048.
  update public.planos set limite_pacientes_ativos = 5 where codigo = 'gratis';

  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);

  for i in 1..5 loop
    insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
    values (a_conta, a_prof, 'Limite ' || i, 'whatsapp', '1197777000' || i)
      returning id into p1;
  end loop;

  select * into t from public.pacientes_da_conta(a_conta);
  if not t.lotou then raise exception '1 · cinco pacientes e a conta não lotou (ativos %)', t.ativos; end if;

  -- 1 e 2 · o sexto é recusado, e a mensagem se explica
  falhou := false;
  begin
    insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
    values (a_conta, a_prof, 'Limite 6', 'whatsapp', '11977770006');
  exception when others then falhou := true; msg := sqlerrm;
  end;
  if not falhou then raise exception '1 · o sexto paciente entrou'; end if;
  raise notice '1 · o sexto é recusado: ok';

  -- Uma mensagem de limite que não diz o número, o que fazer e que existe
  -- saída é uma parede. Esta precisa das três coisas.
  if msg !~ '5' then raise exception '2 · a mensagem não diz qual é o limite: %', msg; end if;
  if msg !~ 'rquiv' then raise exception '2 · a mensagem não diz o que fazer: %', msg; end if;
  -- Fronteira de palavra (`\m` e `\M`), senão "en**cerro**u" casa com "erro"
  -- e o teste reprova a mensagem certa. Regex sem fronteira num idioma cheio
  -- de prefixo e sufixo acusa a palavra errada mais vezes do que acerta.
  if msg ~* '\merros?\M|\mfalha\M|inválid|negad|proibid|não permitid' then
    raise exception '2 · a mensagem culpa em vez de explicar: %', msg;
  end if;
  raise notice '2 · a mensagem se explica sozinha: ok';

  -- 4 · arquivar libera vaga
  select id into p1 from public.pacientes
   where conta_id = a_conta and nome = 'Limite 1';
  perform public.arquivar_paciente(p1, 'processo encerrado no teste');

  select * into t from public.pacientes_da_conta(a_conta);
  if t.lotou then raise exception '4 · arquivei uma e a conta continua lotada (ativos %)', t.ativos; end if;

  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, a_prof, 'Limite 6', 'whatsapp', '11977770006') returning id into p6;
  raise notice '4 · arquivar libera vaga: ok';

  -- 3 · A VERIFICAÇÃO QUE DECIDE O BUILD.
  -- A conta está lotada de novo (5 ativas). Desarquivar a primeira faria 6.
  select * into t from public.pacientes_da_conta(a_conta);
  if not t.lotou then raise exception '3 · esperava a conta lotada antes do teste da porta dos fundos'; end if;

  falhou := false;
  begin
    update public.pacientes set arquivado_em = null where id = p1;
  exception when others then falhou := true; msg := sqlerrm;
  end;

  select ativos into n from public.pacientes_da_conta(a_conta);
  if n > 5 then
    raise exception '3 · A PORTA DOS FUNDOS ESTÁ ABERTA: desarquivar não conta, e a conta tem % ativos num plano de 5', n;
  end if;
  if not falhou then raise exception '3 · desarquivar passou sem ser barrado'; end if;
  raise notice '3 · desarquivar também consome vaga: ok';

  -- 10 · e arquivar continua possível com a conta lotada. Se o limite
  -- fechasse a saída, a conta cheia ficaria presa — e a saída é o que faz o
  -- limite ser aceitável em vez de ser uma parede.
  perform public.arquivar_paciente(p6, 'encerrado, conferindo a saída');
  select ativos into n from public.pacientes_da_conta(a_conta);
  if n <> 4 then raise exception '10 · arquivar com a conta lotada não funcionou (ativos %)', n; end if;
  raise notice '10 · arquivar continua possível com a conta lotada: ok';

  -- 7 · paciente que nasce arquivado não consome vaga (é o caso da importação
  -- de histórico da B26: gente que já encerrou, trazida só como memória)
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone, arquivado_em, encerramento)
  values (a_conta, a_prof, 'Limite Antigo', 'nao_avisar', null, now(), 'importado do histórico');
  select ativos into n from public.pacientes_da_conta(a_conta);
  if n <> 4 then raise exception '7 · o arquivado consumiu vaga (ativos %)', n; end if;
  raise notice '7 · quem nasce arquivado não consome vaga: ok';

  -- 5 · plano pago não tem limite
  perform set_config('request.jwt.claims',
                     json_build_object('sub', b_auth, 'role', 'authenticated')::text, true);
  select * into t from public.pacientes_da_conta(b_conta);
  if t.tem_limite then raise exception '5 · o plano Solo ganhou limite de pacientes'; end if;
  if t.lotou then raise exception '5 · um plano sem limite lotou'; end if;
  raise notice '5 · plano pago sem limite: ok';

  -- 6 · e o limite é dado
  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  update public.planos set limite_pacientes_ativos = 50 where codigo = 'gratis';
  select * into t from public.pacientes_da_conta(a_conta);
  if t.lotou then raise exception '6 · subi o limite para 50 e a conta continua lotada'; end if;

  -- E desligar de vez também é um update: é assim que ele está em produção.
  update public.planos set limite_pacientes_ativos = null where codigo = 'gratis';
  select * into t from public.pacientes_da_conta(a_conta);
  if t.tem_limite then raise exception '6 · zerei o limite e a conta continua limitada'; end if;
  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, a_prof, 'Limite Sem Teto', 'whatsapp', '11977770099');

  -- E fica desligado, que é o estado de produção. A primeira versão desta
  -- parte religava o limite aqui, e a parte 2 exigia que nenhum plano
  -- limitasse — as duas metades da mesma suíte discordando.
  update public.planos set limite_pacientes_ativos = null;
  raise notice '6 · o limite é dado, e desligar também: ok';
end $do$;

-- ==================== parte 2 · quem pergunta, e a rede de segurança

do $do$
declare
  a_auth uuid := 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  b_auth uuid := 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  a_conta uuid; b_conta uuid; t record; n int; vazou boolean; barrou boolean;
begin
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id into b_conta from public.usuarios where auth_user_id = b_auth;

  -- 8 · não é sonda de conta alheia. Quantos pacientes a vizinha atende é
  -- volume de atendimento dela — a lição da B7 com `vaga_esta_livre`, e a
  -- mesma tranca que a 0046b pôs em `teto_da_conta`.
  vazou := false; barrou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
                       json_build_object('sub', b_auth, 'role', 'authenticated')::text, true);
    select * into t from public.pacientes_da_conta(a_conta);
    reset role;
    vazou := true;
  exception when others then barrou := true; reset role;
  end;
  if vazou then
    raise exception '8 · a Bia leu quantos pacientes a Ana atende (%)', t.ativos;
  end if;
  if not barrou then raise exception '8 · a consulta à conta alheia não foi recusada'; end if;
  raise notice '8 · não é sonda de conta alheia: ok';

  -- 9 · e o anônimo não alcança nada disto
  if has_function_privilege('anon', 'public.pacientes_da_conta(uuid)'::regprocedure, 'execute') then
    raise exception '9 · pacientes_da_conta está publicada para o anônimo';
  end if;
  raise notice '9 · o anônimo não alcança: ok';

  -- 11 · O ÚNICO limite de produção é o de mensagens.
  --
  -- Desde a 0048 o Grátis dá tudo o que é registro e cobra só o que economiza
  -- tempo. Se um dia alguém puser teto de pacientes em produção, esta
  -- verificação cai — e é para cair: o limite existiria de novo sobre a parte
  -- que devia ser livre, e alguém teria de dizer por quê.
  select count(*) into n from public.planos where limite_pacientes_ativos is not null;
  if n > 0 then
    raise exception '11 · % plano(s) voltaram a limitar pacientes — o registro é a parte que não se cobra', n;
  end if;

  select limite_mensagens_mes into n from public.planos where codigo = 'gratis';
  if n is null then
    raise exception '11 · o teto de mensagens sumiu, e ele é o único limite que sobrou';
  end if;
  if n > 200 then
    raise exception '11 · o teto de mensagens subiu para %, alto o bastante para não limitar nada', n;
  end if;
  raise notice '11 · o único limite é o de mensagens (%): ok', n;

  -- E em uso normal a fila não pausa mais. Cinco pacientes não geram 500
  -- mensagens não-essenciais em mês nenhum.
  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  select * into t from public.teto_da_conta(a_conta);
  reset role;
  if t.estourou then
    raise exception '11 · uma conta com 4 pacientes já estourou o teto de mensagens';
  end if;
  raise notice '11b · a fila não pausa em uso normal: ok';

  -- 12 · mas a máquina da OP2 continua inteira. Se alguém, ao afrouxar o teto,
  -- tivesse rebaixado um template essencial, o lembrete de véspera passaria a
  -- ser barrável — e o teto novo é tão alto que ninguém descobriria por anos.
  select count(*) into n from public.templates
   where codigo in ('lembrete_de_sessao', 'aviso_de_desmarque', 'encaixe_confirmado')
     and essencial;
  if n <> 3 then
    raise exception '12 · só % dos três templates essenciais continuam essenciais', n;
  end if;
  raise notice '12 · a máquina da OP2 continua de pé: ok';
end $do$;

-- ==================== parte 3 · recolher o rastro

do $do$
declare a_conta uuid; n int;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.limite.com.br'
    union
    select id from public.contas where nome in ('Ana Limite', 'Bia Limite')
  loop
    delete from public.mensagens     where conta_id = a_conta;
    delete from public.sessoes       where conta_id = a_conta;
    delete from public.enquadres     where conta_id = a_conta;
    delete from public.pacientes     where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios      where conta_id = a_conta;
    delete from public.contas        where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.limite.com.br';

  -- O valor de produção é NULO — nenhum plano limita pacientes desde a 0048.
  -- A suíte ligou o limite para si mesma; desligar de volta é obrigação dela.
  update public.planos set limite_pacientes_ativos = null;

  select count(*) into n from public.contas where nome like '%Limite';
  if n <> 0 then raise exception 'parte 3 · sobraram % contas de teste', n; end if;
  select count(*) into n from public.planos where limite_pacientes_ativos is not null;
  if n <> 0 then
    raise exception 'parte 3 · a suíte deixou limite de pacientes ligado em % plano(s)', n;
  end if;

  raise notice 'parte 3 · rastro recolhido: ok';
  raise notice '=== 0047 · o limite de pacientes: 12 verificações, todas passaram ===';
end $do$;
