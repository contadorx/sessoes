-- 0006 · A agenda materializada.
--
-- Decisão de desenho (doc 06): sessões são **instâncias materializadas** do
-- enquadre numa janela rolante, não uma regra calculada na hora. Materializar
-- simplifica fila, cobrança e relatório pelo resto do produto — a fila procura
-- linha, não resolve recorrência; a cobrança soma linha; o relatório conta
-- linha.
--
-- E a exceção (férias, feriado, bloqueio) **edita instâncias, nunca a regra**:
-- tirar duas semanas de férias não mexe no enquadre, e a recorrência volta
-- sozinha depois.
--
-- Tudo que é dia e hora se resolve em America/Sao_Paulo, aqui dentro.

create extension if not exists btree_gist;

-- ---------------------------------------------------------------- exceções

create table if not exists public.excecoes_agenda (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  tipo            text not null check (tipo in ('ferias', 'feriado', 'bloqueio')),
  inicio          date not null,
  fim             date not null,
  motivo          text check (motivo is null or length(motivo) <= 200),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  check (fim >= inicio)
);

create index if not exists excecoes_conta on public.excecoes_agenda (conta_id);
create index if not exists excecoes_periodo
  on public.excecoes_agenda (profissional_id, inicio, fim);

-- ---------------------------------------------------------------- sessões

create table if not exists public.sessoes (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete restrict,
  paciente_id     uuid not null references public.pacientes (id) on delete cascade,
  enquadre_id     uuid references public.enquadres (id) on delete set null,

  inicio          timestamptz not null,
  fim             timestamptz not null,

  origem          text not null default 'recorrencia'
                  check (origem in ('recorrencia', 'encaixe', 'avulsa')),
  estado          text not null default 'prevista' check (estado in (
                    'prevista', 'confirmada', 'realizada',
                    'falta', 'cancelada_cedo', 'cancelada_tarde')),

  -- Retrato do combinado no momento em que a sessão foi marcada. Um reajuste
  -- futuro não pode reescrever quanto custou a sessão de ontem, e a política
  -- que classifica o cancelamento é a que valia quando se combinou.
  valor               numeric(12,2) not null check (valor >= 0),
  politica_horas      smallint not null default 24,
  politica_percentual smallint not null default 50,

  cancelada_em    timestamptz,
  cancelada_por   text check (cancelada_por in ('paciente', 'profissional')),

  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),

  check (fim > inicio),
  check ((estado in ('cancelada_cedo','cancelada_tarde')) = (cancelada_em is not null))
);

create index if not exists sessoes_agenda on public.sessoes (profissional_id, inicio);
create index if not exists sessoes_conta on public.sessoes (conta_id, inicio);
create index if not exists sessoes_paciente on public.sessoes (paciente_id, inicio desc);
create index if not exists sessoes_enquadre on public.sessoes (enquadre_id);

-- Idempotência da materialização: rodar de novo não duplica.
create unique index if not exists sessao_recorrente_unica
  on public.sessoes (enquadre_id, inicio)
  where origem = 'recorrencia';

-- Agenda dupla impossível por construção. Cancelada libera o horário — é
-- exatamente esse buraco que a fila (D1) vai preencher.
alter table public.sessoes drop constraint if exists sessoes_sem_sobreposicao;
alter table public.sessoes add constraint sessoes_sem_sobreposicao
  exclude using gist (
    profissional_id with =,
    tstzrange(inicio, fim, '[)') with &&
  ) where (estado in ('prevista', 'confirmada', 'realizada', 'falta'));

drop trigger if exists sessoes_atualizado_em on public.sessoes;
create trigger sessoes_atualizado_em before update on public.sessoes
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists excecoes_atualizado_em on public.excecoes_agenda;
create trigger excecoes_atualizado_em before update on public.excecoes_agenda
  for each row execute function public.tocar_atualizado_em();

-- ---------------------------------------------------------------- o motor

-- Quantas semanas à frente a agenda existe. Mudar aqui muda em todo lugar.
create or replace function public.janela_semanas()
returns int language sql immutable set search_path = '' as $$ select 8 $$;

/**
 * Materializa um enquadre na janela rolante.
 *
 * Idempotente: pode rodar quantas vezes quiser. Só mexe em sessão `prevista`
 * de origem `recorrencia` — sessão realizada, falta ou cancelada é fato
 * consumado e não se toca.
 */
