-- Teste do editor, da biblioteca de figuras e do que o buscador lê (0054).
--
-- A verificação que decide o build é a nº 9: **o formato de um texto publicado
-- não muda**. Ela é a razão de a coluna existir. Sem o congelamento, ligar a
-- marcação num texto que já está no ar reinterpreta caracteres que estranhos já
-- leram — um `*` vira itálico, um `#` vira subtítulo — sem ninguém ter editado
-- nada. É a mesma família da invariante do endereço congelado da 0051.
--
-- A segunda é a nº 15: **figura usada em texto publicado não se apaga**. Uma
-- biblioteca com botão de apagar é uma máquina de furar página publicada, e o
-- furo aparece semanas depois, para quem está lendo.
--
-- E a nº 5 é a lição da 0052b cobrada antes de doer: acrescentar parâmetro a
-- uma função do PostgREST **cria sobrecarga**, e a antiga continua ganhando.
--
--   parte 1 · a estrutura, e o que ela não pode ter
--     1. post_figuras não carrega coluna de gente nem de conta
--     2. post_figuras não tem política de escrita — escrita é função
--     3. o alt é not null: não existe figura cadastrada sem alternativa
--     4. o bucket é público na leitura, tem teto e lista de tipos — sem SVG
--     5. salvar_post não ficou com sobrecarga
--     6. não existe coluna nem função de palavra-chave ou de nota de SEO
--
--   parte 2 · o formato
--     7. o que já existia continua 'texto' — nenhuma conversão silenciosa
--     8. texto novo nasce 'marcacao'
--     9. publicado recusa trocar de formato, e a recusa diz o que fazer
--    10. e a recusa é gatilho, não função: vale no update direto
--    11. rascunho troca à vontade
--
--   parte 3 · a figura
--    12. registrar_figura recusa alternativa curta, falando de leitor de tela
--    13. o mesmo caminho não entra duas vezes
--    14. tipo fora da lista é recusado — inclusive SVG
--    15. apagar recusa figura usada em texto que já estreou, e diz em quantos
--    16. tirar do ar não libera: continua recusando
--    17. figura não usada sai, e devolve o caminho para o app apagar o arquivo
--    18. quem não é operador não lê a biblioteca nem apaga nada
--
--   parte 4 · o que o buscador vê
--    19. o sitemap traz o que está no ar
--    20. e não traz o marcado como não indexável
--    21. e não traz o que aponta canônica para outro lugar
--    22. o sitemap não é porta para rascunho, nem para o anônimo
--    23. o operador consegue mesmo gravar no balde — a política não trava tudo
--    24. e quem não é operador não grava, nem apaga o que é de outro
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0054_editor_e_figuras.sql

do $do$
declare
  v_rascunho uuid;
  v_no_ar    uuid;
  v_tirado   uuid;
  v_novo     uuid;
  v_fig_usada uuid;
  v_fig_livre uuid;
  v_operador uuid;
  v_n        integer;
  v_txt      text;
  v_erro     text;
  v_fmt      text;
  v_bool     boolean;
begin

-- ============================================================ preâmbulo
--
-- Mesma lição da 0051: `posts` e `post_figuras` não têm `conta_id`, então
-- nenhuma limpeza por conta as alcança. A limpeza é por prefixo.

delete from public.post_links
 where post_id in (select id from public.posts where slug like 'suite-0054-%');
delete from public.posts where slug like 'suite-0054-%';
delete from public.post_figuras where caminho like 'suite-0054/%';

select u.auth_user_id into v_operador
  from public.usuarios u where u.operador = true limit 1;

if v_operador is null then
  raise exception 'FALHOU no preâmbulo: nenhum usuário operador nesta base — as verificações mediriam o vazio';
end if;

raise notice '--- parte 1 · a estrutura ---';

-- 1 · a biblioteca de figuras não carrega gente.
select count(*) into v_n
  from information_schema.columns
 where table_schema = 'public' and table_name = 'post_figuras'
   and column_name in ('conta_id', 'paciente_id', 'sessao_id', 'usuario_id',
                       'profissional_id', 'email', 'telefone', 'cpf', 'ip', 'leitor');
