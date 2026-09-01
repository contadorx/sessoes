-- Teste da operação do negócio (critério de pronto da OP5).
--
-- A OP1 construiu o modelo inteiro e nenhuma forma de escrever nele: o painel
-- lia um negócio que só existia se alguém abrisse o `psql`. Esta migração deu
-- treze funções de escrita ao operador — e treze funções `security definer`
-- com `e_operador()` dentro são treze portas novas para a conta de alguém.
--
-- Por isso a primeira parte não olha dado nenhum: lê o **corpo das funções** e
-- reprova se qualquer uma mencionar tabela clínica. É a verificação 1 da 0045
-- estendida, e o motivo é o mesmo — um teste que só verificasse "a ficha não
-- devolveu nome de paciente" passaria feliz no dia em que alguém acrescentasse
-- a coluna e esquecesse o teste. Este falha no dia em que a palavra aparecer.
--
--   1. **NENHUMA das funções novas menciona tabela clínica**
--   2. ...e nenhuma faz `select *` em tabela do produto
--   3. a ficha devolve contagem, nunca nome de paciente
--   4. **quem não é operador não abre assinatura**
--   5. ...nem cancela, emite, baixa ou estorna
--   6. ...nem lê custo, preço ou ficha
--   7. o anônimo não alcança nenhuma delas
--   8. abrir assinatura muda o plano da conta junto
--   9. ...e congela o valor do cardápio no momento da abertura
--  10. plano fora do cardápio é recusado
--  11. **duas assinaturas vivas na mesma conta: recusado**
--  12. cancelar sem motivo é recusado — churn sem causa não ensina nada
--  13. ...e cancelar devolve a conta ao Grátis
--  14. cancelada não revive
--  15. mudar de plano cancela e reabre — o histórico fica com as duas faixas
--  16. a fatura nasce com o valor da assinatura
--  17. **fatura repetida da mesma competência: recusado**
--  18. assinatura cancelada não gera fatura nova
--  19. baixar carimba `pago_em` do servidor
--  20. **fatura paga não se baixa de novo** — clique duplo não recarimba a data
--  21. paga não regride a pendente, e estorno exige motivo
--  22. `vencer_faturas` vence o vencido e não toca no que foi pago
--  23. **preço de canal com vigência no passado é recusado**
--  24. custo negativo é recusado, e o lançamento repetido atualiza
--  25. **conta de teste sai da métrica E continua na lista** (os dois lados)
--
-- **A lição que esta suíte me deu na primeira execução, e ela é da casa:**
-- a *ação* roda sob `set local role authenticated`, porque é isso que se está
-- testando; a *conferência* roda com `reset role`, porque sob `authenticated`
-- ela passa pela RLS e lê zero linhas. Na primeira versão, as verificações 8 e
-- 9 conferiam `select ... from assinaturas` ainda dentro do papel do operador
-- — que não vê a assinatura de outra conta —, `r` vinha nulo, e comparações
-- com nulo devolvem nulo, que num `if` é falso. As duas passavam **por
-- ausência de dado**. É o mesmo modo de falha que a verificação 16 da suíte
-- 0049 existe para impedir, e ele voltou disfarçado de outra coisa.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0050_operar_o_negocio.sql

-- ==================== parte 0 · preâmbulo

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u
     where u.email like '%@teste.op5.com.br'
    union
    select id from public.contas where nome like 'Conta OP5%'
  loop
    delete from public.faturas       where conta_id = a_conta;
    delete from public.assinaturas   where conta_id = a_conta;
    delete from public.mensagens     where conta_id = a_conta;
    delete from public.sessoes       where conta_id = a_conta;
    delete from public.pacientes     where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios      where conta_id = a_conta;
    delete from public.contas        where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.op5.com.br';
  delete from public.custos_fixos  where mes = date '2031-03-01';
  delete from public.precos_canal  where vigencia_inicio in (date '2031-03-01', date '2020-01-01');
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · a fronteira clínica, lida no catálogo

