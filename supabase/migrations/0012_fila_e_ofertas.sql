-- 0012 · O motor da fila. O coração do produto.
--
-- A cascata é uma máquina de estados por oferta:
--
--   vaga_aberta → oferta_enviada(expira_em) → aceita | recusada | expirada
--                                                  ↓
--                                    próxima da fila | vaga_sem_takers
--
-- Quatro invariantes, todas no banco e não na aplicação:
--
--  1. **Uma oferta viva por vaga.** É fila, não leilão nem broadcast. Índice
--     único parcial garante — não é disciplina de código.
--  2. **O aceite é transacional.** Trava a oferta e a vaga, confere que o
--     horário continua livre, e só então cria a sessão. Dois aceites
--     simultâneos: um vence, o outro recebe "já respondida".
--  3. **A elegibilidade é explicável.** A função não devolve uma lista: devolve
--     todo mundo, com `elegivel` e o **motivo**. É o que a psicóloga vê na tela,
--     e é o que faz ela confiar na fila.
--  4. **Todo evento fica gravado.** A métrica norte (% de cancelamentos com
--     vaga preenchida ou oferecida) sai de uma query sobre estas tabelas, sem
--     instrumentação extra depois.
--
-- Sobre a agenda do Google (paridade da fase 2, e 4 dos 8 concorrentes já
-- têm): o motor nunca pergunta "existe sessão nesta hora?" direto na tabela.
-- Pergunta a `vaga_esta_livre()`. Hoje ela olha `sessoes` e `excecoes_agenda`;
-- quando o sync entrar, ganha mais uma fonte e a fila não muda uma linha. É a
-- costura que evita o pior erro possível do produto: oferecer uma hora que, no
-- calendário dela, não está livre.

-- ---------------------------------------------------------------- ajustes da conta

alter table public.contas
  add column if not exists regra_prioridade text not null default 'mais_tempo_sem_sessao'
    check (regra_prioridade in ('mais_tempo_sem_sessao', 'ordem_de_entrada')),
  add column if not exists oferta_timeout_min smallint not null default 40
    check (oferta_timeout_min between 5 and 720),
  add column if not exists silencio_inicio time not null default '21:00',
  add column if not exists silencio_fim time not null default '08:00';

comment on column public.contas.regra_prioridade is
  'A regra e dela. A fila nunca vira leilao: dinheiro nao compra posicao.';

-- ---------------------------------------------------------------- a fila

create table if not exists public.fila_encaixe (
  id             uuid primary key default gen_random_uuid(),
  conta_id       uuid not null references public.contas (id) on delete cascade,
  paciente_id    uuid not null references public.pacientes (id) on delete cascade,

  -- Quem não topa antecipar só aceita vaga em semana onde não tem sessão.
  topa_antecipar boolean not null default true,

  -- [] = qualquer horário. Senão: [{"dias":[2,4],"de":"14:00","ate":"20:00"}]
  janelas        jsonb not null default '[]'::jsonb,

  -- Desempate manual, quando a dona quer mexer na ordem.
  prioridade     int not null default 0,
  ativo          boolean not null default true,
  entrou_em      timestamptz not null default now(),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),

  unique (paciente_id)
);

create index if not exists fila_conta on public.fila_encaixe (conta_id) where ativo;

-- ---------------------------------------------------------------- as ofertas

create table if not exists public.ofertas (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  sessao_id     uuid not null references public.sessoes (id) on delete cascade,
  paciente_id   uuid not null references public.pacientes (id) on delete cascade,

  -- 'vaga_fixa' entra na D13; a coluna já nasce para não migrar depois.
  fila          text not null default 'encaixe' check (fila in ('encaixe', 'vaga_fixa')),
  ordem         int not null default 1,

  criada_em     timestamptz not null default now(),
  enviar_em     timestamptz not null default now(),
  expira_em     timestamptz not null,
  respondida_em timestamptz,

  estado        text not null default 'enviada'
                check (estado in ('enviada', 'aceita', 'recusada', 'expirada', 'cancelada')),

  check (expira_em > enviar_em),
  check ((estado = 'enviada') = (respondida_em is null))
);

create index if not exists ofertas_sessao on public.ofertas (sessao_id, ordem);
create index if not exists ofertas_conta on public.ofertas (conta_id);
create index if not exists ofertas_paciente on public.ofertas (paciente_id);

-- Para o cron de expiração.
create index if not exists ofertas_vivas on public.ofertas (expira_em)
  where estado = 'enviada';

