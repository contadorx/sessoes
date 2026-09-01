-- Teste do Panorama — a pesquisa que mora no mesmo banco que o produto.
--
-- Este arquivo é diferente de todos os outros da pasta. Nos demais, o papel
-- perigoso é `authenticated` de outra conta; aqui o papel perigoso é `anon`,
-- e ele tem uma chave **publicada dentro do formulário**. Qualquer pessoa que
-- abrir o código-fonte da página tem essa chave na mão. Então a pergunta que
-- este arquivo responde é uma só, feita de sete ângulos:
--
--     com a chave que está publicada, dá para LER alguma coisa?
--
-- A resposta tem que ser não em todos os ângulos, porque o material do outro
-- lado é o texto que uma psicóloga escreveu sobre o dia dela achando que
-- ninguém saberia que foi ela.
--
-- Duas armadilhas específicas do Supabase, e as duas já morderam:
--
--   · view em Postgres nasce com `security_invoker = off` — roda com os
--     direitos do dono e **ignora a RLS das tabelas de baixo**. Uma view nova
--     sobre `pesquisa_respostas` nasce aberta, e o `ALTER DEFAULT PRIVILEGES`
--     do schema public no Supabase já concedeu tudo para `anon`. Quem cria a
--     décima terceira view e esquece as duas linhas do fim da 0044b publica a
--     pesquisa inteira, e não recebe erro nenhum ao fazer isso.
--
--   · RLS sem policy de SELECT não dá erro: dá **zero linha**. É a lição da
--     B11 e ela vale ao contrário aqui — o silêncio que protege é o mesmo
--     silêncio que esconderia o furo, então o teste precisa provar que a
--     leitura foi barrada, e não só que veio vazia. A 0044 põe as duas
--     travas (policy só de insert **e** revoke), e quem responde primeiro é
--     o revoke, com 42501. As verificações 3 e 4 aceitam qualquer uma das
--     duas: exigir uma delas em particular seria ficar vermelho porque o
--     banco está mais fechado do que o teste imaginou.
--
--   1. as três tabelas existem, com RLS ligada
--   2. `anon` INSERE nas três — se isto quebrar, a pesquisa não coleta nada
--   3. `anon` NÃO LÊ nenhuma das três
--   4. `anon` não atualiza, não apaga
--   5. o CHECK barra lixo: texto curto demais, e-mail que não é e-mail
--   6. o CHECK aceita resposta longa — o teto é contra abuso, não contra pessoa
--   7. `duracao_seg` fora da faixa é recusado (e por isso a página trava antes)
--   8. sessao não-uuid é recusado (o motivo do fallback de uuid na página)
--   9. **as 12 views estão com `security_invoker = on`** — nenhuma passa por cima da RLS
--  10. **`anon` não tem privilégio em nenhuma view**, nem para enxergá-la no PostgREST
--  11. `anon` de fato falha ao ler uma view, com dado real embaixo
--  12. NÃO EXISTE view nova sobre as tabelas da pesquisa fora da lista fechada
--  13. **`pesquisa_contatos` não tem FK, nem coluna `sessao`, nem nada que ligue às respostas**
--  14. ...e nenhuma outra tabela aponta para ela
--  15. as tabelas da pesquisa não têm `conta_id` — a pesquisa não é do produto
--  16. ...e por isso não entram em `exportar_conta` nem em `exportar_paciente`
--  17. a eliminação de conta não toca na pesquisa
--  18. `service_role` lê tudo — senão não há como analisar
--  19. as 12 views respondem com o banco vazio (nenhuma divide por zero)
--  20. o e-mail do contato não vaza para `anon` por nenhum caminho
--  21. as duas funções da LGPD (0044d) não estão publicadas em /rest/v1/rpc
--  22. o pedido de exclusão acha o e-mail e apaga a linha
--  23. ...e não alcança as respostas — a ligação não existe nem para isso
--  24. ...e apaga mesmo, em vez de anonimizar
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0044_panorama.sql

-- ==================== parte 0 · preâmbulo

