-- =====================================================================
-- 0054 · o editor, a figura e o que o buscador lê
--
-- A 0051 nasceu com uma recusa escrita em voz alta: "não existe função que
-- transforme o corpo em HTML — a linha entre as duas coisas é a linha entre um
-- blog e um `<script>` de outra pessoa na página inicial do produto". E fechou
-- prevendo o próprio futuro: *"essa tentação chega num dia em que eu vou querer
-- negrito"*.
--
-- O dia chegou. A resposta **não** é afrouxar a recusa.
--
-- INVARIANTE 1 · MARCAÇÃO NÃO É HTML, E A DIFERENÇA É O TIPO DE RETORNO
--
-- O que entra é uma marcação restrita (negrito, itálico, subtítulo, lista,
-- citação, link, figura). O que sai do interpretador é uma **árvore tipada** em
-- que não existe nenhum nó capaz de carregar HTML — não há `{ tipo: "html" }`,
-- e o compilador recusa quem tentar criar um. A tela monta elementos React a
-- partir dessa árvore.
--
-- Isso é diferente de "escapar o HTML depois". Escapar é uma defesa que alguém
-- pode esquecer de aplicar num caminho novo; **não ter o nó** é uma defesa que
-- não depende de ninguém lembrar. O teste de estrutura que reprova
-- `dangerouslySetInnerHTML` no repositório inteiro continua de pé, e continua
-- passando.
--
-- INVARIANTE 2 · O FORMATO DE UM TEXTO PUBLICADO CONGELA
--
-- Um texto já publicado foi escrito **para um interpretador**. Trocar o
-- interpretador depois reinterpreta caracteres que já estão no ar: um `*` que
-- era asterisco vira itálico, um `#` que era número de item vira subtítulo, e
-- um `_` no meio de um nome de arquivo desaparece. Ninguém editou nada, e o
-- texto publicado mudou.
--
-- Por isso `formato` nasce `'texto'` para tudo o que já existe, e o gatilho
-- recusa trocá-lo depois da estreia. É a mesma família da invariante 2 da 0051
-- (o endereço congela) e pelo mesmo motivo: o que estranhos já leram não muda
-- por conveniência de quem administra.
--
-- INVARIANTE 3 · FIGURA APAGADA NÃO PODE DEIXAR BURACO NO QUE ESTÁ NO AR
--
-- Uma biblioteca de figuras com botão de apagar é uma máquina de quebrar texto
-- publicado. `apagar_figura` recusa remover uma figura que aparece no corpo ou
-- na capa de **qualquer texto que já estreou** — inclusive um que está fora do
-- ar, porque tirar do ar não é apagar e voltar é um clique.
--
-- E ela não apaga o arquivo do storage: devolve o caminho para o app apagar
-- pela API própria. Duas coisas em transações diferentes, e a ordem importa —
-- primeiro sai a linha, depois o arquivo. O contrário deixaria linha apontando
-- para arquivo que não existe mais.
--
-- INVARIANTE 4 · ALTERNATIVA E DIMENSÕES SÃO OBRIGATÓRIAS NO CADASTRO
--
-- `alt` é `not null` em `post_figuras`, e não apenas conferido na tela. A 0051
-- já exigia alternativa para a capa; aqui a exigência sobe para o momento do
-- upload, porque é o único momento em que a pessoa está olhando para a imagem.
-- Pedir depois é pedir para uma tela que ela vai fechar.
--
-- Largura e altura vêm juntas e são obrigatórias pelo mesmo motivo, mas outro
-- efeito: sem elas o navegador não reserva espaço, o texto pula quando a imagem
-- carrega, e isso é o CLS que o próprio Google mede. São medidas do arquivo,
-- não opinião — o navegador de quem faz o upload as lê antes de enviar.
--
-- O QUE ESTA MIGRAÇÃO **NÃO** FAZ, E É DECISÃO
--
-- **Não guarda palavra-chave.** A documentação do Google diz, com essas
-- palavras, que a *meta keywords* não é usada pela Busca, e lista "repetição
-- excessiva de palavra-chave" como violação de política de spam. Um campo de
-- palavra-chave num editor é um convite a escrever para o robô — e a única
-- coisa que ele mudaria de fato é o texto ficar pior para quem lê.
--
-- **Não guarda nota de SEO.** A conferência que a tela mostra é uma lista de
-- fatos verificáveis, cada um com a consequência escrita. Nota de 0 a 100 é
-- número inventado sobre coisa que ninguém de fora mede assim, e este produto
-- já recusou inventar número em `piso_multa` pelo mesmo motivo.
--
-- **Não guarda contagem mínima de palavras.** A própria documentação do Google
-- diz que não existe número mágico de palavras. Um editor que exige 300
-- palavras ensina a encher linguiça.
-- =====================================================================

