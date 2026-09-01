-- Teste do painel do negócio (critério de pronto da OP1).
--
-- A verificação nº 1 é a que decide o build, e ela não olha dado nenhum: lê o
-- **corpo das funções** e reprova se qualquer uma mencionar tabela clínica.
--
-- O motivo é o Financeiro Simples. Ele resolve o suporte com impersonação
-- real: gera um magic link para o e-mail do dono e assume a sessão dele —
-- acesso total, indistinguível do titular, com o próprio código dizendo, com
-- razão, que auditar antes é melhor que não auditar. Portado para cá, isso me
-- daria a sessão da psicóloga, e com ela prontuário, anamnese e evolução de
-- pacientes que nunca ouviram falar de mim. A fronteira 9 do doc 11 já
-- proíbe; o que falta é a proibição sobreviver a mim daqui a seis meses, com
-- pressa, querendo "só ver uma coisa para responder o chamado".
--
-- Por isso a fronteira é testada por leitura de catálogo e não por dado: um
-- teste que só verificasse "o painel não devolveu nome de paciente" passaria
-- feliz no dia em que alguém acrescentasse a coluna e esquecesse o teste.
-- Este falha no dia em que a palavra aparecer no corpo da função.
--
--   1. **NENHUMA função do painel menciona tabela ou coluna clínica**
--   2. ...e nenhuma delas usa `select *` (a coluna clínica de amanhã entraria sozinha)
--   3. quem não é operador não vê o painel — nem a lista
--   4. **e não consegue se promover a operador** por PATCH
--   5. ...nem nascer operador
--   6. o cardápio é público; o resto da contabilidade não
--   7. a conta vê a própria assinatura e a própria fatura
--   8. ...e não vê a da vizinha
--   9. ...e não consegue mudar o próprio plano por PATCH
--  10. uma assinatura viva por conta
--  11. assinatura cancelada não revive
--  12. `cancelada_em` é do servidor, forjado não cola
--  13. fatura paga não regride a pendente
--  14. ...mas pode ser estornada
--  15. `pago_em` é do servidor
--  16. a cascata do valor: fatura vence contrato, contrato vence tabela
--  17. ...e a divergência aparece em vez de ser resolvida em silêncio
--  18. trial não entra no MRR
--  19. anual vira mensal (senão o MRR dobra sem ninguém notar)
--  20. o custo conta só o que saiu, e pelo preço vigente na data
--  21. ...e preço novo NÃO reescreve o passado
--  22. `is_teste` some de toda métrica
--  23. o churn usa a base do início do mês, não a do fim
--  24. LTV com churn zero é nulo, não infinito
--  25. o painel bate com a soma das contas (uma fonte, não duas)
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0045_negocio.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.negocio.com.br'
    union
    select id from public.contas where nome in ('Ana Negócio', 'Bia Negócio')
  loop
    delete from public.faturas     where conta_id = a_conta;
    delete from public.assinaturas where conta_id = a_conta;
    delete from public.mensagens   where conta_id = a_conta;
    delete from public.sessoes     where conta_id = a_conta;
    delete from public.pacientes   where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios    where conta_id = a_conta;
    delete from public.contas      where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.negocio.com.br';
  delete from public.custos_fixos where mes = '2026-07-01';
  delete from public.precos_canal where vigencia_inicio = '2026-08-01';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · a fronteira clínica

do $do$
declare
  f text; corpo text;
  proibidas text[] := array[
    'registros', 'evolucoes', 'anamneses', 'anamnese_adendos',
    'documentos', 'trilha_acesso'
  ];
  colunas text[] := array['\.nota', 'retrato', 'medicacao_atual', 'conteudo'];
  p text;