do $do$
begin
  delete from public.pesquisa_abertas   where canal = 'teste-suite';
  delete from public.pesquisa_respostas where canal = 'teste-suite';
  delete from public.pesquisa_contatos  where email like '%@teste-suite.invalido';
  raise notice 'parte 0 · preâmbulo: ok';
end $do$;

-- ==================== parte 1 · a estrutura, e o que anon pode

do $do$
declare
  n int; falhou boolean; barrado boolean; tab text; s uuid := gen_random_uuid();
begin
  -- 1 · as três tabelas, com RLS
  select count(*) into n
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('pesquisa_abertas','pesquisa_respostas','pesquisa_contatos')
     and c.relrowsecurity;
  if n <> 3 then
    raise exception '1 · esperava 3 tabelas da pesquisa com RLS ligada, achei %', n;
  end if;
  raise notice '1 · as três tabelas, com RLS: ok';

  -- 2 · anon insere nas três. É o único direito que ela tem, e é essencial:
  -- se este bloco quebrar, o formulário fica no ar coletando nada.
  set local role anon;

  insert into public.pesquisa_abertas (sessao, canal, dia, irritante, preocupacao)
  values (s, 'teste-suite',
          'reconstrucao do dia com mais de vinte caracteres',
          'a parte irritante', 'a preocupacao');

  insert into public.pesquisa_respostas (sessao, canal, respostas)
  values (s, 'teste-suite', '{"q43":"4","q71":["cobrar","hora_vazia","fiscal"]}'::jsonb);

  insert into public.pesquisa_contatos (email)
  values ('quem-quer-o-relatorio@teste-suite.invalido');

  reset role;
  raise notice '2 · anon insere nas três: ok';

  -- 3 · e não lê nenhuma.
  --
  -- Há **duas** maneiras de a leitura ser barrada, e o teste aceita as duas,
  -- porque o que importa é que ela seja barrada:
  --
  --   · sem policy de SELECT, a RLS devolve zero linha e nenhum erro;
  --   · sem o GRANT, o Postgres levanta 42501 antes de chegar à RLS.
  --
  -- A 0044 faz as duas coisas — cria só policy de insert **e** revoga o
  -- select. Hoje o que responde é o revoke, e um teste que exigisse
  -- especificamente "zero linha" ficaria vermelho por o banco ser mais
  -- fechado do que o esperado. Cair por excesso de proteção é um jeito bobo
  -- de perder um teste, e ensina a afrouxar o banco para o teste passar.
  for tab in select unnest(array['pesquisa_abertas','pesquisa_respostas','pesquisa_contatos']) loop
    barrado := false;
    begin
      set local role anon;
      execute format('select count(*) from public.%I', tab) into n;
      reset role;
      barrado := (n = 0);
      if n <> 0 then
        raise exception '3 · anon leu % linha(s) de % — a pesquisa está pública', n, tab;
      end if;
    exception when insufficient_privilege then
      barrado := true; reset role;
    end;
    if not barrado then
      raise exception '3 · anon não foi barrado em %', tab;
    end if;
  end loop;
  raise notice '3 · anon não lê nenhuma das três: ok';

  -- 4 · nem escreve por cima, nem apaga. Mesma dupla de mecanismos.
  barrado := false;
  begin
    set local role anon;
    update public.pesquisa_abertas set irritante = 'reescrito';
    get diagnostics n = row_count;
    reset role;
    barrado := (n = 0);
    if n <> 0 then raise exception '4 · anon atualizou % linha(s)', n; end if;
  exception when insufficient_privilege then barrado := true; reset role;
  end;
  if not barrado then raise exception '4 · anon não foi barrado no update'; end if;

  barrado := false;
  begin
    set local role anon;
    delete from public.pesquisa_respostas;
    get diagnostics n = row_count;
    reset role;
    barrado := (n = 0);
    if n <> 0 then raise exception '4 · anon apagou % linha(s)', n; end if;
  exception when insufficient_privilege then barrado := true; reset role;
  end;
  if not barrado then raise exception '4 · anon não foi barrado no delete'; end if;
  raise notice '4 · anon não atualiza nem apaga: ok';

  -- 5 · o CHECK barra lixo
  falhou := false;
  begin
    set local role anon;
    insert into public.pesquisa_abertas (sessao, canal, dia, irritante, preocupacao)
    values (gen_random_uuid(), 'teste-suite', 'curto', 'x', 'y');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · o CHECK aceitou texto curto demais'; end if;

  falhou := false;
  begin
    set local role anon;
    insert into public.pesquisa_contatos (email) values ('isto nao e email');
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '5 · o CHECK aceitou e-mail que não é e-mail'; end if;
  raise notice '5 · o CHECK barra lixo: ok';

  -- 6 · mas aceita resposta longa. A 0044c subiu o teto de 60 mil para 400 mil
  -- justamente porque uma respondente prolixa teria o questionário INTEIRO
  -- recusado — e sem ver erro, porque o envio é best-effort. Perder nove
  -- minutos de alguém por excesso de zelo é o pior modo de falha desta pesquisa.
  set local role anon;
  insert into public.pesquisa_respostas (sessao, canal, respostas)
  values (gen_random_uuid(), 'teste-suite',
          jsonb_build_object('q81', repeat('a', 120000)));
  reset role;
  raise notice '6 · resposta longa passa (teto é contra abuso, não contra pessoa): ok';

  -- 7 · duração fora da faixa é recusada. Existe teste porque a consequência
  -- é desproporcional: uma aba esquecida aberta de um dia para o outro
  -- derrubaria o questionário inteiro. A página trava antes, no cliente.
  falhou := false;
  begin
    set local role anon;
    insert into public.pesquisa_respostas (sessao, canal, duracao_seg, respostas)
    values (gen_random_uuid(), 'teste-suite', 90000, '{}'::jsonb);
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '7 · aceitou duracao_seg de 90000'; end if;
  raise notice '7 · duração fora da faixa é recusada: ok';

  -- 8 · sessao não-uuid é recusada. É o motivo de a página ter fallback de
  -- uuid próprio: sem ele, um Safari antigo perde tudo em silêncio.
  falhou := false;
  begin
    set local role anon;
    execute $q$insert into public.pesquisa_abertas (sessao, canal, dia, irritante, preocupacao)
             values ('1756-nao-e-uuid', 'teste-suite',
                     'reconstrucao do dia com mais de vinte caracteres', 'xxxxxxxxxx', 'yyyyyyyyyy')$q$;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then raise exception '8 · aceitou sessao que não é uuid'; end if;
  raise notice '8 · sessao não-uuid é recusada: ok';
