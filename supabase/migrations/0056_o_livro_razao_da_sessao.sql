-- =====================================================================
-- 0056 · P2 · o livro-razão da sessão
--
-- A maior mudança em `sessoes` desde a B2, e a peça que faz o produto
-- responder a pergunta que nenhum concorrente responde: **quanto da capacidade
-- virou receita, e por onde o resto foi.**
--
-- A DECISÃO DE MIGRAÇÃO, E ELA É O BUILD INTEIRO
--
-- `sessoes.estado` **fica como está**. Ele já existe com seis valores, é lido
-- por dezenas de funções e por quinze suítes verdes, e passa a ser oficialmente
-- o **eixo agenda**.
--
-- Ele carrega, misturados, dois fatos que não são de agenda: `confirmada` é
-- fato de confirmação, e a distinção `cedo`/`tarde` é fato de política. A
-- tentação é limpar isso agora. **A decisão é não limpar.** Reescrever `estado`
-- tocaria `sessoes_transicao`, `sessoes_geram_cobranca`, `materializar_enquadre`,
-- `cancelar_sessao`, `abrir_vaga`, `financeiro_do_mes`, `linha_do_tempo` e mais,
-- com quinze suítes que passariam a testar outra coisa. O ganho seria estético;
-- o risco é o de sempre — um gatilho que para de classificar cancelamento e
-- ninguém percebe até a primeira falta não cobrada.
--
-- A conflação fica escrita aqui como **dívida conhecida**, e `eixo_agenda()` é a
-- função que o cockpit lê. Ninguém lê `estado` cru para métrica. Quando o
-- `eixo_confirmacao` estiver de pé (P3), `confirmada` vira redundante e some
-- numa migração de limpeza sozinha, com a regressão inteira em volta.
--
-- INVARIANTE 1 · NENHUM EIXO MUDA POR TELA
--
-- Os quatro eixos novos e o `valor_reconhecido` são **derivados**: uma função
-- só, `recalcular_eixos(sessao)`, lê os fatos que já existem (o estado, a
-- cobrança, o consumo de pacote, a remarcação, o recibo) e escreve o resultado.
-- Os gatilhos apenas a chamam.
--
-- Isso não é elegância: é a única forma de a completude automática passar de
-- 90%. Eixo que se preenche por tela é eixo que fica vazio — e um livro-razão
-- com metade das linhas em branco não mede nada, só dá trabalho.
--
-- E é idempotente de propósito. Rodar de novo sobre a mesma sessão dá o mesmo
-- resultado, o que faz o backfill e a correção de um defeito futuro serem a
-- mesma operação.
--
-- INVARIANTE 2 · `valor_reconhecido` SÓ EXISTE PARA HORA PRESTADA
--
-- Antecipação recebida de sessão futura entra em `eixo_financeiro = 'paga'` e
-- **não** em receita reconhecida. Sem essa separação, a ocupação paga sobe
-- recebendo por hora que ainda não aconteceu — e o número mais importante do
-- produto passa a mentir **para cima**, que é a direção que ninguém questiona.
--
-- A base do valor é `sessoes.valor`, e não a cobrança: é a mesma convenção do
-- `financeiro_do_mes` (F1, migração 0037), onde a coluna "realizado (competência)" soma
-- `s.valor`. Duas convenções de receita no mesmo banco seriam duas verdades, e
-- a que aparecesse primeiro na tela ganharia.
--
-- INVARIANTE 3 · `reposta` — O EIXO QUE JUSTIFICA O BUILD
--
-- A hora se perdeu e o paciente consumiu **outra** hora com o mesmo dinheiro:
-- **duas horas de capacidade, uma receita.** Nenhum sistema do mercado separa
-- isso, e é exatamente onde a remarcação com crédito esconde perda — a B21
-- construiu a remarcação guiada sem essa conta.
--
-- A sessão antiga fica `reposta` com `reposta_por` apontando para a nova, e o
-- `valor_reconhecido` dela é **zero**. A nova fica `vendida` com o valor. Somar
-- as duas daria receita dobrada; ignorar a antiga esconderia a hora perdida.
--
-- INVARIANTE 4 · `eixo_capacidade` É SOBRE A HORA, NÃO SOBRE O DINHEIRO
--
-- Hora entregue é **hora vendida**, mesmo que o pagamento não tenha entrado.
-- Inadimplência e perdão são fatos do eixo financeiro, e é lá que aparecem.
-- Misturar faria o mesmo problema ser contado duas vezes na tabela de perdas —
-- uma vez como hora perdida e outra como dinheiro não recebido —, e um painel
-- que soma o mesmo problema duas vezes é pior que um painel que não existe.
--
-- ONDE ESTA MIGRAÇÃO DIVERGE DO DOC 30, E POR QUÊ
--
-- O doc 30 propõe `eixo_financeiro in ('nao_cobrada','cobrada','paga',
-- 'estornada','credito')`. Aqui há **seis**: `perdoada` é valor próprio.
--
-- Mapear perdão para "estornada" faria a tela dizer *"estornada"* sobre uma
-- cobrança que a psicóloga **perdoou** — e perdoar é decisão dela, com motivo,
-- registrada desde a B11. Palavra errada na tela é exatamente a coisa que este
-- produto recusa, e economizar um valor de `check` não paga esse preço.
--
-- O QUE ESTA MIGRAÇÃO **NÃO** FAZ
--
-- **Não calcula ocupação como número único.** `livro_razao` devolve os eixos e
-- as causas separados; quem os junta em quatro números lado a lado é o P5. Um
-- número solitário de ocupação é manipulável e empurra contra o descanso.
--
-- **Não sugere ação nenhuma para "hora nunca vendida".** Ela aparece como fato,
-- calculada (capacidade menos horas usadas), e não gera sugestão de contato com
-- ninguém — o Código de Ética veda induzir pessoa a recorrer a serviços.
-- =====================================================================