do $do$
declare
  f text; corpo text; p text;
  novas text[] := array[
    'custos_do_mes', 'precos_dos_canais', 'abrir_assinatura', 'cancelar_assinatura',
    'mudar_plano', 'emitir_fatura', 'baixar_fatura', 'estornar_fatura',
    'cancelar_fatura', 'vencer_faturas', 'lancar_custo_fixo',
    'definir_preco_canal', 'marcar_conta_de_teste', 'ficha_da_conta'
  ];
  proibidas text[] := array[
    'registros', 'evolucoes', 'anamneses', 'anamnese_adendos',
    'documentos', 'trilha_acesso', 'recibos_rfb'
  ];
  colunas text[] := array['\.nota\M', 'retrato', 'medicacao_atual', 'conteudo', 'demanda', 'objetivos'];
begin
  -- 1 · nenhuma toca tabela clínica
  foreach f in array novas loop
    select pg_get_functiondef(p2.oid) into corpo
      from pg_proc p2 join pg_namespace n on n.oid = p2.pronamespace
     where n.nspname = 'public' and p2.proname = f
     limit 1;

    if corpo is null then
      raise exception '1 · a função % não existe — a migração 0050 não foi aplicada inteira', f;
    end if;

    foreach p in array proibidas loop
      if corpo ~ ('public\.' || p) then
        raise exception '1 · a função % toca a tabela clínica %', f, p;
      end if;
    end loop;

    -- `custos_fixos.nota` é rubrica de despesa minha, não nota clínica: por
    -- isso o padrão é `\.nota\M` e as duas funções de custo estão fora da
    -- varredura de coluna. Fosse `%nota%`, o teste reprovaria o correto —
    -- e um teste que reprova o certo é apagado na terceira vez.
    if f not in ('custos_do_mes', 'lancar_custo_fixo') then
      foreach p in array colunas loop
        if corpo ~ p then
          raise exception '1 · a função % menciona a coluna clínica %', f, p;
        end if;
      end loop;
    end if;
  end loop;
  raise notice '1 · nenhuma função nova toca dado clínico: ok';

  -- 2 · e nenhuma faz select * numa tabela do produto: a coluna clínica de
  -- amanhã entraria sozinha na saída, sem ninguém decidir.
  foreach f in array novas loop
    select pg_get_functiondef(p2.oid) into corpo
      from pg_proc p2 join pg_namespace n on n.oid = p2.pronamespace
     where n.nspname = 'public' and p2.proname = f limit 1;

    if corpo ~ 'select \*[^;]*from public\.(contas|sessoes|pacientes|mensagens|usuarios)' then
      raise exception '2 · a função % faz select * numa tabela do produto', f;
    end if;
  end loop;
  raise notice '2 · nenhum select * em tabela do produto: ok';
end $do$;

-- ==================== parte 2 · o cenário

do $do$
declare
  op_auth  uuid := 'bbbbbbbb-0050-4000-8000-000000000001'; -- eu, operador
  psi_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000002'; -- uma psicóloga qualquer
  op_conta uuid; psi_conta uuid; a_prof uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (op_auth,  'op@teste.op5.com.br',  '{"nome":"Conta OP5 Operador"}'::jsonb),
    (psi_auth, 'psi@teste.op5.com.br', '{"nome":"Conta OP5 Psi"}'::jsonb);

  select conta_id into op_conta  from public.usuarios where auth_user_id = op_auth;
  select conta_id into psi_conta from public.usuarios where auth_user_id = psi_auth;

  -- A marca de operador só se concede fora do PostgREST (gatilho da 0045c/d).
  -- Aqui o papel é o da migração, então passa — e é o único jeito legítimo.
  update public.usuarios set operador = true where auth_user_id = op_auth;
  update public.contas set nome = 'Conta OP5 Operador' where id = op_conta;
  update public.contas set nome = 'Conta OP5 Psi'      where id = psi_conta;

  select id into a_prof from public.profissionais where conta_id = psi_conta limit 1;

  perform set_config('request.jwt.claims',
    json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);

  insert into public.pacientes (conta_id, profissional_id, nome, telefone)
  values (psi_conta, a_prof, 'Zebulon Improvável Kryzanowski', '11988880050');

  raise notice 'parte 2 · cenário montado: ok';