end $do$;

-- ==================== parte 2 · as views, que é onde a pesquisa vazaria

do $do$
declare
  esperadas text[] := array[
    'v_leitura1_fila','v_leitura3_cobranca','v_leitura4_agenda',
    'v_rendimento_canal','v_leitura5_canal','v_ranking_ponderado',
    'v_nao_e_problema','v_residual','v_residual_textos',
    'v_itens_novos','v_qualidade','v_funil'
  ];
  v text; n int; falhou boolean; sobrando text;
begin
  -- 9 · security_invoker = on nas doze. Sem isto a view roda como o dono e
  -- ignora a RLS de baixo — a RLS insert-only não protege nada por trás dela.
  foreach v in array esperadas loop
    select count(*) into n
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relname = v and c.relkind = 'v'
       and coalesce((select option_value from pg_options_to_table(c.reloptions)
                      where option_name = 'security_invoker'), 'off') = 'on';
    if n <> 1 then
      raise exception '9 · a view % não existe ou está com security_invoker desligado — ela passa por cima da RLS', v;
    end if;
  end loop;
  raise notice '9 · as 12 views com security_invoker = on: ok';

  -- 10 · e revogadas. Trava redundante de propósito: com o revoke, anon nem
  -- enxerga a view no PostgREST.
  foreach v in array esperadas loop
    if has_table_privilege('anon', 'public.' || v, 'select') then
      raise exception '10 · anon tem SELECT em public.% — GET /rest/v1/% lê a pesquisa inteira', v, v;
    end if;
    if has_table_privilege('authenticated', 'public.' || v, 'select') then
      raise exception '10 · authenticated tem SELECT em public.% — qualquer assinante do produto lê a pesquisa', v;
    end if;
  end loop;
  raise notice '10 · anon e authenticated sem privilégio em nenhuma view: ok';

  -- 11 · e na prática, com dado real embaixo. As duas travas anteriores são
  -- de catálogo; esta tenta de verdade.
  falhou := false;
  begin
    set local role anon;
    perform count(*) from public.v_residual_textos;
    reset role;
  exception when others then falhou := true; reset role;
  end;
  if not falhou then
    raise exception '11 · anon conseguiu consultar v_residual_textos — é a view dos textos abertos';
  end if;
  raise notice '11 · anon falha ao ler a view dos textos: ok';

  -- 12 · nenhuma view nova fora da lista. Esta é a verificação que ainda não
  -- tinha razão de existir e vai ter: a próxima view sobre estas tabelas
  -- nasce aberta, e quem a escrever não vai receber aviso nenhum. Aqui recebe.
  select string_agg(c.relname, ', ') into sobrando
    from pg_class c
         join pg_namespace ns on ns.oid = c.relnamespace
         join pg_rewrite rw on rw.ev_class = c.oid
         join pg_depend d on d.objid = rw.oid and d.classid = 'pg_rewrite'::regclass
         join pg_class t on t.oid = d.refobjid
   where ns.nspname = 'public' and c.relkind = 'v'
     and t.relname in ('pesquisa_abertas','pesquisa_respostas','pesquisa_contatos')
     and c.relname <> all (esperadas);
  if sobrando is not null then
    raise exception '12 · view nova sobre as tabelas da pesquisa fora da lista: % — toda view nasce com security_invoker off e aberta para anon; repita as duas linhas do fim da 0044b', sobrando;
  end if;
  raise notice '12 · nenhuma view nova fora da lista fechada: ok';