-- INVARIANTE 1: uma oferta viva por vaga.
create unique index if not exists oferta_viva_unica
  on public.ofertas (sessao_id)
  where estado = 'enviada';

-- Ninguém recebe a mesma vaga duas vezes.
create unique index if not exists oferta_por_paciente_e_vaga
  on public.ofertas (sessao_id, paciente_id);

-- ---------------------------------------------------------------- os eventos

create table if not exists public.eventos_fila (
  id          bigint generated always as identity primary key,
  conta_id    uuid not null references public.contas (id) on delete cascade,
  sessao_id   uuid references public.sessoes (id) on delete cascade,
  oferta_id   uuid references public.ofertas (id) on delete set null,
  tipo        text not null check (tipo in (
                'vaga_aberta', 'oferta_enviada', 'oferta_aceita',
                'oferta_recusada', 'oferta_expirada',
                'vaga_preenchida', 'vaga_sem_takers')),
  detalhe     jsonb not null default '{}'::jsonb,
  em          timestamptz not null default now()
);

create index if not exists eventos_conta on public.eventos_fila (conta_id, em desc);
create index if not exists eventos_sessao on public.eventos_fila (sessao_id, em);

drop trigger if exists fila_atualizado_em on public.fila_encaixe;
create trigger fila_atualizado_em before update on public.fila_encaixe
  for each row execute function public.tocar_atualizado_em();

-- conta_id derivado pelo paciente, como no resto.
create or replace function public.checa_conta_da_fila()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  select p.conta_id into c from public.pacientes p where p.id = new.paciente_id;
  if c is null or c <> public.conta_atual() then
    raise exception 'paciente de outra conta';
  end if;
  new.conta_id := c;
  return new;
end;
$$;

drop trigger if exists fila_conta_derivada on public.fila_encaixe;
create trigger fila_conta_derivada
  before insert or update of paciente_id on public.fila_encaixe
  for each row execute function public.checa_conta_da_fila();

-- ---------------------------------------------------------------- a costura do Google

/**
 * O horário está livre para este profissional?
 *
 * Hoje: nenhuma sessão viva ocupando, e nenhuma exceção (férias, feriado,
 * bloqueio) cobrindo o dia. Quando o sync com a Google Agenda entrar (fase 2),
 * ele acrescenta uma fonte **aqui**, e o motor da fila não muda.
 *
 * `p_ignorar` existe para o aceite: a própria vaga cancelada não conta como
 * ocupação.
 */
