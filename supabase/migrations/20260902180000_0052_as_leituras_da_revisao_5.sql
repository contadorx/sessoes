-- 0052 · as leituras da revisão 5
--
-- Aplicada em 02/09/2026, depois da 0052a (os drops). Verificado no banco:
-- 19 views criadas, ZERO delas legíveis por anon ou authenticated.
--
-- Substitui as migrations 0049, 0050 e 0051, que nunca chegaram a ser
-- aplicadas: elas liam campos que a revisão 5 aposentou. Uma migration só,
-- alinhada ao instrumento que está no ar, conta a mesma história que o
-- formulário — três migrations descrevendo três instrumentos diferentes não
-- contariam.
--
-- O QUE MUDOU NO INSTRUMENTO, E POR QUE ISSO CHEGA AQUI
--
-- As contagens em janela de 3 meses saíram. Ninguém recupera noventa dias de
-- episódios pouco salientes: estima por heurística e antecipa datas. As antigas
-- q41, q55, q56 e q513 pediam exatamente isso — e a H2 era a razão entre duas
-- dessas contagens, enquanto a H7 era uma conjunção tripla sobre a mesma janela.
--
-- No lugar entrou o desenho de ÚLTIMO EPISÓDIO: frequência declarada (q516) e,
-- para quem tem episódio, um evento específico e lembrado (q517 a q520). Cada
-- respondente contribui com um episódio; as três condições da H7 passam a ser
-- fatos sobre esse episódio, e não um contrafactual imaginado sobre um trimestre.
--
-- CAMPOS APOSENTADOS, QUE NÃO PODEM SER REAPROVEITADOS:
--   q01  canal autodeclarado        -> canal_url é a fonte única
--   q41  contagem de 3 meses        -> q41f, frequência
--   q42  guarda o contato           -> duplicava q47
--   q55  contagem de faltas 3 meses -> q516, frequência
--   q56  contagem de cobradas       -> q518, o último episódio
--   q513 conjunção contada          -> q519 + q520, sobre o mesmo episódio
--   q61, q62, q65, q66              -> cortados do bloco 6
--
-- Nenhum desses nomes volta a ser usado com outro sentido. Foi a lição do
-- q48/q49: chave reaproveitada mistura dois significados na mesma coluna.

-- ===========================================================================
-- H1 · a fila, com denominador declarado
-- ===========================================================================
create or replace view public.v_leitura1_fila as
with base as (
  select
    respostas,
    (respostas->'q43_na') is not null  as nao_se_aplica,
    (respostas->>'q43') ~ '^[0-9]+$'   as tem_numero
  from public.pesquisa_respostas
)
select
  count(*)                                                     as n_total,
  count(*) filter (where nao_se_aplica)                        as n_nao_se_aplica,
  round(100.0 * count(*) filter (where nao_se_aplica)
        / nullif(count(*),0), 1)                               as pct_nao_se_aplica,
  count(*) filter (where tem_numero)                           as n_com_numero,
  percentile_cont(0.5)  within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end) as mediana_esperando,
  percentile_cont(0.25) within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end) as p25,
  percentile_cont(0.75) within group (
    order by case when tem_numero then (respostas->>'q43')::numeric end) as p75,
  round(100.0 * count(*) filter (where tem_numero and (respostas->>'q43')::numeric = 0)
        / nullif(count(*) filter (where tem_numero),0), 1)     as pct_zero_entre_quem_respondeu
from base;

comment on view public.v_leitura1_fila is
  'H1. Mediana só sobre quem informou número. pct_nao_se_aplica é resultado, '
  'não descarte: acima de 30% a H1 responde a uma pergunta que a maioria da '
  'categoria não reconhece, e isso é o achado. A avaliação externa objetou que '
  'quem não mantém lista tem zero esperando, não "não se aplica"; a objeção '
  'está registrada no pré-registro e as duas leituras são reportadas.';

-- ===========================================================================
-- H2 · a taxa de cobrança, agora medida no último episódio
-- ===========================================================================
create or replace view public.v_leitura3_cobranca as
with base as (
  select respostas
  from public.pesquisa_respostas
  where respostas->>'q516' is not null
    and respostas->>'q516' <> 'não acontece'
    and respostas->>'q518' is not null
)
select
  count(*)                                                        as n_episodios,
  count(*) filter (where respostas->>'q518' = 'sim')              as cobrou_integral,
  count(*) filter (where respostas->>'q518' = 'em parte')         as cobrou_parte,
  count(*) filter (where respostas->>'q518' = 'não')              as nao_cobrou,
  count(*) filter (where respostas->>'q518' = 'valeu para a remarcada') as virou_credito,
  round(100.0 * count(*) filter (where respostas->>'q518' in ('sim','em parte'))
        / nullif(count(*),0), 1)                                  as pct_cobrado