end $do$;

-- ==================== parte 3 · a separação que sustenta o "não identificados"

do $do$
declare n int; c text;
begin
  -- 13 · pesquisa_contatos não tem como se ligar às respostas. É a promessa
  -- escrita na tela final e na página do estudo, e é o que dispensa a pesquisa
  -- do CEP/CONEP pela Res. CNS 510/2016, art. 1º, par. único, I. Uma FK
  -- acrescentada por conveniência ("só para saber quem respondeu o quê")
  -- desfaz o enquadramento inteiro, e desfaz calada.
  select count(*) into n
    from pg_constraint
   where conrelid = 'public.pesquisa_contatos'::regclass and contype = 'f';
  if n <> 0 then
    raise exception '13 · pesquisa_contatos ganhou % chave(s) estrangeira(s) — isso liga e-mail a resposta e derruba o "participantes não identificados"', n;
  end if;

  select string_agg(attname, ', ') into c
    from pg_attribute
   where attrelid = 'public.pesquisa_contatos'::regclass
     and attnum > 0 and not attisdropped
     and attname in ('sessao','sessao_id','resposta_id','aberta_id','pesquisa_id');
  if c is not null then
    raise exception '13 · pesquisa_contatos ganhou coluna de ligação: % — não pode existir', c;
  end if;
  raise notice '13 · contatos sem FK e sem coluna de ligação: ok';

  -- 14 · e ninguém aponta para ela por fora
  select count(*) into n
    from pg_constraint
   where confrelid = 'public.pesquisa_contatos'::regclass and contype = 'f';
  if n <> 0 then
    raise exception '14 · % tabela(s) apontam para pesquisa_contatos', n;
  end if;
  raise notice '14 · nada aponta para pesquisa_contatos: ok';

  -- 15 · a pesquisa não tem dono no produto. Sem conta_id ela não é dado de
  -- cliente nenhum — e é isso que a mantém fora das exportações e da eliminação.
  select count(*) into n
    from pg_attribute
   where attrelid in ('public.pesquisa_abertas'::regclass,
                      'public.pesquisa_respostas'::regclass,
                      'public.pesquisa_contatos'::regclass)
     and attnum > 0 and not attisdropped and attname = 'conta_id';
  if n <> 0 then
    raise exception '15 · alguma tabela da pesquisa ganhou conta_id — a pesquisa passaria a ser dado do produto';
  end if;
  raise notice '15 · a pesquisa não tem conta_id: ok';

  -- 16 · e as exportações não a mencionam. Uma psicóloga que exporta a conta
  -- dela não pode receber resposta de pesquisa de ninguém — nem a própria,
  -- porque não há como saber que é a dela.
  for c in select p.proname
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public'
              and p.proname in ('exportar_conta','exportar_paciente','eliminar_conta','elegiveis_para_eliminacao')
  loop
    if pg_get_functiondef(('public.' || c)::regproc) ~ 'pesquisa_' then
      raise exception '16 · a função % menciona uma tabela da pesquisa', c;
    end if;
  end loop;
  raise notice '16 · as exportações e a eliminação não tocam na pesquisa: ok';
