-- 0096 · B54 · A lista mostra que o recibo existe, e não entrega a chave dele
--
-- O QUE ACONTECEU
--
-- A 0095 pôs a linha do mês na página do paciente e a suíte **0066** reprovou:
-- a verificação 12 dela diz, desde o P7, que *"o recibo de duzentos dias atrás
-- não aparece — recibo velho ele pede a ela, como sempre pediu"*. E aparecia:
-- `linhas_do_mes` devolve o **id** do documento que cobre o mês, inclusive o
-- que está fora da janela de 90 dias.
--
-- O id sozinho não abre nada — `documento_do_link` continua recusando, e a
-- suíte 0095 prova isso nos dois sentidos. Mas um id numa página de portador é
-- metade de uma URL, e a outra metade é pública. A defesa passaria a ser só a
-- checagem de data dentro de uma função; hoje são duas, e a segunda é não ter
-- o número.
--
-- **E o §5.5 da estratégia do canal previu exatamente isto.** Ele diz que o
-- repositório permanente muda o perfil de risco do link, e que a porta merece
-- fechadura — código de seis dígitos por e-mail. A fechadura não existe: não há
-- adaptador de e-mail neste produto. Eu entreguei a metade que amplia a
-- exposição e deixei de fora a metade que a compensa. Esta migração desfaz a
-- ampliação em vez de fingir que ela é pequena.
--
-- O QUE MUDA
--
-- `linhas_do_mes` ganha `p_so_na_janela`, e **ele nasce ligado**. Com ele, o
-- `recibo` e o `recibo_numero` do documento fora da janela saem **nulos**. O
-- `recibo_em` fica: a pessoa continua sabendo que o recibo de março existe e
-- continua sabendo pedi-lo. É o que a 0066 chama de "pede a ela", e é o que a
-- lista do §5.5 tem de fazer enquanto não há fechadura.
--
-- **O padrão é o lado fechado, e é decisão.** `pagina_do_paciente` não precisou
-- ser reescrita: ela chama com dois argumentos e recebe o recorte seguro de
-- graça. Quem quer o id **pede** — e há um lugar só que pede, com o motivo
-- escrito ao lado. Se um dia alguém acrescentar uma terceira leitura e esquecer
-- do assunto, ela nasce fechada; o defeito de hoje é exatamente o contrário
-- disso, e nasceu de um `default` que abria.
--
-- A TELA DELA NÃO MUDA
--
-- `meses_do_paciente` passa `false` explicitamente: ela abre o recibo de março
-- pela ficha, com a RLS da conta. As duas leituras continuam somando **o mesmo
-- dinheiro** — a verificação 1 da suíte 0095 passou a comparar as duas
-- ignorando o id do documento, que é a única coisa que pode diferir, e a 1b
-- passou a exigir que a página do paciente nunca carregue um id fora da
-- janela.