-- ============================================================ 1 · os eixos

alter table public.sessoes
  add column if not exists eixo_confirmacao text not null default 'nao_pedida',
  add column if not exists eixo_financeiro  text not null default 'nao_cobrada',
  add column if not exists eixo_fiscal      text not null default 'nao_aplicavel',
  add column if not exists eixo_capacidade  text,
  add column if not exists reposta_por      uuid references public.sessoes (id) on delete set null,
  add column if not exists valor_reconhecido numeric(12,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sessoes_eixo_confirmacao_check') then
    alter table public.sessoes add constraint sessoes_eixo_confirmacao_check
      check (eixo_confirmacao in ('nao_pedida', 'pendente', 'confirmada', 'recusada', 'silenciosa'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'sessoes_eixo_financeiro_check') then
    alter table public.sessoes add constraint sessoes_eixo_financeiro_check
      check (eixo_financeiro in ('nao_cobrada', 'cobrada', 'paga', 'perdoada', 'estornada', 'credito'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'sessoes_eixo_fiscal_check') then
    alter table public.sessoes add constraint sessoes_eixo_fiscal_check
      check (eixo_fiscal in ('nao_aplicavel', 'pendente', 'emitida', 'cancelada'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'sessoes_eixo_capacidade_check') then
    alter table public.sessoes add constraint sessoes_eixo_capacidade_check
      check (eixo_capacidade is null or eixo_capacidade in ('vendida', 'perdida', 'reposta'));
  end if;

  -- Invariante 3: `reposta_por` e `reposta` andam juntos. Um sem o outro é
  -- linha que não conta história nenhuma — e é o estado em que um gatilho
  -- meio-escrito deixaria a tabela.
  if not exists (select 1 from pg_constraint where conname = 'sessoes_reposta_aponta') then
    alter table public.sessoes add constraint sessoes_reposta_aponta
      check ((eixo_capacidade = 'reposta') = (reposta_por is not null));
  end if;

  -- Invariante 2, no banco e não na convenção.
  if not exists (select 1 from pg_constraint where conname = 'sessoes_reconhecido_so_prestada') then
    alter table public.sessoes add constraint sessoes_reconhecido_so_prestada
      check (
        valor_reconhecido is null
        or valor_reconhecido = 0
        or estado = 'realizada'
      );
  end if;
end $$;

comment on column public.sessoes.estado is
  'O EIXO AGENDA. Divida conhecida da 0056: ele carrega tambem "confirmada" (fato de confirmacao) e a distincao cedo/tarde (fato de politica). Metrica nunca le esta coluna crua — le eixo_agenda(estado).';

comment on column public.sessoes.eixo_capacidade is
  'O que aconteceu com a HORA, nao com a sessao. reposta = a hora se perdeu e o paciente consumiu outra hora com o mesmo dinheiro: duas horas de capacidade, uma receita.';

comment on column public.sessoes.reposta_por is
  'A sessao que consumiu a hora extra. Preenchido exatamente quando eixo_capacidade = reposta.';

comment on column public.sessoes.valor_reconhecido is
  'Receita reconhecida desta sessao. Pagamento antecipado de sessao ainda nao prestada NAO conta aqui: sem isso a ocupacao paga sobe recebendo por hora que ainda nao aconteceu.';

comment on column public.sessoes.eixo_financeiro is
  'Seis valores, e nao os cinco do doc 30: perdoada e valor proprio. Chamar perdao de estorno faria a tela dizer a palavra errada sobre uma decisao dela.';

create index if not exists sessoes_eixo_capacidade on public.sessoes (eixo_capacidade, inicio);
create index if not exists sessoes_eixo_financeiro on public.sessoes (eixo_financeiro)
  where eixo_financeiro in ('cobrada', 'credito');

-- ====================================================== 2 · o eixo agenda

/**
 * O eixo agenda, lido do `estado`.
 *
 * `prevista` e `confirmada` são a mesma coisa para a agenda: a hora está
 * reservada. A diferença entre elas é confirmação, e confirmação tem eixo
 * próprio — é essa separação que o P3 vai completar.
 *
 * `cancelada_cedo` e `cancelada_tarde` também colapsam: para a agenda, as duas
 * são hora que vagou. A diferença entre elas é política, e política decide
 * cobrança, não ocupação.
 */
create or replace function public.eixo_agenda(p_estado text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_estado
    when 'prevista'        then 'reservada'
    when 'confirmada'      then 'reservada'
    when 'realizada'       then 'realizada'
    when 'falta'           then 'ausente'
    when 'cancelada_cedo'  then 'cancelada'
    when 'cancelada_tarde' then 'cancelada'
    else 'reservada'
  end;
$$;

-- ================================================ 3 · o cálculo dos eixos

/**
 * Recalcula os cinco eixos de uma sessão a partir dos fatos que já existem.
 *
 * **É a única escrita de eixo do sistema inteiro** (invariante 1). Nenhuma tela
 * chama, nenhuma tela pode chamar: a função é `security definer` e está revogada
 * de `authenticated`. Os gatilhos a chamam, e é só.
 *
 * `security definer` porque ela precisa enxergar a verdade — cobrança, consumo
 * de pacote e recibo — independentemente de quem disparou a escrita. Uma
 * gravação feita pelo cron da mensageria e uma feita pela tela têm de produzir
 * o mesmo livro-razão.
 *
 * Idempotente: rodar de novo sobre a mesma sessão dá o mesmo resultado.
 */
create or replace function public.recalcular_eixos(p_sessao uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s           record;
  cob_id      uuid;
  cob_estado  text;
  tem_pacote  boolean;
  nova        uuid;
  v_fin       text;
  v_cap       text;
  v_fiscal    text := 'nao_aplicavel';
  v_valor     numeric(12,2);
  v_conf      text;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then return; end if;

  -- ------------------------------------------------------------ financeiro
  -- Duas variáveis escalares, e não um `record`: em plpgsql, ler um campo de um
  -- record que o `select into` não preencheu levanta "record not assigned yet"
  -- — e o `found` do meio do caminho já foi reescrito pela consulta seguinte.
  -- Foi assim que a 0052c quebrou.
  select id, estado into cob_id, cob_estado
    from public.cobrancas
   where sessao_id = p_sessao and estado <> 'cancelada'
   order by criado_em desc
   limit 1;

  select exists (select 1 from public.pacote_consumos where sessao_id = p_sessao)
    into tem_pacote;

  if cob_id is not null then
    v_fin := case cob_estado
               when 'paga'     then 'paga'
               when 'perdoada' then 'perdoada'
               else 'cobrada'
             end;
  elsif tem_pacote then
    -- O dinheiro desta sessão está na venda do pacote, e não numa cobrança
    -- dela. `credito` é isso, e não "ainda vai pagar".
    v_fin := 'credito';
  else
    -- Mensalidade: a sessão é coberta pela cobrança do mês, que não tem
    -- `sessao_id`. Também é crédito — o dinheiro está em outro lugar.
    if s.enquadre_id is not null and exists (
      select 1 from public.enquadres e
       where e.id = s.enquadre_id and e.modelo_cobranca = 'mensal'
    ) then
      v_fin := 'credito';
    else
      v_fin := 'nao_cobrada';
    end if;
  end if;

  -- ------------------------------------------------------------- confirmação
  -- Enquanto o P3 não existe, o único fato de confirmação que o banco tem é o
  -- `estado = 'confirmada'`. Ele entra aqui em vez de o eixo ficar mentindo
  -- "não pedida" para uma sessão que a pessoa confirmou.
  v_conf := case
              when s.estado = 'confirmada' then 'confirmada'
              when s.eixo_confirmacao in ('pendente', 'recusada', 'silenciosa')
                then s.eixo_confirmacao
              else 'nao_pedida'
            end;

  -- -------------------------------------------------------------- capacidade
  select r.nova_sessao_id into nova
    from public.remarcacoes r
   where r.sessao_id = p_sessao and r.nova_sessao_id is not null
   order by r.escolhida_em desc nulls last
   limit 1;

  if s.estado = 'realizada' then
    -- Invariante 4: hora entregue é hora vendida. Se o dinheiro não ficou,
    -- isso é fato do eixo financeiro — e é lá que a tabela de perdas o lê.
    v_cap := 'vendida';
  elsif s.estado in ('falta', 'cancelada_cedo', 'cancelada_tarde') then
    -- Invariante 3. A remarcação com crédito é onde o mercado esconde perda.
    v_cap := case when nova is not null then 'reposta' else 'perdida' end;
  else
    v_cap := null;   -- ainda não resolveu
  end if;

  -- ------------------------------------------------------- valor reconhecido
  if s.estado <> 'realizada' then
    -- Invariante 2. Zero, e não nulo, quando a sessão já resolveu: zero é um
    -- fato ("esta hora não produziu receita"); nulo é "ainda não sei".
    v_valor := case when v_cap is null then null else 0 end;
  elsif v_fin in ('perdoada', 'estornada') then
    v_valor := 0;
  else
    v_valor := s.valor;
  end if;

  -- ------------------------------------------------------------------ fiscal
  if cob_id is not null then
    select case rb.estado
             when 'emitido'    then 'emitida'
             when 'pendente'   then 'pendente'
             when 'vencido'    then 'pendente'
             else 'cancelada'
           end
      into v_fiscal
      from public.recibos_rfb rb
     where rb.cobranca_id = cob_id
     limit 1;
  end if;

  update public.sessoes
     set eixo_confirmacao  = v_conf,
         eixo_financeiro   = v_fin,
         eixo_fiscal       = coalesce(v_fiscal, 'nao_aplicavel'),
         eixo_capacidade   = v_cap,
         reposta_por       = case when v_cap = 'reposta' then nova else null end,
         valor_reconhecido = v_valor
   where id = p_sessao
     and (eixo_confirmacao, eixo_financeiro, eixo_fiscal, eixo_capacidade,
          reposta_por, valor_reconhecido)
         is distinct from
         (v_conf, v_fin, coalesce(v_fiscal, 'nao_aplicavel'), v_cap,
          case when v_cap = 'reposta' then nova else null end, v_valor);
end;
$$;

-- ============================================================ 4 · os gatilhos

/**
 * Cinco fontes de verdade, cinco gatilhos, uma função.
 *
 * A cláusula `when` de cada um não é otimização: é o que impede recursão. O
 * gatilho de `sessoes` só dispara quando o **estado** muda, então a escrita dos
 * eixos feita por `recalcular_eixos` não o dispara de novo.
 */
create or replace function public.eixos_ao_mudar_sessao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recalcular_eixos(new.id);
  return null;
end;
$$;

drop trigger if exists sessoes_recalculam_eixos on public.sessoes;
create trigger sessoes_recalculam_eixos
  after insert or update of estado on public.sessoes
  for each row execute function public.eixos_ao_mudar_sessao();

/**
 * A cobrança mexe no eixo financeiro e pode zerar o reconhecido (perdão).
 *
 * `after` e não `before`: o cálculo lê a cobrança já gravada. E cobre o
 * `delete` porque cobrança apagada devolve a sessão para `nao_cobrada` — se
 * ficasse `cobrada`, a tabela de perdas mostraria inadimplência de uma dívida
 * que não existe mais.
 */
create or replace function public.eixos_ao_mudar_cobranca()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare alvo uuid;
begin
  alvo := coalesce(new.sessao_id, old.sessao_id);
  if alvo is not null then perform public.recalcular_eixos(alvo); end if;
  return null;
end;
$$;

drop trigger if exists cobrancas_recalculam_eixos on public.cobrancas;
create trigger cobrancas_recalculam_eixos
  after insert or update or delete on public.cobrancas
  for each row execute function public.eixos_ao_mudar_cobranca();

create or replace function public.eixos_ao_consumir_pacote()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare alvo uuid;
begin
  alvo := coalesce(new.sessao_id, old.sessao_id);
  if alvo is not null then perform public.recalcular_eixos(alvo); end if;
  return null;
end;
$$;

drop trigger if exists pacote_consumos_recalculam_eixos on public.pacote_consumos;
create trigger pacote_consumos_recalculam_eixos
  after insert or delete on public.pacote_consumos
  for each row execute function public.eixos_ao_consumir_pacote();

/**
 * A remarcação escolhida é o que transforma `perdida` em `reposta`.
 *
 * Recalcula as **duas** sessões: a antiga, que passa a apontar para a nova, e a
 * nova, que precisa nascer com os eixos preenchidos. Recalcular só a antiga
 * deixaria a nova em branco até alguém mexer nela — e o buraco apareceria
 * exatamente na conta que este build existe para fazer.
 */
create or replace function public.eixos_ao_remarcar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recalcular_eixos(new.sessao_id);
  if new.nova_sessao_id is not null then
    perform public.recalcular_eixos(new.nova_sessao_id);
  end if;
  return null;
end;
$$;

drop trigger if exists remarcacoes_recalculam_eixos on public.remarcacoes;
create trigger remarcacoes_recalculam_eixos
  after update of nova_sessao_id on public.remarcacoes
  for each row execute function public.eixos_ao_remarcar();

create or replace function public.eixos_ao_mudar_recibo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare alvo uuid;
begin
  select c.sessao_id into alvo
    from public.cobrancas c
   where c.id = coalesce(new.cobranca_id, old.cobranca_id);
  if alvo is not null then perform public.recalcular_eixos(alvo); end if;
  return null;
end;
$$;

drop trigger if exists recibos_recalculam_eixos on public.recibos_rfb;
create trigger recibos_recalculam_eixos
  after insert or update or delete on public.recibos_rfb
  for each row execute function public.eixos_ao_mudar_recibo();

-- ============================================================ 5 · o backfill

/**
 * Preenche os eixos do que já existe.
 *
 * Sem isto, a completude começaria em zero e subiria conforme as sessões
 * antigas fossem tocadas — o que é o mesmo que dizer que o mês passado não tem
 * livro-razão. O critério de pronto do P2 é completude acima de 90%, e ela
 * precisa valer para o histórico.
 */
do $$
declare r record;
begin
  for r in select id from public.sessoes order by inicio
  loop
    perform public.recalcular_eixos(r.id);
  end loop;
end $$;

-- ============================================================ 6 · a completude

/**
 * Quantas sessões têm os cinco eixos preenchidos **sem ninguém digitar**.
 *
 * É o critério de pronto do P2 virando consulta. Uma sessão ainda `prevista`
 * conta como completa com `eixo_capacidade` nulo — nulo ali é a resposta certa
 * ("ainda não resolveu"), e exigir valor seria exigir que o banco adivinhasse o
 * futuro.
 */
create or replace function public.completude_dos_eixos(p_de date default null, p_ate date default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select s.*,
           (s.inicio at time zone 'America/Sao_Paulo')::date as dia
      from public.sessoes s
  ), no_periodo as (
    select * from base
     where (p_de is null or dia >= p_de)
       and (p_ate is null or dia <= p_ate)
  )
  select jsonb_build_object(
    'sessoes', (select count(*) from no_periodo),
    'completas', (
      select count(*) from no_periodo
       where eixo_confirmacao is not null
         and eixo_financeiro is not null
         and eixo_fiscal is not null
         and (
           (public.eixo_agenda(estado) = 'reservada' and eixo_capacidade is null)
           or (public.eixo_agenda(estado) <> 'reservada' and eixo_capacidade is not null)
         )
         and (public.eixo_agenda(estado) = 'reservada' or valor_reconhecido is not null)
    ),
    'resolvidas', (select count(*) from no_periodo where public.eixo_agenda(estado) <> 'reservada'),
    'repostas',   (select count(*) from no_periodo where eixo_capacidade = 'reposta')
  );
$$;

-- ============================================================ 7 · o livro-razão

/**
 * O mês inteiro em eixos, e a perda por causa.
 *
 * É a consulta que responde, para qualquer período fechado, **quanto da
 * capacidade virou receita e por onde o resto foi** — o critério de pronto do
 * P2.
 *
 * As causas são as sete do doc 30, e a sétima é calculada e **não tem ação**:
 * `hora_nunca_vendida` é capacidade vendável menos a capacidade usada. Ela
 * aparece como fato e não gera sugestão de contato com ninguém.
 *
 * Note o que **não** está aqui: nenhum percentual de ocupação. Ocupação é
 * quatro números lado a lado, e juntá-los é trabalho do P5 — um número
 * solitário aqui seria manipulável e empurraria contra o descanso.
 */
create or replace function public.livro_razao(
  p_profissional uuid,
  p_de           date,
  p_ate          date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
         and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
       group by 1
    ) g;

  -- ------------------------------------------------- a receita reconhecida
  select coalesce(sum(s.valor_reconhecido), 0)
    into reconhecida
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ------------------------------------------------------------- as causas
  --
  -- 1 · falta sem cobrança: atendeu não, cobrou não.
  select coalesce(sum(s.valor), 0), count(*) into falta_sem, falta_sem_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'falta'
     and s.eixo_financeiro in ('nao_cobrada', 'perdoada');

  -- 2 · falta com cobrança: recebeu, perdeu a hora. Não é perda de dinheiro —
  --     é a política funcionando. Aparece com o valor recuperado ao lado.
  select coalesce(sum(c.valor), 0), count(*) into falta_com, falta_com_n
    from public.sessoes s
    join public.cobrancas c on c.sessao_id = s.id and c.estado = 'paga'
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'falta';

  -- 3 · cancelada com antecedência e não reocupada.
  select coalesce(sum(s.valor), 0), count(*) into cancel_perdida, cancel_perdida_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado in ('cancelada_cedo', 'cancelada_tarde')
     and s.eixo_capacidade = 'perdida';

  -- 4 · reposta: duas horas, uma receita. O valor é o da hora que se perdeu.
  select coalesce(sum(s.valor), 0), count(*) into reposta_v, reposta_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.eixo_capacidade = 'reposta';

  -- 5 · atendida e não recebida: inadimplência.
  select coalesce(sum(s.valor), 0), count(*) into nao_recebida, nao_recebida_n
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'realizada'
     and s.eixo_financeiro = 'cobrada';

  -- 6 · recebida abaixo do combinado: convênio, plataforma, desconto.
  select coalesce(sum(s.valor - c.valor), 0), count(*) into abaixo, abaixo_n
    from public.sessoes s
    join public.cobrancas c on c.sessao_id = s.id and c.estado = 'paga'
   where s.profissional_id = p_profissional
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
$$;

-- ============================================================ 8 · os grants

revoke execute on function public.livro_razao(uuid, date, date)      from public, anon;
revoke execute on function public.completude_dos_eixos(date, date)   from public, anon;
revoke execute on function public.eixo_agenda(text)                  from public, anon;

grant execute on function public.livro_razao(uuid, date, date)     to authenticated;
grant execute on function public.completude_dos_eixos(date, date)  to authenticated;
grant execute on function public.eixo_agenda(text)                 to authenticated;

-- Invariante 1: nenhuma tela escreve eixo. `recalcular_eixos` é da máquina.
revoke execute on function public.recalcular_eixos(uuid)          from public, anon, authenticated;
revoke execute on function public.eixos_ao_mudar_sessao()         from public, anon, authenticated;
revoke execute on function public.eixos_ao_mudar_cobranca()       from public, anon, authenticated;
revoke execute on function public.eixos_ao_consumir_pacote()      from public, anon, authenticated;
revoke execute on function public.eixos_ao_remarcar()             from public, anon, authenticated;
revoke execute on function public.eixos_ao_mudar_recibo()         from public, anon, authenticated;
