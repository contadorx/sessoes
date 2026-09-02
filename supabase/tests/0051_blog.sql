-- =====================================================================
-- Suíte 0051 · o blog
-- =====================================================================
--
-- Metade destas verificações confere o que o sistema **não pode** fazer, e
-- neste caso a lista do "não pode" é maior que a do "pode" — porque esta é a
-- primeira tabela do banco cujo destinatário é um estranho.
--
-- DUAS LIÇÕES ANTIGAS ESTÃO APLICADAS AQUI, E ELAS SE CONTRADIZEM SE FOREM
-- LIDAS DEPRESSA:
--
--   · **A ação roda como o papel; a conferência roda com `reset role`.** Foi o
--     defeito das verificações 8 e 9 da 0050: uma asserção feita ainda sob
--     `set local role` lê pela RLS, volta nula, e nulo num `if` é falso —
--     passa por ausência de dado.
--
--   · **Mas a leitura pública é, ela própria, o objeto do teste.** Então as
--     verificações 4 a 7 fazem justamente o contrário de propósito: elas
--     precisam ler *com* o papel `anon`, porque o que se está medindo é o que
--     o visitante enxerga. A diferença é que ali a leitura é o assunto, e não
--     a forma de conferir outro assunto.
--
-- E a regra da 0049 sobre defesa silenciosa vale de novo: RLS que nega devolve
-- **zero linhas, não erro**. Onde a defesa é a política, a asserção é sobre o
-- que veio; onde a defesa é o `revoke` ou a função, é sobre a exceção.
-- =====================================================================

do $$
declare
  v_rascunho  uuid;
  v_no_ar     uuid;
  v_tirado    uuid;
  v_estreia   timestamptz;
  v_n         integer;
  v_txt       text;
  v_bandeira  boolean;
  v_operador  uuid;
begin

-- ============================================================ preâmbulo
--
-- A suíte recolhe o próprio rastro (lição da B27), e recolhe **antes** também:
-- `posts` não tem `conta_id`, então nenhuma limpeza por conta a alcança. É
-- exatamente o buraco que o Panorama abriu — uma tabela sem conta some da
-- limpeza por conta e some do radar. Aqui a limpeza é pelo prefixo do slug.

delete from public.post_links
 where post_id in (select id from public.posts where slug like 'suite-0051-%');
delete from public.posts where slug like 'suite-0051-%';

-- Quem é o operador nesta base. Se não houver, a suíte não tem como exercitar
-- as funções — e dizer isso é melhor que passar por vacuidade.
select u.auth_user_id into v_operador
  from public.usuarios u where u.operador = true limit 1;

if v_operador is null then
  raise exception 'FALHOU no preâmbulo: nenhum usuário operador nesta base — as 26 verificações mediriam o vazio';
end if;

raise notice '--- parte 1 · a estrutura, e o que ela não pode ter ---';

-- 1 · nem posts nem post_links carregam gente.
--
-- Esta é a verificação que paga o preço da decisão "sem conta_id". A 0044
-- ensinou que uma tabela nova nunca reprova uma lista da qual não faz parte —
-- então a lista está aqui, escrita no dia em que a tabela nasceu.
select count(*) into v_n
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('posts', 'post_links')
   and column_name in ('conta_id', 'paciente_id', 'sessao_id', 'usuario_id',
                       'profissional_id', 'email', 'telefone', 'cpf', 'ip', 'leitor');
if v_n > 0 then
  raise exception 'FALHOU 1: o blog ganhou coluna de gente ou de conta (% coluna(s)) — ele é meu, não é dela, e nada aqui identifica ninguém', v_n;
end if;
raise notice 'ok 1 · o blog não tem coluna de conta nem de pessoa';

-- 2 · nenhuma política de escrita, em nenhuma das duas tabelas.
select count(*) into v_n
  from pg_policies
 where schemaname = 'public'
   and tablename in ('posts', 'post_links')
   and cmd <> 'SELECT';
if v_n > 0 then
  raise exception 'FALHOU 2: apareceu política de escrita no blog (%) — escrita é função, e um PATCH do PostgREST passa por cima de toda regra desta migração', v_n;
end if;
raise notice 'ok 2 · escrita só por função';

