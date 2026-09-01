-- 0046c · A mensagem precisa saber quando saiu.
--
-- A 0045 escreveu `custo_da_conta` contando mensagens por `atualizado_em`, e
-- declarou a imprecisão no cabeçalho: *"uma mensagem enviada em 31/01 às 23h50
-- e confirmada como entregue em 01/02 conta em fevereiro. É um erro de uma
-- mensagem por virada de mês."* A 0046 repetiu a mesma janela em
-- `teto_da_conta`.
--
-- **A imprecisão declarada era muito maior do que a declaração.** `mensagens`
-- tem o gatilho `mensagens_atualizado_em` desde a B9, e ele faz
-- `new.atualizado_em := now()` em **todo** UPDATE. Ou seja, `atualizado_em`
-- não é "quando saiu": é "quando a linha foi tocada pela última vez". Um
-- recibo de entrega, uma retentativa, um webhook atrasado — qualquer um deles
-- traz a mensagem de volta para o mês corrente.
--
-- As consequências são duas, e a segunda é pior:
--
--   · o **custo** de agosto muda depois de agosto fechar, e migra para
--     setembro sozinho;
--   · o **teto** de uma conta gratuita pode não zerar na virada do mês. Basta
--     que as mensagens antigas sejam tocadas por qualquer motivo para elas
--     voltarem a ocupar a cota — e a psicóloga começaria o mês com a fila
--     pausada, sem nada no sistema explicando por quê.
--
-- Achado pela verificação 7 da suíte 0046, que tentou envelhecer sessenta
-- mensagens com um UPDATE e viu a contagem não se mexer. O teste parecia
-- estar errado (não dá para envelhecer o que um gatilho carimba); o que estava
-- errado era a coluna escolhida.
--
-- **A correção é uma coluna que só é escrita uma vez.** `enviada_em` recebe
-- `now()` na primeira transição para um estado que gastou dinheiro — enviada,
-- entregue ou barrada no teto — e nunca mais muda. Custo e teto passam a
-- contar por ela.
--
-- Vale a nota geral, porque ela vai voltar: **`atualizado_em` responde sobre a
-- linha, não sobre o fato.** Toda vez que uma métrica precisar de "quando isto
-- aconteceu", a resposta é uma coluna carimbada no acontecimento, não a de
-- manutenção que um gatilho reescreve.

alter table public.mensagens
  add column if not exists enviada_em timestamptz;

comment on column public.mensagens.enviada_em is
  'Quando a mensagem saiu (ou foi barrada) — carimbado UMA vez e nunca mais. Nao confundir com atualizado_em, que o gatilho reescreve a cada toque: custo e teto contam por esta, senao um recibo de entrega atrasado move a mensagem de mes.';

/**
 * O carimbo do acontecimento.
 *
 * Escreve só na primeira vez. `enviada_em is null` é a guarda inteira: um
 * recibo de entrega que chega depois encontra a coluna preenchida e não mexe
 * nela.
 *
 * `enviando` não conta — é reserva, e uma reserva que falha volta para
 * pendente. O que gastou dinheiro foi sair, ou ter sido barrado tendo sido
 * contado.
 */
create or replace function public.mensagem_carimba_saida()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- plpgsql não faz curto-circuito: escalares dentro do `if`. Lição da 0041.
  if new.estado in ('enviada', 'entregue', 'barrada_no_teto') then
    if new.enviada_em is null then
      new.enviada_em := now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists mensagem_carimba_saida on public.mensagens;
create trigger mensagem_carimba_saida
  before insert or update on public.mensagens
  for each row execute function public.mensagem_carimba_saida();

revoke execute on function public.mensagem_carimba_saida() from public, anon, authenticated;

-- O que já existe recebe o melhor palpite disponível, que é `atualizado_em`.
-- Para as linhas antigas ele é impreciso pelo motivo que esta migração
-- corrige — mas a partir daqui para de piorar, e é melhor do que nulo.
update public.mensagens
   set enviada_em = atualizado_em
 where enviada_em is null
   and estado in ('enviada', 'entregue', 'barrada_no_teto');

create index if not exists mensagens_saida_do_mes
  on public.mensagens (conta_id, enviada_em)
  where enviada_em is not null;

-- ============================================================ o teto conta certo

create or replace function public.teto_da_conta(p_conta uuid)
returns table (
  tem_teto boolean,
  limite integer,
  usadas integer,
  restantes integer,
  estourou boolean,
  pct integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim integer;
  n integer;
  ini date := date_trunc('month', public.hoje_sp())::date;
  papel text := coalesce(current_setting('role', true), 'none');
begin
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'o teto é da conta de quem pergunta';
  end if;

  select p.limite_mensagens_mes into lim
    from public.planos p join public.contas c on c.plano = p.codigo
   where c.id = p_conta;

  if lim is null then
    return query select false, null::integer, 0, null::integer, false, 0;
    return;
  end if;

  -- `enviada_em`, não `atualizado_em`: senão o teto de uma conta gratuita pode
  -- não zerar na virada do mês, e ela começaria fevereiro com a fila pausada
  -- sem nada explicando por quê.
  select count(*)::integer into n
    from public.mensagens m
    join public.templates t on t.codigo = m.template
   where m.conta_id = p_conta
     and not t.essencial
     and m.enviada_em is not null
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date >= ini;

  return query select
    true,
    lim,
    n,
    greatest(lim - n, 0),
    n >= lim,
    least(100, (100 * n / greatest(lim, 1)))::integer;
end;
$$;

revoke execute on function public.teto_da_conta(uuid) from public, anon;
grant execute on function public.teto_da_conta(uuid) to authenticated;

-- ============================================================ o custo, idem

create or replace function public.custo_da_conta(p_conta uuid, p_mes date)
returns table (
  mensagens integer,
  mensagens_centavos integer,
  fixo_centavos integer,
  total_centavos integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ini date := date_trunc('month', p_mes)::date;
  fim date := (date_trunc('month', p_mes) + interval '1 month')::date;
  n integer; msg_mil bigint; fixo_total integer; ativas integer;
begin
  select count(*),
         coalesce(sum(
           coalesce((select pc.centavos_milesimos
                       from public.precos_canal pc
                      where pc.canal = m.canal
                        and pc.vigencia_inicio <= (m.enviada_em at time zone 'America/Sao_Paulo')::date
                      order by pc.vigencia_inicio desc
                      limit 1), 0)
         ), 0)
    into n, msg_mil
    from public.mensagens m
   where m.conta_id = p_conta
     and m.enviada_em is not null
     -- Barrada não custou: ela não saiu. Entra na conta do **teto** (senão a
     -- cota cabe sozinha de novo) e fica fora da conta do **custo** (senão eu
     -- pago por mensagem que eu mesmo impedi de sair).
     and m.estado in ('enviada', 'entregue')
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date >= ini
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date <  fim;

  select coalesce(sum(cf.centavos), 0) into fixo_total
    from public.custos_fixos cf where cf.mes = ini;

  select greatest(count(*), 1) into ativas
    from public.contas c
   where not c.is_teste
     and exists (select 1 from public.assinaturas a
                  where a.conta_id = c.id and a.estado in ('ativa', 'em_atraso'));

  return query select
    n,
    (msg_mil / 1000)::integer,
    (fixo_total / ativas)::integer,
    ((msg_mil / 1000) + (fixo_total / ativas))::integer;
end;
$$;

revoke execute on function public.custo_da_conta(uuid, date) from public, anon, authenticated;
