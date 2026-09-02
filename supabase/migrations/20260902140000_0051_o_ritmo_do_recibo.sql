-- 0051 · o ritmo do recibo
--
-- Duas views para os itens Q5.14 (frequência de emissão) e Q5.15 (quantos de
-- uma vez), acrescentados na revisão 4 do instrumento.
--
-- Elas existem para decidir UM valor de código: o default de
-- contas.ritmo_recibo, hoje 'mensal' por suposição. E existem para decidir se
-- o cartão de emissão do minuto se constrói ou não.
--
-- O portão está escrito no doc 25 e é reproduzido aqui para que quem ler a
-- view saiba o que a resposta obriga:
--
--   modal 'a cada atendimento'  -> o cartão do minuto é a peça principal,
--                                  o CSV do lote vira exceção de fim de mês
--   modal 'semanal' ou 'mensal' -> o CSV é o produto, o cartão é conveniência
--   modal 'fevereiro'           -> o produto é o ALARME, e ele começa em
--                                  novembro; em fevereiro já é retroativo com
--                                  multa correndo
--   modal 'contador'            -> o destinatário do documento não é a
--                                  Receita, é o contador
--
-- Denominador: só quem declarou emitir na Q5.10 ('sempre' ou 'quando pedem')
-- vê estes itens. Quem não emite já foi classificado pela própria Q5.10, e
-- perguntar ritmo a ela produziria categoria sem comportamento por trás.

create or replace view public.v_ritmo_recibo as
with base as (
  select respostas
  from public.pesquisa_respostas
  where respostas->>'q510' in ('sempre', 'quando pedem')
)
select
  coalesce(respostas->>'q514', '(em branco)')          as ritmo,
  count(*)                                             as n,
  round(100.0 * count(*) / nullif((select count(*) from base), 0), 1) as pct
from base
group by 1
order by n desc;

comment on view public.v_ritmo_recibo is
  'Decide o default de contas.ritmo_recibo. Hoje o código assume mensal sem '
  'dado. A moda desta view substitui a suposição — e o doc 25 diz o que cada '
  'moda faz encolher ou crescer no P8.';

create or replace view public.v_lote_recibo as
with base as (
  select respostas
  from public.pesquisa_respostas
  where respostas->>'q510' in ('sempre', 'quando pedem')
)
select
  coalesce(respostas->>'q515', '(em branco)')          as por_vez,
  count(*)                                             as n,
  round(100.0 * count(*) / nullif((select count(*) from base), 0), 1) as pct
from base
group by 1
order by n desc;

comment on view public.v_lote_recibo is
  'Tamanho do lote real. O limite de mil linhas do CSV do Carne-Leao nunca vai '
  'ser atingido; o que esta view decide e outra coisa — se emitir em lote e '
  'uma pratica que ja existe ou uma que o produto teria de ensinar.';

-- O cruzamento que interessa de verdade: quem emite a cada atendimento gasta
-- mais tempo por mes com a parte fiscal do que quem junta? Se não gastar, o
-- cartão do minuto não está resolvendo custo nenhum.
create or replace view public.v_ritmo_x_tempo_fiscal as
select
  coalesce(respostas->>'q514', '(em branco)')          as ritmo,
  coalesce(respostas->>'q511', '(em branco)')          as tempo_fiscal_mes,
  count(*)                                             as n
from public.pesquisa_respostas
where respostas->>'q510' in ('sempre', 'quando pedem')
group by 1, 2
order by 1, 3 desc;

-- A trava. View nova nasce aberta.
do $$
declare v text;
begin
  foreach v in array array[
    'v_ritmo_recibo','v_lote_recibo','v_ritmo_x_tempo_fiscal'
  ] loop
    execute format('alter view public.%I set (security_invoker = on)', v);
    execute format('revoke all on public.%I from anon, authenticated', v);
  end loop;
end $$;
