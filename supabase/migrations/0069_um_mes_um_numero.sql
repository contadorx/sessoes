-- 0069 · Um mês, um número.
--
-- Quatro funções respondem "quanto entrou neste mês" e duas discordavam sem que
-- nenhuma tela dissesse por quê. Segunda fonte de verdade sobre dinheiro é S1
-- automático neste projeto, e a razão não é purismo: se ela vir dois números que
-- não batem, o produto perdeu a discussão que ele existe para ganhar.
--
-- **Os dois corpos abaixo foram lidos do BANCO (`pg_get_functiondef`), não das
-- migrações que os criaram.** A lei 6, e ela não é cerimônia: `livro_razao`
-- nasceu na 0056 e foi tocada por 0056b–e e pelo P5; o que está aqui é a
-- definição viva de 02/09, com o filtro acrescentado, e não a de origem com as
-- correções de meio de caminho perdidas — que foi exatamente como a 0060d
-- perdeu o `enfileirar_mensagem` de `avancar_fila`.
--
-- ============================================================================
-- 1 · `livro_razao` passa a ignorar o histórico importado
-- ============================================================================
--
-- `financeiro_do_mes` filtra `s.origem <> 'importada'` desde a 0040b, com a
-- razão escrita lá: *"uma planilha com dois anos despejaria dezenas de milhares
-- de reais em meses fechados"*. A decisão está certa. Ela só não foi aplicada na
-- segunda função — e o `cockpit_do_mes`, que herda do livro, carregava a
-- divergência para os quatro números da primeira tela.
--
-- O sintoma: rodar o passo 2 do onboarding com dois meses de histórico, abrir
-- `/fechamento/livro` e `/recebimentos/movimentacoes` no mesmo mês. O primeiro
-- mostra receita reconhecida; o segundo mostra R$ 0,00. Nenhuma das duas
-- explica, e não há como ela saber qual está certa.
--
-- **O filtro entra nas oito consultas, não só nas de dinheiro.** É a decisão
-- desta migração, e vale explicar: o livro responde "o que aconteceu com cada
-- hora", e o cockpit divide receita por capacidade. Filtrar só o dinheiro
-- deixaria um mês importado com as horas cheias e a receita zerada — "você
-- trabalhou oitenta horas e não ganhou nada", que é pior que qualquer um dos
-- dois números sozinho, e seria uma **terceira** versão do mesmo mês. Um mês
-- anterior ao uso do produto aparece vazio nas duas telas, e as duas concordam.
--
-- Isto não apaga nada: as sessões importadas continuam na ficha da paciente,
-- que é para onde a importação existe. O que sai é a contabilidade delas.
--
-- Hoje a produção tem zero sessões `importada` — o conserto é anterior à
-- primeira conta que usar o passo 2 do onboarding, e é de propósito.