-- 3 · não existe tabela de leitor.
--
-- Invariante 6. É verificação de estrutura porque a tentação chega depois, com
-- outro nome ("métricas do blog"), e vai parecer inofensiva.
--
-- **E a primeira versão desta verificação reprovou um banco correto.** Ela
-- procurava `%leitura%`, e as doze views do Panorama se chamam `v_leitura1_fila`,
-- `v_leitura3_cobranca` — "leitura" ali é leitura *analítica* da pesquisa, não
-- leitura de página. É a lição da verificação 22 da 0044 outra vez: asserção
-- larga acusa o código certo, e o custo é aprender a ignorar o alarme. Agora
-- ela exige `BASE TABLE` (view não guarda visita) e procura só as palavras que
-- de fato descrevem contar gente.
select count(*) into v_n
  from information_schema.tables
 where table_schema = 'public'
   and table_type = 'BASE TABLE'
   and (table_name like '%visita%' or table_name like '%pageview%'
        or table_name like '%leitor%' or table_name like 'post_acesso%'
        or table_name like 'post_metrica%');
if v_n > 0 then
  raise exception 'FALHOU 3: apareceu tabela de visita/leitor — num site que promete sigilo, contar quem leu o quê é construir o oposto do argumento';
end if;
raise notice 'ok 3 · o blog não conta leitor';

raise notice '--- parte 2 · o que o estranho enxerga ---';

-- Três textos: um rascunho, um no ar, um que esteve no ar e foi tirado.
set local role postgres;
insert into public.posts (slug, titulo, corpo, resumo)
values ('suite-0051-rascunho', 'Rascunho da suíte',
        'Texto de rascunho com mais de vinte caracteres para passar no check do corpo.',
        'resumo do rascunho')
returning id into v_rascunho;

insert into public.posts (slug, titulo, corpo, publicado_em, visivel)
values ('suite-0051-no-ar', 'No ar pela suíte',
        'Texto publicado com mais de vinte caracteres para passar no check do corpo.',
        now() - interval '1 day', true)
returning id into v_no_ar;

insert into public.posts (slug, titulo, corpo, publicado_em, visivel)
values ('suite-0051-tirado', 'Tirado do ar pela suíte',
        'Texto que esteve no ar e foi tirado, com mais de vinte caracteres.',
        now() - interval '2 day', false)
returning id into v_tirado;

insert into public.post_links (post_id, rotulo, url, ordem)
values (v_rascunho, 'link do rascunho', 'https://exemplo.invalido/rascunho', 0),
       (v_no_ar,    'link do que está no ar', 'https://exemplo.invalido/no-ar', 0);

-- 4 · o visitante anônimo lê o que está no ar.
--
-- Aqui a leitura **é** o assunto, então ela roda com o papel de propósito.
set local role anon;
select count(*) into v_n from public.posts where id = v_no_ar;
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 4: o visitante não enxerga o texto publicado (% linha(s)) — a tabela existe para ser lida por quem não tem conta', v_n;
end if;
raise notice 'ok 4 · o que está no ar é público';

-- 5 · e não lê o rascunho.
set local role anon;
select count(*) into v_n from public.posts where id = v_rascunho;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 5: rascunho visível para o visitante — o estado normal de um texto é não estar pronto';
end if;
raise notice 'ok 5 · rascunho não vaza';

-- 6 · nem o que foi tirado do ar.
set local role anon;
select count(*) into v_n from public.posts where id = v_tirado;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 6: texto despublicado continua público — tirar do ar não tirou nada do ar';
end if;
raise notice 'ok 6 · o que foi tirado do ar sai da vitrine';

-- 7 · o link do rascunho não vaza junto.
--
-- O rótulo de um link costuma entregar o assunto do texto que ainda não saiu.
set local role anon;
select count(*) into v_n from public.post_links where post_id = v_rascunho;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 7: link de rascunho legível para o visitante — o rótulo do link entrega o texto';
end if;
raise notice 'ok 7 · link segue o texto';

