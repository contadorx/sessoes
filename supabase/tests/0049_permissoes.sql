-- Teste da permissão clínica e financeira (critério de pronto da OP4).
--
-- A auditoria externa achou o buraco pela tela — "a secretária vê as mesmas
-- doze abas" —, mas o buraco estava na RLS: `evolucoes` só perguntava se a
-- linha era da mesma conta. Esta suíte existe para que a resposta continue
-- sendo não daqui a seis meses, quando alguém acrescentar a décima tabela
-- clínica e esquecer a cláusula.
--
-- Por isso metade das verificações afirmam o que o sistema **não** pode fazer,
-- e três delas rodam a exportação inteira: um arquivo que vaza é a forma mais
-- silenciosa desse erro, e nenhum teste de tela o pegaria.
--
-- A verificação 16 é a que sustenta as outras: ela prova que a dona **vê** o
-- que a secretária não vê. Sem ela, um bug que zerasse a exportação de todo
-- mundo faria as verificações 15 e 17 passarem com louvor.
--
--   1. o padrão do papel: dona vê os dois eixos
--   2. profissional lê clínico e NÃO vê dinheiro
--   3. administradora vê dinheiro e NÃO lê clínico
--   4. secretária não lê nem vê
--   5. sem sessão, as funções dão `false` — não nulo
--   6. **a secretária não enxerga evolução**
--   7. ...nem anamnese, adendo e registro
--   8. ...nem a trilha de quem abriu o quê
--   9. ...e não consegue escrever evolução
--  10. ...nem ver cobrança, documento, recibo, despesa e pasta do contador
--  11. ...mas continua vendo paciente e sessão (senão não marca agenda)
--  12. a profissional lê evolução
--  13. ...e não vê cobrança
--  14. a administradora vê cobrança e não lê evolução
--  15. **a exportação da secretária sai sem prontuário**
--  16. ...e a mesma exportação, pela dona, sai com ele
--  17. ...e sai sem financeiro também
--  18. **a secretária não se concede acesso clínico por PATCH**
--  19. ...nem se promove a dona
--  20. ...nem concede à colega
--  21. a dona concede, e aí a secretária lê — a concessão explícita vence o padrão
--  22. ...e a dona revoga o clínico de uma profissional, e a leitura para
--  23. **nem a dona amplia o próprio acesso**
--  24. 'administradora' é papel válido; papel inventado é recusado
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0049_permissoes.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.permissao.com.br'
    union
    select id from public.contas where nome like 'Clínica Permissão%'
  loop
    delete from public.trilha_acesso     where conta_id = a_conta;
    delete from public.anamnese_adendos  where conta_id = a_conta;
    delete from public.anamneses         where conta_id = a_conta;
    delete from public.evolucoes         where conta_id = a_conta;
    delete from public.registros         where conta_id = a_conta;
    delete from public.documentos        where conta_id = a_conta;
    delete from public.cobrancas         where conta_id = a_conta;
    delete from public.despesas          where conta_id = a_conta;
    delete from public.sessoes           where conta_id = a_conta;
    delete from public.pacientes         where conta_id = a_conta;
    delete from public.profissionais     where conta_id = a_conta;
    delete from public.usuarios          where conta_id = a_conta;
    delete from public.contas            where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.permissao.com.br';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · o padrão do papel

do $do$
declare
  d_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000001'; -- dona
  p_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000002'; -- profissional
  m_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000003'; -- administradora
  s_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000004'; -- secretária
  a_conta uuid; a_prof uuid;
  sobras uuid[];
  b boolean; falhou boolean;