from base;

comment on view public.v_leitura3_cobranca is
  'H2, refeita na revisão 5. Cada respondente contribui com UM episódio — o '
  'último que aconteceu com ela — e não com uma contagem trimestral que '
  'ninguém consegue recuperar. pct_cobrado é a proporção de últimos episódios '
  'em que houve cobrança, integral ou parcial. É estatística de pessoa, não de '
  'episódio: reportar assim, e não como "das faltas do país, X% são cobradas".';

-- A quarta opção da q518 é o vazamento que nenhum sistema enxerga: a sessão
-- não foi cobrada porque o pagamento dela valeu para a remarcada. Duas horas
-- de capacidade, uma receita.
create or replace view public.v_credito_na_remarcacao as
select
  count(*) filter (where respostas->>'q518' = 'valeu para a remarcada') as n_credito,
  count(*) filter (where respostas->>'q38' = 'vale o pagamento da desmarcada') as n_habitual,
  count(*)                                                              as n_total
from public.pesquisa_respostas;

-- ===========================================================================
-- H7 · a conjunção, sobre um episódio real
-- ===========================================================================
create or replace view public.v_conjuncao as
with ep as (
  select
    (respostas->>'q519') = 'sim'                            as com_antecedencia,
    (respostas->>'q518') in ('não','valeu para a remarcada') as nao_cobrada,
    (respostas->>'q520') = 'sim'                            as havia_alguem
  from public.pesquisa_respostas
  where respostas->>'q516' is not null
    and respostas->>'q516' <> 'não acontece'
    and respostas->>'q518' is not null
)
select
  count(*)                                                            as n_episodios,
  count(*) filter (where com_antecedencia)                            as n_antecedencia,
  count(*) filter (where nao_cobrada)                                 as n_nao_cobrada,
  count(*) filter (where havia_alguem)                                as n_havia_alguem,
  count(*) filter (where com_antecedencia and nao_cobrada and havia_alguem) as n_conjuncao,
  round(100.0 * count(*) filter (where com_antecedencia and nao_cobrada and havia_alguem)
        / nullif(count(*),0), 1)                                      as pct_conjuncao
from ep;

comment on view public.v_conjuncao is
  'H7, refeita. A hipótese passa a ser sobre PROPORÇÃO de episódios em que as '
  'três condições coexistiram, e não sobre a mediana de uma contagem '
  'trimestral. As três colunas de margem existem para mostrar o que a versão '
  'antiga escondia: margens altas e conjunção baixa é o resultado que mata a '
  'fila de encaixe como âncora de produto.';

-- ===========================================================================
-- Capacidade e ocupação
-- ===========================================================================
create or replace view public.v_ocupacao as
with base as (
  select (respostas->>'q31')::numeric as sessoes,
         (respostas->>'q37')::numeric as horas,
         (respostas->>'q36')::numeric as livres,
         (respostas->>'q39')::numeric as por_terceiro
  from public.pesquisa_respostas
  where respostas->>'q31' ~ '^[0-9]+$' and respostas->>'q37' ~ '^[0-9]+$'
)
select
  count(*)                                                            as n,
  count(*) filter (where horas = 0)                                   as n_capacidade_zero,
  percentile_cont(0.5) within group (order by sessoes)                as mediana_sessoes,
  percentile_cont(0.5) within group (order by horas)                  as mediana_capacidade,
  percentile_cont(0.5) within group (order by livres)                 as mediana_livres,
  percentile_cont(0.5) within group (
    order by case when horas > 0 then sessoes / horas end)            as mediana_ocupacao,
  percentile_cont(0.5) within group (order by por_terceiro)           as mediana_por_terceiro
from base;

comment on view public.v_ocupacao is
  'n_capacidade_zero não é lixo: é a taxa de não-resposta útil da q37. Se for '
  'alta, a capacidade semanal não pode ser pedida em branco no produto — tem '
  'de ser inferida da agenda e confirmada.';

-- ===========================================================================
-- O estrato que faltava: quem tem a cobrança administrada por terceiro
-- ===========================================================================
create or replace view public.v_administracao_terceiro as
with base as (
  select (respostas->>'q31')::numeric as sessoes,
         (respostas->>'q39')::numeric as terceiro,
         respostas
  from public.pesquisa_respostas
  where respostas->>'q31' ~ '^[0-9]+$' and respostas->>'q39' ~ '^[0-9]+$'
)
select
  count(*)                                                    as n,
  count(*) filter (where terceiro = 0)                        as n_so_direto,
  count(*) filter (where terceiro > 0 and terceiro < sessoes) as n_misto,
  count(*) filter (where sessoes > 0 and terceiro >= sessoes) as n_so_terceiro,
  round(100.0 * sum(terceiro) / nullif(sum(sessoes),0), 1)    as pct_sessoes_por_terceiro
