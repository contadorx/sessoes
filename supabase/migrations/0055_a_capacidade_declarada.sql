-- =====================================================================
-- 0055 · P1 · a capacidade declarada
--
-- O bloco 0 do doc 30, e a primeira peça da trilha P. Sem denominador não há
-- métrica: hoje o banco sabe quanto foi **vendido** (`enquadres`) e não sabe
-- quanto foi **oferecido**. "Quanto da sua capacidade virou receita" não tem
-- como ser respondido, porque a capacidade nunca foi modelada.
--
-- O QUE ESTA MIGRAÇÃO DECIDE, E POR QUÊ
--
-- INVARIANTE 1 · A DECLARAÇÃO NÃO SE REESCREVE PARA TRÁS
--
-- Uma janela é uma **declaração datada**, não uma configuração. Se ela pudesse
-- ser editada com efeito retroativo, o denominador de um mês fechado mudaria
-- toda vez que alguém mexesse na agenda de amanhã — e a ocupação de julho seria
-- diferente conforme o dia em que fosse consultada.
--
-- Por isso `vigencia_de` nunca nasce no passado e `vigencia_ate` nunca é
-- gravada antes de hoje. Quem quiser mudar a semana muda **de hoje para a
-- frente**; o que já foi declarado fica como foi declarado. É o critério de
-- pronto do P1 escrito como gatilho: *mexer na janela hoje não altera nenhum
-- mês fechado*.
--
-- ⚠ **A vigência aqui é [de, ate), e a de `enquadres` é fechada dos dois
-- lados.** Duas convenções no mesmo banco é armadilha, então elas têm **nomes
-- diferentes**: `vigencia_de`/`vigencia_ate` aqui, `vigencia_inicio`/
-- `vigencia_fim` lá. O motivo da divergência é a invariante 1: com fim
-- inclusivo, trocar a semana hoje exigiria fechar a antiga **ontem** — o que é
-- exatamente a reescrita do passado que esta migração proíbe. Com fim
-- exclusivo, fecha-se hoje e abre-se hoje, sem sobreposição e sem retroagir.
--
-- INVARIANTE 2 · REGISTRO E DESCANSO SÃO CAPACIDADE DECLARADA E PROTEGIDA
--
-- `destino in ('atendimento', 'registro', 'descanso')`. As três são horas que a
-- pessoa **declarou**; só a primeira é vendável.
--
-- Isto é a fronteira 4 nova do doc 11, e é a razão de a coluna existir. Um
-- painel que somasse registro e descanso como "hora ociosa" seria um produto
-- para psicólogas empurrando psicóloga a preencher todas as horas — e a
-- ocupação é manipulável exatamente assim: deixando de reservar tempo de
-- prontuário, o número sobe sem nada ter melhorado.
--
-- `capacidade_vendavel` devolve os três separados e **não devolve nenhum campo
-- que os some**. Não há `ociosidade`, não há `horas_livres`. A suíte reprova o
-- dia em que aparecer.
--
-- INVARIANTE 3 · HORA VAGA NÃO É LINHA
--
-- Nenhuma tabela de horários vazios. Vaga é capacidade menos sessões,
-- **calculada**. Materializar milhares de linhas vazias trataria ausência de
-- demanda como estoque — que é precisamente o erro de tese que o doc 30
-- corrigiu. Hora não vendida sem comprador não é inventário; é ausência de
-- demanda, e se existe alguém que queria aquele horário naquele preço é
-- hipótese de pesquisa, não linha de banco.
--
-- INVARIANTE 4 · DUAS JANELAS VIVAS NÃO SE SOBREPÕEM
--
-- Sobreposição no mesmo dia e no mesmo horário conta a mesma hora duas vezes, e
-- o erro vai **para cima** — o denominador cresce e a ocupação cai, ou o
-- vendável cresce e a receita por hora despenca. Erro que empurra o número na
-- direção que a pessoa não questiona é o pior tipo, e por isso é gatilho.
--
-- INVARIANTE 5 · A EXCEÇÃO SUBTRAI, E DIZ QUANTO
--
-- Férias, feriado e bloqueio saem do denominador: sem isso o mês de férias
-- apareceria como catástrofe de ocupação, e o produto estaria cobrando a
-- pessoa por ter descansado. Mas saem **separados por tipo** na resposta —
-- "declarei 40h e tirei 30h de férias" e "declarei 40h e bloqueei 30h" contam
-- histórias diferentes, e esconder a diferença é esconder o que aconteceu com
-- o mês.
--
-- O QUE ESTA MIGRAÇÃO **NÃO** FAZ
--
-- **Não calcula ocupação.** Ocupação precisa do numerador, que é o livro-razão
-- do P2. Entregar meia métrica agora seria entregar um número que muda de
-- significado na próxima build.
--
-- **Não sugere preencher hora nenhuma.** Não há função que liste horários
-- vazios para contato, e não vai haver: o Código de Ética veda induzir pessoa a
-- recorrer a serviços, e uma lista de vagas com botão de "oferecer" é isso com
-- outro nome. A fila da B7 é outra coisa — lá **existe alguém que pediu**.
-- =====================================================================