begin
  -- Cada insert em auth.users provisiona conta própria (gatilho
  -- `ao_criar_auth_user`, padrão da casa desde a B2). Crio as quatro e depois
  -- mudo três para a conta da dona, limpando as contas que sobram — é o que o
  -- convite vai fazer um dia, e é a única forma de montar uma clínica aqui.
  insert into auth.users (id, email, raw_user_meta_data) values
    (d_auth, 'dora@teste.permissao.com.br',  '{"nome":"Clínica Permissão"}'::jsonb),
    (p_auth, 'paula@teste.permissao.com.br', '{"nome":"Clínica Permissão P"}'::jsonb),
    (m_auth, 'alice@teste.permissao.com.br', '{"nome":"Clínica Permissão A"}'::jsonb),
    (s_auth, 'sara@teste.permissao.com.br',  '{"nome":"Clínica Permissão S"}'::jsonb);

  select conta_id into a_conta from public.usuarios where auth_user_id = d_auth;
  select array_agg(conta_id) into sobras from public.usuarios
   where auth_user_id in (p_auth, m_auth, s_auth);

  delete from public.profissionais where conta_id = any(sobras);

  update public.usuarios set conta_id = a_conta, papel = 'profissional'   where auth_user_id = p_auth;
  update public.usuarios set conta_id = a_conta, papel = 'administradora' where auth_user_id = m_auth;
  update public.usuarios set conta_id = a_conta, papel = 'secretaria'     where auth_user_id = s_auth;

  delete from public.contas where id = any(sobras);
  update public.contas set nome = 'Clínica Permissão', tipo = 'clinica' where id = a_conta;

  select id into a_prof from public.profissionais where conta_id = a_conta limit 1;

  -- Os gatilhos de `pacientes` e `sessoes` derivam a conta da sessão, não do
  -- parâmetro — foi assim desde a B5, e é o que impede alguém de escrever numa
  -- conta alheia passando o uuid na mão. Aqui basta a claim: o papel continua
  -- sendo o da migração, então nenhuma RLS atrapalha o preparo do cenário.
  perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);

  -- Dado clínico e dado financeiro para os testes olharem.
  insert into public.pacientes (id, conta_id, profissional_id, nome, telefone)
  values ('aaaaaaaa-0049-4000-8000-0000000000aa', a_conta, a_prof, 'Paciente Permissão', '11999990049');

  insert into public.registros (conta_id, paciente_id, profissional_id, demanda)
  values (a_conta, 'aaaaaaaa-0049-4000-8000-0000000000aa', a_prof, 'demanda que a secretária não pode ler');

  insert into public.evolucoes (conta_id, paciente_id, texto)
  values (a_conta, 'aaaaaaaa-0049-4000-8000-0000000000aa', 'evolução que a secretária não pode ler');

  insert into public.anamneses (conta_id, paciente_id, profissional_id, modelo)
  values (a_conta, 'aaaaaaaa-0049-4000-8000-0000000000aa', a_prof, 'adulto');

  insert into public.anamnese_adendos (conta_id, anamnese_id, texto)
  select a_conta, an.id, 'adendo que a secretária não pode ler'
    from public.anamneses an where an.conta_id = a_conta limit 1;

  insert into public.trilha_acesso (conta_id, auth_user_id, paciente_id, acao)
  values (a_conta, d_auth, 'aaaaaaaa-0049-4000-8000-0000000000aa', 'leu_ficha');

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, valor, estado)
  values (a_conta, a_prof, 'aaaaaaaa-0049-4000-8000-0000000000aa',
          now() + interval '1 day', now() + interval '1 day 50 minutes', 20000, 'prevista');

  insert into public.cobrancas (conta_id, paciente_id, tipo, motivo, valor, estado, competencia)
  values (a_conta, 'aaaaaaaa-0049-4000-8000-0000000000aa', 'sessao', 'sessao_realizada',
          20000, 'aberta', date_trunc('month', now())::date);

  insert into public.despesas (conta_id, paga_em, categoria, descricao, valor)
  values (a_conta, current_date, 'aluguel', 'sala do consultório', 120000);

  -- 1 · a dona vê os dois eixos
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);
  select public.le_clinico() into b;    if not b then reset role; raise exception '1 · a dona não lê clínico'; end if;
  select public.ve_financeiro() into b; if not b then reset role; raise exception '1 · a dona não vê financeiro'; end if;
  reset role;
  raise notice '1 · a dona vê os dois eixos: ok';

  -- 2 · a profissional atende, e o dinheiro é da clínica
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
  select public.le_clinico() into b;    if not b then reset role; raise exception '2 · a profissional não lê o próprio prontuário'; end if;
  select public.ve_financeiro() into b; if b     then reset role; raise exception '2 · a profissional vê o financeiro da clínica'; end if;
  reset role;
  raise notice '2 · profissional: clínico sim, dinheiro não: ok';

  -- 3 · e a administradora é o espelho disso — é o teste que prova que os dois
  -- eixos são independentes, e não dois nomes para a mesma escada de cargos.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', m_auth, 'role', 'authenticated')::text, true);
  select public.le_clinico() into b;    if b     then reset role; raise exception '3 · a administradora lê prontuário'; end if;
  select public.ve_financeiro() into b; if not b then reset role; raise exception '3 · a administradora não vê o financeiro'; end if;
  reset role;
  raise notice '3 · administradora: dinheiro sim, clínico não: ok';

  -- 4 · a secretária não recebe nada por padrão
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select public.le_clinico() into b;    if b then reset role; raise exception '4 · a secretária lê prontuário por padrão'; end if;
  select public.ve_financeiro() into b; if b then reset role; raise exception '4 · a secretária vê dinheiro por padrão'; end if;
  reset role;
  raise notice '4 · a secretária não nasce com acesso: ok';

  -- 5 · sem sessão, `false` e **não nulo**. Numa cláusula de RLS os dois barram
  -- igual; a diferença aparece em qualquer lugar onde alguém escreva
  -- `not le_clinico()` e receba nulo — que não é falso, e passa.
  --
  -- O teste roda como `authenticated` sem claim porque, desde a 0049b, o
  -- `anon` não alcança mais as duas funções (convenção de `papel_atual()`) —
  -- e a segunda metade confere justamente isso.
  set local role authenticated;
  perform set_config('request.jwt.claims', '', true);
  select public.le_clinico() into b;    if b is null or b then reset role; raise exception '5 · le_clinico sem sessão devolveu %', b; end if;
  select public.ve_financeiro() into b; if b is null or b then reset role; raise exception '5 · ve_financeiro sem sessão devolveu %', b; end if;
  reset role;

  falhou := false;
  begin
    set local role anon;
    perform public.le_clinico();
    reset role;
  exception when insufficient_privilege then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · o anônimo alcança le_clinico()'; end if;
  raise notice '5 · sem sessão é false (e o anônimo nem chega lá): ok';