create or replace function public.livro_razao(p_profissional uuid, p_de date, p_ate date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  cap            jsonb;
  min_usados     integer := 0;
  horas          jsonb;
  reconhecida    numeric := 0;
  falta_sem      numeric := 0;  falta_sem_n      integer := 0;
  falta_com      numeric := 0;  falta_com_n      integer := 0;
  cancel_perdida numeric := 0;  cancel_perdida_n integer := 0;
  reposta_v      numeric := 0;  reposta_n        integer := 0;
  nao_recebida   numeric := 0;  nao_recebida_n   integer := 0;
  abaixo         numeric := 0;  abaixo_n         integer := 0;
begin
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  cap := public.capacidade_vendavel(p_profissional, p_de, p_ate);

  -- ------------------------------------------------------------- os eixos
  select jsonb_object_agg(eixo, n), coalesce(sum(minutos) filter (where eixo <> 'cancelada'), 0)
    into horas, min_usados
    from (
      select public.eixo_agenda(s.estado) as eixo,
             count(*) as n,
             sum((extract(epoch from (s.fim - s.inicio)) / 60))::integer as minutos
        from public.sessoes s
       where s.profissional_id = p_profissional
         and s.origem <> 'importada'
         and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
       group by 1
    ) g;

  -- ------------------------------------------------- a receita reconhecida
  select coalesce(sum(s.valor_reconhecido), 0)
    into reconhecida
    from public.sessoes s
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ------------------------------------------------------------- as causas
  --
  -- 1 · falta sem cobrança: atendeu não, cobrou não.
  select coalesce(sum(s.valor), 0), count(*) into falta_sem, falta_sem_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'falta'
     and s.eixo_financeiro in ('nao_cobrada', 'perdoada');

  -- 2 · falta com cobrança: recebeu, perdeu a hora. Não é perda de dinheiro —
  --     é a política funcionando. Aparece com o valor recuperado ao lado.
  select coalesce(sum(c.valor), 0), count(*) into falta_com, falta_com_n
    from public.sessoes s
    join public.cobrancas c on c.sessao_id = s.id and c.estado = 'paga'
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'falta';

  -- 3 · cancelada com antecedência e não reocupada.
  select coalesce(sum(s.valor), 0), count(*) into cancel_perdida, cancel_perdida_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado in ('cancelada_cedo', 'cancelada_tarde')
     and s.eixo_capacidade = 'perdida';

  -- 4 · reposta: duas horas, uma receita. O valor é o da hora que se perdeu.
  select coalesce(sum(s.valor), 0), count(*) into reposta_v, reposta_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.eixo_capacidade = 'reposta';

  -- 5 · atendida e não recebida: inadimplência.
  select coalesce(sum(s.valor), 0), count(*) into nao_recebida, nao_recebida_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'realizada'
     and s.eixo_financeiro = 'cobrada';

  -- 6 · recebida abaixo do combinado: convênio, plataforma, desconto.
  select coalesce(sum(s.valor - c.valor), 0), count(*) into abaixo, abaixo_n
    from public.sessoes s
    join public.cobrancas c on c.sessao_id = s.id and c.estado = 'paga'
   where s.profissional_id = p_profissional
     and s.origem <> 'importada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'realizada'
     and c.valor < s.valor;

  return jsonb_build_object(
    'de', p_de,
    'ate', p_ate,
    'capacidade', cap,
    'horas', coalesce(horas, '{}'::jsonb),
    'minutos_usados', min_usados,
    'receita_reconhecida', reconhecida,
    'causas', jsonb_build_array(
      jsonb_build_object('causa', 'falta_sem_cobranca', 'n', falta_sem_n, 'valor', falta_sem, 'acao', 'propor_cobranca'),
      jsonb_build_object('causa', 'falta_com_cobranca', 'n', falta_com_n, 'valor', falta_com, 'acao', null),
      jsonb_build_object('causa', 'cancelada_nao_revendida', 'n', cancel_perdida_n, 'valor', cancel_perdida, 'acao', 'ver_ofertas'),
      jsonb_build_object('causa', 'reposta', 'n', reposta_n, 'valor', reposta_v, 'acao', 'rever_politica'),
      jsonb_build_object('causa', 'atendida_nao_recebida', 'n', nao_recebida_n, 'valor', nao_recebida, 'acao', 'regua'),
      jsonb_build_object('causa', 'abaixo_do_valor', 'n', abaixo_n, 'valor', abaixo, 'acao', 'ver_contrato'),
      -- A sétima não tem ação, e é deliberado.
      jsonb_build_object(
        'causa', 'hora_nunca_vendida',
        'n', null,
        'minutos', greatest(0, (cap->>'vendavel_min')::integer - min_usados),
        'valor', null,
        'acao', null
      )
    ),
    'completude', public.completude_dos_eixos(p_de, p_ate)
  );
end;
$function$;

-- ============================================================================
-- 2 · `retorno` volta a falar só do que a fila e a política recuperaram
-- ============================================================================
--
-- A CTE `dinheiro` somava `public.cobrancas` sem nenhum filtro de tipo, e o
-- check da tabela é `tipo in ('falta', 'sessao', 'mensalidade', 'pacote')`.
-- Numa conta de mensalistas, o número em serifa de 26 px no alto da agenda era
-- **o faturamento do mês inteiro**, embaixo da frase "que não teria entrado sem
-- a fila e sem a política".
--
-- É a única frase do produto que fazia afirmação contrafactual sobre o dinheiro
-- dela — parente próxima do simulador de ROI que foi morto por decisão, e pior
-- que ele, porque o simulador dizia "se" e este diz "foi".
--
-- O cabeçalho da 0025 já descrevia a coisa certa: *"recebido — a cobrança de
-- cancelamento tardio que ela marcou como paga"*. E o padrão correto já existe
-- na função irmã: `financeiro_do_mes` filtra `cb.tipo = 'falta'` no bloco
-- `recuperado`. Era a mesma cláusula, faltando num lugar só.
--
-- `valor_preenchido` não muda: ele vem da CTE `encaixes`, que já conta só
-- sessão de origem `encaixe` ocupando o horário de uma vaga cancelada.

create or replace function public.retorno(p_de date, p_ate date)
returns table(
  canceladas bigint, oferecidas bigint, preenchidas bigint, taxa numeric,
  valor_preenchido numeric, valor_recebido numeric, valor_em_aberto numeric,
  valor_perdoado numeric, horas_recuperadas numeric
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
  encaixes as (
    select v.id as vaga, v.inicio, v.fim,
           (select e.valor
              from public.sessoes e
             where e.origem = 'encaixe' and e.inicio = v.inicio
               and e.estado not in ('cancelada_cedo', 'cancelada_tarde')
             limit 1) as valor
      from vagas v
     where v.oferta_aceita is not null
  ),
  dinheiro as (
    select
      coalesce(sum(c.valor) filter (where c.estado = 'paga'), 0)     as recebido,
      coalesce(sum(c.valor) filter (where c.estado = 'aberta'), 0)   as em_aberto,
      coalesce(sum(c.valor) filter (where c.estado = 'perdoada'), 0) as perdoado
      from public.cobrancas c
     -- A cláusula que faltava. Sem ela, mensalidade e pacote entravam num
     -- número que a tela apresenta como ganho da fila.
     where c.tipo = 'falta'
       and c.competencia between date_trunc('month', p_de)::date
                             and date_trunc('month', p_ate)::date
  )
  select
    (select count(*) from vagas),
    (select count(*) from vagas where teve_oferta),
    (select count(*) from vagas where oferta_aceita is not null),
    case when (select count(*) from vagas) = 0 then null
         else round(100.0 * (select count(*) from vagas where teve_oferta)
                    / (select count(*) from vagas), 1) end,
    coalesce((select sum(valor) from encaixes), 0),
    (select recebido from dinheiro),
    (select em_aberto from dinheiro),
    (select perdoado from dinheiro),
    coalesce((select sum(extract(epoch from (fim - inicio)) / 3600.0) from encaixes), 0);
$function$;

comment on function public.livro_razao(uuid, date, date) is
  'O que aconteceu com cada hora do periodo. Ignora sessao de origem importada, como financeiro_do_mes faz desde a 0040b: historico colado nao vira receita de mes fechado.';

comment on function public.retorno(date, date) is
  'O que a fila e a politica recuperaram. So cobranca de tipo falta entra no dinheiro — mensalidade e pacote sao faturamento, nao retorno.';