-- ============================================================ 1 · a tabela

create table if not exists public.janelas_atendimento (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,

  -- 0 = domingo, para casar com o extract(dow) do Postgres — a mesma convenção
  -- de `enquadres.dia_semana`.
  dia_semana      smallint not null check (dia_semana between 0 and 6),
  inicio          time not null,
  fim             time not null,

  -- Invariante 2. O padrão é 'atendimento' porque é o que a pessoa vai declarar
  -- primeiro; as outras duas existem para ela poder proteger o resto.
  destino         text not null default 'atendimento'
                  check (destino in ('atendimento', 'registro', 'descanso')),

  -- Invariante 1. [de, ate) — fim EXCLUSIVO, ao contrário de `enquadres`.
  vigencia_de     date not null default public.hoje_sp(),
  vigencia_ate    date,

  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),

  constraint janela_com_duracao check (fim > inicio),
  constraint janela_vigencia_coerente check (vigencia_ate is null or vigencia_ate > vigencia_de)
);

comment on table public.janelas_atendimento is
  'A capacidade DECLARADA: quantas horas a pessoa decide disponibilizar, e para que. Diferente de enquadres, que e capacidade VENDIDA. Vigencia [de, ate) com fim exclusivo — ver o cabecalho da 0055.';

comment on column public.janelas_atendimento.destino is
  'atendimento e vendavel; registro e descanso sao capacidade declarada e PROTEGIDA, nunca ociosidade. Fronteira 4 do doc 11.';

comment on column public.janelas_atendimento.vigencia_ate is
  'Fim EXCLUSIVO: a janela vale ate o dia anterior a esta data. Nunca gravada no passado — a declaracao de um mes fechado nao muda.';

create index if not exists janelas_conta on public.janelas_atendimento (conta_id);
create index if not exists janelas_vigentes
  on public.janelas_atendimento (profissional_id, dia_semana, vigencia_de)
  where vigencia_ate is null;

-- ======================================================== 2 · os gatilhos

/**
 * Invariante 1, no banco.
 *
 * A mensagem diz o que fazer, e não só que não dá — a forma das recusas da
 * 0050. Quem quer mudar a semana muda de hoje para a frente.
 */
create or replace function public.janela_nao_retroage()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare hoje date := public.hoje_sp();
begin
  if tg_op = 'INSERT' and new.vigencia_de < hoje then
    raise exception 'uma janela não começa no passado: a capacidade de um mês fechado é a que foi declarada na época, e mexer nela mudaria a ocupação de um mês que já foi contado. Declare a partir de hoje.';
  end if;

  if new.vigencia_ate is not null and new.vigencia_ate < hoje then
    raise exception 'uma janela não se encerra no passado: isso apagaria capacidade que já foi contada. Encerre de hoje em diante.';
  end if;

  if tg_op = 'UPDATE' and new.vigencia_de is distinct from old.vigencia_de and old.vigencia_de < hoje then
    raise exception 'o começo de uma janela que já valeu não muda — ele é a data em que a declaração passou a existir';
  end if;

  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists janelas_nao_retroagem on public.janelas_atendimento;
create trigger janelas_nao_retroagem
  before insert or update on public.janelas_atendimento
  for each row execute function public.janela_nao_retroage();