if v_n > 0 then
  raise exception 'FALHOU 1: post_figuras ganhou coluna de conta ou de pessoa (% coluna(s))', v_n;
end if;
raise notice 'ok 1 · a biblioteca não tem coluna de conta nem de pessoa';

-- 2 · escrita é função, não política.
select count(*) into v_n
  from pg_policies
 where schemaname = 'public' and tablename = 'post_figuras'
   and cmd in ('INSERT', 'UPDATE', 'DELETE');
if v_n > 0 then
  raise exception 'FALHOU 2: apareceu política de escrita em post_figuras (%) — escrita aqui é função, e é ela que confere o alt', v_n;
end if;
raise notice 'ok 2 · nenhuma política de escrita na biblioteca';

-- 3 · alternativa não é opcional.
--
-- Conferido na coluna, e não na função: uma checagem que só existe na função é
-- uma checagem que o próximo caminho de escrita esquece de repetir.
select is_nullable into v_txt
  from information_schema.columns
 where table_schema = 'public' and table_name = 'post_figuras' and column_name = 'alt';
if v_txt <> 'NO' then
  raise exception 'FALHOU 3: post_figuras.alt aceita nulo — figura sem alternativa é silêncio para quem usa leitor de tela';
end if;
raise notice 'ok 3 · o alt é obrigatório na coluna';

-- 4 · o balde: público para ler, com teto e com lista.
--
-- SVG é XML e executa script. Ele fora da lista é a defesa que vale mesmo
-- quando alguém fala direto com o endpoint do storage, sem passar pela tela.
select public into v_bool from storage.buckets where id = 'blog';
if v_bool is not true then
  raise exception 'FALHOU 4: o bucket blog não é público — figura de blog é arquivo que qualquer pessoa abre';
end if;

select file_size_limit into v_n from storage.buckets where id = 'blog';
if coalesce(v_n, 0) <= 0 or v_n > 20971520 then
  raise exception 'FALHOU 4: o bucket blog está sem teto de tamanho (%)', v_n;
end if;

select count(*) into v_n from storage.buckets
 where id = 'blog' and 'image/svg+xml' = any(allowed_mime_types);
if v_n > 0 then
  raise exception 'FALHOU 4: o bucket aceita SVG — SVG é XML, executa script, e este é um arquivo que estranhos abrem';
end if;

select count(*) into v_n from storage.buckets
 where id = 'blog' and 'image/webp' = any(allowed_mime_types);
if v_n <> 1 then
  raise exception 'FALHOU 4: o bucket não aceita webp — a lista ficou estreita demais para ser usável';
end if;
raise notice 'ok 4 · o balde é público, tem teto, tem lista, e a lista não tem SVG';

-- 5 · a lição da 0052b: acrescentar parâmetro cria sobrecarga.
select count(*) into v_n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'salvar_post';
if v_n <> 1 then
  raise exception 'FALHOU 5: existem % versões de salvar_post — o PostgREST escolhe pelo conjunto de nomes que a chamada manda, e a tela antiga continuaria salvando sem gravar formato, sem erro nenhum', v_n;
end if;
raise notice 'ok 5 · uma versão só de salvar_post';

-- 6 · nem palavra-chave, nem nota.
--
-- A documentação do Google diz que a meta keywords não é usada pela Busca, e
-- trata repetição de palavra-chave como violação de política. Um campo desses
-- no editor só muda uma coisa de verdade: o texto fica pior para quem lê.
select count(*) into v_n
  from information_schema.columns
 where table_schema = 'public' and table_name in ('posts', 'post_figuras')
   and (column_name like '%palavra_chave%' or column_name like '%keyword%'
        or column_name like '%nota_seo%' or column_name like '%pontuacao_seo%'
        or column_name like '%score%');