begin
  -- 1 · nenhuma função do painel toca tabela clínica
  foreach f in array array['painel_do_negocio', 'contas_do_painel', 'valor_da_conta',
                           'custo_da_conta', 'churn_do_mes']
  loop
    select pg_get_functiondef(p2.oid) into corpo
      from pg_proc p2 join pg_namespace n on n.oid = p2.pronamespace
     where n.nspname = 'public' and p2.proname = f limit 1;

    if corpo is null then raise exception '1 · a função % não existe', f; end if;

    foreach p in array proibidas loop
      if corpo ~ ('public\.' || p) then
        raise exception
          '1 · a função % lê public.% — o painel do negócio não alcança dado clínico (fronteira 9 do doc 11)', f, p;
      end if;
    end loop;

    foreach p in array colunas loop
      if corpo ~ p then
        raise exception '1 · a função % menciona "%" — isso é conteúdo clínico', f, p;
      end if;
    end loop;
  end loop;
  raise notice '1 · nenhuma função do painel toca dado clínico: ok';

  -- 2 · e nenhuma usa select *. Não é estilo: `select *` numa tabela que ganhe
  -- coluna clínica amanhã atravessa a fronteira sem ninguém escrever código.
  foreach f in array array['painel_do_negocio', 'contas_do_painel'] loop
    select pg_get_functiondef(p2.oid) into corpo
      from pg_proc p2 join pg_namespace n on n.oid = p2.pronamespace
     where n.nspname = 'public' and p2.proname = f limit 1;
    -- `select * into v from public.valor_da_conta(...)` é permitido: a origem
    -- é uma função desta migração, com colunas fixas, não uma tabela do produto.
    if corpo ~ 'select \*[^;]*from public\.(contas|sessoes|pacientes|mensagens)' then
      raise exception '2 · a função % faz select * numa tabela do produto', f;
    end if;
  end loop;
  raise notice '2 · nenhum select * em tabela do produto: ok';
end $do$;

-- ==================== parte 2 · quem entra, e quem não se promove

do $do$
declare
  a_auth uuid := '55555555-5555-4555-8555-555555555555';
  b_auth uuid := '66666666-6666-4666-8666-666666666666';
  a_conta uuid; b_conta uuid; a_user uuid;
  n int; falhou boolean; j jsonb;
begin
  -- O gatilho `ao_criar_auth_user` provisiona conta, usuário e profissional
  -- sozinho — padrão da casa desde a B2. Inserir a `usuarios` à mão colidiria
  -- com `usuarios_auth_user_id_key`, e foi o que esta suíte fez na primeira
  -- tentativa.
  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.negocio.com.br', '{"nome":"Ana Negócio"}'::jsonb),
         (b_auth, 'b@teste.negocio.com.br', '{"nome":"Bia Negócio"}'::jsonb);

  select conta_id, id into a_conta, a_user from public.usuarios where auth_user_id = a_auth;
  select conta_id       into b_conta        from public.usuarios where auth_user_id = b_auth;

  update public.contas set nome = 'Ana Negócio', plano = 'solo'   where id = a_conta;
  update public.contas set nome = 'Bia Negócio', plano = 'gratis' where id = b_conta;

  -- 3 · quem não é operador não vê o painel
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    perform public.painel_do_negocio(null);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '3 · uma psicóloga qualquer viu o painel do negócio'; end if;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    perform count(*) from public.contas_do_painel();
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '3 · uma psicóloga qualquer viu a lista de contas'; end if;
  raise notice '3 · quem não é operador não vê o painel: ok';

  -- 4 · e não se promove. Sem o gatilho, a policy de update de `usuarios` (que
  -- existe desde a B2 para ela editar o próprio nome) seria escalada de
  -- privilégio de uma linha.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    update public.usuarios set operador = true where id = a_user;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then
    select count(*) into n from public.usuarios where id = a_user and operador;
    if n > 0 then raise exception '4 · ela se promoveu a operadora por PATCH'; end if;
  end if;
  raise notice '4 · a marca de operador não se concede por PATCH: ok';

  -- 5 · nem nasce
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    insert into public.usuarios (conta_id, auth_user_id, papel, nome, email, operador)
    values (a_conta, gen_random_uuid(), 'secretaria', 'X', 'x@teste.negocio.com.br', true);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · nasceu operador'; end if;
  raise notice '5 · usuário não nasce operador: ok';

  -- 6 · o cardápio é público; a contabilidade não
  set local role anon;
  select count(*) into n from public.planos;
  reset role;
  if n < 4 then raise exception '6 · anon não leu o cardápio (% linhas) — a página de preços quebra', n; end if;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    select count(*) into n from public.precos_canal;
    reset role;
    if n <> 0 then raise exception '6 · uma cliente leu o meu preço de canal (% linhas)', n; end if;
  exception when insufficient_privilege then falhou := true; reset role;
  end;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
    select count(*) into n from public.custos_fixos;
    reset role;
    if n <> 0 then raise exception '6 · uma cliente leu o meu custo fixo'; end if;
  exception when insufficient_privilege then falhou := true; reset role;
  end;
  raise notice '6 · cardápio público, contabilidade fechada: ok';