/**
 * Invariante 4: duas janelas vivas não ocupam o mesmo pedaço de semana.
 *
 * A comparação é sobre a **interseção de vigências**, e não sobre "as duas
 * abertas": duas janelas fechadas em períodos que se cruzam contariam a mesma
 * hora duas vezes em qualquer consulta ao passado.
 *
 * `coalesce(vigencia_ate, 'infinity')` resolve o aberto sem um `or` a mais, e
 * `overlaps` compara os horários sem escrever a álgebra de intervalos à mão —
 * que é onde este tipo de checagem costuma errar por um minuto.
 */
create or replace function public.janela_nao_sobrepoe()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare v_outra record;
begin
  select j.inicio, j.fim, j.destino into v_outra
    from public.janelas_atendimento j
   where j.profissional_id = new.profissional_id
     and j.dia_semana = new.dia_semana
     and j.id is distinct from new.id
     and daterange(j.vigencia_de, j.vigencia_ate, '[)')
         && daterange(new.vigencia_de, new.vigencia_ate, '[)')
     and (j.inicio, j.fim) overlaps (new.inicio, new.fim)
   limit 1;

  if found then
    raise exception 'esta faixa se sobrepõe a outra do mesmo dia (% às %, %): a mesma hora contada duas vezes infla a capacidade e faz a ocupação parecer menor do que é',
      to_char(v_outra.inicio, 'HH24:MI'), to_char(v_outra.fim, 'HH24:MI'), v_outra.destino;
  end if;

  return new;
end;
$$;

drop trigger if exists janelas_nao_sobrepoem on public.janelas_atendimento;
create trigger janelas_nao_sobrepoem
  before insert or update on public.janelas_atendimento
  for each row execute function public.janela_nao_sobrepoe();

-- ============================================================== 3 · a RLS

alter table public.janelas_atendimento enable row level security;

drop policy if exists "janelas da conta: ler" on public.janelas_atendimento;
create policy "janelas da conta: ler"
  on public.janelas_atendimento for select to authenticated
  using (conta_id = public.conta_atual());

-- Sem política de escrita: quem grava é `definir_semana`, e é ela que fecha a
-- semana antiga na mesma transação em que abre a nova. Um insert solto pela
-- tela deixaria as duas valendo, e a invariante 4 recusaria — com uma mensagem
-- que culparia a pessoa por um passo que a tela esqueceu de dar.

-- ==================================================== 4 · declarar a semana

/**
 * Substitui a semana inteira, valendo de uma data em diante.
 *
 * **Substitui, e não acrescenta.** A tela edita a semana como um todo, e um
 * "acrescentar faixa" exigiria um "remover faixa" — duas portas para uma lista
 * de seis linhas, e nenhuma das duas fechando a vigência corretamente.
 *
 * O fechamento e a abertura acontecem na mesma transação e na mesma data: a
 * antiga recebe `vigencia_ate = p_a_partir` (fim exclusivo) e a nova nasce com
 * `vigencia_de = p_a_partir`. Não há dia coberto duas vezes nem dia descoberto.
 *
 * As janelas que **ainda não tinham começado** são apagadas em vez de fechadas:
 * uma declaração que nunca valeu para nenhum dia não é história de nada, e
 * fechá-la em `p_a_partir` produziria vigência de comprimento zero.
 *
 * Cada item de `p_janelas`: `{dia, inicio, fim, destino}`. Item pela metade é
 * ignorado — a mesma regra de `definir_links_do_post`: o formulário manda a
 * lista toda, inclusive as linhas em branco.
 */