if v_n > 0 then
  raise exception 'FALHOU 6: apareceu campo de palavra-chave ou de nota de SEO (% coluna(s)) — número inventado sobre coisa que ninguém de fora mede assim', v_n;
end if;
raise notice 'ok 6 · sem palavra-chave e sem nota de SEO';

raise notice '--- parte 2 · o formato ---';

set local role postgres;

insert into public.posts (slug, titulo, corpo, resumo)
values ('suite-0054-rascunho', 'Rascunho da suíte 54',
        'Texto de rascunho com mais de vinte caracteres para passar no check do corpo.',
        'resumo do rascunho')
returning id into v_rascunho;

insert into public.posts (slug, titulo, corpo, publicado_em, visivel)
values ('suite-0054-no-ar', 'No ar pela suíte 54',
        'Texto publicado com mais de vinte caracteres, com * asterisco e # cerquilha.',
        now() - interval '1 day', true)
returning id into v_no_ar;

insert into public.posts (slug, titulo, corpo, publicado_em, visivel)
values ('suite-0054-tirado', 'Tirado do ar pela suíte 54',
        'Texto que esteve no ar e foi tirado, com mais de vinte caracteres.',
        now() - interval '2 day', false)
returning id into v_tirado;

reset role;

-- 7 · nada foi convertido por debaixo do pano.
select formato into v_fmt from public.posts where id = v_no_ar;
if v_fmt <> 'texto' then
  raise exception 'FALHOU 7: o texto que já existia virou "%" — a migração converteu conteúdo publicado sem ninguém pedir', v_fmt;
end if;
raise notice 'ok 7 · o que já existia continua em texto puro';

-- 8 · o que nasce pelo editor de hoje nasce com marcação.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_operador::text, 'role', 'authenticated')::text, true);
set local role authenticated;
select public.salvar_post(
  null, 'suite-0054-novo', 'Texto novo da suíte 54',
  'Corpo do texto novo, com mais de vinte caracteres para passar no check.'
) into v_novo;
reset role;

select formato into v_fmt from public.posts where id = v_novo;
if v_fmt <> 'marcacao' then
  raise exception 'FALHOU 8: texto novo nasceu em "%" — o editor de hoje escreve marcação', v_fmt;
end if;
raise notice 'ok 8 · texto novo nasce em marcação';

-- 9 · publicado recusa trocar, e a recusa manda para o caminho certo.
v_erro := null;
begin
  set local role authenticated;
  perform public.salvar_post(
    v_no_ar, 'suite-0054-no-ar', 'No ar pela suíte 54',
    'Texto publicado com mais de vinte caracteres, com * asterisco e # cerquilha.',
    null, null, null, 'marcacao'
  );
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro is null then
  raise exception 'FALHOU 9: um texto que já estreou trocou de interpretador — o asterisco e a cerquilha que estão no ar passariam a significar outra coisa sem ninguém ter editado nada';
end if;
if v_erro not ilike '%rascunho%' then
  raise exception 'FALHOU 9: recusou com "%" — a mensagem precisa dizer o que fazer (duplicar num rascunho), e não só que não dá', v_erro;
end if;

select formato into v_fmt from public.posts where id = v_no_ar;
if v_fmt <> 'texto' then
  raise exception 'FALHOU 9: a recusa não segurou o valor — ficou em "%"', v_fmt;
end if;
raise notice 'ok 9 · o formato do que está no ar não muda, e a recusa diz o caminho';

-- 10 · e é gatilho, não função: o update direto esbarra igual.
--
-- A lição da 0040h ao contrário. Se a defesa morasse só em salvar_post, um
-- PATCH pelo PostgREST — ou a próxima função de escrita que alguém escrever —
-- passaria por cima dela.
v_erro := null;
begin
  set local role postgres;
  update public.posts set formato = 'marcacao' where id = v_tirado;
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro is null then
  raise exception 'FALHOU 10: o update direto trocou o formato de um texto que já estreou — a defesa está na função e não no banco';
end if;
raise notice 'ok 10 · a defesa é gatilho: vale para qualquer caminho de escrita';

