-- 0044b · As leituras do Panorama.
-- JÁ APLICADA no projeto remoto em 01/09/2026.
--
-- Toda view nasce FECHADA para anon, e isso não é zelo excessivo:
-- no Supabase o ALTER DEFAULT PRIVILEGES do schema public concede todos
-- os privilégios de relação ao papel anon, e view em Postgres nasce com
-- security_invoker = off — roda com os direitos do dono e IGNORA a RLS
-- das tabelas de baixo. Sem o bloco do fim deste arquivo, qualquer pessoa
-- com a chave anon (que é pública, está no formulário) faria
--     GET /rest/v1/v_residual_textos
-- e leria todos os textos abertos das respondentes.

-- Leitura 1 · A pergunta que decide o produto.
-- Mediana de pessoas esperando por um horário (Q4.3).
-- Se vier abaixo de 3, a fila oferece para ninguém.
create or replace view public.v_leitura1_fila as
select
  count(*)                                                          as n,
  percentile_cont(0.5) within group (order by (respostas->>'q43')::numeric) as mediana_esperando,
  percentile_cont(0.25) within group (order by (respostas->>'q43')::numeric) as p25,
  percentile_cont(0.75) within group (order by (respostas->>'q43')::numeric) as p75,
  round(100.0 * count(*) filter (where (respostas->>'q43')::numeric = 0) / nullif(count(*),0), 1)
                                                                    as pct_com_zero_esperando
from public.pesquisa_respostas
where respostas->>'q43' ~ '^[0-9]+$';

-- Leitura 3 · Taxa de cobrança da falta (Q5.6 ÷ Q5.5),
-- medida sem nunca ter perguntado sobre constrangimento.
create or replace view public.v_leitura3_cobranca as
select
  count(*)                                                        as n,
  sum((respostas->>'q55')::numeric)                               as faltas_total,
  sum((respostas->>'q56')::numeric)                               as cobradas_total,
  round(100.0 * sum((respostas->>'q56')::numeric)
        / nullif(sum((respostas->>'q55')::numeric),0), 1)         as pct_cobrado,
  round(100.0 * count(*) filter (where (respostas->>'q56')::numeric = 0)
        / nullif(count(*),0), 1)                                  as pct_que_nunca_cobrou
from public.pesquisa_respostas
where respostas->>'q55' ~ '^[0-9]+$'
  and respostas->>'q56' ~ '^[0-9]+$'
  and (respostas->>'q55')::numeric > 0;

-- Leitura 4 · A tese central. O ranking muda entre quem tem
-- agenda cheia (Q3.6 = 0 horários livres) e quem tem agenda frouxa?
-- Se for igual nos dois grupos, a dor não é a que se pensava.
create or replace view public.v_leitura4_agenda as
select
  case
    when (respostas->>'q36')::numeric = 0 then 'agenda cheia'
    when (respostas->>'q36')::numeric between 1 and 3 then 'agenda quase cheia'
    else 'agenda com folga'
  end                                                             as grupo,
  item                                                            as dor_no_top3,
  count(*)                                                        as votos
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q71') as item
where respostas->>'q36' ~ '^[0-9]+$'
group by 1, 2
order by 1, 3 desc;

-- Rendimento por canal de divulgação: quantas respostas cada link trouxe,
-- e quantas foram até o fim. É o que diz onde insistir.
create or replace view public.v_rendimento_canal as
select
  coalesce(a.canal_url, 'sem código')                             as canal_link,
  count(distinct a.sessao)                                        as abriram_e_escreveram,
  count(distinct r.sessao)                                        as completaram,
  round(100.0 * count(distinct r.sessao) / nullif(count(distinct a.sessao),0), 1) as pct_conclusao
from public.pesquisa_abertas a
left join public.pesquisa_respostas r on r.sessao = a.sessao
group by 1
order by 2 desc;

-- Leitura 5 · O ranking por canal de recrutamento.
-- Se a lista de espera do Sessões ranquear diferente dos CRPs,
-- o que você mediu foi o próprio viés de recrutamento.
create or replace view public.v_leitura5_canal as
select
  canal,
  item                                                            as dor_no_top3,
  count(*)                                                        as votos,
  round(100.0 * count(*) / nullif(sum(count(*)) over (partition by canal),0), 1) as pct_do_canal
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q71') as item
group by 1, 2
order by 1, 3 desc;

-- Ranking geral do trade-off forçado (Q7.1), ponderado pela posição:
-- 1º lugar vale 3, 2º vale 2, 3º vale 1.
create or replace view public.v_ranking_ponderado as
select
  item                                                            as dor,
  sum(case ord when 1 then 3 when 2 then 2 else 1 end)            as pontos,
  count(*)                                                        as vezes_no_top3,
  count(*) filter (where ord = 1)                                 as vezes_em_primeiro
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q71') with ordinality as t(item, ord)
group by 1
order by 2 desc;

-- O piso: o que as pessoas marcaram como "não é problema nenhum" (Q7.2).
-- Uma dor muito votada aqui é uma feature que não deveria ser construída.
create or replace view public.v_nao_e_problema as
select
  item                                                            as dor,
  count(*)                                                        as votos,
  round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas),0), 1) as pct
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q72') as item
group by 1
order by 2 desc;