-- ================================================ 1 · o que o texto passa a ter

alter table public.posts
  add column if not exists formato text not null default 'texto';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'posts_formato_conhecido'
  ) then
    alter table public.posts
      add constraint posts_formato_conhecido check (formato in ('texto', 'marcacao'));
  end if;
end $$;

comment on column public.posts.formato is
  'Como o corpo deve ser lido. "texto" e paragrafo puro (o de 0051); "marcacao" passa pelo interpretador restrito. Congelado depois da estreia: trocar reinterpreta caracteres que ja estao no ar.';

-- A canônica existe para o texto publicado primeiro em outro lugar. Só https:
-- canônica relativa é ambígua para o rastreador, e canônica http numa página
-- https é a mesma armadilha de conteúdo misto da figura.
alter table public.posts
  add column if not exists canonica text;

alter table public.posts
  add column if not exists indexavel boolean not null default true;

alter table public.posts
  add column if not exists figura_largura integer;

alter table public.posts
  add column if not exists figura_altura integer;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'posts_canonica_https') then
    alter table public.posts
      add constraint posts_canonica_https
      check (canonica is null or canonica ~ '^https://');
  end if;

  if not exists (select 1 from pg_constraint where conname = 'posts_figura_medidas') then
    alter table public.posts
      add constraint posts_figura_medidas
      check (
        (figura_largura is null) = (figura_altura is null)
        and (figura_largura is null or figura_largura between 1 and 20000)
        and (figura_altura  is null or figura_altura  between 1 and 20000)
      );
  end if;
end $$;

comment on column public.posts.indexavel is
  'Falso pede aos buscadores para nao indexar. Nao esconde de ninguem: quem tem o link le. Serve para pagina fina que existe por outro motivo.';

comment on column public.posts.canonica is
  'O endereco original, quando este texto saiu antes em outro lugar. Vazio significa "o original e este".';

-- ============================================== 2 · o formato congela na estreia

/**
 * Invariante 2 do cabeçalho, no banco e não na tela.
 *
 * A mensagem diz o que fazer, e não só o que não dá — é a forma das recusas da
 * 0050. Duplicar o texto num rascunho novo é a saída honesta: o que está no ar
 * continua como estava, e a versão nova estreia com outro endereço.
 */
create or replace function public.formato_publicado_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.publicado_em is not null and new.formato is distinct from old.formato then
    raise exception 'este texto já estreou e o formato dele não muda: trocar o interpretador reescreveria o que as pessoas já leram. Duplique num rascunho novo se quiser reescrever com marcação.';
  end if;
  return new;
end;
$$;

drop trigger if exists posts_formato_congelado on public.posts;
create trigger posts_formato_congelado
  before update on public.posts
  for each row execute function public.formato_publicado_nao_muda();

-- ================================================== 3 · a biblioteca de figuras

