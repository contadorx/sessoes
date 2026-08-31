-- 0022 · B11 — a política que se aplica sozinha (D2).
--
-- Esta é a metade menos vistosa e mais importante da tese. A fila recupera o
-- dinheiro do horário; isto recupera o dinheiro que já era dela e ela não
-- cobrava — porque cobrar exige uma conversa constrangedora, e a conversa
-- constrangedora não acontece.
--
-- Quatro decisões, e nenhuma é técnica:
--
-- **1. Quem cobra é o combinado, não ela.** A cobrança nasce da política
-- congelada *naquela sessão* (o retrato da B5), não da política de hoje. Mudar
-- o valor amanhã não reescreve o que foi combinado ontem.
--
-- **2. Não vir é desmarcar com zero hora de antecedência.** A falta usa o mesmo
-- percentual da política, e não um valor cheio inventado aqui. Se as conversas
-- da fase 0 pedirem uma regra própria para falta, ela vira campo do enquadre —
-- não um número escondido numa função.
--
-- **3. Existe uma hora de silêncio antes do aviso.** A mensagem não sai no
-- mesmo minuto do cancelamento. Alguém que desmarca em cima da hora costuma
-- estar num dia ruim, e receber a conta no mesmo segundo é a versão automática
-- da falta de tato que o produto existe para evitar. A hora também é o espaço
-- em que ela perdoa antes de qualquer coisa sair.
--
-- **4. Perdoar é um toque, e não manda mensagem nenhuma.** A régua automática
-- tem de ter freio, e o freio tem de ser mais fácil de usar do que o acelerador.
-- Quem perdoa fala com a pessoa; robô avisando "foi perdoado" transformaria um
-- gesto em notificação.

alter table public.contas
  add column if not exists cobranca_atraso_min smallint not null default 60
    check (cobranca_atraso_min between 0 and 1440);

comment on column public.contas.cobranca_atraso_min is
  'Minutos entre o cancelamento tardio e o aviso de cobranca. E a janela do perdao.';

-- ---------------------------------------------------------------- a tabela

create table if not exists public.cobrancas (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id) on delete cascade,
  paciente_id uuid not null references public.pacientes (id) on delete cascade,
  sessao_id   uuid references public.sessoes (id) on delete cascade,

  tipo        text not null check (tipo in ('falta', 'sessao', 'mensalidade', 'pacote')),
  motivo      text not null check (motivo in ('cancelada_tarde', 'falta', 'avulsa')),
  valor       numeric(12,2) not null check (valor > 0),

  -- O retrato da política que gerou esta cobrança. Fica aqui para que a
  -- pergunta "por que R$ 100?" tenha resposta daqui a dois anos.
  politica_horas      smallint,
  politica_percentual smallint,
  valor_da_sessao     numeric(12,2),

  estado      text not null default 'aberta'
              check (estado in ('aberta', 'paga', 'perdoada', 'cancelada')),
  perdoada_em timestamptz,
  paga_em     timestamptz,

  competencia date not null,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Uma cobrança viva por sessão. Desfazer o cancelamento cancela a cobrança
-- (não apaga), e aí uma nova pode nascer — a trilha guarda as duas.
create unique index if not exists cobranca_viva_por_sessao
  on public.cobrancas (sessao_id)
  where sessao_id is not null and estado <> 'cancelada';

create index if not exists cobrancas_da_conta
  on public.cobrancas (conta_id, competencia desc, criado_em desc);
create index if not exists cobrancas_do_paciente
  on public.cobrancas (paciente_id, criado_em desc);
create index if not exists cobrancas_abertas
  on public.cobrancas (conta_id) where estado = 'aberta';

drop trigger if exists cobrancas_atualizado_em on public.cobrancas;
create trigger cobrancas_atualizado_em before update on public.cobrancas
  for each row execute function public.tocar_atualizado_em();

-- ------------------------------------------------------------- a aritmética

/**
 * O valor da multa, com a mesma regra do `lib/dinheiro` do app: arredonda
 * meio-centavo **para longe do zero**, nunca para o par mais próximo. Duas
 * implementações da mesma conta têm de dar o mesmo número, ou a tela mostra uma
 * coisa e a cobrança guarda outra.
 */
create or replace function public.multa_da_politica(
  p_valor numeric,
  p_percentual smallint
)
returns numeric
language sql
immutable
security invoker
set search_path = ''
as $$
  select round(coalesce(p_valor, 0) * coalesce(p_percentual, 0) / 100.0, 2);
$$;

-- --------------------------------------------------------------- o gatilho

/**
 * A sessão mudou de estado. Se virou cobrável, a cobrança nasce; se deixou de
 * ser, a cobrança morre.
 *
 * Roda **depois** da transição, e não dentro de `cancelar_sessao()`, pelo mesmo
 * motivo da 0010: o que não pode ser burlado não pode depender de qual função
 * alguém escolheu chamar.
 */
create or replace function public.ao_mudar_estado_da_sessao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cobravel_antes boolean;
  cobravel_agora boolean;
  quanto numeric;
  atraso int;
  nova uuid;