-- 11 · rascunho troca à vontade. A trava é sobre o que estranhos já leram.
set local role authenticated;
perform public.salvar_post(
  v_rascunho, 'suite-0054-rascunho', 'Rascunho da suíte 54',
  'Texto de rascunho com mais de vinte caracteres para passar no check do corpo.',
  'resumo do rascunho', null, null, 'marcacao'
);
reset role;

select formato into v_fmt from public.posts where id = v_rascunho;
if v_fmt <> 'marcacao' then
  raise exception 'FALHOU 11: rascunho não conseguiu trocar de formato (ficou em "%") — a trava passou do ponto e virou obstáculo para quem ainda não publicou', v_fmt;
end if;
raise notice 'ok 11 · rascunho troca de formato à vontade';

raise notice '--- parte 3 · a figura ---';

-- 12 · alternativa curta é recusada, e a frase diz por quê.
v_erro := null;
begin
  set local role authenticated;
  perform public.registrar_figura(
    'suite-0054/curta.png', '/blog/curta.png', 'ok', 800, 600, 12345, 'image/png');
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro is null then
  raise exception 'FALHOU 12: figura cadastrada com alternativa de duas letras';
end if;
if v_erro not ilike '%leitor de tela%' then
  raise exception 'FALHOU 12: recusou com "%" — a mensagem precisa dizer para quem a alternativa serve', v_erro;
end if;
raise notice 'ok 12 · alternativa curta é recusada, e a recusa explica';

-- Duas figuras: uma que vai para um texto publicado, outra livre.
set local role authenticated;
select public.registrar_figura(
  'suite-0054/usada.png', '/blog/suite-0054-usada.png',
  'Uma figura usada num texto publicado', 1200, 800, 200000, 'image/png')
  into v_fig_usada;

select public.registrar_figura(
  'suite-0054/livre.webp', '/blog/suite-0054-livre.webp',
  'Uma figura que ninguém usou ainda', 640, 480, 40000, 'image/webp')
  into v_fig_livre;
reset role;

-- 13 · o mesmo caminho não entra duas vezes.
--
-- Sem o único, a conferência de uso passaria a mentir: apagar uma das duas
-- linhas deixaria a outra apontando para um arquivo que o app já removeu.
v_erro := null;
begin
  set local role authenticated;
  perform public.registrar_figura(
    'suite-0054/usada.png', '/blog/outro.png',
    'A mesma figura cadastrada de novo', 1200, 800, 200000, 'image/png');
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 13: o mesmo caminho do bucket entrou duas vezes na biblioteca';
end if;
raise notice 'ok 13 · caminho duplicado é recusado';

-- 14 · SVG não passa nem pela tabela.
v_erro := null;
begin
  set local role authenticated;
  perform public.registrar_figura(
    'suite-0054/x.svg', '/blog/x.svg', 'Um desenho vetorial', 100, 100, 900, 'image/svg+xml');
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 14: SVG entrou na biblioteca — SVG é XML e executa script numa página que estranhos abrem';
end if;
raise notice 'ok 14 · SVG é recusado também na tabela';

-- Põe a figura usada dentro do corpo de um texto publicado.
set local role postgres;
update public.posts
   set corpo = corpo || E'\n\n![Uma figura usada num texto publicado](/blog/suite-0054-usada.png)'
 where id = v_no_ar;
reset role;

-- 15 · a contagem enxerga o uso no corpo, e a recusa diz o número.
set local role authenticated;
select usos_no_ar into v_n from public.figuras_do_blog() where id = v_fig_usada;
reset role;
if coalesce(v_n, 0) < 1 then
  raise exception 'FALHOU 15: a biblioteca não viu a figura usada dentro do corpo — o botão de apagar apareceria sem aviso nenhum';
end if;

v_erro := null;
begin
  set local role authenticated;
  perform public.apagar_figura(v_fig_usada);
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro is null then
  raise exception 'FALHOU 15: apagou figura que está num texto publicado — o buraco aparece semanas depois, para quem está lendo';