-- 8 · o link do texto publicado aparece.
--
-- A verificação que sustenta a 7, na forma da 16 da 0049: sem ela, uma
-- política que escondesse **todos** os links faria a 7 passar com louvor.
set local role anon;
select count(*) into v_n from public.post_links where post_id = v_no_ar;
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 8: o link do texto publicado sumiu (% linha(s)) — a 7 estaria passando por a política esconder tudo', v_n;
end if;
raise notice 'ok 8 · o link do que está no ar aparece';

raise notice '--- parte 3 · o que o visitante não consegue escrever ---';

-- 9 · anon não insere.
set local role anon;
v_bandeira := false;
begin
  insert into public.posts (slug, titulo, corpo)
  values ('suite-0051-invasor', 'Invasor', 'Texto do invasor com mais de vinte caracteres aqui.');
  v_bandeira := true;
exception when others then
  null;
end;
reset role;
if v_bandeira then
  delete from public.posts where slug = 'suite-0051-invasor';
  raise exception 'FALHOU 9: o visitante anônimo escreveu no blog';
end if;
raise notice 'ok 9 · anon não escreve';

-- 10 · authenticated não-operador também não.
--
-- E a asserção é sobre o **estado**, não sobre a exceção: se um dia a defesa
-- aqui virar política de RLS em vez de revoke, o update acertará zero linhas e
-- voltará sem erro — a lição da verificação 20 da 0049. Esperar exceção seria
-- medir a mensagem em vez de medir a porta.
set local role authenticated;
begin
  update public.posts set titulo = 'sequestrado' where id = v_no_ar;
exception when others then
  null;
end;
reset role;
select titulo into v_txt from public.posts where id = v_no_ar;
if v_txt <> 'No ar pela suíte' then
  raise exception 'FALHOU 10: quem está logado reescreveu o blog — o título agora é "%"', v_txt;
end if;
raise notice 'ok 10 · quem está logado não reescreve o blog';

-- 11 · e não apaga.
set local role authenticated;
begin
  delete from public.posts where id = v_no_ar;
exception when others then
  null;
end;
reset role;
select count(*) into v_n from public.posts where id = v_no_ar;
if v_n <> 1 then
  raise exception 'FALHOU 11: texto publicado apagado por quem está logado';
end if;
raise notice 'ok 11 · quem está logado não apaga o blog';

-- 12 · e as funções recusam quem não é operador.
--
-- Aqui a asserção **é** sobre a exceção, porque a defesa é a primeira linha da
-- função e ela levanta. Onde a defesa é silenciosa, mede-se o estado; onde ela
-- fala, mede-se a fala.
set local role authenticated;
v_bandeira := false;
begin
  perform public.publicar_post(v_rascunho);
  v_bandeira := true;
exception when others then
  null;
end;
reset role;
if v_bandeira then
  raise exception 'FALHOU 12: não-operador publicou';
end if;
select visivel into v_bandeira from public.posts where id = v_rascunho;
if v_bandeira then
  raise exception 'FALHOU 12b: a chamada foi recusada e o rascunho foi ao ar assim mesmo';
end if;
raise notice 'ok 12 · publicar exige operador, e o rascunho continuou rascunho';

raise notice '--- parte 4 · as invariantes do texto ---';

-- 13 · o endereço de um texto publicado não muda.
v_bandeira := false;
begin
  update public.posts set slug = 'suite-0051-outro-endereco' where id = v_no_ar;
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  raise exception 'FALHOU 13: o endereço de um texto publicado mudou — todo link que alguém guardou virou 404 em silêncio';
end if;
raise notice 'ok 13 · endereço publicado é congelado';

-- 14 · mas o de um rascunho muda.
--
-- Sem esta, a 13 passaria com um gatilho que simplesmente proíbe tudo — e
-- corrigir um slug feio antes de publicar é justamente quando não custa nada.
update public.posts set slug = 'suite-0051-rascunho-corrigido' where id = v_rascunho;
select slug into v_txt from public.posts where id = v_rascunho;
if v_txt <> 'suite-0051-rascunho-corrigido' then
  raise exception 'FALHOU 14: não deu para corrigir o endereço de um rascunho';
end if;
update public.posts set slug = 'suite-0051-rascunho' where id = v_rascunho;
raise notice 'ok 14 · endereço de rascunho ainda se corrige';

