-- 0090 · A hora que a fila preencheu só "voltou" depois de acontecer
--
-- O QUE FOI MEDIDO ANTES DE ESCREVER
--
-- Duas telas do produto respondem "quanto a fila recuperou neste mês", e no
-- banco de hoje elas dizem coisas diferentes:
--
--   `retorno`            (agenda, "Retorno · setembro")     → R$ 950,00
--   `financeiro_do_mes`  (movimentações, "Voltou para o mês") → R$ 0,00
--
-- As cinco sessões com `origem = 'encaixe'` do banco estão em `prevista` (4) e
-- `cancelada_cedo` (1). **Nenhuma aconteceu.** A `financeiro_do_mes` conta só
-- `realizada` e por isso mostra zero; a `retorno` conta toda encaixe não
-- cancelada — inclusive as que ainda vão acontecer — e mostra novecentos e
-- cinquenta reais em serifa de 26 px, embaixo da frase *"que não teria entrado
-- sem a fila e sem a política"*.
--
-- Dinheiro de sessão que ainda não aconteceu **não entrou**. A frase afirma o
-- contrário, e é a mesma família do S1-B da B44: a única frase do produto que
-- faz afirmação contrafactual sobre o dinheiro dela. A B44 consertou a CTE
-- `dinheiro` (que somava os quatro tipos de cobrança) e não tocou nesta.
--
-- A REGRA NOVA
--
-- A vaga preenchida continua contando como preenchida — **a fila fez o trabalho
-- dela**, e isso é fato no minuto em que alguém aceita. O que passa a esperar é
-- o dinheiro:
--
--   `valor_preenchido` · `horas_recuperadas`   só o que está `realizada`
--   `valor_agendado`   · `horas_agendadas`     marcado, ainda por acontecer
--
-- E a falta cai fora das duas somas, de propósito: encaixe que virou `falta` não
-- aconteceu e não vai acontecer. Se ela cobrou, o dinheiro aparece em
-- `valor_recebido`, que é a coluna da multa — contar nos dois seria a mesma hora
-- somada duas vezes.
--
-- POR QUE `DROP` E NÃO `CREATE OR REPLACE`
--
-- A função devolve tabela, e duas colunas novas mudam a assinatura de saída. Os
-- grants voltam explícitos logo abaixo: `drop` os leva junto, e uma função sem
-- `grant` é uma tela que para de abrir sem ninguém entender por quê.

drop function if exists public.retorno(date, date);

create function public.retorno(p_de date, p_ate date)
returns table (
  canceladas        integer,
  oferecidas        integer,
  preenchidas       integer,
  taxa              numeric,
  valor_preenchido  numeric,
  valor_agendado    numeric,
  valor_recebido    numeric,
  valor_em_aberto   numeric,
  valor_perdoado    numeric,
  horas_recuperadas numeric,
  horas_agendadas   numeric
)
language sql
stable
set search_path = ''
as $function$
  with vagas as (
    select s.id, s.inicio, s.fim,
           exists (select 1 from public.ofertas o where o.sessao_id = s.id) as teve_oferta,
           (select o.id from public.ofertas o
             where o.sessao_id = s.id and o.estado = 'aceita' limit 1) as oferta_aceita
      from public.sessoes s
     where s.estado in ('cancelada_cedo', 'cancelada_tarde')
       and (s.cancelada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
  ),
  -- O `left join lateral` no lugar da subconsulta escalar: agora a CTE precisa
  -- do **estado** da sessão que preencheu, e não só do valor dela.
  --
  -- Sem filtro de conta, como o resto desta função: ela não é `security
  -- definer`, então a RLS já devolve só o que é da conta de quem chamou. Se um
  -- dia a RLS cair, isto para de funcionar em vez de vazar.
  encaixes as (
    select v.id as vaga, v.inicio, v.fim, e.estado, e.valor
      from vagas v
      left join lateral (
        select s2.estado, s2.valor
          from public.sessoes s2
         where s2.origem = 'encaixe'
           and s2.inicio = v.inicio
           and s2.estado not in ('cancelada_cedo', 'cancelada_tarde')
         limit 1
      ) e on true
     where v.oferta_aceita is not null
  ),
  dinheiro as (
    select
      coalesce(sum(c.valor) filter (where c.estado = 'paga'), 0)     as recebido,
      coalesce(sum(c.valor) filter (where c.estado = 'aberta'), 0)   as em_aberto,
      coalesce(sum(c.valor) filter (where c.estado = 'perdoada'), 0) as perdoado
      from public.cobrancas c
     where c.tipo = 'falta'
       and c.competencia between date_trunc('month', p_de)::date
                             and date_trunc('month', p_ate)::date
  )
  select
    (select count(*) from vagas)::integer,
    (select count(*) from vagas where teve_oferta)::integer,
    (select count(*) from vagas where oferta_aceita is not null)::integer,
    case when (select count(*) from vagas) = 0 then null
         else round(100.0 * (select count(*) from vagas where teve_oferta)
                    / (select count(*) from vagas), 1) end,
    coalesce((select sum(valor) filter (where estado = 'realizada') from encaixes), 0),
    coalesce((select sum(valor) filter (where estado in ('prevista', 'confirmada')) from encaixes), 0),
    (select recebido from dinheiro),
    (select em_aberto from dinheiro),
    (select perdoado from dinheiro),
    coalesce((select sum(extract(epoch from (fim - inicio)) / 3600.0)
                filter (where estado = 'realizada') from encaixes), 0),
    coalesce((select sum(extract(epoch from (fim - inicio)) / 3600.0)
                filter (where estado in ('prevista', 'confirmada')) from encaixes), 0);
$function$;

revoke all on function public.retorno(date, date) from public, anon;
grant execute on function public.retorno(date, date) to authenticated, service_role;

comment on function public.retorno(date, date) is
  'O que a fila recuperou no periodo, pelas vagas canceladas nele. valor_preenchido e horas_recuperadas contam SO encaixe realizada: dinheiro de sessao que ainda nao aconteceu nao entrou. O que esta marcado e por acontecer vai em valor_agendado/horas_agendadas, separado. Encaixe que virou falta nao entra em nenhuma das duas: se ela cobrou, o dinheiro esta em valor_recebido.';