end $do$;

-- ==================== parte 2 · o corte vale no dado, não na tela

do $do$
declare
  p_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000002';
  m_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000003';
  s_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000004';
  n int; falhou boolean;
begin
  -- 6 · a evolução. O modo de falha que este teste guarda não é a tela: é a
  -- consulta direta ao PostgREST, que não passa por menu nenhum.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.evolucoes;
  reset role;
  if n <> 0 then raise exception '6 · a secretária leu % evolução(ões)', n; end if;
  raise notice '6 · a secretária não enxerga evolução: ok';

  -- 7 · e as outras três tabelas clínicas
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select (select count(*) from public.anamneses)
       + (select count(*) from public.anamnese_adendos)
       + (select count(*) from public.registros) into n;
  reset role;
  if n <> 0 then raise exception '7 · a secretária leu % linha(s) de anamnese/adendo/registro', n; end if;
  raise notice '7 · nem anamnese, adendo ou registro: ok';

  -- 8 · a trilha. "Fulana abriu o prontuário de Beltrana" é informação clínica
  -- com outra roupa: diz quem está em atendimento e com quem.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.trilha_acesso;
  reset role;
  if n <> 0 then raise exception '8 · a secretária leu % linha(s) da trilha', n; end if;
  raise notice '8 · nem a trilha de quem abriu o quê: ok';

  -- 9 · e não escreve. Ler é o vazamento; escrever é a falsificação — um
  -- registro clínico assinado por quem não atendeu.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
    insert into public.evolucoes (conta_id, paciente_id, texto)
    values (public.conta_atual(), 'aaaaaaaa-0049-4000-8000-0000000000aa', 'escrita indevida');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '9 · a secretária escreveu evolução'; end if;
  raise notice '9 · nem escreve evolução: ok';

  -- 10 · o eixo financeiro
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select (select count(*) from public.cobrancas)
       + (select count(*) from public.despesas)
       + (select count(*) from public.documentos)
       + (select count(*) from public.recibos_rfb)
       + (select count(*) from public.pastas_contador) into n;
  reset role;
  if n <> 0 then raise exception '10 · a secretária leu % linha(s) do financeiro', n; end if;
  raise notice '10 · nem cobrança, documento, recibo, despesa ou pasta: ok';

  -- 11 · e o que ela PRECISA continua lá. Este é o contra-argumento que a
  -- própria auditoria levantou contra si mesma: restringir demais devolve
  -- trabalho para a psicóloga, que é o oposto do produto.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select (select count(*) from public.pacientes) + (select count(*) from public.sessoes) into n;
  reset role;
  if n < 2 then raise exception '11 · a secretária perdeu a agenda: viu % linha(s)', n; end if;
  raise notice '11 · mas continua vendo paciente e sessão: ok';

  -- 12 · a profissional lê o prontuário
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.evolucoes;
  reset role;
  if n < 1 then raise exception '12 · a profissional não leu a própria evolução'; end if;
  raise notice '12 · a profissional lê evolução: ok';

  -- 13 · e não vê o caixa da clínica
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.cobrancas;
  reset role;
  if n <> 0 then raise exception '13 · a profissional leu % cobrança(s)', n; end if;
  raise notice '13 · ...e não vê cobrança: ok';

  -- 14 · a administradora, espelhada
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', m_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.cobrancas;
  if n < 1 then reset role; raise exception '14 · a administradora não viu a cobrança'; end if;
  select count(*) into n from public.evolucoes;
  reset role;
  if n <> 0 then raise exception '14 · a administradora leu % evolução(ões)', n; end if;
  raise notice '14 · administradora: cobrança sim, evolução não: ok';