create or replace function public.vaga_esta_livre(
  p_profissional uuid,
  p_inicio timestamptz,
  p_fim timestamptz,
  p_ignorar uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.sessoes s
     where s.profissional_id = p_profissional
       and s.id is distinct from p_ignorar
       and s.estado in ('prevista', 'confirmada', 'realizada', 'falta')
       and tstzrange(s.inicio, s.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
  )
  and not exists (
    select 1 from public.excecoes_agenda x
     where x.profissional_id = p_profissional
       and (p_inicio at time zone 'America/Sao_Paulo')::date between x.inicio and x.fim
  );
$$;

-- ---------------------------------------------------------------- janelas e silêncio

/** O horário cabe em alguma das janelas do paciente? Lista vazia = qualquer hora. */
create or replace function public.cabe_na_janela(p_janelas jsonb, p_inicio timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when p_janelas is null or jsonb_array_length(p_janelas) = 0 then true
    else exists (
      select 1
        from jsonb_array_elements(p_janelas) j
       where (
              j->'dias' is null
              or jsonb_array_length(j->'dias') = 0
              or extract(dow from (p_inicio at time zone 'America/Sao_Paulo'))::int in (
                   select v::int from jsonb_array_elements_text(j->'dias') v
                 )
             )
         and (j->>'de'  is null or (p_inicio at time zone 'America/Sao_Paulo')::time >= (j->>'de')::time)
         and (j->>'ate' is null or (p_inicio at time zone 'America/Sao_Paulo')::time <= (j->>'ate')::time)
    )
  end;
$$;

/**
 * Quando esta oferta pode sair. Ninguém recebe proposta de terapia às 23h —
 * e a regra mora aqui, não na lembrança de quem chama.
 */
create or replace function public.proximo_envio(p_conta uuid, p_agora timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c record;
  agora_local timestamp;
  hora_local time;
  dentro_do_silencio boolean;
begin
  select silencio_inicio, silencio_fim into c from public.contas where id = p_conta;
  if not found then return p_agora; end if;

  agora_local := p_agora at time zone 'America/Sao_Paulo';
  hora_local := agora_local::time;

  dentro_do_silencio := case
    when c.silencio_inicio < c.silencio_fim
      then hora_local >= c.silencio_inicio and hora_local < c.silencio_fim
    else hora_local >= c.silencio_inicio or hora_local < c.silencio_fim
  end;

  if not dentro_do_silencio then
    return p_agora;
  end if;

  -- Próxima ocorrência do fim do silêncio.
  return case
    when hora_local < c.silencio_fim
      then (agora_local::date + c.silencio_fim) at time zone 'America/Sao_Paulo'
    else ((agora_local::date + 1) + c.silencio_fim) at time zone 'America/Sao_Paulo'
  end;
end;
$$;

-- ---------------------------------------------------------------- elegibilidade

/**
 * INVARIANTE 3: devolve **todo mundo da fila**, com `elegivel` e o motivo.
 *
 * A tela da B8 renderiza isto direto — inclusive os "✕ fora da janela" e
 * "✕ em pausa". É o que faz a psicóloga confiar que a fila não inventou.
 */
create or replace function public.elegiveis_para_vaga(p_sessao uuid)
returns table (
  paciente_id uuid,
  nome text,
  elegivel boolean,
  motivo text,
  ordem bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with vaga as (
    select s.id, s.conta_id, s.profissional_id, s.inicio, s.fim,
           c.regra_prioridade
      from public.sessoes s
      join public.contas c on c.id = s.conta_id
     where s.id = p_sessao
  ),
  candidatos as (
    select
      f.paciente_id,
      p.nome,
      f.prioridade,
      f.entrou_em,
      f.janelas,
      f.topa_antecipar,
      p.estado as estado_paciente,
      p.msg_canal,
      v.*,
      (select max(s2.inicio)
         from public.sessoes s2
        where s2.paciente_id = f.paciente_id
          and s2.estado = 'realizada'
          and s2.inicio < now()) as ultima_sessao,
      exists (
        select 1 from public.sessoes s3
         where s3.paciente_id = f.paciente_id
           and s3.estado in ('prevista', 'confirmada')
           and s3.inicio >= v.inicio - interval '3 days'
           and s3.inicio <= v.inicio + interval '3 days'
      ) as tem_sessao_por_perto,
      exists (
        select 1 from public.sessoes s4
         where s4.paciente_id = f.paciente_id
           and s4.estado in ('prevista', 'confirmada', 'realizada')
           and tstzrange(s4.inicio, s4.fim, '[)') && tstzrange(v.inicio, v.fim, '[)')
      ) as ocupado_na_hora,
      (select o.estado from public.ofertas o
        where o.sessao_id = p_sessao and o.paciente_id = f.paciente_id) as ja_ofertado
    from public.fila_encaixe f
    join public.pacientes p on p.id = f.paciente_id
    cross join vaga v
   where f.ativo
     and f.conta_id = v.conta_id
  )
  select
    c.paciente_id,
    c.nome,
    (c.motivo_calculado is null) as elegivel,
    coalesce(c.motivo_calculado, 'na fila') as motivo,
    row_number() over (
      order by
        (c.motivo_calculado is null) desc,
        c.prioridade desc,
        case when c.regra_prioridade = 'mais_tempo_sem_sessao'
             then coalesce(c.ultima_sessao, '-infinity'::timestamptz) end asc,
        c.entrou_em asc
    ) as ordem
  from (
    select cc.*,
      case
        when cc.estado_paciente = 'pausa'                        then 'em pausa'
        when cc.estado_paciente in ('alta','encerrado','arquivado') then 'não está em atendimento'
        when cc.msg_canal = 'nao_avisar'                          then 'pediu para não ser avisado'
        when cc.ja_ofertado = 'recusada'                          then 'já recusou esta vaga'
        when cc.ja_ofertado is not null                           then 'já recebeu esta oferta'
        when cc.ocupado_na_hora                                   then 'já tem sessão nesse horário'
        when not public.cabe_na_janela(cc.janelas, cc.inicio)     then 'fora da janela'
        when not cc.topa_antecipar and cc.tem_sessao_por_perto    then 'não quer antecipar'
        else null
      end as motivo_calculado
    from candidatos cc
  ) c
  order by ordem;
$$;

grant execute on function public.elegiveis_para_vaga(uuid) to authenticated;

-- ---------------------------------------------------------------- a cascata

/** Cria a oferta para o próximo elegível, ou registra que a fila acabou. */
create or replace function public.avancar_fila(p_sessao uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v record;
  proximo record;
  nova uuid;
  quando timestamptz;
  n int;
begin
  select s.id, s.conta_id, c.oferta_timeout_min
    into v
    from public.sessoes s
    join public.contas c on c.id = s.conta_id
   where s.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  -- INVARIANTE 1, conferida antes de tentar: já existe oferta viva?
  if exists (select 1 from public.ofertas o
              where o.sessao_id = p_sessao and o.estado = 'enviada') then
    return null;
  end if;

  select * into proximo
    from public.elegiveis_para_vaga(p_sessao)
   where elegivel
   order by ordem
   limit 1;

  if not found then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'vaga_sem_takers', '{}'::jsonb);
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  select count(*) + 1 into n from public.ofertas where sessao_id = p_sessao;

  insert into public.ofertas (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_sessao, proximo.paciente_id, n,
          quando, quando + make_interval(mins => v.oferta_timeout_min))
  returning id into nova;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (v.conta_id, p_sessao, nova, 'oferta_enviada',
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'enviar_em', quando));

  return nova;
end;
$$;

/**
 * Abre a vaga e dispara a cascata. Só sessão cancelada e futura é vaga —
 * é exatamente o buraco que a D1 existe para tapar.
 */
create or replace function public.abrir_vaga(p_sessao uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare s record;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then raise exception 'sessão não encontrada'; end if;

  if s.estado not in ('cancelada_cedo', 'cancelada_tarde') then
    raise exception 'só horário cancelado vira vaga';
  end if;

  if s.inicio <= now() then
    raise exception 'esta hora já passou';
  end if;

  if not exists (select 1 from public.eventos_fila e
                  where e.sessao_id = p_sessao and e.tipo = 'vaga_aberta') then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (s.conta_id, p_sessao, 'vaga_aberta',
            jsonb_build_object('inicio', s.inicio, 'valor', s.valor));
  end if;

  return public.avancar_fila(p_sessao);
end;
$$;

/**
 * INVARIANTE 2: o aceite é transacional.
 *
 * Trava a oferta, confere que ela ainda está viva, trava a vaga, confere que o
 * horário continua livre, e só então cria a sessão. Dois aceites simultâneos:
 * o segundo encontra a oferta já respondida e recebe erro — nunca duas pessoas
 * na mesma hora.
 */
create or replace function public.responder_oferta(p_oferta uuid, p_resposta text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  o record;
  s record;
  valor_do_paciente numeric(12,2);
  duracao int;
  n int;
begin
  if p_resposta not in ('aceita', 'recusada') then
    raise exception 'resposta precisa ser aceita ou recusada';
  end if;

  select * into o from public.ofertas where id = p_oferta for update;
  if not found then raise exception 'oferta não encontrada'; end if;

  if o.estado <> 'enviada' then
    raise exception 'oferta já respondida (%)' , o.estado;
  end if;

  if p_resposta = 'recusada' then
    update public.ofertas
       set estado = 'recusada', respondida_em = now()
     where id = p_oferta;

    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo)
    values (o.conta_id, o.sessao_id, p_oferta, 'oferta_recusada');

    perform public.avancar_fila(o.sessao_id);
    return 'recusada';
  end if;

  -- Aceite. A vaga é travada antes de qualquer decisão.
  select * into s from public.sessoes where id = o.sessao_id for update;

  if s.estado not in ('cancelada_cedo', 'cancelada_tarde') then
    raise exception 'esta vaga não está mais aberta';
  end if;

  if not public.vaga_esta_livre(s.profissional_id, s.inicio, s.fim, s.id) then
    raise exception 'o horário deixou de estar livre';
  end if;

  -- Quem entra paga o próprio combinado, não o de quem desmarcou.
  select en.valor, en.duracao_min into valor_do_paciente, duracao
    from public.enquadres en
   where en.paciente_id = o.paciente_id and en.vigencia_fim is null;

  insert into public.sessoes (
    conta_id, profissional_id, paciente_id, inicio, fim,
    origem, estado, valor, politica_horas, politica_percentual
  )
  values (
    s.conta_id, s.profissional_id, o.paciente_id, s.inicio, s.fim,
    'encaixe', 'prevista',
    coalesce(valor_do_paciente, s.valor),
    s.politica_horas, s.politica_percentual
  );

  update public.ofertas
     set estado = 'aceita', respondida_em = now()
   where id = p_oferta;

  update public.ofertas
     set estado = 'cancelada', respondida_em = now()
   where sessao_id = o.sessao_id and estado = 'enviada' and id <> p_oferta;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (o.conta_id, o.sessao_id, p_oferta, 'oferta_aceita', '{}'::jsonb);

  insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
  values (o.conta_id, o.sessao_id, 'vaga_preenchida',
          jsonb_build_object('paciente_id', o.paciente_id,
                             'valor', coalesce(valor_do_paciente, s.valor)));

  return 'aceita';
end;
$$;

/** O cron da expiração: vence o prazo, a fila anda sozinha. */
create or replace function public.expirar_ofertas()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  o record;
  n int := 0;
begin
  for o in
    select * from public.ofertas
     where estado = 'enviada' and expira_em <= now()
     for update skip locked
  loop
    update public.ofertas
       set estado = 'expirada', respondida_em = now()
     where id = o.id;

    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo)
    values (o.conta_id, o.sessao_id, o.id, 'oferta_expirada');

    perform public.avancar_fila(o.sessao_id);
    n := n + 1;
  end loop;

  return n;
end;
$$;

-- ---------------------------------------------------------------- a métrica norte

/**
 * INVARIANTE 4: a métrica sai daqui, sem instrumentação extra.
 *
 * % de cancelamentos com vaga preenchida **ou ao menos oferecida**. Alvo ≥ 60%.
 * É o número que decide se o produto se justifica.
 */
create or replace function public.taxa_de_preenchimento(p_de date, p_ate date)
returns table (
  canceladas bigint,
  oferecidas bigint,
  preenchidas bigint,
  taxa numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with vagas as (
    select s.id,
           exists (select 1 from public.ofertas o where o.sessao_id = s.id) as teve_oferta,
           exists (select 1 from public.ofertas o
                    where o.sessao_id = s.id and o.estado = 'aceita') as foi_preenchida
      from public.sessoes s
     where s.estado in ('cancelada_cedo', 'cancelada_tarde')
       and (s.cancelada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
  )
  select
    count(*) as canceladas,
    count(*) filter (where teve_oferta) as oferecidas,
    count(*) filter (where foi_preenchida) as preenchidas,
    case when count(*) = 0 then null
         else round(100.0 * count(*) filter (where teve_oferta) / count(*), 1)
    end as taxa
  from vagas;
$$;

grant execute on function public.taxa_de_preenchimento(date, date) to authenticated;
grant execute on function public.abrir_vaga(uuid) to authenticated;
grant execute on function public.responder_oferta(uuid, text) to authenticated;
grant execute on function public.expirar_ofertas() to authenticated;
grant execute on function public.avancar_fila(uuid) to authenticated;

revoke execute on function public.checa_conta_da_fila() from public, anon, authenticated;
revoke execute on function public.vaga_esta_livre(uuid, timestamptz, timestamptz, uuid) from public, anon;
revoke execute on function public.proximo_envio(uuid, timestamptz) from public, anon;

-- ---------------------------------------------------------------- RLS

alter table public.fila_encaixe enable row level security;
alter table public.ofertas enable row level security;
alter table public.eventos_fila enable row level security;

drop policy if exists "fila da conta: ler" on public.fila_encaixe;
create policy "fila da conta: ler" on public.fila_encaixe for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "fila da conta: criar" on public.fila_encaixe;
create policy "fila da conta: criar" on public.fila_encaixe for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "fila da conta: editar" on public.fila_encaixe;
create policy "fila da conta: editar" on public.fila_encaixe for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

drop policy if exists "fila da conta: sair" on public.fila_encaixe;
create policy "fila da conta: sair" on public.fila_encaixe for delete to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "ofertas da conta: ler" on public.ofertas;
create policy "ofertas da conta: ler" on public.ofertas for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "ofertas da conta: criar" on public.ofertas;
create policy "ofertas da conta: criar" on public.ofertas for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "ofertas da conta: editar" on public.ofertas;
create policy "ofertas da conta: editar" on public.ofertas for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Eventos são append-only: lê e insere, nunca edita nem apaga. É a trilha de
-- onde sai a métrica — e trilha que se edita não é trilha.
drop policy if exists "eventos da conta: ler" on public.eventos_fila;
create policy "eventos da conta: ler" on public.eventos_fila for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "eventos da conta: registrar" on public.eventos_fila;
create policy "eventos da conta: registrar" on public.eventos_fila for insert to authenticated
  with check (conta_id = public.conta_atual());

comment on table public.ofertas is
  'Cascata: uma oferta viva por vaga (indice parcial). Aceite transacional com lock na vaga.';
comment on table public.eventos_fila is
  'Append-only. A metrica norte sai daqui.';
