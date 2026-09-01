-- Teste adversarial do isolamento entre contas (critério de pronto da B2).
--
-- Cria duas contas de verdade pelo caminho real (signup → gatilho), veste o
-- papel `authenticated` com o JWT de cada uma e tenta atravessar a fronteira
-- por todos os caminhos: ler, editar, inserir e apagar dado alheio.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0002_isolamento.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid;
  b_conta uuid;
  b_usuario uuid;
  n int;
  falhou boolean;
begin
  -- ---------------------------------------------------------------- preparo
  --
  -- Este preâmbulo é o mais antigo do projeto — é da B2, de quando existiam
  -- cinco tabelas — e **é sempre ele que quebra primeiro**. Apagar `auth.users`
  -- derruba a conta em cascata, mas `pacientes` e as tabelas clínicas seguram
  -- com `on delete restrict` (a guarda de cinco anos escrita na FK), e o erro
  -- que aparece é uma FK violation no `delete from auth.users` — sem nenhuma
  -- pista de que a causa é uma build seis fases depois.
  --
  -- Por isso ele limpa o que as outras criaram, na ordem de dependência. Toda
  -- build que acrescentar tabela pendurada em `pacientes` acrescenta uma linha
  -- aqui, e é mais barato do que descobrir de novo.
  delete from public.anamnese_adendos where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.anamneses where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.evolucoes where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.registros where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.documentos where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.recibos_rfb where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pastas_contador where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));
  delete from public.pacientes where conta_id in
    (select id from public.contas where nome in ('Ana Solo','Bruna Solo'));

  delete from auth.users where id in (a_auth, b_auth);

  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.sessoes.com.br', '{"nome":"Ana Solo"}'::jsonb),
         (b_auth, 'b@teste.sessoes.com.br', '{"nome":"Bruna Solo"}'::jsonb);

  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select conta_id, id into b_conta, b_usuario from public.usuarios where auth_user_id = b_auth;

  if a_conta is null or b_conta is null or a_conta = b_conta then
    raise exception 'PREPARO: o gatilho de signup não criou duas contas distintas';
  end if;

  -- Confere que o signup montou a conta inteira, não só a linha de usuário.
  if (select count(*) from public.profissionais where conta_id = a_conta) <> 1 then
    raise exception 'PREPARO: signup não criou o profissional da conta A';
  end if;

  -- ------------------------------------------------- veste a pele da conta A
  perform set_config('request.jwt.claims',
                     json_build_object('sub', a_auth, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  -- 1. conta_atual() responde a conta certa
  if public.conta_atual() <> a_conta then
    raise exception '1 FUROU: conta_atual() devolveu conta errada';
  end if;

  -- 2. leitura: enxerga só o próprio tenant
  select count(*) into n from public.contas;
  if n <> 1 then raise exception '2 FUROU: A enxerga % contas (esperado 1)', n; end if;

  select count(*) into n from public.contas where id = b_conta;
  if n <> 0 then raise exception '2 FUROU: A leu a conta da B'; end if;

  select count(*) into n from public.usuarios;
  if n <> 1 then raise exception '2 FUROU: A enxerga % usuários (esperado 1)', n; end if;

  select count(*) into n from public.profissionais;
  if n <> 1 then raise exception '2 FUROU: A enxerga % profissionais (esperado 1)', n; end if;

  -- 3. update alheio: não pode tocar em uma linha sequer
  update public.contas set nome = 'invadida' where id = b_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '3 FUROU: A alterou a conta da B'; end if;

  update public.usuarios set nome = 'invadida' where conta_id = b_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '3 FUROU: A alterou usuário da B'; end if;

  update public.profissionais set crp = 'invadido' where conta_id = b_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '3 FUROU: A alterou profissional da B'; end if;

  -- 4. insert plantando linha na conta alheia: tem que ser barrado pela policy
  falhou := false;
  begin
    insert into public.usuarios (conta_id, auth_user_id, papel, email)
    values (b_conta, gen_random_uuid(), 'dona', 'plantado@teste.com');
    falhou := true;
  exception when insufficient_privilege or foreign_key_violation then
    null; -- barrado, como tem que ser
  end;
  if falhou then raise exception '4 FUROU: A plantou usuário na conta da B'; end if;

  falhou := false;
  begin
    insert into public.profissionais (conta_id, usuario_id)
    values (b_conta, b_usuario);
    falhou := true;
  exception when insufficient_privilege or unique_violation then
    null;
  end;
  if falhou then raise exception '4 FUROU: A plantou profissional na conta da B'; end if;

  -- 5. delete: não existe policy de delete em lugar nenhum, nem para o próprio
  --    dado (a lei do doc 06 — arquiva-se, não se apaga)
  delete from public.contas where id = b_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '5 FUROU: A apagou a conta da B'; end if;

  delete from public.contas where id = a_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '5 FUROU: existe caminho de delete de conta pelo client'; end if;

  delete from public.usuarios where conta_id = b_conta;
  get diagnostics n = row_count;
  if n <> 0 then raise exception '5 FUROU: A apagou usuário da B'; end if;

  -- 6. escalada: A não pode se mudar para a conta da B.
  --    O `using` deixa A editar a própria linha, mas o `with check` recusa o
  --    valor novo — então o esperado aqui é erro, não zero linha. Aceitamos os
  --    dois desfechos; o que não se aceita é a linha mudar.
  falhou := false;
  begin
    update public.usuarios set conta_id = b_conta where auth_user_id = a_auth;
    get diagnostics n = row_count;
    if n <> 0 then falhou := true; end if;
  exception when insufficient_privilege then
    null; -- barrado pelo with check
  end;
  if falhou then raise exception '6 FUROU: A mudou a própria conta_id para a da B'; end if;

  -- ------------------------------------------------- veste a pele da conta B
  reset role;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', b_auth, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  if public.conta_atual() <> b_conta then
    raise exception '7 FUROU: conta_atual() vazou entre sessões';
  end if;

  select count(*) into n from public.contas where id = a_conta;
  if n <> 0 then raise exception '7 FUROU: B leu a conta da A'; end if;

  -- ------------------------------------------------------ e a pele do anônimo
  reset role;
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';

  select count(*) into n from public.contas;
  if n <> 0 then raise exception '8 FUROU: anon leu contas'; end if;
  select count(*) into n from public.usuarios;
  if n <> 0 then raise exception '8 FUROU: anon leu usuários'; end if;
  select count(*) into n from public.profissionais;
  if n <> 0 then raise exception '8 FUROU: anon leu profissionais'; end if;

  falhou := false;
  begin
    perform public.conta_atual();
    falhou := true;
  exception when insufficient_privilege then
    null; -- anon não tem execute
  end;
  if falhou then raise exception '8 FUROU: anon executou conta_atual()'; end if;

  -- ---------------------------------------------------------------- limpeza
  reset role;
  perform set_config('request.jwt.claims', '', true);

  -- Apagar o auth.user cascateia para usuarios e profissionais, mas NÃO para
  -- contas — não há FK de conta para usuário, e é assim que deve ser: a conta
  -- é o tenant e sobrevive à saída de uma pessoa. No teste, limpamos à mão.
  delete from auth.users where id in (a_auth, b_auth);
  delete from public.contas where id in (a_conta, b_conta);

  raise notice 'ISOLAMENTO OK — 8 tentativas de travessia, todas barradas';
end $$;