end $do$;

-- ==================== parte 4 · quem lê de verdade, e o banco vazio

do $do$
declare
  esperadas text[] := array[
    'v_leitura1_fila','v_leitura3_cobranca','v_leitura4_agenda',
    'v_rendimento_canal','v_leitura5_canal','v_ranking_ponderado',
    'v_nao_e_problema','v_residual','v_residual_textos',
    'v_itens_novos','v_qualidade','v_funil'
  ];
  v text; n int;
begin
  -- 17 · a eliminação de conta não alcança a pesquisa (contraparte de dado da 16)
  select count(*) into n from public.pesquisa_respostas where canal = 'teste-suite';
  if n < 2 then raise exception '17 · as respostas da parte 1 sumiram'; end if;
  raise notice '17 · a pesquisa não é alcançada pela eliminação de conta: ok';

  -- 18 · service_role lê tudo — senão não há análise possível
  set local role service_role;
  select count(*) into n from public.pesquisa_abertas;
  if n < 1 then raise exception '18 · service_role não leu pesquisa_abertas'; end if;
  select count(*) into n from public.v_funil;
  if n <> 1 then raise exception '18 · service_role não leu v_funil'; end if;
  reset role;
  raise notice '18 · service_role lê tabelas e views: ok';

  -- 19 · as doze views respondem sem estourar. Todas dividem por count(*) e
  -- todas usam nullif — mas "usa nullif" é leitura, e isto é execução.
  foreach v in array esperadas loop
    begin
      execute format('select count(*) from public.%I', v) into n;
    exception when others then
      raise exception '19 · a view % estourou: %', v, sqlerrm;
    end;
  end loop;
  raise notice '19 · as 12 views respondem sem estourar: ok';

  -- 20 · e o e-mail não sai por nenhum caminho que anon alcance. Nenhuma das
  -- doze views toca em pesquisa_contatos, e é bom que continue assim: uma view
  -- que juntasse contato a resposta seria a única maneira de a promessa cair.
  foreach v in array esperadas loop
    if pg_get_viewdef(('public.' || v)::regclass) ~ 'pesquisa_contatos' then
      raise exception '20 · a view % lê pesquisa_contatos — nenhuma leitura pode juntar e-mail a resposta', v;
    end if;
  end loop;
  raise notice '20 · nenhuma view toca no e-mail: ok';

  -- 21 · as duas funções da 0044d não são rota. `create function` concede
  -- EXECUTE ao PUBLIC — tropeço da 0018, e aqui ele daria a qualquer pessoa
  -- com a chave do formulário um oráculo de "fulana respondeu?", um e-mail
  -- por vez.
  foreach v in array array['pesquisa_contato_existe','esquecer_contato_da_pesquisa'] loop
    if has_function_privilege('anon', ('public.' || v || '(text)')::regprocedure, 'execute') then
      raise exception '21 · anon executa public.% — está publicada em /rest/v1/rpc', v;
    end if;
    if has_function_privilege('authenticated', ('public.' || v || '(text)')::regprocedure, 'execute') then
      raise exception '21 · authenticated executa public.%', v;
    end if;
    if not has_function_privilege('service_role', ('public.' || v || '(text)')::regprocedure, 'execute') then
      raise exception '21 · service_role NÃO executa public.% — o pedido de exclusão não teria como ser atendido', v;
    end if;
  end loop;
  raise notice '21 · as duas funções da LGPD são só da service_role: ok';