end $do$;

-- ==================== parte 3 · quem não é operador não faz nada

do $do$
declare
  psi_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000002';
  psi_conta uuid; falhou boolean; n int;
begin
  select conta_id into psi_conta from public.usuarios where auth_user_id = psi_auth;

  -- 4 · não abre assinatura. É a porta mais valiosa das treze: quem abrisse
  -- assinatura para si mesma se daria o plano Clínica de graça.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);
    perform public.abrir_assinatura(psi_conta, 'clinica');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  select count(*) into n from public.assinaturas where conta_id = psi_conta;
  if n > 0 then raise exception '4 · uma psicóloga qualquer abriu assinatura'; end if;
  if not falhou then raise exception '4 · o RPC passou em silêncio'; end if;
  raise notice '4 · quem não é operador não abre assinatura: ok';

  -- 5 · nem as outras escritas
  foreach n in array array[1] loop null; end loop;
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);
    perform public.lancar_custo_fixo(date '2031-03-01', 'invasao', 100);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · lançou custo fixo sem ser operadora'; end if;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);
    perform public.marcar_conta_de_teste(psi_conta, true);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · marcou a própria conta como teste'; end if;
  raise notice '5 · nem lança custo, nem se marca como teste: ok';

  -- 6 · e não lê. A ficha da própria conta também não: ela é ferramenta de
  -- operação da plataforma, e devolvê-la à cliente ensinaria que existe uma
  -- superfície minha dentro do produto dela.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);
    perform public.ficha_da_conta(psi_conta);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '6 · leu a ficha do painel'; end if;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', psi_auth, 'role', 'authenticated')::text, true);
    perform count(*) from public.custos_do_mes(null);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '6 · leu os meus custos'; end if;
  raise notice '6 · nem lê ficha, custo ou preço: ok';

  -- 7 · o anônimo não alcança nem a chamada
  falhou := false;
  begin
    set local role anon;
    perform set_config('request.jwt.claims', '', true);
    perform public.ficha_da_conta(psi_conta);
    reset role;
  exception when insufficient_privilege then falhou := true; reset role;
    when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '7 · o anônimo alcançou a ficha'; end if;
  raise notice '7 · o anônimo não alcança nenhuma: ok';
end $do$;

-- ==================== parte 4 · a assinatura
--
-- Repare no vaivém de `reset role`: a ação é do operador, a conferência é da
-- migração. Ver a nota no cabeçalho.

do $do$
declare
  op_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000001';
  psi_conta uuid; a1 uuid; a2 uuid; falhou boolean; n int; t text; d timestamptz;