from base;

create or replace view public.v_via_terceiro as
select v.valor as via, count(*) as n
from public.pesquisa_respostas r
cross join lateral jsonb_array_elements_text(r.respostas->'q310') as v(valor)
where r.respostas ? 'q310'
group by v.valor order by n desc;

comment on view public.v_administracao_terceiro is
  'Sem este corte, quem tem a cobrança administrada por clínica, plataforma ou '
  'convênio entra na mesma média de quem cobra sozinha — e metade do bloco 5 '
  'não descreve a prática dela. Todo resultado financeiro é estratificado aqui.';

-- ===========================================================================
-- Fiscal · o ramo PF, o ramo PJ e o ritmo do recibo
-- ===========================================================================
create or replace view public.v_fluxo_pagamento as
select coalesce(respostas->>'q27','(em branco)') as fluxo,
       count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas),0), 1) as pct
from public.pesquisa_respostas
group by 1 order by n desc;

comment on view public.v_fluxo_pagamento is
  'A q27 deixou de perguntar natureza jurídica declarada e passou a perguntar '
  'por onde o dinheiro entrou nos últimos 30 dias. É o que ramifica o bloco '
  'fiscal, e é o denominador da H4: só quem recebeu no CPF. "prefiro não '
  'dizer" fica FORA do denominador — não se presume pessoa física.';

create or replace view public.v_receita_saude as
with base as (
  select respostas from public.pesquisa_respostas
  where respostas->>'q27' in ('CPF','os dois')
    and respostas->>'q510' is not null
    and respostas->>'q510' <> 'não houve'
)
select coalesce(respostas->>'q510','(em branco)') as emissao,
       count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from base),0), 1) as pct
from base group by 1 order by n desc;

comment on view public.v_receita_saude is
  'H4. Denominador: quem recebeu no CPF nos últimos 30 dias e teve recebimento '
  'no período. "quem emite é o contador" NÃO é descumprimento — a Receita '
  'admite emissão por representante autorizado.';

create or replace view public.v_ritmo_recibo as
with base as (
  select respostas from public.pesquisa_respostas
  where respostas->>'q510' in ('todos','alguns')
)
select coalesce(respostas->>'q514','(em branco)') as quando_emite,
       count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from base),0), 1) as pct
from base group by 1 order by n desc;

comment on view public.v_ritmo_recibo is
  'Decide o default de contas.ritmo_recibo, hoje "mensal" por suposição. '
  'Moda "na data do pagamento" -> o cartão do minuto é a peça principal. '
  'Moda "depois do fim do mês" -> o CSV do lote é o produto. '
  'A obrigação é per-sessão desde 2025 e a emissão em lote existe desde '
  'novembro/2025; qual dos dois ritmos a categoria pratica é o que falta saber.';

create or replace view public.v_lote_recibo as
with base as (
  select respostas from public.pesquisa_respostas
  where respostas->>'q510' in ('todos','alguns')
)
select coalesce(respostas->>'q515','(em branco)') as por_vez,
       count(*) as n
from base group by 1 order by n desc;

create or replace view public.v_nota_fiscal_pj as
with base as (
  select respostas from public.pesquisa_respostas
  where respostas->>'q27' in ('CNPJ','os dois')
    and respostas->>'q521' is not null
    and respostas->>'q521' <> 'não houve'
)
select coalesce(respostas->>'q521','(em branco)') as emissao_nfse,
       count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from base),0), 1) as pct
from base group by 1 order by n desc;

comment on view public.v_nota_fiscal_pj is
  'A realidade fiscal de quem recebe no CNPJ, que o instrumento não media. '
  'Não entra na H4 — a H4 é sobre o Receita Saúde, que é obrigação de pessoa '
  'física. Esta é descritiva, e é a primeira medida do gênero na categoria.';

create or replace view public.v_ritmo_x_tempo_fiscal as
select coalesce(respostas->>'q514','(em branco)') as quando_emite,
       coalesce(respostas->>'q511','(em branco)') as tempo_fiscal_mes,
       count(*) as n
from public.pesquisa_respostas
where respostas->>'q510' in ('todos','alguns')
group by 1,2 order by 1, 3 desc;

