-- 0001 · A lista de espera da landing.
--
-- Primeira tabela do projeto, e por isso mesmo já com RLS ativa: a regra do
-- doc 05 é "RLS desde a primeira tabela", nunca "ativo depois".
--
-- Postura de acesso: o público pode INSERIR (é um formulário aberto) e não pode
-- LER nada. Não existe policy de select, update ou delete — quem precisa ler é
-- o dono, pelo painel do Supabase ou pela service role.

create extension if not exists "pgcrypto";

-- Função utilitária única de "dia" no fuso do produto (doc 05, lei nº 3).
-- Tudo que é data no Sessões é calculado em America/Sao_Paulo, no banco.
create or replace function public.hoje_sp()
returns date
language sql
stable
security invoker
set search_path = ''
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

create table if not exists public.interessados (
  id            uuid primary key default gen_random_uuid(),
  email         text not null,
  nome          text,
  perfil        text not null default 'nao_informado'
                check (perfil in ('autonoma', 'clinica', 'estudante', 'outro', 'nao_informado')),
  sessoes_semana int check (sessoes_semana is null or sessoes_semana between 0 and 200),
  origem        text,
  criado_em     timestamptz not null default now(),
  criado_dia    date not null default public.hoje_sp()
);

-- Um e-mail, um registro. Reinscrever não duplica nem vaza que já existe.
create unique index if not exists interessados_email_unico
  on public.interessados (lower(email));

create index if not exists interessados_criado_dia
  on public.interessados (criado_dia);

alter table public.interessados enable row level security;

-- Só inserir. Nenhuma policy de leitura, por construção.
drop policy if exists "qualquer um se inscreve" on public.interessados;
create policy "qualquer um se inscreve"
  on public.interessados
  for insert
  to anon, authenticated
  with check (
    email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and length(email) between 5 and 254
    and (nome is null or length(nome) <= 120)
  );

comment on table public.interessados is
  'Lista de espera captada na landing. Insert público, leitura só pelo dono (sem policy de select).';