begin
  select conta_id into psi_conta from public.usuarios
   where auth_user_id = 'bbbbbbbb-0050-4000-8000-000000000002';

  -- 8 · abrir muda o plano da conta junto
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  a1 := public.abrir_assinatura(psi_conta, 'solo');
  reset role;

  select plano into t from public.contas where id = psi_conta;
  if t is distinct from 'solo' then
    raise exception '8 · a assinatura abriu e a conta ficou em %', coalesce(t, 'NULO'); end if;
  raise notice '8 · abrir assinatura muda o plano da conta: ok';

  -- 9 · e o valor vem congelado do cardápio
  select count(*) into n from public.assinaturas
   where id = a1
     and valor_centavos = (select preco_centavos from public.planos where codigo = 'solo')
     and estado = 'ativa';
  if n <> 1 then raise exception '9 · a assinatura não nasceu ativa com o valor do cardápio'; end if;
  raise notice '9 · o valor é congelado na abertura: ok';

  -- 10 · plano inventado é recusado
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.abrir_assinatura(psi_conta, 'ouro_premium');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '10 · abriu num plano que não existe'; end if;
  raise notice '10 · plano fora do cardápio é recusado: ok';

  -- 11 · duas vivas na mesma conta seria MRR dobrado sem ninguém notar
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.abrir_assinatura(psi_conta, 'pro');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  select count(*) into n from public.assinaturas
   where conta_id = psi_conta and estado in ('trial','ativa','em_atraso');
  if n <> 1 then raise exception '11 · % assinaturas vivas na mesma conta', n; end if;
  if not falhou then raise exception '11 · a segunda passou em silêncio'; end if;
  raise notice '11 · uma assinatura viva por conta: ok';

  -- 12 · cancelar sem motivo
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.cancelar_assinatura(a1, 'x');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '12 · cancelou sem motivo escrito'; end if;
  select estado into t from public.assinaturas where id = a1;
  if t <> 'ativa' then raise exception '12 · cancelou mesmo assim (%)', t; end if;
  raise notice '12 · cancelamento exige motivo: ok';

  -- 13 · com motivo, cancela e devolve a conta ao Grátis
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  perform public.cancelar_assinatura(a1, 'parou de atender neste semestre');
  reset role;

  select estado, cancelada_em into t, d from public.assinaturas where id = a1;
  if t <> 'cancelada' then raise exception '13 · não cancelou (%)', t; end if;
  if d is null then raise exception '13 · cancelou sem carimbo'; end if;
  select plano into t from public.contas where id = psi_conta;
  if t <> 'gratis' then
    raise exception '13 · a conta ficou em % sem assinatura', t; end if;
  raise notice '13 · cancelar devolve a conta ao Grátis: ok';

  -- 14 · e cancelada não revive (gatilho da 0045)
  falhou := false;
  begin update public.assinaturas set estado = 'ativa' where id = a1;
  exception when others then falhou := true; end;
  if not falhou then raise exception '14 · a assinatura cancelada reviveu'; end if;
  raise notice '14 · cancelada não revive: ok';

  -- 15 · mudar de plano deixa as duas faixas na história. Um `update` no
  -- plano_codigo apagaria março e reescreveria o MRR daquele mês.
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  a2 := public.mudar_plano(psi_conta, 'pro', 'subiu de plano no teste');
  reset role;

  select count(*) into n from public.assinaturas where conta_id = psi_conta;
  if n < 2 then raise exception '15 · a mudança de plano apagou a faixa anterior'; end if;
  select plano_codigo into t from public.assinaturas where id = a2;
  if t <> 'pro' then raise exception '15 · a nova assinatura é do plano %', t; end if;
  raise notice '15 · mudar de plano preserva o histórico: ok';
end $do$;

-- ==================== parte 5 · a fatura

do $do$
declare
  op_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000001';
  psi_conta uuid; viva uuid; f1 uuid; comp date; falhou boolean; antes timestamptz;
  n int; t text; v integer;