create table if not exists public.post_figuras (
  id        uuid primary key default gen_random_uuid(),

  -- O caminho dentro do bucket. Único: dois cadastros para o mesmo arquivo
  -- fariam a conferência de uso mentir na hora de apagar.
  caminho   text not null unique check (length(btrim(caminho)) between 3 and 400),

  url       text not null check (url ~ '^(/|https://)'),

  -- Invariante 4: alternativa no cadastro, não na tela.
  alt       text not null check (length(btrim(alt)) between 3 and 200),

  largura   integer not null check (largura between 1 and 20000),
  altura    integer not null check (altura between 1 and 20000),

  -- Cinco megabytes. O limite real é o do bucket; este é o que dá mensagem em
  -- português antes de a pessoa esperar o upload inteiro para ouvir não.
  bytes     integer not null check (bytes between 1 and 5242880),

  tipo      text not null check (tipo in ('image/jpeg', 'image/png', 'image/webp', 'image/avif')),

  criado_em timestamptz not null default now()
);

comment on table public.post_figuras is
  'As figuras do blog. Sem conta_id, como posts: e o blog do produto, nao o de um cliente. O alt e not null de proposito — e o unico momento em que quem sobe esta olhando para a imagem.';

create index if not exists post_figuras_recentes on public.post_figuras (criado_em desc);

alter table public.post_figuras enable row level security;

-- Só o operador enxerga a biblioteca. As figuras usadas num texto publicado
-- são públicas pela URL — isso é outra coisa: a lista do que existe, inclusive
-- o que foi subido e nunca usado, é do painel.
drop policy if exists "post_figuras: so o operador" on public.post_figuras;
create policy "post_figuras: so o operador"
  on public.post_figuras for select
  to authenticated
  using (public.e_operador());

-- Sem política de escrita: escrita é função, como em toda a 0051.

-- ====================================================== 4 · o balde do storage

/**
 * O bucket público das figuras do blog.
 *
 * Público na leitura porque é isso que uma figura de blog é: um arquivo que
 * qualquer pessoa na internet abre. O que **não** é público é a escrita, e é
 * ela que as políticas abaixo trancam.
 *
 * `file_size_limit` e `allowed_mime_types` são a defesa que não depende da
 * tela: um `POST` direto no endpoint do storage com um `.svg` — que é XML e
 * executa script — ou com um arquivo de 400 MB esbarra aqui, não no formulário.
 * SVG fica de fora da lista por isso, e não por falta de utilidade.
 */
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'blog', 'blog', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "blog: qualquer um le" on storage.objects;
create policy "blog: qualquer um le"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'blog');

drop policy if exists "blog: so o operador sobe" on storage.objects;
create policy "blog: so o operador sobe"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'blog' and public.e_operador());

drop policy if exists "blog: so o operador troca" on storage.objects;
create policy "blog: so o operador troca"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'blog' and public.e_operador())
  with check (bucket_id = 'blog' and public.e_operador());

drop policy if exists "blog: so o operador apaga" on storage.objects;
create policy "blog: so o operador apaga"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'blog' and public.e_operador());

-- ====================================================== 5 · as funções da figura

/**
 * Cadastra uma figura que já subiu.
 *
 * A ordem é essa: o navegador sobe o arquivo (com a sessão dele, passando pelas
 * políticas acima) e **depois** registra. Se o registro falhar, sobra um
 * arquivo órfão no bucket — que é o lado barato de errar. O contrário, registrar
 * antes, deixaria linha apontando para arquivo que nunca chegou, e aí a figura
 * aparece quebrada num texto publicado.
 */