-- 15 · a data de estreia não se reescreve.
v_bandeira := false;
begin
  update public.posts set publicado_em = now() where id = v_no_ar;
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  raise exception 'FALHOU 15: a estreia foi reescrita — republicar passou a inventar novidade';
end if;
raise notice 'ok 15 · a estreia é escrita uma vez';

-- 16 · visível sem estreia é estado impossível.
v_bandeira := false;
begin
  update public.posts set visivel = true where id = v_rascunho;
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  raise exception 'FALHOU 16: um texto foi ao ar sem data de estreia — e a vitrine ordena por essa data';
end if;
raise notice 'ok 16 · não se vai ao ar sem estrear';

-- 17 · figura sem alternativa não passa.
v_bandeira := false;
begin
  update public.posts set figura_url = '/blog/foto.png', figura_alt = null where id = v_rascunho;
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  raise exception 'FALHOU 17: figura sem texto alternativo entrou — para quem usa leitor de tela ela vira enfeite mudo';
end if;
raise notice 'ok 17 · figura exige alternativa';

-- 18 · javascript: não é URL de link.
v_bandeira := false;
begin
  insert into public.post_links (post_id, rotulo, url, ordem)
  values (v_no_ar, 'clique aqui', 'javascript:alert(1)', 9);
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  delete from public.post_links where url like 'javascript:%';
  raise exception 'FALHOU 18: um javascript: entrou como link — isso é XSS armazenado numa página que estranhos abrem';
end if;
raise notice 'ok 18 · javascript: não é endereço';

-- 19 · data: não é figura.
v_bandeira := false;
begin
  update public.posts
     set figura_url = 'data:text/html,<script>alert(1)</script>', figura_alt = 'alternativa'
   where id = v_rascunho;
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  raise exception 'FALHOU 19: um data: entrou como figura';
end if;
raise notice 'ok 19 · data: não é figura';

-- 20 · slug com maiúscula, espaço ou acento é recusado.
--
-- Não é estética: o endereço vai para dentro de um link compartilhado, e um
-- espaço vira %20 na barra de alguém.
v_bandeira := false;
begin
  insert into public.posts (slug, titulo, corpo)
  values ('Suite 0051 Errado', 'Errado', 'Texto com mais de vinte caracteres para o check.');
  v_bandeira := true;
exception when others then
  null;
end;
if v_bandeira then
  delete from public.posts where titulo = 'Errado';
  raise exception 'FALHOU 20: slug com espaço e maiúscula entrou';
end if;
raise notice 'ok 20 · o endereço tem forma';

raise notice '--- parte 5 · as funções, como o operador ---';

-- As funções são `security definer` com `e_operador()` dentro, então a suíte
-- precisa chegar nelas **como o operador**. É o mesmo arranjo da 0050: os
-- claims entram na sessão, a ação roda com o papel, e a conferência sai dele.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_operador::text, 'role', 'authenticated')::text, true);

-- 21 · salvar cria, e devolve o id.
set local role authenticated;
select public.salvar_post(
         null, 'suite-0051-pela-funcao', 'Criado pela função',
         'Corpo criado pela função, com mais de vinte caracteres para o check.',
         'um resumo') into v_txt;
reset role;
if v_txt is null then
  raise exception 'FALHOU 21: salvar_post não devolveu id';
end if;
select count(*) into v_n from public.posts where slug = 'suite-0051-pela-funcao';
if v_n <> 1 then
  raise exception 'FALHOU 21b: o texto não foi criado (% linha(s))', v_n;
end if;
raise notice 'ok 21 · salvar_post cria';

-- 22 · publicar carimba a estreia; republicar não a reescreve.
set local role authenticated;
perform public.publicar_post(v_txt::uuid);
reset role;
select publicado_em into v_estreia from public.posts where id = v_txt::uuid;
if v_estreia is null then
  raise exception 'FALHOU 22: publicou sem carimbar a estreia';
end if;

set local role authenticated;
perform public.despublicar_post(v_txt::uuid);
perform public.publicar_post(v_txt::uuid);
reset role;
select publicado_em, visivel into v_estreia, v_bandeira from public.posts where id = v_txt::uuid;
if not v_bandeira then
  raise exception 'FALHOU 22b: republicar não pôs de volta no ar';
