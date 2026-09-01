-- 0049 · As leituras que a revisao 2 do instrumento exige.
-- Depende dos itens novos do formulario: q37 (capacidade), q38 (hora reposta),
-- q512 (antecipacao ja praticada), q513 (a conjuncao), q69 (regularizacao).
-- NAO aplicada no banco remoto — aplique quando publicar o formulario revisado.

-- ============================================================
-- REVISÃO 2 · as leituras que a tese nova exige
-- ============================================================
-- Aplicar como migration 0049. Depende dos itens novos do formulário:
-- q37 (capacidade), q38 (hora reposta), q512 (antecipação), q513 (conjunção),
-- q69 (regularização).

-- A OCUPAÇÃO DA CATEGORIA. Q3.1 (sessões atendidas) sobre Q3.7 (horas
-- disponibilizadas). É a primeira medida de ocupação de consultório de
-- psicologia que existe no Brasil, e ela cabe num gráfico só.
create or replace view public.v_ocupacao as
with base as (
  select (respostas->>'q31')::numeric as atendidas,
         (respostas->>'q37')::numeric as capacidade
  from public.pesquisa_respostas
  where respostas->>'q31' ~ '^[0-9]+$'
    and respostas->>'q37' ~ '^[0-9]+$'
    and (respostas->>'q37')::numeric > 0
)
select
  count(*)                                                        as n,
  percentile_cont(0.5) within group (order by atendidas/capacidade)  as mediana_ocupacao,
  percentile_cont(0.25) within group (order by atendidas/capacidade) as p25,
  percentile_cont(0.75) within group (order by atendidas/capacidade) as p75,
  round(100.0 * count(*) filter (where atendidas/capacidade < 0.5)
        / nullif(count(*),0), 1)                                  as pct_abaixo_de_meia_agenda,
  percentile_cont(0.5) within group (order by capacidade - atendidas) as mediana_horas_vagas
from base;

-- A HORA REPOSTA (Q3.8). Se "vale o pagamento da desmarcada" for maioria,
-- a remarcacao com credito e um vazamento maior que a falta — duas horas de
-- capacidade por uma receita — e o eixo_capacidade do livro-razao vira a
-- feature mais valiosa do roadmap.
create or replace view public.v_hora_reposta as
select
  respostas->>'q38'                                               as pratica,
  count(*)                                                        as n,
  round(100.0 * count(*) / nullif(sum(count(*)) over (),0), 1)    as pct
from public.pesquisa_respostas
where respostas->>'q38' is not null
group by 1
order by 2 desc;

-- A CONJUNCAO (Q5.13) — H7. Todas as outras leituras medem margens; esta
-- mede o produto delas. Mediana zero mata a fila de encaixe como ancora.
create or replace view public.v_conjuncao as
with base as (
  select (respostas->>'q513')::numeric as n_conj,
         (respostas->>'q55')::numeric  as n_faltas
  from public.pesquisa_respostas
  where respostas->>'q513' ~ '^[0-9]+$'
)
select
  count(*)                                                        as n,
  percentile_cont(0.5) within group (order by n_conj)             as mediana,
  percentile_cont(0.75) within group (order by n_conj)            as p75,
  round(100.0 * count(*) filter (where n_conj = 0) / nullif(count(*),0), 1) as pct_zero,
  round(avg(n_conj / nullif(n_faltas,0))::numeric, 3)             as fracao_das_faltas_que_qualificam
from base;

-- A ANTECIPACAO JA PRATICADA (Q5.12). Decide se o piloto existe.
create or replace view public.v_antecipacao as
select
  respostas->>'q512'                                              as pratica,
  count(*)                                                        as n,
  round(100.0 * count(*) / nullif(sum(count(*)) over (),0), 1)    as pct
from public.pesquisa_respostas
where respostas->>'q512' is not null
group by 1
order by 2 desc;

-- A DUVIDA DE REGULARIZACAO (Q6.9). O terreno sem concorrente.
-- "nenhuma" existe para poder ganhar: se for maioria, a trilha de
-- regularizacao nao tem demanda e sai do roadmap antes de custar codigo.
create or replace view public.v_regularizacao as
select
  item                                                            as duvida,
  count(*)                                                        as n,
  round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas),0), 1) as pct
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q69') as item
group by 1
order by 2 desc;

-- A DURACAO REAL. Rode nas primeiras 30 completas e corrija o numero
-- declarado em TODAS as pecas. Declarar 9 e levar 15 quebra a promessa.
create or replace view public.v_duracao_real as
select
  count(*)                                                        as n,
  round((percentile_cont(0.5) within group (order by duracao_seg::double precision)/60.0)::numeric, 1) as mediana_min,
  round((percentile_cont(0.9) within group (order by duracao_seg::double precision)/60.0)::numeric, 1) as p90_min,
  round(100.0 * count(*) filter (where duracao_seg > 720) / nullif(count(*),0), 1) as pct_acima_de_12min
from public.pesquisa_respostas
where duracao_seg is not null and duracao_seg between 60 and 7200;

do $$
declare v text;
begin
  foreach v in array array['v_ocupacao','v_hora_reposta','v_conjuncao',
                           'v_antecipacao','v_regularizacao','v_duracao_real'] loop
    execute format('alter view public.%I set (security_invoker = on)', v);
    execute format('revoke all on public.%I from anon, authenticated', v);
  end loop;
end $$;