end $do$;

-- ==================== parte 3 · a exportação, que é por onde vaza calado

do $do$
declare
  d_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000001';
  s_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000004';
  j jsonb;
begin
  -- 15 · `exportar_conta` é `security invoker`, então a RLS vale dentro dela.
  -- O arquivo não "esconde" o prontuário: o `select` não o enxergou.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select public.exportar_conta() into j;
  reset role;

  if jsonb_array_length(j -> 'evolucoes')        <> 0 then raise exception '15 · a exportação da secretária trouxe evolução'; end if;
  if jsonb_array_length(j -> 'anamneses')        <> 0 then raise exception '15 · ...trouxe anamnese'; end if;
  if jsonb_array_length(j -> 'anamnese_adendos') <> 0 then raise exception '15 · ...trouxe adendo'; end if;
  if jsonb_array_length(j -> 'registros')        <> 0 then raise exception '15 · ...trouxe registro clínico'; end if;
  if jsonb_array_length(j -> 'trilha_acesso')    <> 0 then raise exception '15 · ...trouxe a trilha'; end if;
  raise notice '15 · a exportação da secretária sai sem prontuário: ok';

  -- 17 · e sem o financeiro
  if jsonb_array_length(j -> 'cobrancas')       <> 0 then raise exception '17 · a exportação da secretária trouxe cobrança'; end if;
  if jsonb_array_length(j -> 'despesas')        <> 0 then raise exception '17 · ...trouxe despesa'; end if;
  if jsonb_array_length(j -> 'recibos_rfb')     <> 0 then raise exception '17 · ...trouxe recibo'; end if;
  if jsonb_array_length(j -> 'pastas_contador') <> 0 then raise exception '17 · ...trouxe pasta do contador'; end if;
  raise notice '17 · ...e sai sem o financeiro: ok';

  -- 16 · o teste que sustenta os outros dois. Sem ele, um bug que zerasse a
  -- exportação de todo mundo passaria como se fosse segurança.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);
  select public.exportar_conta() into j;
  reset role;

  if jsonb_array_length(j -> 'evolucoes') < 1 then raise exception '16 · a exportação da dona veio SEM evolução — o corte pegou quem não devia'; end if;
  if jsonb_array_length(j -> 'anamneses') < 1 then raise exception '16 · ...sem anamnese'; end if;
  if jsonb_array_length(j -> 'registros') < 1 then raise exception '16 · ...sem registro clínico'; end if;
  if jsonb_array_length(j -> 'cobrancas') < 1 then raise exception '16 · ...sem cobrança'; end if;
  raise notice '16 · ...e a exportação da dona sai com tudo: ok';
end $do$;

-- ==================== parte 4 · ninguém amplia o próprio acesso

do $do$
declare
  d_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000001';
  p_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000002';
  s_auth uuid := 'aaaaaaaa-0049-4000-8000-000000000004';
  s_user uuid; p_user uuid; d_user uuid;
  n int; falhou boolean; b boolean;
