-- 0044 · Panorama da Prática Psicológica — as três tabelas da pesquisa.
-- Insert anônimo, leitura nenhuma. Mesmo padrão de public.interessados.
-- JÁ APLICADA no projeto remoto em 01/09/2026. Este arquivo existe para
-- o repositório não divergir do banco.

create table public.pesquisa_abertas (
  id             uuid primary key default gen_random_uuid(),
  sessao         uuid not null,
  criado_em      timestamptz not null default now(),
  canal          text,
  canal_url      text,
  dia            text not null,
  irritante      text not null,
  gambiarra      text,
  preocupacao    text not null,
  ua             text
);
comment on table public.pesquisa_abertas is
  'Bloco 1 do questionario, gravado no envio do bloco — antes de qualquer lista fechada e antes de a pessoa poder desistir no meio. Quem abandona depois ainda deixa o dado mais valioso.';
comment on column public.pesquisa_abertas.dia is
  'Q1.1 · reconstrucao do ultimo dia atendido, sem valencia. Vem antes das outras de proposito: pergunta emoldurada como problema so recupera o que a pessoa ja chama de problema.';
comment on column public.pesquisa_abertas.irritante is 'Q1.2 · a parte mais irritante que nao foi atender.';
comment on column public.pesquisa_abertas.gambiarra is 'Q1.3 · a solucao improvisada.';
comment on column public.pesquisa_abertas.preocupacao is 'Q1.4 · a preocupacao com o consultorio.';
create index on public.pesquisa_abertas (sessao);
create index on public.pesquisa_abertas (criado_em);

create table public.pesquisa_respostas (
  id             uuid primary key default gen_random_uuid(),
  sessao         uuid not null,
  criado_em      timestamptz not null default now(),
  canal          text,
  canal_url      text,
  duracao_seg    integer,
  ordem_itens    text[],
  respostas      jsonb not null
);
comment on table public.pesquisa_respostas is
  'Questionario completo, chaveado pelo codigo da pergunta. ordem_itens guarda a ordem em que os 17 itens do trade-off foram exibidos, para checar efeito de ordem.';
create index on public.pesquisa_respostas (sessao);
create index on public.pesquisa_respostas (criado_em);
create index on public.pesquisa_respostas using gin (respostas);

create table public.pesquisa_contatos (
  id             uuid primary key default gen_random_uuid(),
  criado_em      timestamptz not null default now(),
  email          text not null,
  quer_relatorio boolean not null default true,
  topa_conversa  boolean not null default false,
  whatsapp       text
);
comment on table public.pesquisa_contatos is
  'As duas portas opcionais da tela final. Sem NENHUMA ligacao com as respostas — e isso que sustenta "participantes nao identificados" da Res. CNS 510/2016, art. 1, par. unico, I. Nao criar FK, nao criar coluna sessao, nunca.';

alter table public.pesquisa_abertas   enable row level security;
alter table public.pesquisa_respostas enable row level security;
alter table public.pesquisa_contatos  enable row level security;

create policy "qualquer um responde a aberta" on public.pesquisa_abertas
  for insert to anon, authenticated with check (
    length(dia) between 20 and 8000
    and length(irritante) between 10 and 8000
    and length(preocupacao) between 10 and 8000
    and (gambiarra is null or length(gambiarra) <= 8000)
    and (canal is null or length(canal) <= 60)
    and (canal_url is null or length(canal_url) <= 40)
    and (ua is null or length(ua) <= 200)
  );

create policy "qualquer um responde o questionario" on public.pesquisa_respostas
  for insert to anon, authenticated with check (
    jsonb_typeof(respostas) = 'object'
    and length(respostas::text) <= 60000
    and (duracao_seg is null or duracao_seg between 0 and 86400)
    and (canal is null or length(canal) <= 60)
    and (canal_url is null or length(canal_url) <= 40)
    and (ordem_itens is null or array_length(ordem_itens, 1) <= 40)
  );

create policy "qualquer um deixa contato" on public.pesquisa_contatos
  for insert to anon, authenticated with check (
    email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and length(email) between 5 and 254
    and (whatsapp is null or length(whatsapp) <= 30)
  );

-- Nenhuma policy de SELECT: o publico insere e nao le.
revoke select, update, delete, truncate, references, trigger
  on public.pesquisa_abertas, public.pesquisa_respostas, public.pesquisa_contatos
  from anon, authenticated;