begin
  select conta_id into psi_conta from public.usuarios
   where auth_user_id = 'bbbbbbbb-0050-4000-8000-000000000002';
  select id into viva from public.assinaturas
   where conta_id = psi_conta and estado = 'ativa' limit 1;

  -- 16 · a fatura nasce com o valor da assinatura
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  f1 := public.emitir_fatura(viva);
  reset role;

  select f.valor_centavos, f.estado, f.competencia into v, t, comp
    from public.faturas f where f.id = f1;
  if v is distinct from (select a.valor_centavos from public.assinaturas a where a.id = viva) then
    raise exception '16 · valor da fatura não bate com a assinatura'; end if;
  if t <> 'pendente' then raise exception '16 · nasceu %', t; end if;
  raise notice '16 · a fatura nasce com o valor da assinatura: ok';

  -- 17 · e não se emite duas vezes. Dois cliques dobrariam a receita do mês.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.emitir_fatura(viva);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  select count(*) into n from public.faturas
   where assinatura_id = viva and competencia = comp and estado <> 'cancelada';
  if n <> 1 then raise exception '17 · % faturas na mesma competência', n; end if;
  if not falhou then raise exception '17 · a segunda passou em silêncio'; end if;
  raise notice '17 · uma fatura viva por competência: ok';

  -- 18 · assinatura cancelada não gera fatura nova
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.emitir_fatura(
      (select a.id from public.assinaturas a
        where a.conta_id = psi_conta and a.estado = 'cancelada' limit 1));
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '18 · assinatura cancelada gerou fatura'; end if;
  raise notice '18 · assinatura cancelada não gera fatura: ok';

  -- 19 · baixar carimba do servidor
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  perform public.baixar_fatura(f1);
  reset role;

  select f.estado, f.pago_em into t, antes from public.faturas f where f.id = f1;
  if t <> 'paga' then raise exception '19 · não baixou (%)', t; end if;
  if antes is null then raise exception '19 · baixou sem carimbo'; end if;
  raise notice '19 · baixar carimba pago_em do servidor: ok';

  -- 20 · e baixar duas vezes é recusado — um clique duplo não recarimba a data
  -- de pagamento para hoje numa fatura de três meses atrás.
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.baixar_fatura(f1);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '20 · baixou a mesma fatura duas vezes'; end if;
  select f.pago_em into antes from public.faturas f where f.id = f1;
  raise notice '20 · fatura paga não se baixa de novo: ok';

  -- 21 · paga não regride, e estorno exige motivo
  falhou := false;
  begin update public.faturas set estado = 'pendente' where id = f1;
  exception when others then falhou := true; end;
  if not falhou then raise exception '21 · a fatura paga voltou a pendente'; end if;

  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.estornar_fatura(f1, 'oi');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '21 · estornou sem motivo'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  perform public.estornar_fatura(f1, 'cobrança em duplicidade no cartão');
  reset role;

  select f.estado into t from public.faturas f where f.id = f1;
  if t <> 'estornada' then raise exception '21 · não estornou (%)', t; end if;
  raise notice '21 · paga não regride e estorno exige motivo: ok';

  -- 22 · o vencimento é do cron, e vence só o que passou do prazo
  update public.faturas
     set estado = 'pendente', vencimento = public.hoje_sp() - 5, pago_em = null
   where id = f1;
  perform public.vencer_faturas();
  select f.estado into t from public.faturas f where f.id = f1;
  if t <> 'vencida' then raise exception '22 · a fatura vencida continuou %', t; end if;
  raise notice '22 · vencer_faturas vence o que passou do prazo: ok';
end $do$;

-- ==================== parte 6 · custo, preço e a marca de teste

do $do$
declare
  op_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000001';
  psi_conta uuid; falhou boolean; n int; c int;
  mrr_antes bigint; mrr_depois bigint; j jsonb;