create or replace function public.definir_semana(
  p_profissional uuid,
  p_janelas      jsonb,
  p_a_partir     date default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conta   uuid := public.conta_atual();
  v_quando  date := coalesce(p_a_partir, public.hoje_sp());
  v_item    jsonb;
  v_n       integer := 0;
  v_dia     smallint;
  v_inicio  time;
  v_fim     time;
  v_destino text;
begin
  if v_conta is null then raise exception 'sem conta na sessão'; end if;

  if not exists (
    select 1 from public.profissionais p
     where p.id = p_profissional and p.conta_id = v_conta
  ) then
    raise exception 'profissional não encontrado nesta conta';
  end if;

  if v_quando < public.hoje_sp() then
    raise exception 'a semana passa a valer de hoje em diante, nunca para trás: a capacidade de um mês fechado é a que foi declarada na época';
  end if;

  -- O que nunca chegou a valer some; o que valeu é fechado no dia da troca.
  delete from public.janelas_atendimento
   where profissional_id = p_profissional
     and conta_id = v_conta
     and vigencia_de >= v_quando;

  update public.janelas_atendimento
     set vigencia_ate = v_quando
   where profissional_id = p_profissional
     and conta_id = v_conta
     and vigencia_de < v_quando
     and (vigencia_ate is null or vigencia_ate > v_quando);

  if p_janelas is null or jsonb_typeof(p_janelas) <> 'array' then
    return 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_janelas)
  loop
    if coalesce(v_item ->> 'inicio', '') = '' or coalesce(v_item ->> 'fim', '') = '' then
      continue;
    end if;

    v_dia     := (v_item ->> 'dia')::smallint;
    v_inicio  := (v_item ->> 'inicio')::time;
    v_fim     := (v_item ->> 'fim')::time;
    v_destino := coalesce(nullif(btrim(coalesce(v_item ->> 'destino', '')), ''), 'atendimento');

    insert into public.janelas_atendimento
      (conta_id, profissional_id, dia_semana, inicio, fim, destino, vigencia_de)
    values
      (v_conta, p_profissional, v_dia, v_inicio, v_fim, v_destino, v_quando);

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

/**
 * A semana como ela vale numa data — para a tela desenhar o que está valendo.
 */
