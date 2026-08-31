-- 0025 · B14 — o retorno e o começo.
--
-- Duas funções, e as duas existem para responder perguntas que a psicóloga faz
-- sozinha, em voz baixa: *"por onde eu começo?"* e *"isto está valendo a pena?"*.
--
-- ## Sobre o número do retorno
--
-- A tentação óbvia aqui é somar tudo e mostrar um número grande. É também a
-- forma mais rápida de perder a cliente: ela vai conferir contra o extrato, a
-- conta não vai bater, e a partir daí nenhum número desta tela é acreditado de
-- novo. Um painel de ROI que infla não é otimista — é um painel que se
-- autodestrói no primeiro mês.
--
-- Então o retorno vem **separado em três**, e só o primeiro par é dinheiro:
--
--   · **preenchido** — a vaga que ia ficar vazia e não ficou. Este é o dinheiro
--     que só existe por causa da fila; sem ela, aquela hora era zero;
--   · **recebido** — a cobrança de cancelamento tardio que ela marcou como paga;
--   · **em aberto** — cobrado e ainda não pago. **Não é dinheiro.** Aparece em
--     separado, e nunca somado ao resto.
--
-- E mais um, que não é receita e é o que mais importa para quem duvida da
-- própria firmeza: **perdoado**. Quantas vezes ela abriu mão. Sem julgamento,
-- sem alerta — só o fato, que ela nunca teve como ver.

/**
 * O retorno do período.
 *
 * `p_de` e `p_ate` são datas civis de São Paulo, inclusivas.
 */
create or replace function public.retorno(p_de date, p_ate date)
returns table (
  canceladas          bigint,
  oferecidas          bigint,
  preenchidas         bigint,
  taxa                numeric,
  valor_preenchido    numeric,
  valor_recebido      numeric,
  valor_em_aberto     numeric,
  valor_perdoado      numeric,
  horas_recuperadas   numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with vagas as (
    select s.id, s.inicio, s.fim,
           exists (select 1 from public.ofertas o where o.sessao_id = s.id) as teve_oferta,
           (select o.id from public.ofertas o
             where o.sessao_id = s.id and o.estado = 'aceita' limit 1) as oferta_aceita
      from public.sessoes s
     where s.estado in ('cancelada_cedo', 'cancelada_tarde')
       and (s.cancelada_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
  ),
  -- O encaixe que nasceu de cada vaga aceita. É o valor **do paciente que
  -- entrou**, não o da sessão cancelada: quem entra paga o próprio combinado.
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
     where c.competencia between date_trunc('month', p_de)::date
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
$$;

/**
 * Por onde começar.
 *
 * Devolve o estado real da conta — não uma lista de tarefas marcada à mão. A
 * diferença importa: um checklist que a pessoa marca sozinha vira mentira na
 * primeira distração, e aí a tela passa a dizer "tudo pronto" para quem não
 * consegue preencher a primeira vaga.
 *
 * Aqui cada passo é uma pergunta ao banco. Se a resposta mudar — ela apagar o
 * único paciente, por exemplo — o começo reaparece sozinho.
 */
create or replace function public.estado_inicial()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pacientes',   (select count(*) from public.pacientes where estado <> 'arquivado'),
    'enquadres',   (select count(*) from public.enquadres where vigencia_fim is null),
    'sessoes',     (select count(*) from public.sessoes
                     where inicio >= now() and estado in ('prevista', 'confirmada')),
    'na_fila',     (select count(*) from public.fila_encaixe),
    'com_canal',   (select count(*) from public.pacientes
                     where estado <> 'arquivado' and msg_canal <> 'nao_avisar'
                       and (telefone is not null or email is not null)),
    'politica_definida', exists (
      select 1 from public.enquadres
       where vigencia_fim is null and politica_percentual > 0
    ),
    'vagas_abertas', (select count(*) from public.ofertas),
    'preenchidas',   (select count(*) from public.ofertas where estado = 'aceita')
  );
$$;

revoke execute on function public.retorno(date, date) from public, anon;
revoke execute on function public.estado_inicial() from public, anon;
grant execute on function public.retorno(date, date) to authenticated;
grant execute on function public.estado_inicial() to authenticated;

comment on function public.retorno(date, date) is
  'Retorno do periodo, separado: preenchido e recebido sao dinheiro; em aberto nao e.';