create or replace function public.materializar_enquadre(p_enquadre uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  de date;
  ate date;
  criadas int := 0;
begin
  select en.*, p.profissional_id, p.conta_id as conta
    into e
    from public.enquadres en
    join public.pacientes p on p.id = en.paciente_id
   where en.id = p_enquadre;

  if not found then return 0; end if;

  de  := greatest(public.hoje_sp(), e.vigencia_inicio);
  ate := least(public.hoje_sp() + (public.janela_semanas() * 7),
               coalesce(e.vigencia_fim, date '9999-12-31'));

  -- Limpa as previsões que não deveriam existir: fora da vigência, fora da
  -- janela, ou cobertas por uma exceção. Nunca apaga o que já aconteceu.
  delete from public.sessoes s
   where s.enquadre_id = p_enquadre
     and s.origem = 'recorrencia'
     and s.estado = 'prevista'
     and s.inicio >= (public.hoje_sp()::timestamp at time zone 'America/Sao_Paulo')
     and (
       (s.inicio at time zone 'America/Sao_Paulo')::date not between de and ate
       or exists (
         select 1 from public.excecoes_agenda x
          where x.profissional_id = e.profissional_id
            and (s.inicio at time zone 'America/Sao_Paulo')::date between x.inicio and x.fim
       )
     );

  if e.vigencia_fim is not null and e.vigencia_fim < public.hoje_sp() then
    return 0;
  end if;

  with ocorrencias as (
    select d::date as dia
      from generate_series(de, ate, interval '1 day') d
     where extract(dow from d) = e.dia_semana
  ),
  livres as (
    select o.dia
      from ocorrencias o
     where not exists (
       select 1 from public.excecoes_agenda x
        where x.profissional_id = e.profissional_id
          and o.dia between x.inicio and x.fim
     )
  )
  insert into public.sessoes (
    conta_id, profissional_id, paciente_id, enquadre_id,
    inicio, fim, origem, estado, valor, politica_horas, politica_percentual
  )
  select
    e.conta, e.profissional_id, e.paciente_id, e.id,
    ((l.dia + e.hora) at time zone 'America/Sao_Paulo'),
    ((l.dia + e.hora) at time zone 'America/Sao_Paulo') + make_interval(mins => e.duracao_min),
    'recorrencia', 'prevista', e.valor, e.politica_horas, e.politica_percentual
  from livres l
  -- Não materializa no passado: a agenda de trás é histórico, não projeção.
  where ((l.dia + e.hora) at time zone 'America/Sao_Paulo') >= now()
  on conflict (enquadre_id, inicio) where origem = 'recorrencia' do nothing;

  get diagnostics criadas = row_count;
  return criadas;
end;
$$;

/** Roda a janela rolante da conta inteira. É isto que o cron chama. */
create or replace function public.materializar_conta(p_conta uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  total int := 0;
begin
  for r in
    select en.id
      from public.enquadres en
     where en.conta_id = p_conta
       and en.vigencia_fim is null
  loop
    total := total + public.materializar_enquadre(r.id);
  end loop;
  return total;
end;
$$;

-- ---------------------------------------------------------------- gatilhos

create or replace function public.ao_mudar_enquadre()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.materializar_enquadre(new.id);
  return new;
end;
$$;

drop trigger if exists enquadres_materializa on public.enquadres;
create trigger enquadres_materializa
  after insert or update of dia_semana, hora, duracao_min, valor,
                            politica_horas, politica_percentual,
                            vigencia_inicio, vigencia_fim
  on public.enquadres
  for each row execute function public.ao_mudar_enquadre();

/**
 * Exceção **edita instâncias, nunca a regra**. Criar férias apaga as previsões
 * do período; remover as férias devolve a recorrência, porque a materialização
 * é idempotente e roda de novo.
 */
create or replace function public.ao_mudar_excecao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prof uuid := coalesce(new.profissional_id, old.profissional_id);
  r record;
begin
  for r in
    select en.id
      from public.enquadres en
      join public.pacientes p on p.id = en.paciente_id
     where p.profissional_id = prof
       and en.vigencia_fim is null
  loop
    perform public.materializar_enquadre(r.id);
  end loop;

  return coalesce(new, old);
end;
$$;

drop trigger if exists excecoes_materializa on public.excecoes_agenda;
create trigger excecoes_materializa
  after insert or update or delete on public.excecoes_agenda
  for each row execute function public.ao_mudar_excecao();

-- conta_id derivado, como nas outras tabelas.
create or replace function public.checa_conta_da_excecao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare c uuid;
begin
  select p.conta_id into c from public.profissionais p where p.id = new.profissional_id;
  if c is null or c <> public.conta_atual() then
    raise exception 'profissional de outra conta';
  end if;
  new.conta_id := c;
  return new;
end;
$$;

drop trigger if exists excecoes_conta on public.excecoes_agenda;
create trigger excecoes_conta
  before insert or update of profissional_id on public.excecoes_agenda
  for each row execute function public.checa_conta_da_excecao();

-- ---------------------------------------------------------------- RLS

alter table public.sessoes enable row level security;
alter table public.excecoes_agenda enable row level security;

drop policy if exists "sessoes da conta: ler" on public.sessoes;
create policy "sessoes da conta: ler"
  on public.sessoes for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "sessoes da conta: editar" on public.sessoes;
create policy "sessoes da conta: editar"
  on public.sessoes for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Criar sessão pelo client é só encaixe e avulsa; a recorrente nasce do motor.
drop policy if exists "sessoes da conta: criar" on public.sessoes;
create policy "sessoes da conta: criar"
  on public.sessoes for insert to authenticated
  with check (conta_id = public.conta_atual() and origem in ('encaixe', 'avulsa'));

drop policy if exists "excecoes da conta: ler" on public.excecoes_agenda;
create policy "excecoes da conta: ler"
  on public.excecoes_agenda for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "excecoes da conta: criar" on public.excecoes_agenda;
create policy "excecoes da conta: criar"
  on public.excecoes_agenda for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "excecoes da conta: editar" on public.excecoes_agenda;
create policy "excecoes da conta: editar"
  on public.excecoes_agenda for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Exceção é a única coisa que se apaga de verdade no produto: desmarcar as
-- férias tem que devolver a recorrência.
drop policy if exists "excecoes da conta: apagar" on public.excecoes_agenda;
create policy "excecoes da conta: apagar"
  on public.excecoes_agenda for delete to authenticated
  using (conta_id = public.conta_atual());

revoke execute on function public.materializar_enquadre(uuid) from public, anon;
revoke execute on function public.ao_mudar_enquadre() from public, anon, authenticated;
revoke execute on function public.ao_mudar_excecao() from public, anon, authenticated;
revoke execute on function public.checa_conta_da_excecao() from public, anon, authenticated;
grant execute on function public.materializar_conta(uuid) to authenticated;

comment on table public.sessoes is
  'Instancias materializadas do enquadre. Excecao edita instancia, nunca a regra.';
