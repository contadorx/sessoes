-- 0005 · Pacientes e enquadres.
--
-- O **enquadre** é a entidade-chave do produto (doc 06): é dele que nascem as
-- sessões, a cobrança e, na fase 2, o contrato. Um paciente tem histórico de
-- enquadres — reajustar (D14) cria um novo e fecha o anterior, **nunca** faz
-- update silencioso no valor. A tabela já nasce com esse formato, mesmo antes
-- da feature existir.
--
-- Minimização de dados por postura, não por preguiça (doc 03/07): o cadastro
-- guarda o mínimo para agendar, avisar e emitir recibo. Nada clínico aqui —
-- prontuário é a camada da fase 3, com RLS por profissional.

-- ---------------------------------------------------------------- pacientes

create table if not exists public.pacientes (
  id             uuid primary key default gen_random_uuid(),
  conta_id       uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete restrict,

  nome           text not null check (length(trim(nome)) between 1 and 120),
  telefone       text check (telefone is null or telefone ~ '^\+?[0-9]{10,15}$'),
  email          text check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  -- CPF só quando houver recibo a emitir (Receita Saúde, F2a). Guardado sem
  -- máscara; validação de dígito fica na aplicação.
  cpf            char(11) check (cpf is null or cpf ~ '^[0-9]{11}$'),
  nascimento     date,
  -- Para menores: quem responde. Lista de {nome, telefone, parentesco}.
  responsaveis   jsonb not null default '[]'::jsonb,

  estado         text not null default 'interessado' check (estado in (
                   'interessado', 'triagem', 'em_atendimento',
                   'pausa', 'alta', 'encerrado', 'arquivado')),
  origem         text,

  -- D3 nasce aqui, no cadastro — não vira caixinha escondida em configurações.
  msg_canal      text not null default 'whatsapp'
                 check (msg_canal in ('whatsapp', 'sms', 'email', 'nao_avisar')),
  msg_modo       text not null default 'discreto'
                 check (msg_modo in ('discreto', 'completo')),

  -- Anotação administrativa. NUNCA conteúdo clínico: isso é fase 3, outra
  -- camada, outra RLS.
  observacao     text check (observacao is null or length(observacao) <= 2000),

  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create index if not exists pacientes_conta on public.pacientes (conta_id);
create index if not exists pacientes_profissional on public.pacientes (profissional_id);
create index if not exists pacientes_estado on public.pacientes (conta_id, estado);

-- ---------------------------------------------------------------- enquadres

create table if not exists public.enquadres (
  id             uuid primary key default gen_random_uuid(),
  conta_id       uuid not null references public.contas (id) on delete cascade,
  paciente_id    uuid not null references public.pacientes (id) on delete cascade,

  -- 0 = domingo, para casar com o extract(dow) do Postgres.
  dia_semana     smallint not null check (dia_semana between 0 and 6),
  hora           time not null,
  duracao_min    smallint not null default 50 check (duracao_min between 15 and 240),

  valor          numeric(12,2) not null check (valor >= 0),
  social         boolean not null default false,
  modelo_cobranca text not null default 'avulso'
                 check (modelo_cobranca in ('avulso', 'mensal', 'pacote')),

  -- A política que a D2 aplica sozinha. Fica no enquadre porque é o combinado
  -- daquele paciente, não uma configuração global da conta.
  politica_horas      smallint not null default 24 check (politica_horas between 0 and 168),
  politica_percentual smallint not null default 50 check (politica_percentual between 0 and 100),

  -- Vigência em vez de um booleano `ativo`: reajuste (D14) fecha o enquadre
  -- corrente e abre outro, preservando o histórico do que foi combinado quando.
  vigencia_inicio date not null default public.hoje_sp(),
  vigencia_fim    date,
  motivo_fim      text check (motivo_fim in ('reajuste', 'mudanca_horario', 'encerramento')),

  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),

  check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);

create index if not exists enquadres_conta on public.enquadres (conta_id);
create index if not exists enquadres_paciente on public.enquadres (paciente_id);

-- No máximo um enquadre aberto por paciente. É esta constraint que garante que
-- "o horário da Maria" é uma coisa só, e que reajuste fecha antes de abrir.
create unique index if not exists enquadre_aberto_unico
  on public.enquadres (paciente_id)
  where vigencia_fim is null;

-- Consulta quente da agenda: os enquadres abertos de um dia da semana.
create index if not exists enquadres_abertos_por_dia
  on public.enquadres (conta_id, dia_semana, hora)
  where vigencia_fim is null;

-- ---------------------------------------------------------------- coerência

-- `conta_id` é derivado, não digitado: o cliente não escolhe em que conta a
-- linha cai. E o profissional/paciente referenciado tem que ser da mesma conta
-- — senão a RLS de leitura protege, mas o dado nasce torto.
create or replace function public.checa_conta_do_paciente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.conta_id := public.conta_atual();

  if new.conta_id is null then
    raise exception 'sem conta na sessão';
  end if;

  if not exists (
    select 1 from public.profissionais p
     where p.id = new.profissional_id and p.conta_id = new.conta_id
  ) then
    raise exception 'profissional de outra conta';
  end if;

  return new;
end;
$$;

drop trigger if exists pacientes_conta on public.pacientes;
create trigger pacientes_conta
  before insert or update of profissional_id on public.pacientes
  for each row execute function public.checa_conta_do_paciente();

create or replace function public.checa_conta_do_enquadre()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  conta_do_paciente uuid;
begin
  select p.conta_id into conta_do_paciente
    from public.pacientes p where p.id = new.paciente_id;

  if conta_do_paciente is null then
    raise exception 'paciente inexistente';
  end if;

  if conta_do_paciente <> public.conta_atual() then
    raise exception 'paciente de outra conta';
  end if;

  new.conta_id := conta_do_paciente;
  return new;
end;
$$;

drop trigger if exists enquadres_conta on public.enquadres;
create trigger enquadres_conta
  before insert or update of paciente_id on public.enquadres
  for each row execute function public.checa_conta_do_enquadre();

drop trigger if exists pacientes_atualizado_em on public.pacientes;
create trigger pacientes_atualizado_em before update on public.pacientes
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists enquadres_atualizado_em on public.enquadres;
create trigger enquadres_atualizado_em before update on public.enquadres
  for each row execute function public.tocar_atualizado_em();

-- ---------------------------------------------------------------- RLS

alter table public.pacientes enable row level security;
alter table public.enquadres enable row level security;

drop policy if exists "pacientes da conta: ler" on public.pacientes;
create policy "pacientes da conta: ler"
  on public.pacientes for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "pacientes da conta: criar" on public.pacientes;
create policy "pacientes da conta: criar"
  on public.pacientes for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "pacientes da conta: editar" on public.pacientes;
create policy "pacientes da conta: editar"
  on public.pacientes for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

drop policy if exists "enquadres da conta: ler" on public.enquadres;
create policy "enquadres da conta: ler"
  on public.enquadres for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "enquadres da conta: criar" on public.enquadres;
create policy "enquadres da conta: criar"
  on public.enquadres for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "enquadres da conta: editar" on public.enquadres;
create policy "enquadres da conta: editar"
  on public.enquadres for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Sem DELETE, como no resto: paciente vira `arquivado`, enquadre ganha
-- vigencia_fim. Nada some.

revoke execute on function public.checa_conta_do_paciente() from public, anon, authenticated;
revoke execute on function public.checa_conta_do_enquadre() from public, anon, authenticated;

comment on table public.enquadres is
  'O combinado vivo: dia, hora, valor e politica. Reajuste fecha e abre outro, nunca faz update no valor.';