comment on view public.v_ritmo_x_tempo_fiscal is
  'O cruzamento que decide se a feature se paga: quem emite na data do '
  'pagamento gasta MAIS tempo por mês do que quem junta? Se não gastar, o '
  'cartão do minuto não está resolvendo custo nenhum.';

-- ===========================================================================
-- Demanda não atendida
-- ===========================================================================
create or replace view public.v_procura_sem_horario as
select coalesce(respostas->>'q41f','(em branco)') as frequencia,
       count(*) as n
from public.pesquisa_respostas group by 1 order by n desc;

create or replace view public.v_destino_demanda as
select d.valor as destino, count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas
                                        where respostas ? 'q49'),0), 1) as pct
from public.pesquisa_respostas r
cross join lateral jsonb_array_elements_text(r.respostas->'q49') as d(valor)
where r.respostas ? 'q49'
group by d.valor order by n desc;

comment on view public.v_destino_demanda is
  'Objetivo 7 do protocolo. O encaminhamento para colega foi nomeado por uma '
  'respondente do piloto como o destino comum, e não existia no instrumento: '
  'mediávamos a lista de espera sem medir a alternativa a ela.';

-- ===========================================================================
-- Antecipação, regularização, textos abertos e operação
-- ===========================================================================
create or replace view public.v_antecipacao as
select coalesce(respostas->>'q512','(em branco)') as pratica,
       count(*) as n,
       round(100.0 * count(*) / nullif((select count(*) from public.pesquisa_respostas),0), 1) as pct
from public.pesquisa_respostas group by 1 order by n desc;

create or replace view public.v_regularizacao as
select d.valor as duvida, count(*) as n
from public.pesquisa_respostas r
cross join lateral jsonb_array_elements_text(r.respostas->'q69') as d(valor)
where r.respostas ? 'q69'
group by d.valor order by n desc;

create or replace view public.v_nao_se_aplica_textos as
select criado_em, canal_url,
       respostas->>'q43_como' as q43_como,
       respostas->>'q44_como' as q44_como,
       respostas->>'q51_como' as q51_como
from public.pesquisa_respostas
where coalesce(respostas->>'q43_como','') <> ''
   or coalesce(respostas->>'q44_como','') <> ''
   or coalesce(respostas->>'q51_como','') <> ''
order by criado_em;

comment on view public.v_nao_se_aplica_textos is
  'Material aberto. Entra na codificação da etapa 1 do plano de análise, junto '
  'com o bloco 1 e o texto do item residual — antes de qualquer ranking.';

create or replace view public.v_duracao_real as
select
  count(*) as n,
  round((percentile_cont(0.5) within group (order by duracao_seg::double precision)/60.0)::numeric, 1) as mediana_min,
  round((percentile_cont(0.25) within group (order by duracao_seg::double precision)/60.0)::numeric, 1) as p25_min,
  round((percentile_cont(0.75) within group (order by duracao_seg::double precision)/60.0)::numeric, 1) as p75_min
from public.pesquisa_respostas
where duracao_seg between 120 and 7200;

comment on view public.v_duracao_real is
  'O número que corrige o tempo declarado em todas as peças. O declarado hoje é '
  '"cerca de 15 minutos" e é provisório: a primeira respondente real levou 17,9 '
  'minutos, dos quais 8,5 nos blocos 0 e 1. Metade do tempo está nas quatro '
  'abertas, que são o coração do desenho e não se cortam.';

-- ===========================================================================
-- A trava. View nova nasce aberta: security_invoker off e grant do anon.
-- Sem estas duas linhas, qualquer pessoa com a chave publishable lê os textos.
-- ===========================================================================
do $$
declare v text;
begin
  foreach v in array array[
    'v_leitura1_fila','v_leitura3_cobranca','v_credito_na_remarcacao','v_conjuncao',
    'v_ocupacao','v_administracao_terceiro','v_via_terceiro','v_fluxo_pagamento',
    'v_receita_saude','v_ritmo_recibo','v_lote_recibo','v_nota_fiscal_pj',
    'v_ritmo_x_tempo_fiscal','v_procura_sem_horario','v_destino_demanda',
    'v_antecipacao','v_regularizacao','v_nao_se_aplica_textos','v_duracao_real'
  ] loop
    execute format('alter view public.%I set (security_invoker = on)', v);
    execute format('revoke all on public.%I from anon, authenticated', v);
  end loop;
end $$;

-- As views da 0044b que liam campos aposentados e não têm substituta aqui
-- ficam existindo e devolvendo vazio. Não são apagadas de propósito: apagar
-- view é irreversível na migration e o custo de uma view vazia é zero.