end $do$;

-- ==================== parte 4b · o pedido de exclusão funciona
-- Direito do titular que não tem tela: se quebrar, ninguém percebe até
-- alguém pedir para sair da lista e a resposta ser "não consegui".

do $do$
declare n int; r record;
begin
  -- 22 · o e-mail casa apesar de maiúscula e espaço — o pedido chega escrito
  -- à mão numa resposta de e-mail, e " Ana@Exemplo.com " precisa achar a linha
  insert into public.pesquisa_contatos (email) values ('  TesteLGPD@teste-suite.invalido ');

  select * into r from public.pesquisa_contato_existe('testelgpd@teste-suite.invalido');
  if r.achou is not true then
    raise exception '22 · a confirmação não achou o e-mail (art. 18, I)';
  end if;

  select public.esquecer_contato_da_pesquisa(' TESTELGPD@teste-suite.invalido ') into n;
  if n <> 1 then raise exception '22 · o esquecer devolveu % em vez de 1', n; end if;

  -- A contagem olha só o e-mail deste teste. Olhar o domínio inteiro pegaria
  -- junto o contato que a verificação 2 inseriu e que só sai na parte 5 — e o
  -- teste falharia com "sobrou 1 contato" apontando para uma função que
  -- funcionou. Asserção larga demais acusa o código errado.
  select count(*) into n from public.pesquisa_contatos
   where lower(btrim(email)) = 'testelgpd@teste-suite.invalido';
  if n <> 0 then raise exception '22 · sobrou % contato depois de apagar', n; end if;
  raise notice '22 · o pedido de exclusão apaga de verdade: ok';

  -- 23 · e apagar o e-mail NÃO apaga resposta nenhuma. Apagar junto exigiria
  -- saber qual resposta é de quem — a ligação que não existe e não pode
  -- existir. É o desenho, não um esquecimento, e por isso tem teste.
  if pg_get_functiondef('public.esquecer_contato_da_pesquisa(text)'::regprocedure)
       ~ 'pesquisa_respostas|pesquisa_abertas' then
    raise exception '23 · esquecer_contato_da_pesquisa menciona as tabelas de resposta — alguém criou a ligação';
  end if;
  raise notice '23 · apagar o e-mail não alcança as respostas: ok';

  -- 24 · e o e-mail some de verdade: nada de anonimizar ou marcar removido,
  -- que deixaria a linha existindo e o pedido por atender
  if pg_get_functiondef('public.esquecer_contato_da_pesquisa(text)'::regprocedure) !~ 'delete from' then
    raise exception '24 · a função não apaga a linha — anonimizar não atende ao art. 18, VI aqui';
  end if;
  raise notice '24 · a linha é apagada, não maquiada: ok';
end $do$;

-- ==================== parte 5 · recolher o rastro
-- Lição da B27: suíte que deixa linha para trás quebra a suíte seguinte, e
-- quebra com erro que não fala dela. Aqui é barato porque nada tem FK.

do $do$
declare n int;
begin
  delete from public.pesquisa_abertas   where canal = 'teste-suite';
  delete from public.pesquisa_respostas where canal = 'teste-suite';
  delete from public.pesquisa_contatos  where email like '%@teste-suite.invalido';

  select count(*) into n from public.pesquisa_abertas where canal = 'teste-suite';
  if n <> 0 then raise exception 'parte 5 · sobrou linha de teste'; end if;

  raise notice 'parte 5 · rastro recolhido: ok';
  raise notice '=== 0044 · o Panorama: 24 verificações, todas passaram ===';
end $do$;
