-- 0002 · O núcleo multi-tenant: contas, usuarios, profissionais.
--
-- Lei do doc 05: RLS na criação da tabela, nunca "ativo depois".
-- Tenant = conta. `conta_id` em tudo, e toda leitura passa por ele.
--
-- Cuidado central: a política de `usuarios` não pode consultar `usuarios`
-- diretamente — isso é recursão de RLS. Por isso `public.conta_atual()` é
-- `security definer`: ela atravessa a RLS uma vez, em lugar controlado, e
-- devolve só o `conta_id` de quem está logado.

-- ---------------------------------------------------------------- utilidades

create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------- tabelas

create table if not exists public.contas (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(trim(nome)) between 1 and 120),
  tipo          text not null default 'solo' check (tipo in ('solo', 'clinica')),
  plano         text not null default 'gratis'
                check (plano in ('gratis', 'solo', 'pro', 'clinica')),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.usuarios (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  auth_user_id  uuid not null unique references auth.users (id) on delete cascade,
  papel         text not null default 'dona'
                check (papel in ('dona', 'profissional', 'secretaria')),
  nome          text,
  email         text not null,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.profissionais (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  usuario_id    uuid not null references public.usuarios (id) on delete cascade,
  crp           text,
  assina_como   text,
  cor_agenda    text not null default '#1C6B58',
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (conta_id, usuario_id)
);

-- FK sempre indexada (lei do doc 05; os advisors de performance cobram).
create index if not exists usuarios_conta on public.usuarios (conta_id);
create index if not exists profissionais_conta on public.profissionais (conta_id);
create index if not exists profissionais_usuario on public.profissionais (usuario_id);

do $$
declare t text;
begin
  foreach t in array array['contas', 'usuarios', 'profissionais'] loop
    execute format(
      'drop trigger if exists %I_atualizado_em on public.%I;
       create trigger %I_atualizado_em before update on public.%I
         for each row execute function public.tocar_atualizado_em();',
      t, t, t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------- quem sou eu

-- Atravessa a RLS de propósito e em um lugar só. `stable` para o planner
-- chamar uma vez por query; `search_path` fixo por exigência do doc 05.
create or replace function public.conta_atual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.conta_id
    from public.usuarios u
   where u.auth_user_id = (select auth.uid())
   limit 1;
$$;

revoke execute on function public.conta_atual() from public;
grant execute on function public.conta_atual() to authenticated;

create or replace function public.papel_atual()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.papel
    from public.usuarios u
   where u.auth_user_id = (select auth.uid())
   limit 1;
$$;

revoke execute on function public.papel_atual() from public;
grant execute on function public.papel_atual() to authenticated;

-- ---------------------------------------------------------------- RLS

alter table public.contas        enable row level security;
alter table public.usuarios      enable row level security;
alter table public.profissionais enable row level security;

-- contas: enxerga e edita só a própria; ninguém cria ou apaga conta pelo client
-- (quem cria é o gatilho de signup; apagar conta é operação de suporte).
drop policy if exists "conta propria: ler" on public.contas;
create policy "conta propria: ler"
  on public.contas for select to authenticated
  using (id = public.conta_atual());

drop policy if exists "conta propria: editar" on public.contas;
create policy "conta propria: editar"
  on public.contas for update to authenticated
  using (id = public.conta_atual() and public.papel_atual() = 'dona')
  with check (id = public.conta_atual());

-- usuarios: só os da mesma conta. Criar usuário é da dona (fase 4 usa isso).
drop policy if exists "usuarios da conta: ler" on public.usuarios;
create policy "usuarios da conta: ler"
  on public.usuarios for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "usuarios da conta: criar" on public.usuarios;
create policy "usuarios da conta: criar"
  on public.usuarios for insert to authenticated
  with check (conta_id = public.conta_atual() and public.papel_atual() = 'dona');

drop policy if exists "usuarios da conta: editar" on public.usuarios;
create policy "usuarios da conta: editar"
  on public.usuarios for update to authenticated
  using (
    conta_id = public.conta_atual()
    and (public.papel_atual() = 'dona' or auth_user_id = (select auth.uid()))
  )
  with check (conta_id = public.conta_atual());

-- profissionais: mesma conta.
drop policy if exists "profissionais da conta: ler" on public.profissionais;
create policy "profissionais da conta: ler"
  on public.profissionais for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "profissionais da conta: criar" on public.profissionais;
create policy "profissionais da conta: criar"
  on public.profissionais for insert to authenticated
  with check (conta_id = public.conta_atual() and public.papel_atual() = 'dona');

drop policy if exists "profissionais da conta: editar" on public.profissionais;
create policy "profissionais da conta: editar"
  on public.profissionais for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Nenhuma policy de DELETE em lugar nenhum: apagar não é operação de produto
-- (lei do doc 06 — arquiva-se, não se apaga).

-- ---------------------------------------------------------------- signup

-- Um cadastro novo nasce como conta solo, com a pessoa como dona e como
-- profissional. Feito em gatilho para não haver janela entre criar o auth.user
-- e existir a conta — e para não depender de o client fazer três inserts.
create or replace function public.ao_criar_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  nova_conta uuid;
  novo_usuario uuid;
  nome_informado text;
begin
  nome_informado := nullif(trim(coalesce(new.raw_user_meta_data ->> 'nome', '')), '');

  insert into public.contas (nome, tipo, plano)
  values (coalesce(nome_informado, split_part(new.email, '@', 1)), 'solo', 'gratis')
  returning id into nova_conta;

  insert into public.usuarios (conta_id, auth_user_id, papel, nome, email)
  values (nova_conta, new.id, 'dona', nome_informado, new.email)
  returning id into novo_usuario;

  insert into public.profissionais (conta_id, usuario_id, crp, assina_como)
  values (nova_conta, novo_usuario,
          nullif(trim(coalesce(new.raw_user_meta_data ->> 'crp', '')), ''),
          nome_informado);

  return new;
end;
$$;

drop trigger if exists ao_criar_auth_user on auth.users;
create trigger ao_criar_auth_user
  after insert on auth.users
  for each row execute function public.ao_criar_auth_user();

comment on function public.conta_atual() is
  'conta_id do usuário logado. security definer de propósito: evita recursão de RLS em usuarios.';