-- ============================================================
-- O RESIDUAL — a medida de validade da lista inteira
-- ============================================================
-- Toda lista fechada de dores é um conjunto de pressupostos de quem
-- escreveu a lista. O item "outra coisa — qual?" é a única porta pela
-- qual o resultado principal desta pesquisa consegue produzir uma
-- categoria que nós não escrevemos.
--
-- Como ler o pct_escolheu:
--   até 10%  · a lista cobriu bem o espaço de dores da categoria
--   10 a 20% · há um domínio faltando; leia os textos e nomeie
--   acima de 20% · a lista está errada, e o ranking dos outros 16
--                  itens deve ser reportado como provisório
--
-- Esta view é para ser olhada ANTES do v_ranking_ponderado. Se o
-- residual for alto, o ranking mede a nossa imaginação, não a rotina.
create or replace view public.v_residual as
with total as (
  select count(*)::numeric as n from public.pesquisa_respostas
),
esc as (
  select t.ord,
         nullif(btrim(r.respostas->>'q71_outra'), '') as txt
  from public.pesquisa_respostas r
       join lateral jsonb_array_elements_text(r.respostas->'q71')
            with ordinality as t(item, ord) on t.item = 'outra'
)
select
  (select n from total)::bigint                                   as n_respostas,
  count(*)                                                        as escolheu_outra,
  round(100.0 * count(*) / nullif((select n from total), 0), 1)   as pct_escolheu,
  count(*) filter (where ord = 1)                                 as em_primeiro_lugar,
  count(*) filter (where txt is not null)                         as com_texto
from esc;

-- Os textos do residual, um por linha, para codificação aberta.
-- Codifique estes JUNTO com o bloco 1 e ANTES de olhar o ranking:
-- é o mesmo material — o que a rotina tem e a nossa lista não previu.
create or replace view public.v_residual_textos as
select
  r.criado_em,
  r.canal,
  r.canal_url,
  o.ord                                                           as posicao_no_top3,
  btrim(r.respostas->>'q71_outra')                                as texto
from public.pesquisa_respostas r
     join lateral jsonb_array_elements_text(r.respostas->'q71')
          with ordinality as o(item, ord) on o.item = 'outra'
where nullif(btrim(r.respostas->>'q71_outra'), '') is not null
order by o.ord, r.criado_em;

-- Os dois itens acrescentados na revisão de 01/09, isolados.
-- Eles entraram porque a auditoria concluiu que a omissão era erro —
-- e não porque haja feature para eles. Se ficarem no fim do ranking,
-- a auditoria errou, e isso também é resultado que vai no relatório.
create or replace view public.v_itens_novos as
select
  item                                                            as dor,
  count(*)                                                        as vezes_no_top3,
  count(*) filter (where ord = 1)                                 as vezes_em_primeiro,
  round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas),0), 1) as pct
from public.pesquisa_respostas,
     lateral jsonb_array_elements_text(respostas->'q71') with ordinality as t(item, ord)
where item in ('laudos', 'mensagens')
group by 1
order by 2 desc;

-- Qualidade da amostra: quantas somas de Q3.3 não fecham com Q3.2.
-- Resposta descuidada, detectada sem pergunta-armadilha.
create or replace view public.v_qualidade as
select
  count(*)                                                        as n_com_faltas,
  count(*) filter (
    where (respostas->>'q33a')::numeric + (respostas->>'q33b')::numeric
        + (respostas->>'q33c')::numeric <> (respostas->>'q32')::numeric
  )                                                               as soma_nao_fecha,
  round(avg(duracao_seg)/60.0, 1)                                 as duracao_media_min,
  count(*) filter (where duracao_seg < 120)                       as suspeitos_rapidos
from public.pesquisa_respostas
where respostas->>'q32' ~ '^[0-9]+$' and (respostas->>'q32')::numeric > 0;

-- Funil: quantas pessoas deixaram o bloco aberto e não terminaram.
-- O bloco aberto é o dado mais valioso, e ele é gravado cedo de propósito.
create or replace view public.v_funil as
select
  (select count(*) from public.pesquisa_abertas)                  as enviaram_bloco_aberto,
  (select count(*) from public.pesquisa_respostas)                as completaram,
  (select count(*) from public.pesquisa_abertas a
    where not exists (select 1 from public.pesquisa_respostas r where r.sessao = a.sessao))
                                                                  as abandonaram_depois_do_aberto;

-- ============================================================
-- FECHAMENTO DAS VIEWS — sem isto, a pesquisa vaza inteira
-- ============================================================
-- No Supabase, o ALTER DEFAULT PRIVILEGES do schema public concede
-- todos os privilégios de relação ao papel `anon`, e view em Postgres
-- nasce com security_invoker = off — ou seja, roda com os direitos do
-- dono (postgres) e IGNORA a RLS das tabelas de baixo.
--
-- Consequência, se este bloco não existir: qualquer pessoa com a chave
-- anon — que é pública, está embutida no formulário — poderia fazer
--     GET /rest/v1/v_residual_textos
-- e ler todos os textos abertos das respondentes. A RLS insert-only das
-- tabelas não protege nada disso, porque a view passa por cima dela.
--
-- Duas travas, de propósito redundantes:
--   1. security_invoker = on  → a view passa a respeitar a RLS; como
--      anon não tem policy de SELECT, anon vê zero linha.
--   2. revoke                 → anon nem enxerga a view no PostgREST.
-- Você continua lendo tudo pelo painel do Supabase e pela service_role.

do $$
declare v text;
begin
  foreach v in array array[
    'v_leitura1_fila','v_leitura3_cobranca','v_leitura4_agenda',
    'v_rendimento_canal','v_leitura5_canal','v_ranking_ponderado',
    'v_nao_e_problema','v_residual','v_residual_textos',
    'v_itens_novos','v_qualidade','v_funil'
  ] loop
    execute format('alter view public.%I set (security_invoker = on)', v);
    execute format('revoke all on public.%I from anon, authenticated', v);
  end loop;
end $$;