end if;
select count(*) into v_n from public.posts
 where id = v_txt::uuid and publicado_em = v_estreia;
if v_n <> 1 then
  raise exception 'FALHOU 22c: a estreia mudou entre publicar e republicar';
end if;
raise notice 'ok 22 · publicar carimba uma vez, e só uma';

-- 23 · apagar recusa o que já esteve no ar, e aceita o rascunho.
--
-- Os dois lados, pelo motivo da 0050: exigir só a recusa deixaria passar uma
-- função que recusa tudo.
set local role authenticated;
v_bandeira := false;
begin
  perform public.apagar_post(v_txt::uuid);
  v_bandeira := true;
exception when others then
  null;
end;
reset role;
if v_bandeira then
  raise exception 'FALHOU 23: um texto que já esteve no ar foi apagado';
end if;

set local role authenticated;
perform public.apagar_post(v_rascunho);
reset role;
select count(*) into v_n from public.posts where id = v_rascunho;
if v_n <> 0 then
  raise exception 'FALHOU 23b: não deu para apagar um rascunho — e rascunho errado se apaga';
end if;
raise notice 'ok 23 · publicado não se apaga; rascunho sim';

-- 24 · a lista de links é substituída, e a linha pela metade é ignorada.
set local role authenticated;
select public.definir_links_do_post(
  v_no_ar,
  '[{"rotulo":"primeiro","url":"https://exemplo.invalido/a"},
    {"rotulo":"","url":"https://exemplo.invalido/vazio"},
    {"rotulo":"segundo","url":"/interno"}]'::jsonb) into v_n;
reset role;
if v_n <> 2 then
  raise exception 'FALHOU 24: a função gravou % link(s) — esperava 2, com a linha sem rótulo ignorada', v_n;
end if;
select count(*) into v_n from public.post_links where post_id = v_no_ar;
if v_n <> 2 then
  raise exception 'FALHOU 24b: a lista antiga não foi substituída (% linha(s) na tabela)', v_n;
end if;
raise notice 'ok 24 · a lista de links substitui, e ignora a linha pela metade';

-- 25 · o painel enxerga rascunho; a vitrine não.
--
-- Os dois lados da mesma pergunta, e é a lição da verificação 25 da 0050:
-- "some da vitrine" não quer dizer "some de tudo".
set local role postgres;
insert into public.posts (slug, titulo, corpo)
values ('suite-0051-so-no-painel', 'Só no painel',
        'Texto que só o painel deve enxergar, com mais de vinte caracteres.');
reset role;

set local role authenticated;
select count(*) into v_n from public.posts_do_painel() where slug = 'suite-0051-so-no-painel';
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 25: o painel do operador não enxerga o próprio rascunho (% linha(s))', v_n;
end if;

set local role anon;
select count(*) into v_n from public.posts where slug = 'suite-0051-so-no-painel';
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 25b: o rascunho que o painel mostra também está público';
end if;
raise notice 'ok 25 · o painel vê o rascunho, a vitrine não';

-- 26 · post_do_painel devolve texto e links juntos.
set local role authenticated;
select public.post_do_painel(v_no_ar)::text into v_txt;
reset role;
if v_txt is null or position('"links"' in v_txt) = 0 or position('primeiro' in v_txt) = 0 then
  raise exception 'FALHOU 26: post_do_painel não trouxe os links junto com o texto';
end if;
raise notice 'ok 26 · o texto vem com os links';

-- ============================================================ limpeza
--
-- Recolhe o próprio rastro. E recolhe **por slug**, não por conta: a lição do
-- Panorama é que o que nasce sem `conta_id` some da limpeza por conta.
perform set_config('request.jwt.claims', null, true);

delete from public.post_links
 where post_id in (select id from public.posts where slug like 'suite-0051-%');
delete from public.posts where slug like 'suite-0051-%';

select count(*) into v_n from public.posts where slug like 'suite-0051-%';
if v_n <> 0 then
  raise exception 'FALHOU na limpeza: sobraram % texto(s) da suíte', v_n;
end if;

raise notice '';
raise notice '=====================================================';
raise notice '  0051 · 26 verificações passaram';
raise notice '=====================================================';

end $$;
