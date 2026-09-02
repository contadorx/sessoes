-- =====================================================================
-- 0051 · O blog, e as três páginas que um produto pago precisa ter
-- =====================================================================
--
-- POR QUE ESTA MIGRAÇÃO EXISTE
--
-- O Leandro pediu duas coisas na mesma frase: *"crie em negócio a
-- administração de um blog com figuras e links, e coloque na página principal
-- do Sessões. Coloque também termos de serviço, segurança e privacidade."*
--
-- As duas metades parecem administrativas e não são. Elas mudam **quem é o
-- leitor deste banco**.
--
-- Até aqui, toda linha de dado neste sistema pertencia a uma conta e existia
-- para ser lida por quem está dentro dela. A RLS inteira foi construída em
-- volta de uma pergunta só — *"é da mesma conta?"* — e depois, na 0049, de uma
-- segunda: *"esta pessoa tem acesso clínico?"*. Todo furo que este projeto
-- encontrou em nove meses foi uma variação de responder mal a essas duas.
--
-- `posts` é a primeira tabela cujo destino é **um estranho não autenticado**.
-- A pergunta que a RLS faz aqui é outra, e é invertida: não "de quem é isto",
-- mas **"eu escolhi publicar isto?"**. E como a resposta certa quase sempre é
-- "não" (rascunho é o estado normal de um texto), o padrão tem de ser fechado.
--
--
-- A DECISÃO QUE ORGANIZA A MIGRAÇÃO
--
-- **Nada aqui tem `conta_id`, e isso é deliberado.** O blog é meu, não é da
-- psicóloga. Se `posts` tivesse `conta_id`, ele entraria em `exportar_conta`,
-- seria alcançado por `eliminar_conta`, contaria no painel — e um dia alguém
-- apagaria a conta de teste e levaria junto um texto publicado.
--
-- Mas o preço dessa escolha já foi pago uma vez neste projeto, e está escrito
-- no diário: as tabelas do Panorama também não têm `conta_id`, e por isso
-- ficaram **fora de todo o maquinário de LGPD** sem que nenhuma suíte
-- reclamasse — uma tabela nova nunca reprova uma lista da qual não faz parte.
--
-- Então esta migração paga o preço na hora: a suíte 0051 confere, por
-- estrutura, que `posts` e `post_links` **não têm coluna de paciente, de conta
-- nem de sessão**, e reprova se alguém acrescentar. Sem `conta_id` por
-- decisão, e sem dado de gente por construção.
--
--
-- AS INVARIANTES, E O QUE CADA UMA CUSTA FORA DO SOFTWARE
--
-- 1. **Publicado é uma coisa, visível é outra.** Duas colunas, não uma.
--    `publicado_em` é a data em que o texto foi ao ar pela primeira vez e
--    **nunca é reescrita**; `visivel` é se ele está no ar agora. Tirar do ar
--    esconde; não faz o texto voltar a ser inédito. Uma coluna só obrigaria a
--    zerar a data para despublicar — e um texto que esteve no ar no dia 3
--    esteve no ar no dia 3, inclusive para quem o citou. Republicar não
--    inventa novidade.
--
-- 2. **Endereço de texto publicado não muda.** O `slug` é congelado por
--    gatilho a partir da primeira publicação. Trocar o endereço de um texto
--    que alguém compartilhou quebra o link dessa pessoa em silêncio, e o
--    sintoma aparece meses depois como "o site dá 404". Corrigir um slug feio
--    é possível **enquanto é rascunho**, que é quando não custa nada.
--
-- 3. **Texto que já foi ao ar não se apaga pelo app.** `apagar_post` recusa
--    qualquer post com `publicado_em` preenchido — some da vista com
--    `despublicar_post`, e a linha fica. É a mesma família do documento
--    emitido da 0029 e do adendo da 0043: o que outra pessoa pode ter lido não
--    é meu para fazer desaparecer.
--
-- 4. **URL é `http`, `https` ou caminho do próprio site — e nada mais.** Um
--    `javascript:` num link, ou um `data:` numa figura, é XSS armazenado numa
--    página que estranhos abrem. Eu sou o único que escreve aqui hoje, e a
--    restrição continua valendo, porque a defesa não é contra um invasor: é
--    contra eu colar, num dia cansado, uma URL que veio de outro lugar.
--
-- 5. **O corpo é texto, não HTML.** A coluna guarda parágrafos separados por
--    linha em branco, e a tela renderiza como texto. Não existe
--    `dangerouslySetInnerHTML` no caminho, e há teste no TS que reprova se
--    aparecer. Um blog que aceita HTML é um blog que aceita `<script>`.
--
-- 6. **O blog não conta leitor.** Nenhuma tabela de visita, nenhum
--    identificador por pessoa, nenhum cookie. Num site cujo argumento inteiro
--    é sigilo, medir quem leu "o que fazer quando o paciente some" seria
--    construir exatamente o que a página promete não existir. Se um dia eu
--    quiser saber o que é lido, isso vem agregado da borda, não de uma linha
--    por visita.
--
-- 7. **Escrita só por função, como na 0050.** As tabelas continuam sem
--    política de INSERT, UPDATE e DELETE. `e_operador()` na primeira linha de
--    cada função.
--
--
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
--
-- Não cria editor de HTML, não cria upload de imagem e não cria agendamento de
-- publicação. A figura entra por URL — arquivo em `public/blog/` ou endereço
-- https —, porque upload exigiria bucket, política de storage e um caminho de
-- arquivo público que hoje não existe, e nada disso é necessário para um blog
-- que ainda não tem o primeiro texto.
--
-- As três páginas legais (termos, segurança, privacidade) **não moram no
-- banco**. São páginas do repositório, versionadas em git, porque documento
-- que rege um contrato tem de ter histórico de alteração que eu não consigo
-- editar por uma tela às onze da noite. O blog é conteúdo; termos são
-- compromisso.
-- =====================================================================