create or replace function public.semana_declarada(
  p_profissional uuid,
  p_em           date default null
)
returns table (
  id          uuid,
  dia_semana  smallint,
  inicio      time,
  fim         time,
  destino     text,
  minutos     integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select j.id, j.dia_semana, j.inicio, j.fim, j.destino,
         (extract(epoch from (j.fim - j.inicio)) / 60)::integer
    from public.janelas_atendimento j
   where j.profissional_id = p_profissional
     and j.vigencia_de <= coalesce(p_em, public.hoje_sp())
     and (j.vigencia_ate is null or coalesce(p_em, public.hoje_sp()) < j.vigencia_ate)
   order by j.dia_semana, j.inicio;
$$;

-- =================================================== 5 · a capacidade do período

/**
 * O denominador — e cada coisa no seu balde.
 *
 * Percorre dia a dia o período, soma os minutos das janelas vigentes **naquele
 * dia** (é isso que faz uma troca de semana no meio do mês ser respeitada) e
 * separa em quatro destinos: vendável, registro, descanso e fora (a exceção).
 *
 * **O que ela não devolve, e é decisão:** nenhum campo que some vendável com
 * registro e descanso, e nenhum campo chamado ociosidade, hora livre ou coisa
 * parecida. `declarado_min` existe para a frase "você declarou X e ofereceu Y",
 * e a distância entre os dois é tempo protegido, não desperdício.
 *
 * `sem_janela` é o que impede a pior tela possível: 0% de ocupação para quem
 * simplesmente ainda não declarou nada. Ausência de declaração e capacidade
 * zero são coisas diferentes, e confundi-las é acusar alguém de não ter
 * trabalhado.
 *
 * `security invoker`: quem filtra é a RLS. `definer` aqui devolveria a
 * capacidade de outra conta para quem passasse um uuid adivinhado.
 */
create or replace function public.capacidade_vendavel(
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
  v_dia       date;
  v_vendavel  integer := 0;
  v_registro  integer := 0;
  v_descanso  integer := 0;
  v_ferias    integer := 0;
  v_feriado   integer := 0;
  v_bloqueio  integer := 0;
  v_dias      integer := 0;
  v_tem       boolean := false;
  v_r         record;
  v_excecao   text;
begin
  if p_ate < p_de then
    raise exception 'o período termina antes de começar';
  end if;
  if p_ate - p_de > 1100 then
    raise exception 'período longo demais: peça no máximo três anos por vez';
  end if;

  v_dia := p_de;
  while v_dia <= p_ate loop
    v_dias := v_dias + 1;

    -- O tipo de exceção que cobre o dia. `order by` para que férias ganhem de
    -- um bloqueio sobreposto: o mês precisa contar a história maior.
    select e.tipo into v_excecao
      from public.excecoes_agenda e
     where e.profissional_id = p_profissional
       and v_dia between e.inicio and e.fim
     order by case e.tipo when 'ferias' then 1 when 'feriado' then 2 else 3 end
     limit 1;

    for v_r in
      select j.destino,
             (extract(epoch from (j.fim - j.inicio)) / 60)::integer as minutos
        from public.janelas_atendimento j
       where j.profissional_id = p_profissional
         and j.dia_semana = extract(dow from v_dia)::smallint
         and j.vigencia_de <= v_dia
         and (j.vigencia_ate is null or v_dia < j.vigencia_ate)
    loop
      v_tem := true;

      if v_excecao is not null then
        -- Invariante 5: sai do denominador, mas dizendo por quê.
        if    v_excecao = 'ferias'  then v_ferias   := v_ferias   + v_r.minutos;
        elsif v_excecao = 'feriado' then v_feriado  := v_feriado  + v_r.minutos;
        else                             v_bloqueio := v_bloqueio + v_r.minutos;
        end if;
      elsif v_r.destino = 'atendimento' then
        v_vendavel := v_vendavel + v_r.minutos;
      elsif v_r.destino = 'registro' then
        v_registro := v_registro + v_r.minutos;
      else
        v_descanso := v_descanso + v_r.minutos;
      end if;
    end loop;

    v_excecao := null;
    v_dia := v_dia + 1;
  end loop;

  return jsonb_build_object(
    'de', p_de,
    'ate', p_ate,
    'dias', v_dias,
    'sem_janela', not v_tem,
    'vendavel_min', v_vendavel,
    'registro_min', v_registro,
    'descanso_min', v_descanso,
    -- O declarado é o que ela ofereceu de si, e inclui o que protegeu. Ele
    -- NÃO é denominador de ocupação: quem é denominador é `vendavel_min`.
    'declarado_min', v_vendavel + v_registro + v_descanso,
    'fora', jsonb_build_object(
      'ferias', v_ferias,
      'feriado', v_feriado,
      'bloqueio', v_bloqueio,
      'total', v_ferias + v_feriado + v_bloqueio
    )
  );
end;
$$;

-- ============================================= 6 · o começo pergunta por isso

/**
 * `estado_inicial` ganha a capacidade — o critério de pronto do P1 diz que o
 * onboarding não termina sem ela.
 *
 * Corpo copiado da definição viva da 0025, com dois campos a mais e nada além.
 * `create or replace` é `drop` + `create` disfarçado, e o jeito de não perder o
 * que estava lá é partir do que estava lá.
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
    'preenchidas',   (select count(*) from public.ofertas where estado = 'aceita'),
    -- Novo na 0055. `janelas` conta as faixas vigentes hoje; `semana_min` é o
    -- que elas somam numa semana, e é o número que a pessoa reconhece.
    'janelas', (
      select count(*) from public.janelas_atendimento j
       where j.vigencia_de <= public.hoje_sp()
         and (j.vigencia_ate is null or public.hoje_sp() < j.vigencia_ate)
    ),
    'semana_min', coalesce((
      select sum((extract(epoch from (j.fim - j.inicio)) / 60)::integer)
        from public.janelas_atendimento j
       where j.vigencia_de <= public.hoje_sp()
         and (j.vigencia_ate is null or public.hoje_sp() < j.vigencia_ate)
    ), 0)
  );
$$;

-- ============================================================ 7 · os grants

revoke execute on function public.definir_semana(uuid, jsonb, date)          from public, anon;
revoke execute on function public.semana_declarada(uuid, date)               from public, anon;
revoke execute on function public.capacidade_vendavel(uuid, date, date)      from public, anon;

grant execute on function public.definir_semana(uuid, jsonb, date)      to authenticated;
grant execute on function public.semana_declarada(uuid, date)           to authenticated;
grant execute on function public.capacidade_vendavel(uuid, date, date)  to authenticated;

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.janela_nao_retroage()  from public, anon, authenticated;
revoke execute on function public.janela_nao_sobrepoe()  from public, anon, authenticated;