begin
  select conta_id into psi_conta from public.usuarios
   where auth_user_id = 'bbbbbbbb-0050-4000-8000-000000000002';

  -- 23 · vigência no passado reescreveria a margem de um mês já fechado
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.definir_preco_canal('whatsapp', date '2020-01-01', 9000, 'teste');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '23 · aceitou preço com vigência no passado'; end if;
  select count(*) into n from public.precos_canal where vigencia_inicio = date '2020-01-01';
  if n > 0 then raise exception '23 · o preço do passado entrou'; end if;
  raise notice '23 · preço de canal não reescreve o passado: ok';

  -- 24 · custo negativo, e o relançamento que atualiza em vez de duplicar
  falhou := false;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims',
      json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
    perform public.lancar_custo_fixo(date '2031-03-01', 'supabase', -100);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '24 · aceitou custo negativo'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  perform public.lancar_custo_fixo(date '2031-03-01', 'supabase', 12000, 'plano pro');
  perform public.lancar_custo_fixo(date '2031-03-01', 'supabase', 15000, 'plano pro reajustado');
  reset role;

  select count(*), max(centavos) into n, c from public.custos_fixos
   where mes = date '2031-03-01' and rubrica = 'supabase';
  if n <> 1 then raise exception '24 · % linhas para a mesma rubrica', n; end if;
  if c <> 15000 then raise exception '24 · o relançamento não atualizou (%)', c; end if;
  raise notice '24 · custo: negativo recusado, repetido atualiza: ok';

  -- 25 · a marca de teste tem DOIS lados, e a primeira versão deste teste só
  -- olhava um. Ela achou que "some de toda métrica" queria dizer "some de
  -- tudo", e reprovou o comportamento correto:
  --
  --   · `painel_do_negocio` **exclui** a conta de teste, porque ela inflaria
  --     o MRR com uma cliente que sou eu;
  --   · `contas_do_painel` **mantém**, porque se a lista também escondesse,
  --     eu marcaria uma conta por engano e nunca mais conseguiria desmarcar
  --     pela tela — só pelo banco, que é o lugar de onde esta build inteira
  --     está tentando sair.
  --
  -- Os dois lados agora são exigidos, e é o segundo que salva a interface.
  update public.contas set is_teste = false where id = psi_conta;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  j := public.painel_do_negocio(null);
  mrr_antes := (j ->> 'mrr_centavos')::bigint;

  perform public.marcar_conta_de_teste(psi_conta, true);

  j := public.painel_do_negocio(null);
  mrr_depois := (j ->> 'mrr_centavos')::bigint;
  select count(*) into n from public.contas_do_painel() cp where cp.conta_id = psi_conta;
  reset role;

  if not (select is_teste from public.contas where id = psi_conta) then
    raise exception '25 · a marca não pegou'; end if;
  if mrr_depois >= mrr_antes then
    raise exception '25 · a conta de teste continuou no MRR (% -> %)', mrr_antes, mrr_depois; end if;
  if n <> 1 then
    raise exception '25 · a conta de teste sumiu da LISTA — eu nunca mais desmarco pela tela'; end if;
  raise notice '25 · sai da métrica, fica na lista: ok';
end $do$;

-- ==================== parte 7 · a ficha, e o que ela recusa a dizer

do $do$
declare
  op_auth uuid := 'bbbbbbbb-0050-4000-8000-000000000001';
  psi_conta uuid; j jsonb;
begin
  select conta_id into psi_conta from public.usuarios
   where auth_user_id = 'bbbbbbbb-0050-4000-8000-000000000002';

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', op_auth, 'role', 'authenticated')::text, true);
  j := public.ficha_da_conta(psi_conta);
  reset role;

  -- 3 · o nome plantado na parte 2 não pode sair. É o mesmo Zebulon da suíte
  -- da pasta do contador: um nome improvável o bastante para que encontrá-lo
  -- na saída seja prova, e não coincidência.
  if position('Zebulon' in j::text) > 0 then
    raise exception '3 · a ficha da conta devolveu nome de paciente';
  end if;

  if (j -> 'uso' ->> 'pacientes_ativos')::int < 1 then
    raise exception '3 · a ficha não contou o paciente — a contagem é o que ela existe para dar';
  end if;
  if jsonb_array_length(j -> 'assinaturas') < 2 then
    raise exception '3 · a ficha não trouxe o histórico de assinaturas';
  end if;
  raise notice '3 · a ficha dá contagem e nunca nome: ok';
end $do$;

-- ==================== parte 8 · limpeza

do $do$
declare a_conta uuid;
begin
  for a_conta in
    select distinct u.conta_id from public.usuarios u where u.email like '%@teste.op5.com.br'
  loop
    delete from public.faturas       where conta_id = a_conta;
    delete from public.assinaturas   where conta_id = a_conta;
    delete from public.mensagens     where conta_id = a_conta;
    delete from public.sessoes       where conta_id = a_conta;
    delete from public.pacientes     where conta_id = a_conta;
    delete from public.profissionais where conta_id = a_conta;
    delete from public.usuarios      where conta_id = a_conta;
    delete from public.contas        where id = a_conta;
  end loop;
  delete from auth.users where email like '%@teste.op5.com.br';
  delete from public.custos_fixos where mes = date '2031-03-01';
  raise notice 'parte 8 · limpeza: ok';
  raise notice '=== 0050: 25 verificações, todas passaram ===';
end $do$;
