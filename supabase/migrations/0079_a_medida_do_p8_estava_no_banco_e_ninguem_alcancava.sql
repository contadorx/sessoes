-- 0079 · A medida do P8 estava no banco, e ninguém alcançava.
--
-- A 0067 criou `telemetria_do_receita_saude()` e escreveu, no comentário da
-- própria função, para que ela servia:
--
--     "Mede o PRODUTO, nao a pessoa. E o instrumento do portao escrito no
--      claude/25 — se a mediana de dias ate a baixa nao cair, o cartao nao
--      serviu e ele e candidato a sumir."
--
-- E o cabeçalho da 0067 foi mais longe: *"uma feature que não carrega consigo
-- o que a mediria é uma feature que ninguém desliga depois"*.
--
-- Só que a função nasceu **presa a `conta_atual()`** e liberada para
-- `authenticated`. Duas consequências, e as duas anulam o que ela existia para
-- fazer:
--
--   1. **Quem precisa do número não consegue lê-lo.** A pergunta é "o cartão
--      serviu?", e ela é minha. Para respondê-la com uma função por conta eu
--      teria de entrar na conta de cada uma — impersonação, que o `CLAUDE.md`
--      §4 proíbe *"em qualquer forma"*. O instrumento existia e era inalcançável
--      justamente por quem ia usá-lo.
--
--   2. **Três dos quatro números dela já existiam em outro lugar.**
--      `receita_saude_do_ano()` devolve `pendentes`, `emitidos` e o resto, e é
--      ela que a tela do P8 lê. Duas funções respondendo à mesma pergunta com
--      recortes diferentes (uma por ano, outra por tudo) é a **segunda fonte de
--      verdade** do §9 esperando alguém comparar os dois números.
--
-- Sobrava um número só que era dela sozinha: a mediana de dias entre o
-- pagamento e a baixa. E esse, mostrado para a psicóloga, seria uma medida do
-- atraso **dela** sem nenhuma ação atrelada — o oposto do
-- `resumo_do_envio_manual` da OP9, cuja mediana existe porque diz quanto tempo
-- a vaga ficou parada e o que fazer a respeito.
--
-- Então a função sai, e entra a que responde à pergunta de verdade.
--
-- ## `receita_saude_do_painel()`
--
-- Mesmo desenho de `painel_do_negocio`, `contas_do_painel` e
-- `retencao_do_painel`: `security definer`, `e_operador()` conferido por
-- dentro, sem `conta_id` por parâmetro, e **`not is_teste`**.
--
-- O `is_teste` não é detalhe. Hoje a conta de demonstração tem 72 recibos e as
-- contas reais têm seis no total: uma mediana que somasse as duas me diria que
-- o cartão funciona com base em dado que eu mesmo plantei. O escopo é quem a
-- P8 serve — **PF com o modo ligado** —, o que também tira a conta PJ, para
-- quem o cartão não existe.
--
-- E o que não tem amostra volta **nulo, não zero**, pela mesma razão que o LTV
-- da 0045 volta nulo com churn zero: *"«∞» numa tela dá confiança em vez de dar
-- informação"*. Com uma conta tendo marcado um recibo, a mediana é um número
-- que parece medida e não é.
--
-- A função não dá veredito. Ela devolve os números e o tamanho da amostra; se
-- o cartão serviu é decisão minha, e decisão de produto não se delega para um
-- `case when` no banco.
--
-- **Nada de paciente, nada de sessão.** Contagens e uma mediana de dias, e é a
-- fronteira 9 cumprida onde ela tem de ser cumprida: aqui dentro.

drop function if exists public.telemetria_do_receita_saude();

create or replace function public.receita_saude_do_painel()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_contas            integer := 0;
  v_com_recibo        integer := 0;
  v_que_marcaram      integer := 0;
  v_dias              numeric;
  v_marcados          integer := 0;
  v_pendentes         integer := 0;
  v_anos_anteriores   integer := 0;
begin
  if not public.e_operador() then
    raise exception 'só o operador da plataforma vê a medida do Receita Saúde';
  end if;

  select count(*)::integer into v_contas
    from public.contas c
   where not c.is_teste
     and coalesce(c.regime, 'pf') = 'pf'
     and coalesce(c.receita_saude, false);

  select
    count(distinct r.conta_id) filter (where true)::integer,
    count(distinct r.conta_id) filter (where r.marcado_por_ela_em is not null)::integer,
    count(*) filter (where r.estado = 'marcado_por_ela')::integer,
    count(*) filter (where r.estado = 'pendente')::integer,
    count(*) filter (
      where r.estado = 'pendente'
        and extract(year from r.competencia)::int
            < extract(year from public.hoje_sp())::int
    )::integer,
    percentile_cont(0.5) within group (
      order by (r.marcado_por_ela_em - r.pago_em)
    ) filter (
      where r.estado = 'marcado_por_ela' and r.marcado_por_ela_em is not null
    )
    into v_com_recibo, v_que_marcaram, v_marcados, v_pendentes,
         v_anos_anteriores, v_dias
    from public.recibos_rfb r
    join public.contas c on c.id = r.conta_id
   where not c.is_teste
     and coalesce(c.regime, 'pf') = 'pf'
     and coalesce(c.receita_saude, false);

  return jsonb_build_object(
    'contas', v_contas,
    'contas_com_recibo', coalesce(v_com_recibo, 0),
    'contas_que_marcaram', coalesce(v_que_marcaram, 0),
    -- Nulo quando ninguém marcou nada: zero dia seria a afirmação de que a
    -- baixa é instantânea. Mesma escolha da mediana do `resumo_do_envio_manual`
    -- da OP9 e do LTV da 0045.
    'dias_ate_a_baixa', v_dias,
    'marcados', coalesce(v_marcados, 0),
    'pendentes', coalesce(v_pendentes, 0),
    -- Pendência que atravessa o ano é a que vira multa: o prazo é o último dia
    -- de fevereiro do ano seguinte, e quem chegou a janeiro sem lançar tem um
    -- mês para lançar um ano inteiro.
    'pendentes_de_anos_anteriores', coalesce(v_anos_anteriores, 0)
  );
end;
$$;

comment on function public.receita_saude_do_painel() is
  'P8, do lado do operador. Mede o PRODUTO, nao a pessoa: contagens e uma mediana de dias, nenhum paciente, nenhuma sessao. Substitui telemetria_do_receita_saude(), que media a mesma coisa presa a conta_atual() — inalcancavel para quem precisa do numero, e segunda fonte de verdade dos numeros de receita_saude_do_ano(). Exclui conta de teste: a de demonstracao tem mais recibos que todas as reais somadas.';

-- `revoke ... from public` primeiro, e não `from anon`: em Postgres o `EXECUTE`
-- de função nova nasce em `PUBLIC`, e revogar de `anon` não tira nada. Foi o
-- que a 0075 aprendeu e a 0076 teve de consertar depois.
revoke all on function public.receita_saude_do_painel() from public, anon;
grant execute on function public.receita_saude_do_painel() to authenticated, service_role;
