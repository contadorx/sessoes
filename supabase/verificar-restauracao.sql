-- A prova de que o restore voltou inteiro.
--
-- Rodar no SQL Editor da base **restaurada**, não na de produção.
-- Levanta exceção no primeiro furo. Silêncio = passou.
--
-- O que se verifica aqui não é "tem dado". Dado quase sempre volta. O que some
-- num restore mal feito são as **defesas**: RLS desligada, política que não
-- veio, gatilho ausente, extensão faltando. Uma base restaurada sem gatilho
-- continua respondendo a todas as telas — e para de classificar cancelamento,
-- de recalcular destino de mensagem e de gerar cobrança. Ninguém percebe até o
-- primeiro cancelamento tardio não ser cobrado.
--
-- ---------------------------------------------------------------------------
-- POR QUE ESTE ARQUIVO FOI REESCRITO EM 03/09
-- ---------------------------------------------------------------------------
--
-- Ele conferia por **lista escrita à mão** — a lei 7 do `CLAUDE.md`, no arquivo
-- que carrega o único critério de pronto do projeto que não se verifica lendo.
-- E as listas tinham envelhecido exatamente como a lei prevê. Medido contra o
-- catálogo do banco em 03/09/2026:
--
--     tabelas .......... conferia  44 de  56   (12 fora)
--     funções .......... conferia 147 de 285  (138 fora)
--     gatilhos ......... conferia  38 de  79   (41 fora)
--     views ............ conferia  12 de  29   (17 fora)
--     contagens ........ conferia  36 de  56   (20 fora)
--
-- Entre as doze tabelas que ninguém conferia: `janelas_atendimento` (a
-- capacidade declarada, um dos quatro núcleos do produto), `objetivos` (o
-- plano terapêutico, que é prontuário), `links_do_paciente`, `avaliacoes`.
--
-- E entre as dezessete views: **`v_nao_se_aplica_textos`** — uma view de texto
-- livre escrito por psicóloga, a mesma família de `v_residual_textos`, cujo
-- risco este arquivo já descrevia em nove linhas antes de deixar a irmã dela
-- de fora. Um restore que trouxesse essa view sem `security_invoker` passava
-- calado por aqui.
--
-- A reescrita tem uma regra só: **onde o catálogo consegue responder, não há
-- lista.** Sobra uma lista só, a das tabelas com RLS e sem política, porque
-- isso é *decisão* e não fato — e ela reprova nos dois sentidos: tabela nova
-- sem política e não declarada reprova; tabela declarada que ganhou política
-- também reprova.
--
-- O que o catálogo sozinho não sabe é o que **existia antes**. Uma tabela que
-- sumiu no restore não deixa rastro na base restaurada. Isso não vira lista
-- escrita à mão: vira a **impressão digital** da parte 2 deste arquivo, que se
-- gera do próprio catálogo, se roda nas duas bases e se compara. O passo 1 do
-- `RESTAURAR.md` manda tirá-la da produção antes do ensaio.

-- ===========================================================================
-- PARTE 1 · o que se prova sem saber o que havia antes
-- ===========================================================================

do $$
declare
  faltando text;
  n int;