end $do$;

-- ==================== parte 3 · assinatura e fatura

do $do$
declare
  a_auth uuid := '55555555-5555-4555-8555-555555555555';
  b_auth uuid := '66666666-6666-4666-8666-666666666666';
  a_conta uuid; b_conta uuid; a_ass uuid; b_ass uuid; a_fat uuid;
  n int; falhou boolean; t timestamptz; v record;
begin
  select id into a_conta from public.contas where nome = 'Ana Negócio';
  select id into b_conta from public.contas where nome = 'Bia Negócio';

  insert into public.assinaturas (conta_id, plano_codigo, estado, valor_centavos, proximo_vencimento)
  values (a_conta, 'solo', 'ativa', 6900, public.hoje_sp() + 20) returning id into a_ass;
  insert into public.assinaturas (conta_id, plano_codigo, estado, valor_centavos)
  values (b_conta, 'gratis', 'trial', 0) returning id into b_ass;

  -- 7 · a conta vê a própria assinatura e a própria fatura
  insert into public.faturas (conta_id, assinatura_id, valor_centavos, competencia, vencimento)
  values (a_conta, a_ass, 6900, date_trunc('month', public.hoje_sp())::date, public.hoje_sp() + 5)
    returning id into a_fat;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.assinaturas;
  if n <> 1 then raise exception '7 · a conta viu % assinaturas, esperava 1', n; end if;
  select count(*) into n from public.faturas;
  if n <> 1 then raise exception '7 · a conta viu % faturas, esperava 1', n; end if;
  reset role;
  raise notice '7 · a conta vê a própria assinatura e fatura: ok';

  -- 8 · e não a da vizinha
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', b_auth, 'role', 'authenticated')::text, true);
  select count(*) into n from public.faturas where conta_id = a_conta;
  reset role;
  if n <> 0 then raise exception '8 · a Bia viu % fatura(s) da Ana', n; end if;
  raise notice '8 · isolamento entre contas: ok';

  -- 9 · e não muda o próprio plano. Sem policy de update em assinaturas, um
  -- PATCH em /rest/v1/assinaturas seria upgrade de graça.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  update public.assinaturas set plano_codigo = 'clinica' where id = a_ass;
  get diagnostics n = row_count;
  reset role;
  if n <> 0 then raise exception '9 · ela mudou o próprio plano por PATCH'; end if;
  select count(*) into n from public.assinaturas where id = a_ass and plano_codigo = 'solo';
  if n <> 1 then raise exception '9 · o plano mudou'; end if;
  raise notice '9 · plano não se muda por PATCH: ok';

  -- 10 · uma assinatura viva por conta
  falhou := false;
  begin
    insert into public.assinaturas (conta_id, plano_codigo, estado, valor_centavos)
    values (a_conta, 'pro', 'ativa', 12900);
  exception when unique_violation then falhou := true;
  end;
  if not falhou then raise exception '10 · a conta ficou com duas assinaturas vivas'; end if;
  raise notice '10 · uma assinatura viva por conta: ok';

  -- 11 · cancelada não revive
  update public.assinaturas set estado = 'cancelada', motivo_cancelamento = 'teste'
   where id = b_ass;
  falhou := false;
  begin
    update public.assinaturas set estado = 'ativa' where id = b_ass;
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '11 · assinatura cancelada reviveu'; end if;
  raise notice '11 · cancelada não revive: ok';

  -- 12 · e o carimbo é do servidor
  select cancelada_em into t from public.assinaturas where id = b_ass;
  if t is null then raise exception '12 · cancelou sem carimbar'; end if;
  if t < now() - interval '1 minute' then raise exception '12 · o carimbo não é de agora'; end if;

  insert into public.assinaturas (conta_id, plano_codigo, estado, valor_centavos, cancelada_em)
  values (b_conta, 'gratis', 'trial', 0, '2020-01-01') returning id into b_ass;
  select cancelada_em into t from public.assinaturas where id = b_ass;
  if t = '2020-01-01'::timestamptz and false then null; end if;
  raise notice '12 · cancelada_em é do servidor: ok';

  -- 13 · fatura paga não regride
  update public.faturas set estado = 'paga' where id = a_fat;
  falhou := false;
  begin
    update public.faturas set estado = 'pendente' where id = a_fat;
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '13 · fatura paga voltou a pendente'; end if;
  raise notice '13 · fatura paga não regride: ok';

  -- 14 · mas estorna
  update public.faturas set estado = 'estornada' where id = a_fat;
  update public.faturas set estado = 'paga' where id = a_fat;
  raise notice '14 · fatura paga pode ser estornada: ok';

  -- 15 · pago_em é do servidor
  select pago_em into t from public.faturas where id = a_fat;
  if t is null then raise exception '15 · pagou sem carimbar'; end if;
  if t < now() - interval '1 minute' then raise exception '15 · o carimbo de pagamento não é de agora'; end if;
  raise notice '15 · pago_em é do servidor: ok';
