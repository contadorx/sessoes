-- 0050 · o que o piloto ensinou
--
-- Origem: primeira resposta-piloto real (02/09/2026). A respondente digitou 0
-- na Q4.3 porque o formulário exigia um número, quando a verdade era "isso não
-- se aplica ao meu jeito de trabalhar" — ela não trabalha com lista de espera
-- porque encaminha para colegas.
--
-- Isso não é detalhe de UX. A H1 pré-registrada é "a mediana de pessoas em
-- espera é inferior a 3". Sem separar zero de não-se-aplica, a H1 é confirmada
-- por artefato do instrumento, e o pré-registro passa a proteger um resultado
-- que o próprio desenho fabricou.
--
-- A revisão 3 do formulário cria a saída (q43_na, q44_na) e um item novo (q49,
-- o destino de quem procura e não consegue horário). Estas views leem isso.
--
-- O campo é q49, e não q48: o q48 do formulário antigo guarda outro sentido
-- ('recusou alguém por falta de horário', item aposentado na revisão 2) e ainda
-- existe em linha gravada. Reaproveitar a chave misturaria dois significados.

-- ---------------------------------------------------------------------------
-- Leitura 1 · refeita. O denominador agora é declarado, não implícito.
-- ---------------------------------------------------------------------------
create or replace view public.v_leitura1_fila as
with base as (
  select
    respostas,
    (respostas->'q43_na') is not null                as nao_se_aplica,
    (respostas->>'q43') ~ '^[0-9]+$'                 as tem_numero
  from public.pesquisa_respostas
)
select
  count(*)                                                      as n_total,
  count(*) filter (where nao_se_aplica)                         as n_nao_se_aplica,
  round(100.0 * count(*) filter (where nao_se_aplica)
        / nullif(count(*),0), 1)                                as pct_nao_se_aplica,
  count(*) filter (where tem_numero)                            as n_com_numero,
  percentile_cont(0.5)  within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end)
                                                                as mediana_esperando,
  percentile_cont(0.25) within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end) as p25,
  percentile_cont(0.75) within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end) as p75,
  round(100.0 * count(*) filter (where tem_numero and (respostas->>'q43')::numeric = 0)
        / nullif(count(*) filter (where tem_numero),0), 1)      as pct_zero_entre_quem_respondeu
from base;

comment on view public.v_leitura1_fila is
  'H1. A mediana é calculada SÓ sobre quem informou número. pct_nao_se_aplica é '
  'resultado, não descarte: se for alta, a fila não é uma categoria da '
  'categoria, e a H1 responde a uma pergunta que a maioria não reconhece.';

-- ---------------------------------------------------------------------------
-- O destino da demanda não atendida (Q4.9 · campo q49) · o caminho que faltava
-- ---------------------------------------------------------------------------
create or replace view public.v_destino_demanda as
select
  d.valor                                                as destino,
  count(*)                                               as n,
  round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas
                                   where respostas ? 'q49'),0), 1) as pct
from public.pesquisa_respostas r
cross join lateral jsonb_array_elements_text(r.respostas->'q49') as d(valor)
where r.respostas ? 'q49'
group by d.valor
order by n desc;

comment on view public.v_destino_demanda is
  'Objetivo 7 do protocolo. O encaminhamento para colega foi nomeado por uma '
  'respondente do piloto como o destino comum, e não existia no instrumento: '
  'mediamos a lista de espera sem medir a alternativa a ela.';

-- ---------------------------------------------------------------------------
-- Quem escapou pelo "não se aplica", e o que escreveu
-- ---------------------------------------------------------------------------
create or replace view public.v_nao_se_aplica as
select
  count(*) filter (where respostas ? 'q43_na')                 as n_q43_na,
  count(*) filter (where respostas ? 'q44_na')                 as n_q44_na,
  count(*)                                                     as n_total
from public.pesquisa_respostas;

create or replace view public.v_nao_se_aplica_textos as
select
  criado_em,
  canal_url,
  respostas->>'q43_como' as q43_como,
  respostas->>'q44_como' as q44_como
from public.pesquisa_respostas
where coalesce(respostas->>'q43_como','') <> ''
   or coalesce(respostas->>'q44_como','') <> ''
order by criado_em;

comment on view public.v_nao_se_aplica_textos is
  'Material aberto. Entra na codificação da etapa 1 do plano de análise, junto '
  'com o bloco 1 e o texto do item residual — antes de qualquer ranking.';

-- ---------------------------------------------------------------------------
-- A trava. View nova nasce aberta: security_invoker off e grant do anon.
-- Sem estas duas linhas, qualquer pessoa com a chave publishable lê os textos.
-- ---------------------------------------------------------------------------
do $$
declare v text;
begin
  foreach v in array array[
    'v_leitura1_fila','v_destino_demanda','v_nao_se_aplica','v_nao_se_aplica_textos'
  ] loop
    execute format('alter view public.%I set (security_invoker = on)', v);
    execute format('revoke all on public.%I from anon, authenticated', v);
  end loop;
end $$;