-- ============================================================ 1 · as tabelas

create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),

  -- O endereço. Congelado por gatilho depois da primeira publicação.
  slug          text not null unique
                check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 80),

  titulo        text not null check (length(btrim(titulo)) between 3 and 160),
  resumo        text          check (resumo is null or length(resumo) between 3 and 400),
  corpo         text not null check (length(btrim(corpo)) >= 20),

  -- A figura. Caminho do próprio site ou https — ver invariante 4.
  figura_url    text          check (figura_url is null or figura_url ~ '^(/|https://)'),
  -- Texto alternativo. Sem ele a figura é enfeite para quem usa leitor de tela.
  figura_alt    text          check (figura_alt is null or length(figura_alt) between 3 and 200),

  -- Invariante 1: a data da estreia, e se está no ar agora. Duas perguntas.
  publicado_em  timestamptz,
  visivel       boolean not null default false,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  -- Figura sem alternativa não passa. É acessibilidade, e é barata aqui.
  constraint figura_com_alternativa
    check (figura_url is null or figura_alt is not null),

  -- Visível sem nunca ter sido publicado é estado impossível: quem publica
  -- carimba a data. Sem isto, um `update visivel = true` direto poria no ar um
  -- texto sem data de estreia, e a listagem pública ordena por essa data.
  constraint visivel_exige_estreia
    check (not visivel or publicado_em is not null)
);

comment on table public.posts is
  'Os textos do blog. Primeira tabela deste banco escrita para quem nao tem conta: a RLS pergunta "eu publiquei isto?", nao "de quem e isto". Sem conta_id de proposito, e sem dado de pessoa por construcao.';

comment on column public.posts.publicado_em is
  'A estreia. Escrita uma vez e nunca reescrita — despublicar esconde, nao apaga a data.';

comment on column public.posts.visivel is
  'Se esta no ar agora. Separado de publicado_em para que tirar do ar nao faca o texto voltar a ser inedito.';

create table if not exists public.post_links (
  id        uuid primary key default gen_random_uuid(),
  post_id   uuid not null references public.posts(id) on delete cascade,
  rotulo    text not null check (length(btrim(rotulo)) between 2 and 120),
  url       text not null check (url ~ '^(/|https://|http://)'),
  ordem     smallint not null default 0 check (ordem between 0 and 99),
  criado_em timestamptz not null default now(),

  unique (post_id, ordem)
);

comment on table public.post_links is
  'Os links que um texto carrega. Cascade no post: link sem texto nao existe. A URL e conferida por check — javascript: numa pagina publica e XSS armazenado.';