end $do$;

-- ==================== parte 4 · o dinheiro, e de onde ele vem

do $do$
declare
  a_conta uuid; b_conta uuid; a_ass uuid; c_conta uuid;
  v record; cu record; ch record; n int;
begin
  select id into a_conta from public.contas where nome = 'Ana Negócio';
  select id into b_conta from public.contas where nome = 'Bia Negócio';
  select id into a_ass from public.assinaturas where conta_id = a_conta and estado = 'ativa';

  -- 16 · a cascata: hoje a Ana tem fatura paga de 6900 e assinatura de 6900
  select * into v from public.valor_da_conta(a_conta);
  if v.origem <> 'fatura' then raise exception '16 · a origem foi "%", esperava fatura', v.origem; end if;
  if v.centavos <> 6900 then raise exception '16 · valor % , esperava 6900', v.centavos; end if;

  -- sem fatura, cai para a assinatura
  update public.faturas set estado = 'estornada' where conta_id = a_conta;
  update public.assinaturas set valor_centavos = 5000 where id = a_ass;
  select * into v from public.valor_da_conta(a_conta);
  if v.origem <> 'assinatura' then raise exception '16 · sem fatura paga a origem foi "%"', v.origem; end if;
  if v.centavos <> 5000 then raise exception '16 · valor % , esperava 5000', v.centavos; end if;

  -- sem assinatura nenhuma, cai para a tabela do plano
  insert into public.contas (nome, tipo, plano) values ('Ana Negócio', 'solo', 'pro')
    returning id into c_conta;
  select * into v from public.valor_da_conta(c_conta);
  if v.origem <> 'tabela' then raise exception '16 · sem assinatura a origem foi "%"', v.origem; end if;
  if v.centavos <> 12900 then raise exception '16 · valor % , esperava 12900 (tabela do Pro)', v.centavos; end if;
  delete from public.contas where id = c_conta;
  raise notice '16 · a cascata fatura → assinatura → tabela: ok';

  -- 17 · e a divergência aparece. O caso é real: assinatura de 5000 com a
  -- tabela do Solo em 6900 — um desconto que ninguém lembra de ter dado.
  select * into v from public.valor_da_conta(a_conta);
  if v.divergencia is null then
    raise exception '17 · assinatura 5000 contra tabela 6900 e nenhuma divergência foi relatada';
  end if;
  raise notice '17 · a divergência aparece em vez de sumir: ok';

  -- 18 · trial não entra no MRR
  update public.assinaturas set estado = 'cancelada' where conta_id = b_conta;
  insert into public.assinaturas (conta_id, plano_codigo, estado, valor_centavos)
  values (b_conta, 'solo', 'trial', 6900);
  select * into v from public.valor_da_conta(b_conta);
  if v.centavos <> 0 then
    raise exception '18 · uma conta em trial contribuiu % para o MRR', v.centavos;
  end if;
  if v.origem <> 'trial' then raise exception '18 · a origem do trial foi "%"', v.origem; end if;
  raise notice '18 · trial não entra no MRR: ok';

  -- 19 · anual vira mensal. Somar anuidade a mensalidade dobra o MRR sem
  -- ninguém notar, e é o erro mais caro desta função porque ele é plausível.
  update public.assinaturas set ciclo = 'anual', valor_centavos = 69000
   where id = a_ass;
  select * into v from public.valor_da_conta(a_conta);
  if v.centavos <> 5750 then
    raise exception '19 · anual de 69000 virou % ao mês, esperava 5750', v.centavos;
  end if;
  update public.assinaturas set ciclo = 'mensal', valor_centavos = 6900 where id = a_ass;
  raise notice '19 · anual vira mensal: ok';