end if;
if v_erro not ilike '%estrearam%' and v_erro not ilike '%estreou%' then
  raise exception 'FALHOU 15: recusou com "%" — a mensagem precisa dizer que o motivo é o texto já ter estreado', v_erro;
end if;

select count(*) into v_n from public.post_figuras where id = v_fig_usada;
if v_n <> 1 then
  raise exception 'FALHOU 15: a recusa não segurou a linha';
end if;
raise notice 'ok 15 · figura usada em texto publicado não se apaga';

-- 16 · tirar do ar não libera.
--
-- Tirar do ar é esconder, e voltar é um clique. Liberar a exclusão aqui seria
-- transformar um clique reversível numa perda que não volta.
set local role postgres;
update public.posts set visivel = false where id = v_no_ar;
reset role;

v_erro := null;
begin
  set local role authenticated;
  perform public.apagar_figura(v_fig_usada);
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro is null then
  raise exception 'FALHOU 16: tirar o texto do ar liberou apagar a figura — voltar ao ar é um clique, e a figura não voltaria junto';
end if;
raise notice 'ok 16 · tirar do ar não libera apagar a figura';

set local role postgres;
update public.posts set visivel = true where id = v_no_ar;
reset role;

-- 17 · a que ninguém usa sai, e devolve o caminho para o app apagar o arquivo.
set local role authenticated;
select public.apagar_figura(v_fig_livre) into v_txt;
reset role;

if v_txt <> 'suite-0054/livre.webp' then
  raise exception 'FALHOU 17: apagar_figura devolveu "%" — sem o caminho, o app não tem como apagar o arquivo e o balde vira depósito', v_txt;
end if;
select count(*) into v_n from public.post_figuras where id = v_fig_livre;
if v_n <> 0 then
  raise exception 'FALHOU 17: a linha ficou';
end if;
raise notice 'ok 17 · figura sem uso sai, e devolve o caminho do arquivo';

-- 18 · quem não é operador não chega perto.
perform set_config('request.jwt.claims', null, true);

v_erro := null;
begin
  set local role authenticated;
  perform * from public.figuras_do_blog();
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 18: quem não é operador leu a biblioteca de figuras';
end if;

v_erro := null;
begin
  set local role authenticated;
  perform public.apagar_figura(v_fig_usada);
  reset role;
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 18: quem não é operador apagou figura';
end if;
raise notice 'ok 18 · a biblioteca é do operador';

raise notice '--- parte 4 · o que o buscador vê ---';

-- 19 · o sitemap traz o que está no ar.
set local role anon;
select count(*) into v_n from public.posts_do_sitemap() where slug = 'suite-0054-no-ar';
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 19: o sitemap não trouxe o texto que está no ar';
end if;
raise notice 'ok 19 · o sitemap traz o que está no ar';

-- 20 · e não traz o que pede para não ser indexado.
--
-- Pôr um endereço `noindex` no sitemap é mandar o rastreador a um lugar para
-- ele descobrir que não devia ter ido.
set local role postgres;
update public.posts set indexavel = false where id = v_no_ar;
reset role;

set local role anon;
select count(*) into v_n from public.posts_do_sitemap() where slug = 'suite-0054-no-ar';
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 20: o sitemap listou um endereço marcado como não indexável';
end if;

set local role postgres;
update public.posts set indexavel = true where id = v_no_ar;
reset role;
raise notice 'ok 20 · o não indexável fica fora do sitemap';

-- 21 · e não traz o que declara que o original é outro.
set local role postgres;
update public.posts set canonica = 'https://outrolugar.invalido/texto' where id = v_no_ar;
reset role;

set local role anon;
select count(*) into v_n from public.posts_do_sitemap() where slug = 'suite-0054-no-ar';
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 21: o sitemap indicou como original um texto que declara canônica em outro endereço';
end if;

set local role postgres;
update public.posts set canonica = null where id = v_no_ar;
reset role;
raise notice 'ok 21 · o que aponta canônica para fora fica de fora do sitemap';