create index if not exists post_links_por_post on public.post_links (post_id, ordem);

-- A listagem pública ordena pela estreia e só enxerga o que está no ar.
create index if not exists posts_vitrine
  on public.posts (publicado_em desc)
  where visivel;

-- ============================================================ 2 · os gatilhos

/**
 * O carimbo de atualização é do servidor, como em todo o resto deste banco.
 */
create or replace function public.post_carimba()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

/**
 * O endereço de um texto publicado não muda.
 *
 * Invariante 2. E é gatilho, e não `check`, porque a regra compara o valor
 * novo com o antigo — um `check` só enxerga a linha resultante e deixaria
 * passar a troca.
 *
 * A comparação é com `publicado_em`, e não com `visivel`: um texto que esteve
 * no ar e foi tirado continua tendo um endereço que alguém guardou.
 */
create or replace function public.slug_publicado_nao_muda()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.publicado_em is not null and new.slug is distinct from old.slug then
    raise exception
      'este texto já foi publicado em % — o endereço dele está em links que outras pessoas guardaram, e trocá-lo quebra esses links sem aviso. Corrija o endereço enquanto é rascunho.',
      to_char(old.publicado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
  end if;

  -- Invariante 1, do lado do gatilho: a estreia é escrita uma vez.
  if old.publicado_em is not null and new.publicado_em is distinct from old.publicado_em then
    raise exception 'a data de estreia de um texto publicado não se reescreve';
  end if;

  return new;
end;
$$;

drop trigger if exists tg_post_carimba on public.posts;
create trigger tg_post_carimba
  before update on public.posts
  for each row execute function public.post_carimba();

drop trigger if exists tg_slug_publicado_nao_muda on public.posts;
create trigger tg_slug_publicado_nao_muda
  before update on public.posts
  for each row execute function public.slug_publicado_nao_muda();

-- ============================================================ 3 · a RLS

alter table public.posts      enable row level security;
alter table public.post_links enable row level security;

/**
 * A leitura pública, e ela é a razão de a tabela existir.
 *
 * `to anon, authenticated` — o visitante da landing não tem sessão, e é ele o
 * destinatário. A cláusula é a pergunta invertida desta migração: **está no ar
 * e já estreou?**
 *
 * O que fica de fora, para quem chegar aqui pelo `/rest/v1/posts`: rascunho,
 * texto tirado do ar, e a coluna `visivel` de qualquer linha que não passe. Um
 * `GET` anônimo devolve exatamente a vitrine, e nada além.
 */
drop policy if exists "posts: o que esta no ar" on public.posts;
create policy "posts: o que esta no ar"
  on public.posts for select
  to anon, authenticated
  using (visivel and publicado_em is not null and publicado_em <= now());

/**
 * O operador vê o que ainda não publicou. É a única leitura a mais.
 */
drop policy if exists "posts: o operador ve os rascunhos" on public.posts;
create policy "posts: o operador ve os rascunhos"
  on public.posts for select
  to authenticated
  using (public.e_operador());

/**
 * Link segue o texto: só aparece se o texto aparece.
 *
 * Sem esta subconsulta, os links de um rascunho ficariam legíveis — e o rótulo
 * de um link costuma entregar o assunto do texto que ainda não saiu.
 */
drop policy if exists "post_links: seguem o texto" on public.post_links;
create policy "post_links: seguem o texto"
  on public.post_links for select
  to anon, authenticated
  using (
    exists (
      select 1
        from public.posts p
       where p.id = post_links.post_id
         and p.visivel
         and p.publicado_em is not null
         and p.publicado_em <= now()
    )
  );

drop policy if exists "post_links: o operador ve os rascunhos" on public.post_links;
create policy "post_links: o operador ve os rascunhos"
  on public.post_links for select
  to authenticated
  using (public.e_operador());

-- Invariante 7: nenhuma política de INSERT, UPDATE ou DELETE. Escrita é função.

-- ============================================================ 4 · as funções

/**
 * Cria ou atualiza um texto.
 *
 * `p_id` nulo cria; preenchido atualiza. Um upsert por slug seria mais curto e
 * estaria errado: corrigir o título de um texto **mudando o slug** criaria um
 * segundo texto em silêncio, e o primeiro continuaria no ar.
 */
create or replace function public.salvar_post(
  p_id         uuid,
  p_slug       text,
  p_titulo     text,
  p_corpo      text,
  p_resumo     text default null,
  p_figura_url text default null,
  p_figura_alt text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.e_operador() then
    raise exception 'só o operador escreve no blog';
  end if;

  if p_id is null then
    insert into public.posts (slug, titulo, corpo, resumo, figura_url, figura_alt)
    values (
      lower(btrim(p_slug)),
      btrim(p_titulo),
      btrim(p_corpo),
      nullif(btrim(coalesce(p_resumo, '')), ''),
      nullif(btrim(coalesce(p_figura_url, '')), ''),
      nullif(btrim(coalesce(p_figura_alt, '')), '')
    )
    returning id into v_id;
  else
    update public.posts
       set slug       = lower(btrim(p_slug)),
           titulo     = btrim(p_titulo),
           corpo      = btrim(p_corpo),
           resumo     = nullif(btrim(coalesce(p_resumo, '')), ''),
           figura_url = nullif(btrim(coalesce(p_figura_url, '')), ''),
           figura_alt = nullif(btrim(coalesce(p_figura_alt, '')), '')
     where id = p_id
    returning id into v_id;

    if v_id is null then
      raise exception 'texto não encontrado';
    end if;
  end if;

  return v_id;
end;
$$;

/**
 * Põe no ar.
 *
 * A estreia é carimbada **só na primeira vez**. Da segunda em diante o texto
 * volta com a data que sempre teve — invariante 1.
 */
create or replace function public.publicar_post(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r record;
begin
  if not public.e_operador() then
    raise exception 'só o operador publica';
  end if;

  select id, publicado_em, corpo, titulo into r
    from public.posts where id = p_id;

  if r.id is null then
    raise exception 'texto não encontrado';
  end if;

  -- plpgsql não curto-circuita: o record já está atribuído aqui, e é por isso
  -- que estas conferências vêm depois do `if r.id is null`.
  if length(btrim(coalesce(r.corpo, ''))) < 20 then
    raise exception 'texto vazio não vai ao ar';
  end if;

  update public.posts
     set visivel      = true,
         publicado_em = coalesce(publicado_em, now())
   where id = p_id;
end;
$$;

/**
 * Tira do ar. Não apaga, e não mexe na data da estreia.
 */
create or replace function public.despublicar_post(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'só o operador despublica';
  end if;

  update public.posts set visivel = false where id = p_id;

  if not found then
    raise exception 'texto não encontrado';
  end if;
end;
$$;

/**
 * Apaga — e recusa qualquer texto que já esteve no ar.
 *
 * Invariante 3. Rascunho que nasceu errado se apaga; texto que estranho pode
 * ter lido, não. A mensagem manda para o caminho certo em vez de só negar.
 */
create or replace function public.apagar_post(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_publicado timestamptz;
begin
  if not public.e_operador() then
    raise exception 'só o operador apaga';
  end if;

  select publicado_em into v_publicado from public.posts where id = p_id;

  if not found then
    raise exception 'texto não encontrado';
  end if;

  if v_publicado is not null then
    raise exception
      'este texto já esteve no ar e não se apaga — tire do ar, que a linha fica e o endereço para de responder';
  end if;

  delete from public.posts where id = p_id;
end;
$$;

/**
 * Substitui a lista de links de um texto.
 *
 * Substitui, e não acrescenta: a tela edita a lista inteira, e um "acrescentar"
 * exigiria uma segunda função para remover — duas portas para uma lista de
 * três itens. O `delete` e o `insert` estão na mesma transação, então uma lista
 * recusada pelo `check` de URL deixa a antiga como estava.
 */
create or replace function public.definir_links_do_post(p_id uuid, p_links jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item  jsonb;
  v_ordem smallint := 0;
  v_n     integer  := 0;
begin
  if not public.e_operador() then
    raise exception 'só o operador edita os links';
  end if;

  if not exists (select 1 from public.posts where id = p_id) then
    raise exception 'texto não encontrado';
  end if;

  delete from public.post_links where post_id = p_id;

  if p_links is null or jsonb_typeof(p_links) <> 'array' then
    return 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_links)
  loop
    -- Item sem rótulo ou sem endereço é linha pela metade: ignorada, não
    -- gravada em branco. A tela manda a lista toda, inclusive as vazias.
    if coalesce(btrim(v_item ->> 'rotulo'), '') <> ''
       and coalesce(btrim(v_item ->> 'url'), '') <> '' then
      insert into public.post_links (post_id, rotulo, url, ordem)
      values (p_id, btrim(v_item ->> 'rotulo'), btrim(v_item ->> 'url'), v_ordem);
      v_ordem := v_ordem + 1;
      v_n := v_n + 1;
    end if;
  end loop;

  return v_n;
end;
$$;

/**
 * A listagem do painel — rascunhos inclusive.
 *
 * Existe como função, e não como `select` direto com a política do operador,
 * por um motivo só: a contagem de links. Fazer isso na tela seria uma consulta
 * por linha.
 */
create or replace function public.posts_do_painel()
returns table (
  id           uuid,
  slug         text,
  titulo       text,
  resumo       text,
  figura_url   text,
  visivel      boolean,
  publicado_em timestamptz,
  atualizado_em timestamptz,
  links        integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'só o operador vê o painel do blog';
  end if;

  return query
    select p.id, p.slug, p.titulo, p.resumo, p.figura_url,
           p.visivel, p.publicado_em, p.atualizado_em,
           (select count(*)::integer from public.post_links l where l.post_id = p.id)
      from public.posts p
     order by coalesce(p.publicado_em, p.criado_em) desc;
end;
$$;

/**
 * Um texto por dentro, para a tela de edição. Rascunho inclusive.
 */
create or replace function public.post_do_painel(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v jsonb;
begin
  if not public.e_operador() then
    raise exception 'só o operador vê o painel do blog';
  end if;

  select jsonb_build_object(
           'post', to_jsonb(p) - 'criado_em',
           'links', coalesce(
             (select jsonb_agg(jsonb_build_object('rotulo', l.rotulo, 'url', l.url) order by l.ordem)
                from public.post_links l where l.post_id = p.id),
             '[]'::jsonb)
         )
    into v
    from public.posts p
   where p.id = p_id;

  if v is null then
    raise exception 'texto não encontrado';
  end if;

  return v;
end;
$$;

-- ============================================================ 5 · os grants

-- A leitura pública é por RLS, não por função: `anon` faz `select` na tabela e
-- a política decide. Por isso as tabelas precisam do grant de select.
grant select on public.posts      to anon, authenticated;
grant select on public.post_links to anon, authenticated;

-- E nada além de select. Sem isso, a ausência de política de INSERT seria a
-- única trava, e este projeto já aprendeu na 0018 que uma trava só não basta.
revoke insert, update, delete on public.posts      from anon, authenticated;
revoke insert, update, delete on public.post_links from anon, authenticated;

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.post_carimba()             from public, anon, authenticated;
revoke execute on function public.slug_publicado_nao_muda()  from public, anon, authenticated;

-- As funções de escrita: `public` e `anon` fora; `authenticated` entra e quem
-- barra é o `e_operador()` de dentro — a mesma forma da 0045 e da 0050.
revoke execute on function public.salvar_post(uuid, text, text, text, text, text, text) from public, anon;
revoke execute on function public.publicar_post(uuid)                                   from public, anon;
revoke execute on function public.despublicar_post(uuid)                                from public, anon;
revoke execute on function public.apagar_post(uuid)                                     from public, anon;
revoke execute on function public.definir_links_do_post(uuid, jsonb)                    from public, anon;
revoke execute on function public.posts_do_painel()                                     from public, anon;
revoke execute on function public.post_do_painel(uuid)                                  from public, anon;

grant execute on function public.salvar_post(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.publicar_post(uuid)                                   to authenticated;
grant execute on function public.despublicar_post(uuid)                                to authenticated;
grant execute on function public.apagar_post(uuid)                                     to authenticated;
grant execute on function public.definir_links_do_post(uuid, jsonb)                    to authenticated;
grant execute on function public.posts_do_painel()                                     to authenticated;
grant execute on function public.post_do_painel(uuid)                                  to authenticated;