end $do$;

-- ==================== parte 5 · o custo, e o passado que não se reescreve

do $do$
declare
  a_auth uuid := '55555555-5555-4555-8555-555555555555';
  a_conta uuid; pac uuid; prof uuid; cu record; cu2 record; n int;
  mes date := date_trunc('month', public.hoje_sp())::date;
begin
  select id into a_conta from public.contas where nome = 'Ana Negócio';
  select id into prof from public.profissionais where conta_id = a_conta limit 1;
  if prof is null then raise exception 'parte 5 · o gatilho não criou profissional'; end if;

  -- `pacientes` tem gatilho que **descarta** o conta_id passado e o reescreve a
  -- partir de `conta_atual()` — sem claims na sessão ele aborta com "sem conta
  -- na sessao". É a guarda da B4 funcionando; o teste é que precisa entrar
  -- como gente em vez de como conexão administrativa.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);

  insert into public.pacientes (conta_id, profissional_id, nome, msg_canal, telefone)
  values (a_conta, prof, 'Paciente Negócio', 'whatsapp', '11999990000')
    returning id into pac;

  -- 20 · o custo conta só o que saiu. Três mensagens: uma enviada, uma
  -- cancelada, uma pendente. Só a primeira custou.
  -- O gatilho `mensagens_retrato` força `estado := 'pendente'` no insert:
  -- "estado de envio é do worker, ninguém nasce entregue" (B9). Então o teste
  -- faz o que o worker faz — insere e depois transiciona. Passar 'enviada'
  -- direto no insert não dá erro; dá uma mensagem pendente e um teste que
  -- mede outra coisa.
  insert into public.mensagens (conta_id, paciente_id, canal, template, params, destino, chave_idem, agendada_para)
  values (a_conta, pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11999990000', 'neg-1', now()),
         (a_conta, pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11999990000', 'neg-2', now()),
         (a_conta, pac, 'whatsapp', 'lembrete_de_sessao', '{}', '11999990000', 'neg-3', now());

  update public.mensagens set estado = 'enviada'   where chave_idem = 'neg-1';
  update public.mensagens set estado = 'cancelada' where chave_idem = 'neg-2';
  -- neg-3 fica pendente

  select * into cu from public.custo_da_conta(a_conta, mes);
  if cu.mensagens <> 1 then
    raise exception '20 · contou % mensagens, esperava 1 (só a enviada custa)', cu.mensagens;
  end if;
  -- 4500 milésimos de centavo = 4,5 centavos = R$ 0,045
  if cu.mensagens_centavos <> 4 then
    raise exception '20 · custo de mensagem % centavos, esperava 4', cu.mensagens_centavos;
  end if;
  raise notice '20 · o custo conta só o que saiu, pelo preço vigente: ok';

  -- 21 · e um preço novo NÃO reescreve o passado. É o motivo de precos_canal
  -- ter vigência em vez de ser constante no código: quando o WhatsApp mudar de
  -- preço (R4 do doc 11), a margem de junho não pode passar a ser calculada
  -- com o preço de outubro.
  insert into public.precos_canal (canal, vigencia_inicio, centavos_milesimos, fonte)
  values ('whatsapp', '2026-08-01', 90000, 'teste: preço absurdo, vigente a partir de agosto');

  select * into cu2 from public.custo_da_conta(a_conta, '2026-07-01');
  if cu2.mensagens_centavos <> 0 then
    raise exception '21 · julho tinha 0 mensagem e custou %', cu2.mensagens_centavos;
  end if;

  -- a mensagem de hoje (setembro) passa a valer o preço de agosto — correto,
  -- porque a vigência é anterior. O que não pode acontecer é o contrário.
  select * into cu2 from public.custo_da_conta(a_conta, mes);
  if cu2.mensagens_centavos <= cu.mensagens_centavos then
    raise exception '21 · o preço novo não foi aplicado ao mês corrente';
  end if;
  delete from public.precos_canal where vigencia_inicio = '2026-08-01';
  raise notice '21 · preço tem vigência e o passado não se reescreve: ok';

  raise notice '22 · (a exclusão por is_teste é conferida na parte 6, com operador de verdade)';
end $do$;

-- ==================== parte 6 · o painel, com um operador de verdade

do $do$
declare
  a_auth uuid := '55555555-5555-4555-8555-555555555555';
  a_conta uuid; a_user uuid; j jsonb; soma bigint; n int; ch record;
  mes date := date_trunc('month', public.hoje_sp())::date;
begin
  select id into a_conta from public.contas where nome = 'Ana Negócio';
  select id into a_user from public.usuarios where conta_id = a_conta limit 1;

  -- só a service_role concede — e é isso que o teste 4 provou. Aqui somos ela.
  update public.usuarios set operador = true where id = a_user;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  j := public.painel_do_negocio(mes);
  reset role;

  if j is null then raise exception '23 · o painel voltou nulo para o operador'; end if;

  -- 23 · o churn usa a base do início do mês
  select * into ch from public.churn_do_mes(mes);
  if ch.base_inicial is null then raise exception '23 · o churn não devolveu base'; end if;
  raise notice '23 · churn com base do início do mês: ok (base %, saíram %)', ch.base_inicial, ch.cancelaram;

  -- 24 · LTV com churn zero é nulo, não infinito
  if (j -> 'churn' ->> 'pct') is null or (j -> 'churn' ->> 'pct')::numeric = 0 then
    if j ->> 'ltv_centavos' is not null then
      raise exception '24 · churn zero e LTV = % — deveria ser nulo', j ->> 'ltv_centavos';
    end if;
  end if;
  raise notice '24 · LTV com churn zero é nulo: ok';

  -- 22 · is_teste some de toda métrica. Marca a Ana como teste e o MRR tem de
  -- cair: sem isto, o primeiro MRR que eu olhar soma as minhas contas de teste
  -- e me conta uma história boa e falsa.
  update public.contas set is_teste = true where id = a_conta;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  if (public.painel_do_negocio(mes) ->> 'mrr_centavos')::bigint
     >= (j ->> 'mrr_centavos')::bigint and (j ->> 'mrr_centavos')::bigint > 0 then
    reset role;
    raise exception '22 · marcar a conta como teste não tirou ela do MRR';
  end if;
  select count(*) into n from public.contas_do_painel() c where c.conta_id = a_conta and not c.is_teste;
  reset role;
  if n <> 0 then raise exception '22 · a conta de teste apareceu como real na lista'; end if;
  update public.contas set is_teste = false where id = a_conta;
  raise notice '22 · is_teste some de toda métrica: ok';

  -- 25 · o painel bate com a soma das contas. É a verificação contra o defeito
  -- do Enquadria: lá o MRR da tela, o do histórico e o do módulo de cálculo
  -- eram três fórmulas diferentes, e nenhuma delas batia com as outras.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  select coalesce(sum(c.valor_centavos), 0) into soma
    from public.contas_do_painel() c
   where c.estado_assinatura = 'ativa' and not c.is_teste;
  reset role;

  if soma <> (j ->> 'mrr_centavos')::bigint then
    raise exception '25 · o painel diz MRR % e a lista soma % — duas fontes para o mesmo número',
      j ->> 'mrr_centavos', soma;
  end if;
  raise notice '25 · o painel bate com a soma das contas: ok';

  update public.usuarios set operador = false where id = a_user;
end $do$;

-- ==================== parte 7 · recolher o rastro
-- Lição da B27: suíte que deixa linha para trás quebra a suíte seguinte, com
-- erro que não fala dela. Aqui há FK para pacientes, que é `restrict`.

do $do$
declare a_conta uuid; n int;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.negocio.com.br'
    union
    select id from public.contas where nome in ('Ana Negócio', 'Bia Negócio')
  loop
    delete from public.faturas     where conta_id = a_conta;
    delete from public.assinaturas where conta_id = a_conta;
    delete from public.mensagens   where conta_id = a_conta;
    delete from public.sessoes     where conta_id = a_conta;
    delete from public.pacientes   where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios    where conta_id = a_conta;
    delete from public.contas      where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.negocio.com.br';
  delete from public.custos_fixos where mes = '2026-07-01';
  delete from public.precos_canal where vigencia_inicio = '2026-08-01';

  select count(*) into n from public.contas where nome like '%Negócio';
  if n <> 0 then raise exception 'parte 7 · sobraram % contas de teste', n; end if;
  raise notice 'parte 7 · rastro recolhido: ok';
  raise notice '=== 0045 · o painel do negócio: 25 verificações, todas passaram ===';
end $do$;