create or replace function public.registrar_figura(
  p_caminho text,
  p_url     text,
  p_alt     text,
  p_largura integer,
  p_altura  integer,
  p_bytes   integer,
  p_tipo    text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.e_operador() then
    raise exception 'só o operador sobe figura para o blog';
  end if;

  if length(btrim(coalesce(p_alt, ''))) < 3 then
    raise exception 'descreva a figura em poucas palavras: sem isso, quem usa leitor de tela recebe silêncio no lugar dela';
  end if;

  insert into public.post_figuras (caminho, url, alt, largura, altura, bytes, tipo)
  values (btrim(p_caminho), btrim(p_url), btrim(p_alt), p_largura, p_altura, p_bytes, btrim(p_tipo))
  returning id into v_id;

  return v_id;
end;
$$;

/**
 * A biblioteca, com a contagem de onde cada figura está sendo usada.
 *
 * `usos` conta a capa e o corpo de qualquer texto — publicado ou não. É o
 * número que a tela mostra ao lado do botão de apagar, e é o que faz a recusa
 * da invariante 3 não parecer arbitrária quando ela acontece.
 */
create or replace function public.figuras_do_blog()
returns table (
  id        uuid,
  caminho   text,
  url       text,
  alt       text,
  largura   integer,
  altura    integer,
  bytes     integer,
  tipo      text,
  criado_em timestamptz,
  usos      integer,
  usos_no_ar integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'só o operador vê a biblioteca de figuras';
  end if;

  return query
    select f.id, f.caminho, f.url, f.alt, f.largura, f.altura, f.bytes, f.tipo, f.criado_em,
           (select count(*)::integer from public.posts p
             where p.figura_url = f.url or position(f.url in p.corpo) > 0),
           (select count(*)::integer from public.posts p
             where p.publicado_em is not null
               and (p.figura_url = f.url or position(f.url in p.corpo) > 0))
      from public.post_figuras f
     order by f.criado_em desc;
end;
$$;

/**
 * Tira a figura da biblioteca — invariante 3.
 *
 * Devolve o caminho no bucket para o app apagar o arquivo em seguida. Devolver
 * em vez de apagar aqui é reconhecer o que este banco não alcança: o arquivo
 * mora no storage, e apagá-lo é chamada de API, não `delete`.
 */
create or replace function public.apagar_figura(p_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url     text;
  v_caminho text;
  v_no_ar   integer;
begin
  if not public.e_operador() then
    raise exception 'só o operador apaga figura do blog';
  end if;

  select url, caminho into v_url, v_caminho
    from public.post_figuras where id = p_id;

  if v_url is null then
    raise exception 'figura não encontrada';
  end if;

  select count(*)::integer into v_no_ar
    from public.posts p
   where p.publicado_em is not null
     and (p.figura_url = v_url or position(v_url in p.corpo) > 0);

  if v_no_ar > 0 then
    raise exception 'esta figura está em % texto(s) que já estrearam: apagá-la deixaria buraco no que as pessoas já leram. Tire a figura do texto primeiro.', v_no_ar;
  end if;

  delete from public.post_figuras where id = p_id;

  return v_caminho;
end;
$$;

-- ============================================ 6 · salvar_post, sem sobrecarga

/**
 * A lição da 0052b, aplicada antes de doer.
 *
 * Acrescentar parâmetro a uma função do PostgREST **cria uma sobrecarga**; a
 * antiga continua de pé, e o PostgREST escolhe pelo conjunto de nomes que a
 * chamada manda. Sem este `drop`, uma tela antiga em cache continuaria salvando
 * pela versão de sete parâmetros — sem erro, e sem gravar formato nenhum.
 */
drop function if exists public.salvar_post(uuid, text, text, text, text, text, text);

create or replace function public.salvar_post(
  p_id             uuid,
  p_slug           text,
  p_titulo         text,
  p_corpo          text,
  p_resumo         text default null,
  p_figura_url     text default null,
  p_figura_alt     text default null,
  p_formato        text default null,
  p_canonica       text default null,
  p_indexavel      boolean default true,
  p_figura_largura integer default null,
  p_figura_altura  integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_formato text;
begin
  if not public.e_operador() then
    raise exception 'só o operador escreve no blog';
  end if;

  if p_id is null then
    -- Texto novo nasce com marcação: é o editor de hoje. Os antigos ficam com
    -- 'texto' e nunca são convertidos por debaixo do pano.
    insert into public.posts (
      slug, titulo, corpo, resumo, figura_url, figura_alt,
      formato, canonica, indexavel, figura_largura, figura_altura
    )
    values (
      lower(btrim(p_slug)),
      btrim(p_titulo),
      btrim(p_corpo),
      nullif(btrim(coalesce(p_resumo, '')), ''),
      nullif(btrim(coalesce(p_figura_url, '')), ''),
      nullif(btrim(coalesce(p_figura_alt, '')), ''),
      coalesce(nullif(btrim(coalesce(p_formato, '')), ''), 'marcacao'),
      nullif(btrim(coalesce(p_canonica, '')), ''),
      coalesce(p_indexavel, true),
      p_figura_largura,
      p_figura_altura
    )
    returning id into v_id;
  else
    -- Formato ausente na chamada mantém o que está gravado. É o que faz uma
    -- tela que não conhece a coluna não zerá-la.
    select coalesce(nullif(btrim(coalesce(p_formato, '')), ''), formato)
      into v_formato
      from public.posts where id = p_id;

    update public.posts
       set slug           = lower(btrim(p_slug)),
           titulo         = btrim(p_titulo),
           corpo          = btrim(p_corpo),
           resumo         = nullif(btrim(coalesce(p_resumo, '')), ''),
           figura_url     = nullif(btrim(coalesce(p_figura_url, '')), ''),
           figura_alt     = nullif(btrim(coalesce(p_figura_alt, '')), ''),
           formato        = v_formato,
           canonica       = nullif(btrim(coalesce(p_canonica, '')), ''),
           indexavel      = coalesce(p_indexavel, true),
           figura_largura = p_figura_largura,
           figura_altura  = p_figura_altura
     where id = p_id
    returning id into v_id;

    if v_id is null then
      raise exception 'texto não encontrado';
    end if;
  end if;

  return v_id;
end;
$$;

-- ================================================ 7 · o que o sitemap precisa

/**
 * A lista para o sitemap — e por que ela é função e não `select`.
 *
 * O `sitemap.xml` é gerado por uma rota sem sessão. Ela poderia ler a tabela
 * com a chave anônima e a política pública já filtraria certo. A função existe
 * por outro motivo: **o sitemap não deve listar o que pede para não ser
 * indexado.** Pôr um endereço `noindex` no sitemap é mandar o rastreador a um
 * lugar para ele descobrir que não devia ter ido — desperdício de rastreio, e a
 * própria documentação trata sitemap como sugestão de rastreio, não de índice.
 *
 * `stable` e sem `security definer`: quem chama é o anônimo, e a política
 * pública é exatamente o filtro certo. Definer aqui abriria rascunho.
 */
create or replace function public.posts_do_sitemap()
returns table (slug text, atualizado_em timestamptz, publicado_em timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.slug, p.atualizado_em, p.publicado_em
    from public.posts p
   where p.visivel
     and p.publicado_em is not null
     and p.publicado_em <= now()
     and p.indexavel
     and p.canonica is null
   order by p.publicado_em desc
   limit 5000;
$$;

-- ============================================================ 8 · os grants

revoke execute on function public.registrar_figura(text, text, text, integer, integer, integer, text) from public, anon;
revoke execute on function public.figuras_do_blog()                     from public, anon;
revoke execute on function public.apagar_figura(uuid)                   from public, anon;
revoke execute on function public.salvar_post(uuid, text, text, text, text, text, text, text, text, boolean, integer, integer) from public, anon;

grant execute on function public.registrar_figura(text, text, text, integer, integer, integer, text) to authenticated;
grant execute on function public.figuras_do_blog()   to authenticated;
grant execute on function public.apagar_figura(uuid) to authenticated;
grant execute on function public.salvar_post(uuid, text, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;

-- O sitemap é lido por quem não tem sessão. É a única função deste arquivo que
-- o anônimo executa, e ela não enxerga nada além do que a política já libera.
grant execute on function public.posts_do_sitemap() to anon, authenticated;

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.formato_publicado_nao_muda() from public, anon, authenticated;