create or replace function public.linhas_do_mes(
  p_paciente uuid,
  p_limite int default 12,
  p_so_na_janela boolean default true
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with comp as (
    -- A competência existe se houve dinheiro combinado nela **ou** documento
    -- emitido sobre ela. Cobrança cancelada não cria mês: ela é o combinado que
    -- deixou de existir, e um mês que só tem cancelamento não aconteceu.
    select distinct date_trunc('month', cb.competencia)::date as mes
      from public.cobrancas cb
     where cb.paciente_id = p_paciente
       and cb.estado <> 'cancelada'
       and cb.competencia is not null
    union
    select distinct date_trunc('month', dc.periodo_de)::date
      from public.documentos dc
     where dc.paciente_id = p_paciente
       and dc.cancelado_em is null
  ),
  ultimos as (
    select mes from comp order by mes desc limit greatest(coalesce(p_limite, 12), 1)
  ),
  dinheiro as (
    select
      u.mes,
      coalesce(sum(cb.valor), 0)                                          as combinado,
      count(cb.id)                                                        as quantos,
      coalesce(sum(cb.valor) filter (where cb.estado = 'aberta'), 0)      as aberto,
      coalesce(sum(cb.valor) filter (where cb.estado = 'paga'), 0)        as pago,
      coalesce(sum(cb.valor) filter (where cb.estado = 'perdoada'), 0)    as perdoado,
      max(cb.paga_em) filter (where cb.estado = 'paga')                   as pago_em
    from ultimos u
    left join public.cobrancas cb
      on cb.paciente_id = p_paciente
     and cb.estado <> 'cancelada'
     and date_trunc('month', cb.competencia)::date = u.mes
    group by u.mes
  ),
  papel as (
    select
      u.mes,
      dc.id         as recibo,
      dc.numero     as recibo_numero,
      dc.emitido_em as recibo_em,
      -- A janela da 0066, lida aqui e não reimplementada na tela: quem decide
      -- se o link serve o documento é `documento_do_link`, e esta coluna só
      -- **antecipa** a resposta dela para a lista não oferecer o que a porta
      -- recusa. Se as duas discordarem um dia, é aqui que se conserta.
      (dc.emitido_em > now() - interval '90 days') as recibo_na_janela
    from ultimos u
    left join lateral (
      select d.id, d.numero, d.emitido_em
        from public.documentos d
       where d.paciente_id = p_paciente
         and d.tipo = 'recibo'
         and d.cancelado_em is null
         -- Sobreposição, não igualdade: o recibo de 01/07 a 30/09 cobre os três
         -- meses, e é assim que um informe trimestral aparece nos três.
         and d.periodo_de  <= (u.mes + interval '1 month' - interval '1 day')::date
         and d.periodo_ate >= u.mes
       order by d.emitido_em desc
       limit 1
    ) dc on true
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'competencia',      d.mes,
             'combinado',        d.combinado,
             'quantos',          d.quantos,
             'aberto',           d.aberto,
             'pago',             d.pago,
             'perdoado',         d.perdoado,
             'pago_em',          d.pago_em,
             -- O id e o número só saem quando há porta para eles. Fora da
             -- janela, quem lê pela página sabe que o recibo existe (por
             -- `recibo_em`) e não recebe o endereço dele. É o padrão: quem
             -- quiser o id passa `p_so_na_janela => false` e assina embaixo.
             'recibo',           case when p_so_na_janela and not coalesce(p.recibo_na_janela, false)
                                      then null else p.recibo end,
             'recibo_numero',    case when p_so_na_janela and not coalesce(p.recibo_na_janela, false)
                                      then null else p.recibo_numero end,
             'recibo_em',        p.recibo_em,
             'recibo_na_janela', coalesce(p.recibo_na_janela, false)
           ) order by d.mes desc
         ), '[]'::jsonb)
    from dinheiro d
    join papel p on p.mes = d.mes;
$function$;

-- A assinatura antiga (dois argumentos) desaparece: o `default` da terceira faz
-- `linhas_do_mes(p, 12)` continuar válido, e deixar as duas vivas seria a
-- sobrecarga que engole a chamada errada em silêncio — o defeito da 0052b.
drop function if exists public.linhas_do_mes(uuid, int);

revoke all on function public.linhas_do_mes(uuid, int, boolean) from public, anon;
grant execute on function public.linhas_do_mes(uuid, int, boolean) to authenticated, service_role;

comment on function public.linhas_do_mes(uuid, int, boolean) is
  'A linha do mes por competencia. Com p_so_na_janela, o id e o numero do recibo fora dos 90 dias saem nulos — a pagina do paciente mostra que o recibo existe sem entregar o endereco dele. Fonte unica das duas telas.';

create or replace function public.meses_do_paciente(p_paciente uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select public.linhas_do_mes(p_paciente, 12, false);
$function$;

comment on function public.meses_do_paciente(uuid) is
  'A linha do mes na tela dela — com os ids, porque ela abre o recibo antigo pela ficha, com a RLS da conta. Mesma funcao que a pagina do paciente le, com a janela desligada.';
