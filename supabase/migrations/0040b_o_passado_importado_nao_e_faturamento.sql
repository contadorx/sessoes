-- 0040b · O passado importado não é faturamento.
--
-- A 0040 criou `origem = 'importada'` e a decisão 6 disse o que ela significa.
-- Falta a consequência aritmética: `financeiro_do_mes` conta `realizado` por
-- sessão realizada no período, e uma planilha com dois anos de atendimento
-- despejaria dezenas de milhares de reais de faturamento em meses fechados.
--
-- Uma linha muda, e é a linha inteira desta migração. O resto é a função
-- reemitida verbatim, porque `create or replace` não aceita meio corpo.
--
-- (`recuperado.encaixes` já filtra `origem = 'encaixe'`, e por isso não é
-- alcançado por sessão importada. `recebido`, `em_aberto` e `perdoado` vêm de
-- cobranças, que a 0040 proibiu de nascer sobre sessão importada.)

create or replace function public.financeiro_do_mes(p_de date, p_ate date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  realizado_valor numeric := 0;  realizado_n int := 0;
  recebido_valor  numeric := 0;  recebido_n  int := 0;
  aberto_valor    numeric := 0;  aberto_n    int := 0;
  perdoado_valor  numeric := 0;  perdoado_n  int := 0;
  despesa_valor   numeric := 0;  despesa_n   int := 0;
  encaixe_valor   numeric := 0;  encaixe_n   int := 0;
  falta_valor     numeric := 0;  falta_n     int := 0;
  sem_valor       numeric := 0;  sem_n       int := 0;
  por_tipo        jsonb;
  por_categoria   jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  -- ------------------------------------------------- realizado (competência)
  select coalesce(sum(s.valor), 0), count(*)
    into realizado_valor, realizado_n
    from public.sessoes s
   where s.conta_id = c
     and s.estado = 'realizada'
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ------------------------------------------------------- recebido (caixa)
  select coalesce(sum(cb.valor), 0), count(*)
    into recebido_valor, recebido_n
    from public.cobrancas cb
   where cb.conta_id = c
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  select coalesce(jsonb_object_agg(t.tipo, t.soma), '{}'::jsonb)
    into por_tipo
    from (
      select cb.tipo, sum(cb.valor) as soma
        from public.cobrancas cb
       where cb.conta_id = c
         and cb.estado = 'paga'
         and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
       group by cb.tipo
    ) t;

  -- -------------------------------------------- em aberto e perdoado (comp.)
  select coalesce(sum(cb.valor), 0), count(*)
    into aberto_valor, aberto_n
    from public.cobrancas cb
   where cb.conta_id = c and cb.estado = 'aberta'
     and cb.competencia between date_trunc('month', p_de)::date and p_ate;

  select coalesce(sum(cb.valor), 0), count(*)
    into perdoado_valor, perdoado_n
    from public.cobrancas cb
   where cb.conta_id = c and cb.estado = 'perdoada'
     and cb.competencia between date_trunc('month', p_de)::date and p_ate;

  -- ------------------------------------------------------------- despesas
  select coalesce(sum(d.valor), 0), count(*)
    into despesa_valor, despesa_n
    from public.despesas d
   where d.conta_id = c and d.paga_em between p_de and p_ate;

  select coalesce(jsonb_agg(x order by x->>'categoria'), '[]'::jsonb)
    into por_categoria
    from (
      select jsonb_build_object(
               'categoria', d.categoria,
               'valor', sum(d.valor),
               'lancamentos', count(*)
             ) as x
        from public.despesas d
       where d.conta_id = c and d.paga_em between p_de and p_ate
       group by d.categoria
    ) g;

  -- ------------------------------------------------------- o que voltou
  select coalesce(sum(s.valor), 0), count(*)
    into encaixe_valor, encaixe_n
    from public.sessoes s
   where s.conta_id = c
     and s.estado = 'realizada'
     and s.origem = 'encaixe'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  select coalesce(sum(cb.valor), 0), count(*)
    into falta_valor, falta_n
    from public.cobrancas cb
   where cb.conta_id = c
     and cb.tipo = 'falta'
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ---------------------------------------------------------- sem registro
  select coalesce(sum(x.valor), 0), count(*)
    into sem_valor, sem_n
    from public.sessoes_sem_registro(p_de, p_ate) x;

  return jsonb_build_object(
    'de', p_de,
    'ate', p_ate,
    'realizado', jsonb_build_object('valor', realizado_valor, 'sessoes', realizado_n),
    'recebido',  jsonb_build_object('valor', recebido_valor, 'cobrancas', recebido_n,
                                    'por_tipo', por_tipo),
    'em_aberto', jsonb_build_object('valor', aberto_valor, 'cobrancas', aberto_n),
    'perdoado',  jsonb_build_object('valor', perdoado_valor, 'cobrancas', perdoado_n),
    'despesas',  jsonb_build_object('valor', despesa_valor, 'lancamentos', despesa_n,
                                    'por_categoria', por_categoria),
    -- Sobra, não lucro: é caixa menos despesa lançada, e não pretende ser
    -- resultado contábil. DRE está fora do produto por decisão (doc 03 §7).
    'sobra', recebido_valor - despesa_valor,
    'recuperado', jsonb_build_object(
      'encaixes', encaixe_n, 'valor_encaixes', encaixe_valor,
      'faltas', falta_n, 'valor_faltas', falta_valor
    ),
    'sem_registro', jsonb_build_object('sessoes', sem_n, 'valor', sem_valor)
  );
end;
$$;

comment on function public.financeiro_do_mes(date, date) is
  'F1: realizado (competencia) e recebido (caixa) lado a lado. Nao existe total. Sessao importada nao entra em realizado: e memoria de outro sistema, nao faturamento deste.';