begin
  -- ------------------------------------------- 1. RLS ligada em toda tabela
  -- Uma tabela restaurada com RLS desligada não dá erro em lugar nenhum: ela
  -- só devolve os dados de todo mundo para qualquer um.
  select string_agg(c.relname, ', ' order by c.relname) into faltando
    from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
   where n2.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

  if faltando is not null then
    raise exception 'SEM RLS — tabelas abertas: %', faltando;
  end if;

  -- ------------------------------------------ 2. toda tabela tem política…
  -- …menos as cinco que **não devem ter**, e cada uma foi decidida assim na
  -- migração que a criou:
  --
  --   calendarios_segredo (0040c) · o token do calendário. Se um dia aparecer
  --     política nela, é sinal de que alguém abriu o segredo.
  --   precos_canal, custos_fixos (0045) · painel do negócio: é meu, não é dela.
  --   avisos_assinatura (0052) · a régua da MINHA assinatura.
  --   limites_tecnicos (0060) · freio meu, não é produto.
  --
  -- Zero política com RLS ligada = zero linha para `anon` e `authenticated`,
  -- e quem precisa chega por função `security definer`. A conferência é nos
  -- dois sentidos de propósito: a tabela nova que nasce sem política tem de
  -- ser **decidida aqui** antes de existir em silêncio, e a tabela declarada
  -- que ganhou política é um vazamento com a mesma cara de manutenção.
  select string_agg(c.relname, ', ' order by c.relname) into faltando
    from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
   where n2.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
     and not exists (select 1 from pg_policies p
                      where p.schemaname = 'public' and p.tablename = c.relname)
     and c.relname <> all (array['calendarios_segredo','precos_canal',
                                 'custos_fixos','avisos_assinatura',
                                 'limites_tecnicos']);

  if faltando is not null then
    raise exception 'RLS LIGADA E SEM REGRA em: % — pode ser o desenho, mas decida e escreva aqui antes de existir em silêncio', faltando;
  end if;

  select string_agg(t, ', ') into faltando
    from unnest(array['calendarios_segredo','precos_canal','custos_fixos',
                      'avisos_assinatura','limites_tecnicos']) as t
   where exists (select 1 from pg_policies p
                  where p.schemaname = 'public' and p.tablename = t);

  if faltando is not null then
    raise exception 'TABELA FECHADA GANHOU POLÍTICA: % — estas cinco existem para não ter nenhuma', faltando;
  end if;

  -- --------------------------------------------- 3. nenhuma view aberta
  --
  -- Esta é a verificação mais barata de esquecer e a mais cara de errar.
  --
  -- As views da pesquisa leem tabelas cujo material é o texto que uma
  -- psicóloga escreveu sobre o dia dela. Elas só não vazam por duas travas
  -- postas à mão no fim da 0044b: `security_invoker = on`, que faz a view
  -- respeitar a RLS de baixo em vez de rodar como dona, e o revoke, que
  -- esconde a view do PostgREST. As duas são *opções de relação* e *grants* —
  -- exatamente o tipo de coisa que um restore parcial, um dump com flag
  -- diferente ou um `create or replace view` de manutenção deixa cair sem
  -- avisar. E o modo de falha é mudo: a view volta funcionando, as consultas
  -- do painel continuam certas, e a única diferença é que agora qualquer
  -- pessoa com a chave que está publicada no formulário faz
  -- `GET /rest/v1/v_residual_textos` e lê tudo.
  --
  -- A regra vale para **toda** view de `public`, sem lista: hoje as 29 são do
  -- Panorama e nenhuma é servida ao app. Se um dia existir view que precise
  -- ser lida por `authenticated`, é aqui que a decisão aparece — e é bom que
  -- apareça reprovando.
  select string_agg(c.relname, ', ' order by c.relname) into faltando
    from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
   where n2.nspname = 'public' and c.relkind = 'v'
     and (coalesce((select option_value from pg_options_to_table(c.reloptions)
                     where option_name = 'security_invoker'), 'off') <> 'on'
       or has_table_privilege('anon', c.oid, 'select')
       or has_table_privilege('authenticated', c.oid, 'select'));

  if faltando is not null then
    raise exception 'VIEWS ABERTAS: % — sem security_invoker ou com SELECT para anon/authenticated, o que está embaixo delas está legível com a chave que está no formulário. Reaplique o bloco final da 0044b.', faltando;
  end if;

  -- ------------------------------- 4. todo `security definer` com search_path
  -- Lei 2. Sem `search_path` fixado, quem controla o schema de busca escolhe
  -- qual `contas` a função vai ler — de dentro de uma função que roda como
  -- dona. Um restore não costuma perder isso; um `create or replace` de
  -- manutenção perde.
  select string_agg(p.proname, ', ' order by p.proname) into faltando
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
                      where cfg like 'search_path=%');

  if faltando is not null then
    raise exception 'SECURITY DEFINER SEM search_path: %', faltando;
  end if;

  -- ------------------------------------------- 5. toda FK com índice (lei 2)
  -- Uma FK sem índice do lado que referencia varre a tabela inteira a cada
  -- delete do lado referenciado — e apagar paciente e encerrar conta são
  -- justamente operações de delete em cascata. A 0077 fechou as vinte que
  -- estavam abertas; esta verificação existe para não haver a vigésima
  -- primeira.
  select string_agg(x.rotulo, ', ' order by x.rotulo) into faltando
    from (
      select cl.relname || '.' || con.conname as rotulo
        from pg_constraint con
        join pg_class cl on cl.oid = con.conrelid
        join pg_namespace n2 on n2.oid = cl.relnamespace
       where n2.nspname = 'public' and con.contype = 'f'
         and not exists (
           select 1 from pg_index i
            where i.indrelid = con.conrelid
              and (i.indkey::smallint[])[0:array_length(con.conkey, 1) - 1] = con.conkey)
    ) x;

  if faltando is not null then
    raise exception 'FK SEM ÍNDICE: %', faltando;
  end if;

  -- --------------------------------- 6. todo gatilho com a função no lugar
  -- Um gatilho órfão não existe no Postgres, mas uma função de gatilho que
  -- voltou vazia, sim. Aqui se confere o que o catálogo consegue: que a
  -- função de cada gatilho ainda é `trigger`.
  select string_agg(t.tgname, ', ' order by t.tgname) into faltando
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n2 on n2.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
   where n2.nspname = 'public' and not t.tgisinternal
     and p.prorettype <> 'trigger'::regtype;

  if faltando is not null then
    raise exception 'GATILHO COM FUNÇÃO ERRADA: %', faltando;
  end if;

  -- ------------------------------------------ 7. a extensão da exclusão
  -- Sem btree_gist, a restrição que torna impossível duas pessoas no mesmo
  -- horário simplesmente não existe.
  if not exists (select 1 from pg_extension where extname = 'btree_gist') then
    raise exception 'FALTA btree_gist — duas pessoas na mesma hora voltou a ser possível';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.sessoes'::regclass and contype = 'x'
  ) then
    raise exception 'FALTA a restrição de exclusão em sessoes';
  end if;

  -- --------------------------------------------- 8. os tetos que existem hoje
  --
  -- A versão anterior deste arquivo exigia `planos.limite_mensagens_mes` no
  -- Grátis e teria **reprovado uma base saudável**: a 0060 tirou o teto mensal
  -- de todos os planos de propósito — *"a unidade cobrada passou a ser a
  -- sessão"* — e moveu o freio para `limites_tecnicos`, medido por hora e por
  -- dia. O arquivo tinha ficado com a decisão de 0047b, revogada por 0060, e
  -- o ensaio de restore ia parar num alarme falso no pior momento possível.
  --
  -- Os dois tetos técnicos existem **contra o laço, não contra a cliente**: um
  -- bug que reenfileira a mesma oferta mil vezes gasta dinheiro de verdade e
  -- queima o número no WhatsApp. Um restore que os perdesse deixaria a base
  -- respondendo tudo e sem freio nenhum.
  select string_agg(t, ', ') into faltando
    from unnest(array['mensagens_por_conta_hora','mensagens_por_paciente_dia']) as t
   where not exists (select 1 from public.limites_tecnicos l
                      where l.codigo = t and l.valor > 0);

  if faltando is not null then
    raise exception 'TETO TÉCNICO AUSENTE: % — sem ele um laço reenfileira sem parar, gasta dinheiro de verdade e queima o número no WhatsApp (0060)', faltando;
  end if;

  -- E o inverso é defeito do mesmo tamanho: um restore que trouxesse os dois
  -- tetos de plano de volta cobraria pela parte que não se cobra (0048) e
  -- barraria mensagem em silêncio (0060).
  select count(*) into n from public.planos
   where limite_pacientes_ativos is not null or limite_mensagens_mes is not null;
  if n > 0 then
    raise exception '% plano(s) voltaram com teto de PACIENTES ou de MENSAGENS — o registro é a parte que não se cobra (0048) e a unidade cobrada é a sessão (0060)', n;
  end if;

  -- O Gratuito, especificamente, é o que a vitrine promete: sessões sem
  -- limite, e o canal na mão dela.
  if exists (select 1 from public.planos
              where codigo = 'gratis'
                and (limite_sessoes_mes is not null or canal_saida <> 'manual')) then
    raise exception 'O GRATUITO VOLTOU DIFERENTE DO QUE A VITRINE PROMETE — "Sessões sem limite" e canal manual (0061)';
  end if;

  -- ------------------------------------------ 9. os essenciais do teto
  --
  -- `templates.essencial` decide quem continua recebendo quando o teto
  -- estoura. Um restore que rebaixasse um deles faria a mensagem parar de sair
  -- — e o sintoma seria um paciente faltando, não um erro.
  --
  -- A lista era de três e ficou de três quando a 0057 acrescentou o quarto,
  -- `confirmacao_de_sessao`, cujo motivo está escrito na própria linha: *"a
  -- hora aparece como 'não respondeu' sem nunca ter sido perguntada"*. Por
  -- isso a conferência é nos dois sentidos: essencial que sumiu reprova, e
  -- essencial novo que ninguém declarou aqui também.
  select string_agg(t, ', ') into faltando
    from unnest(array['lembrete_de_sessao','aviso_de_desmarque',
                      'encaixe_confirmado','confirmacao_de_sessao']) as t
   where not exists (
     select 1 from public.templates x where x.codigo = t and x.essencial
   );

  if faltando is not null then
    raise exception 'TEMPLATES ESSENCIAIS AUSENTES OU REBAIXADOS: % — sem isto o teto do plano passa a barrar mensagem que o paciente precisa receber', faltando;
  end if;

  select string_agg(x.codigo, ', ' order by x.codigo) into faltando
    from public.templates x
   where x.essencial
     and x.codigo <> all (array['lembrete_de_sessao','aviso_de_desmarque',
                                'encaixe_confirmado','confirmacao_de_sessao']);

  if faltando is not null then
    raise exception 'ESSENCIAL NÃO DECLARADO: % — essencial é a mensagem que passa por cima do teto do plano; decida e escreva aqui antes de existir em silêncio', faltando;
  end if;

  raise notice 'DEFESAS OK — RLS, políticas, views fechadas, search_path, FKs indexadas, gatilhos, extensões, tetos técnicos e templates essenciais. Falta comparar a impressão digital (parte 2).';