begin
  select id into s_user from public.usuarios where auth_user_id = s_auth;
  select id into p_user from public.usuarios where auth_user_id = p_auth;
  select id into d_user from public.usuarios where auth_user_id = d_auth;

  -- 18 · a escalada de uma linha. A política de UPDATE de `usuarios` deixa
  -- cada uma editar a própria linha (para trocar o nome) desde a B2; sem o
  -- gatilho, esse ramo viraria uma concessão de acesso a prontuário.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
    update public.usuarios set acesso_clinico = true where id = s_user;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  select count(*) into n from public.usuarios where id = s_user and acesso_clinico is true;
  if n > 0 then raise exception '18 · a secretária se concedeu acesso clínico'; end if;
  if not falhou then raise exception '18 · o PATCH passou em silêncio (pior que passar com erro)'; end if;
  raise notice '18 · a secretária não se concede acesso clínico: ok';

  -- 19 · nem pelo caminho do cargo
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
    update public.usuarios set papel = 'dona' where id = s_user;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  select count(*) into n from public.usuarios where id = s_user and papel = 'dona';
  if n > 0 then raise exception '19 · a secretária virou dona'; end if;
  raise notice '19 · nem se promove a dona: ok';

  -- 20 · nem faz da colega uma ponte.
  --
  -- Aqui a negativa é **silenciosa**, e é de propósito: a linha da colega não
  -- passa pela cláusula USING da política de UPDATE, então o `update` acerta
  -- zero linhas e volta sem erro. O gatilho nem chega a rodar — não há linha
  -- para ele examinar.
  --
  -- Por isso este teste olha o **estado**, e não a exceção. Foi o que ele me
  -- ensinou na primeira execução, quando eu tinha escrito `if not falhou then
  -- raise` e ele reprovou um sistema que estava certo: RLS que nega devolve
  -- zero linhas, não erro, e um teste que espera exceção onde a defesa é
  -- silenciosa mede a mensagem em vez de medir a porta.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  update public.usuarios set acesso_clinico = true where id = p_user;
  reset role;

  select count(*) into n from public.usuarios where id = p_user and acesso_clinico is true;
  if n > 0 then raise exception '20 · a secretária concedeu acesso à colega'; end if;
  raise notice '20 · nem concede à colega (a RLS nega calada): ok';

  -- 21 · e a dona concede. É a metade que faz a permissão ser permissão: uma
  -- porta que nunca abre não é controle de acesso, é uma parede.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);
  update public.usuarios set acesso_clinico = true where id = s_user;
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', s_auth, 'role', 'authenticated')::text, true);
  select public.le_clinico() into b;
  select count(*) into n from public.evolucoes;
  reset role;
  if not b then raise exception '21 · concedido e le_clinico continuou falso'; end if;
  if n < 1 then raise exception '21 · concedido e a evolução continuou invisível'; end if;
  raise notice '21 · a dona concede, e a concessão vence o padrão do papel: ok';

  -- 22 · e o outro sentido, que é o que prova que os eixos não são uma escada:
  -- tirar o clínico de quem o teria por cargo.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);
  update public.usuarios set acesso_clinico = false where id = p_user;
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.evolucoes;
  reset role;
  if n <> 0 then raise exception '22 · revogado e a profissional continuou lendo % evolução(ões)', n; end if;
  raise notice '22 · ...e revoga de quem teria por cargo: ok';

  -- 23 · nem a dona em si mesma. Se a dona pudesse, a auditoria de quem
  -- concedeu o quê perderia o sentido: toda concessão teria dois autores
  -- possíveis e nenhum registro de qual foi.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', d_auth, 'role', 'authenticated')::text, true);
    update public.usuarios set acesso_clinico = false where id = d_user;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '23 · a dona mexeu no próprio acesso'; end if;
  raise notice '23 · nem a dona amplia o próprio acesso: ok';

  -- Devolve a profissional ao estado de origem para não deixar rastro de teste
  -- num banco que é o de produção.
  update public.usuarios set acesso_clinico = null where id = p_user;
end $do$;

-- ==================== parte 5 · o cargo novo

do $do$
declare falhou boolean;
begin
  -- 24 · 'administradora' entrou no check, e o check continua fechado. Um
  -- papel inventado tem que ser recusado pelo banco, não tratado como
  -- "nenhuma permissão" por acidente do coalesce.
  falhou := false;
  begin
    insert into public.usuarios (conta_id, auth_user_id, papel, email)
    select conta_id, gen_random_uuid(), 'gerente', 'g@teste.permissao.com.br'
      from public.usuarios where email = 'dora@teste.permissao.com.br';
  exception when check_violation then falhou := true;
  end;
  if not falhou then raise exception '24 · o banco aceitou um papel inventado'; end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'usuarios_papel_check'
       and pg_get_constraintdef(oid) like '%administradora%')
  then raise exception '24 · administradora não está no check'; end if;
  raise notice '24 · o cargo novo existe e o check continua fechado: ok';
end $do$;

-- ==================== parte 6 · limpeza

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.permissao.com.br'
  loop
    delete from public.trilha_acesso     where conta_id = a_conta;
    delete from public.anamnese_adendos  where conta_id = a_conta;
    delete from public.anamneses         where conta_id = a_conta;
    delete from public.evolucoes         where conta_id = a_conta;
    delete from public.registros         where conta_id = a_conta;
    delete from public.cobrancas         where conta_id = a_conta;
    delete from public.despesas          where conta_id = a_conta;
    delete from public.sessoes           where conta_id = a_conta;
    delete from public.pacientes         where conta_id = a_conta;
    delete from public.profissionais     where conta_id = a_conta;
    delete from public.usuarios          where conta_id = a_conta;
    delete from public.contas            where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.permissao.com.br';
  raise notice 'parte 6 · limpeza: ok';
  raise notice '=== 0049: 24 verificações, todas passaram ===';
end $do$;