begin
  cobravel_antes := old.estado in ('cancelada_tarde', 'falta');
  cobravel_agora := new.estado in ('cancelada_tarde', 'falta');

  if cobravel_antes = cobravel_agora then
    return new;
  end if;

  -- --------------------------------------------------- deixou de ser cobrável
  if cobravel_antes and not cobravel_agora then
    update public.cobrancas
       set estado = 'cancelada'
     where sessao_id = new.id and estado in ('aberta', 'perdoada');

    -- E o aviso que ainda não saiu não sai. Desfazer e mesmo assim mandar a
    -- conta seria o pior desfecho possível deste build.
    update public.mensagens
       set estado = 'cancelada'
     where chave_idem like 'cobranca:%'
       and estado = 'pendente'
       and (params->>'sessao_id') = new.id::text;

    return new;
  end if;

  -- ------------------------------------------------------ virou cobrável
  quanto := public.multa_da_politica(new.valor, new.politica_percentual);

  -- Política de 0% é uma escolha legítima e comum. Não gerar cobrança de zero
  -- é diferente de gerar uma cobrança zerada: a segunda vira linha na tela, na
  -- soma e na mensagem.
  if quanto <= 0 then
    return new;
  end if;

  select cobranca_atraso_min into atraso from public.contas where id = new.conta_id;

  insert into public.cobrancas (
    conta_id, paciente_id, sessao_id, tipo, motivo, valor,
    politica_horas, politica_percentual, valor_da_sessao, competencia
  )
  values (
    new.conta_id, new.paciente_id, new.id, 'falta', new.estado, quanto,
    new.politica_horas, new.politica_percentual, new.valor,
    date_trunc('month', (new.inicio at time zone 'America/Sao_Paulo')::date)::date
  )
  on conflict do nothing
  returning id into nova;

  if nova is null then
    return new;
  end if;

  perform public.enfileirar_mensagem(
    new.paciente_id,
    'aviso_de_cobranca',
    'cobranca:' || nova::text,
    jsonb_build_object(
      'cobranca_id', nova,
      'sessao_id', new.id,
      'inicio', new.inicio,
      'valor_centavos', round(quanto * 100)::bigint
    ),
    now() + make_interval(mins => coalesce(atraso, 60))
  );

  return new;
end;
$$;

drop trigger if exists sessoes_geram_cobranca on public.sessoes;
create trigger sessoes_geram_cobranca after update of estado on public.sessoes
  for each row when (old.estado is distinct from new.estado)
  execute function public.ao_mudar_estado_da_sessao();

-- ----------------------------------------------------------------- o freio

/**
 * Perdoar.
 *
 * Não apaga: marca. A cobrança perdoada continua contando na trilha, porque
 * "quantas vezes ela abriu mão" é uma das coisas mais úteis que este sistema
 * pode devolver para alguém que acha que não sabe cobrar.
 *
 * E cancela o aviso que ainda não saiu — perdoar depois que a mensagem foi é
 * consertar; perdoar antes é evitar.
 */
create or replace function public.perdoar_cobranca(p_cobranca uuid, p_motivo text default null)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare c record;
begin
  select * into c from public.cobrancas where id = p_cobranca;
  if not found then raise exception 'cobrança não encontrada'; end if;
  if c.estado <> 'aberta' then
    raise exception 'só dá para perdoar cobrança aberta (esta está %)', c.estado;
  end if;

  update public.cobrancas
     set estado = 'perdoada', perdoada_em = now()
   where id = p_cobranca;

  update public.mensagens
     set estado = 'cancelada'
   where chave_idem = 'cobranca:' || p_cobranca::text
     and estado = 'pendente';

  return 'perdoada';
end;
$$;

/** Recebeu. O meio de pagamento é da fase 2; aqui é o registro dela. */
create or replace function public.marcar_cobranca_paga(p_cobranca uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.cobrancas
     set estado = 'paga', paga_em = now()
   where id = p_cobranca and estado = 'aberta';

  if not found then raise exception 'cobrança não está aberta'; end if;
  return 'paga';
end;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.cobrancas enable row level security;

drop policy if exists "cobranças da conta: ler" on public.cobrancas;
create policy "cobranças da conta: ler" on public.cobrancas for select to authenticated
  using (conta_id = public.conta_atual());

-- Criar à mão é para a cobrança avulsa (fase 2). A automática vem do gatilho.
drop policy if exists "cobranças da conta: criar" on public.cobrancas;
create policy "cobranças da conta: criar" on public.cobrancas for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "cobranças da conta: editar" on public.cobrancas;
create policy "cobranças da conta: editar" on public.cobrancas for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Sem política de delete: cobrança perdoada é informação, não sujeira.

revoke execute on function public.ao_mudar_estado_da_sessao() from public, anon, authenticated;
revoke execute on function public.multa_da_politica(numeric, smallint) from public, anon;
revoke execute on function public.perdoar_cobranca(uuid, text) from public, anon;
revoke execute on function public.marcar_cobranca_paga(uuid) from public, anon;
grant execute on function public.perdoar_cobranca(uuid, text) to authenticated;
grant execute on function public.marcar_cobranca_paga(uuid) to authenticated;
grant execute on function public.multa_da_politica(numeric, smallint) to authenticated;

comment on table public.cobrancas is
  'D2: nasce do gatilho com a politica congelada na sessao. Perdoar marca, nao apaga.';