end $$;

-- ===========================================================================
-- PARTE 2 · a impressão digital
-- ===========================================================================
--
-- O que a parte 1 não consegue: dizer que **não sumiu nada**. Uma tabela que
-- não voltou não deixa rastro na base restaurada — ela só não está lá.
--
-- Em vez de uma lista escrita à mão do que deveria existir (era assim que este
-- arquivo errava), a expectativa se **gera do catálogo da produção**, antes do
-- ensaio. Rode este mesmo bloco nas duas bases e compare linha a linha:
--
--     · `n` igual e `digital` igual  → a classe voltou inteira
--     · `n` menor                    → sumiu coisa; use o detalhe abaixo
--     · `n` igual e `digital` difere → trocou de nome ou de assinatura
--
-- `digital` é o md5 dos nomes ordenados. Ele muda com qualquer diferença, e é
-- curto o bastante para caber num print de celular no meio de um incidente.

with catalogo as (
  select 'tabelas' as classe, c.relname as nome
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
  union all
  select 'colunas', c.relname || '.' || a.attname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid
   where n.nspname = 'public' and c.relkind = 'r'
     and a.attnum > 0 and not a.attisdropped
  union all
  select 'views', c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
  union all
  select 'funcoes', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
  union all
  select 'gatilhos', c.relname || '.' || t.tgname
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and not t.tgisinternal
  union all
  select 'politicas', p.tablename || '.' || p.policyname
    from pg_policies p where p.schemaname = 'public'
  union all
  select 'indices', c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'i'
  union all
  select 'restricoes', cl.relname || '.' || con.conname
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_namespace n on n.oid = cl.relnamespace
   where n.nspname = 'public'
  union all
  -- A superfície do link mágico: o que o visitante sem sessão alcança. Um
  -- restore que devolvesse `EXECUTE` para `public` numa função nova entra aqui
  -- como diferença, e é a mesma classe de defeito da 0075.
  select 'anon_executa', p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
  union all
  select 'authenticated_executa', p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
  union all
  select 'extensoes', e.extname from pg_extension e
)
select classe,
       count(*) as n,
       md5(string_agg(nome, E'\n' order by nome)) as digital
  from catalogo
 group by classe
 order by classe;

-- O detalhe, quando uma classe difere. Troque a classe e rode nas duas bases;
-- o `except` responde o que falta de um lado.
--
--   select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind = 'r' order by 1;

-- ---------------------------------------------------------------- as contagens
--
-- Compare com o que você anotou antes do restore. Diferença aqui não é
-- necessariamente erro (o backup é de um instante anterior), mas **zero onde
-- havia dado é sempre erro**.
--
-- Sem lista: a contagem se faz sobre o catálogo, então a tabela que nascer
-- amanhã já entra. `query_to_xml` é o jeito de contar linha de tabela cujo
-- nome só se sabe em tempo de consulta sem precisar de função nova.

select c.relname as tabela,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I', c.relname),
                           false, true, '')))[1]::text::bigint as linhas
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
union all
select 'auth.users', count(*) from auth.users
 order by 1;