-- 22 · o sitemap não é porta de serviço para rascunho.
--
-- A função é `security invoker` de propósito: quem chama é o anônimo, e a
-- política pública é o filtro. `definer` aqui teria aberto rascunho para a
-- internet inteira por uma rota que ninguém olha duas vezes.
set local role anon;
select count(*) into v_n from public.posts_do_sitemap()
 where slug in ('suite-0054-rascunho', 'suite-0054-tirado', 'suite-0054-novo');
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 22: o sitemap entregou rascunho ou texto fora do ar (% linha(s)) para quem não tem sessão', v_n;
end if;

select prosecdef into v_bool
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'posts_do_sitemap';
if v_bool is not false then
  raise exception 'FALHOU 22: posts_do_sitemap virou security definer — a rota do sitemap não tem sessão, e definer aqui passa por cima da política pública';
end if;
raise notice 'ok 22 · o sitemap enxerga exatamente a vitrine';

-- 23 · a política do balde deixa o operador subir.
--
-- Uma política de storage que recusa **tudo** é indistinguível de uma que
-- funciona até alguém tentar subir a primeira figura — e aí o defeito aparece
-- em produção, na frente de quem está escrevendo. O caminho aqui é um insert
-- direto em `storage.objects`, que é o que a API do storage faz por baixo.
--
-- O `raise` no fim do bloco é de propósito: ele desfaz o subbloco inteiro, e
-- com ele a linha inserida. **A plataforma não deixa apagar de
-- `storage.objects` por SQL** — há um gatilho `storage.protect_delete` que
-- recusa, e a mensagem manda usar a API. Sem este truque, a suíte deixaria um
-- arquivo fantasma no balde toda vez que rodasse.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_operador::text, 'role', 'authenticated')::text, true);

v_erro := null;
begin
  set local role authenticated;
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('blog', 'suite-0054/politica.png', v_operador, '{}'::jsonb);
  reset role;
  raise exception 'SUBIU';
exception when others then
  v_erro := sqlerrm;
end;
reset role;

if v_erro <> 'SUBIU' then
  raise exception 'FALHOU 23: o operador não conseguiu gravar no balde ("%") — a figura só falharia na frente de quem está escrevendo', v_erro;
end if;
raise notice 'ok 23 · o operador sobe para o balde';

-- 24 · e quem não é operador não sobe.
perform set_config('request.jwt.claims', null, true);

v_erro := null;
begin
  set local role authenticated;
  insert into storage.objects (bucket_id, name, metadata)
  values ('blog', 'suite-0054/invasor.png', '{}'::jsonb);
  reset role;
  raise exception 'SUBIU';
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro = 'SUBIU' then
  raise exception 'FALHOU 24: quem não é operador subiu arquivo para o balde do blog';
end if;

-- E o apagar. Aqui a asserção é sobre a **política**, e não sobre uma tentativa,
-- porque a tentativa mediria a coisa errada: a plataforma recusa `delete` direto
-- em `storage.objects` para todo mundo, com ou sem política. Quem apaga de
-- verdade é a API do storage, e é a política abaixo que ela consulta — então é
-- ela que precisa existir e precisa perguntar pelo operador.
select count(*) into v_n
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and cmd = 'DELETE'
   and qual like '%e_operador%' and qual like '%blog%';
if v_n <> 1 then
  raise exception 'FALHOU 24: não há política de DELETE do balde blog amarrada ao operador (% encontrada(s)) — a API do storage apagaria por conta de quem estiver logado', v_n;
end if;
raise notice 'ok 24 · o balde é do operador para subir e para apagar';

-- ============================================================ recolher o rastro
delete from public.post_links
 where post_id in (select id from public.posts where slug like 'suite-0054-%');
delete from public.posts where slug like 'suite-0054-%';
delete from public.post_figuras where caminho like 'suite-0054/%';

raise notice 'SUITE 0054 PASSOU: 24 verificações';
end $do$;
