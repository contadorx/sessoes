-- 0033 · B20 — avulso, mensalista e pacote (D15).
--
-- Até aqui o produto sabia cobrar uma coisa só: a falta. A `modelo_cobranca` do
-- enquadre existe desde a 0005 e nunca foi lida por ninguém — era um campo
-- decorativo esperando esta build.
--
-- A prática real cobra dos três jeitos, e os genéricos só sabem o avulso (doc
-- 03, D15). O que decide se este build presta não é suportar os três nomes: é
-- acertar os quatro casos que fazem a psicóloga desconfiar do sistema e voltar
-- para a planilha.
--
-- ## 1. O mês de cinco terças
--
-- É a pergunta que todo mensalista responde de um jeito, e nenhum sistema
-- pergunta. Aqui ela é respondida por **uma escolha só**, e a escolha é o
-- próprio valor:
--
--   - `mensalidade_valor` preenchido → **valor fixo**. O mês de cinco terças sai
--     pelo mesmo preço. É o que "mensalidade" significa para a maioria.
--   - `mensalidade_valor` nulo → **por sessão do mês**. O mês de cinco terças
--     sai maior, e o de quatro sai menor.
--
-- Duas colunas (um valor e um booleano "cobra a quinta?") diriam a mesma coisa
-- de dois jeitos, e um dia discordariam.
--
-- ## 2. Férias não descontam a mensalidade fixa — a vigência sim
--
-- No valor fixo, uma semana de férias dela **não** reduz o mês. Reduzir
-- transformaria mensalidade em avulso disfarçado, que é exatamente o que quem
-- cobra mensal não quer. Mas quem **entra ou sai no meio do mês** paga
-- proporcional às sessões que couberam na vigência — cobrar o mês inteiro de
-- quem começou dia 25 é o tipo de erro que se descobre na conversa mais
-- constrangedora possível.
--
-- No modo por sessão, é o contrário e por construção: menos sessões, menos
-- dinheiro. Quem escolhe o modo escolhe também esse comportamento.
--
-- ## 3. Falta dentro do mensal já foi paga
--
-- Se a pessoa paga R$ 800 pelas quatro terças de março e falta a uma delas,
-- cobrar a multa por cima é **cobrar duas vezes pela mesma hora**. O padrão é
-- não cobrar; quem quiser o contrário liga `falta_cobra_a_parte` no combinado e
-- vê a decisão escrita na tela. No pacote é igual: a falta **consome o crédito**
-- (a hora foi reservada e perdida) e não gera cobrança nova.
--
-- ## 4. Saldo de pacote é derivado, nunca contado à mão
--
-- Um `saldo` como coluna mutável desanda: dois consumos concorrentes, um
-- estorno esquecido, um `update` manual, e o número na tela deixa de
-- corresponder à realidade — sem ninguém perceber, porque nada nele é
-- verificável. Aqui cada consumo é uma linha ligada à sessão que o consumiu
-- (única por sessão), e o saldo é uma subtração. Um saldo errado passa a ser um
-- consumo errado, que tem data e sessão.
--
-- ## E a cobrança da sessão realizada nasce desligada
--
-- `contas.cobra_sessao` vem `false`. Ligá-la faz cada sessão realizada virar uma
-- cobrança em aberto — que é o que quem cobra pelo sistema quer, e é ruína para
-- quem recebe em dinheiro na hora e usa isto só como agenda: a régua da B18
-- começaria a lembrar pessoas que não devem nada. Escolha explícita, com a
-- consequência escrita ao lado do interruptor.

-- ------------------------------------------------------------- as colunas

alter table public.contas
  add column if not exists cobra_sessao boolean not null default false,
  add column if not exists mensalidade_dia smallint not null default 1
    check (mensalidade_dia between 1 and 28);

comment on column public.contas.cobra_sessao is
  'Sessao realizada vira cobranca em aberto. Desligado por padrao: ligar muda o que a regua faz.';
comment on column public.contas.mensalidade_dia is
  'Dia do mes em que a mensalidade e gerada. Ate 28 para existir em fevereiro.';

alter table public.enquadres
  add column if not exists mensalidade_valor numeric(12,2)
    check (mensalidade_valor is null or mensalidade_valor >= 0),
  add column if not exists falta_cobra_a_parte boolean not null default false,
  add column if not exists pacote_quantidade smallint
    check (pacote_quantidade is null or pacote_quantidade between 1 and 60);

comment on column public.enquadres.mensalidade_valor is
  'Preenchido = valor fixo do mes (o mes de cinco sai igual). Nulo = por sessao do mes.';
comment on column public.enquadres.falta_cobra_a_parte is
  'No mensal e no pacote, a hora ja foi paga. true cobra a multa por cima assim mesmo.';

alter table public.cobrancas
  add column if not exists enquadre_id uuid references public.enquadres (id) on delete set null,
  add column if not exists pacote_id uuid;

-- Motivos novos. O `motivo` responde "por que esta linha existe" dois anos
-- depois, quando ninguém lembra do mês em questão.
alter table public.cobrancas drop constraint if exists cobrancas_motivo_check;
alter table public.cobrancas add constraint cobrancas_motivo_check
  check (motivo in (
    'cancelada_tarde', 'falta', 'avulsa',
    'sessao_realizada', 'mensalidade', 'pacote'
  ));

-- Uma mensalidade viva por combinado e competência. É a invariante que impede a
-- passada diária de cobrar o mesmo mês duas vezes se rodar duas vezes — e ela
-- roda duas vezes no dia em que alguém reexecutar o cron à mão.
create unique index if not exists mensalidade_por_competencia
  on public.cobrancas (enquadre_id, competencia)
  where tipo = 'mensalidade' and estado <> 'cancelada';

-- --------------------------------------------------------------- pacotes

create table if not exists public.pacotes (
  id           uuid primary key default gen_random_uuid(),
  conta_id     uuid not null references public.contas (id) on delete cascade,
  paciente_id  uuid not null references public.pacientes (id) on delete cascade,
  enquadre_id  uuid references public.enquadres (id) on delete set null,

  quantidade   smallint not null check (quantidade between 1 and 60),
  valor        numeric(12,2) not null check (valor >= 0),

  -- Pacote sem prazo é crédito eterno, e crédito eterno vira discussão três
  -- anos depois. A data é obrigatória e a tela sugere uma.
  validade     date not null,

  vendido_em   timestamptz not null default now(),
  cancelado_em timestamptz,
  motivo_cancelamento text
);

create index if not exists pacotes_do_paciente
  on public.pacotes (paciente_id, vendido_em desc);
create index if not exists pacotes_vivos
  on public.pacotes (conta_id) where cancelado_em is null;

/**
 * O consumo. Uma linha por sessão, e a sessão é única aqui dentro.
 *
 * O índice único não é otimização: é a garantia de que uma sessão que muda de
 * estado várias vezes (realizada → desfeita → realizada) não come três créditos.
 */
create table if not exists public.pacote_consumos (
  id         uuid primary key default gen_random_uuid(),
  conta_id   uuid not null references public.contas (id) on delete cascade,
  pacote_id  uuid not null references public.pacotes (id) on delete cascade,
  sessao_id  uuid not null references public.sessoes (id) on delete cascade,
  motivo     text not null check (motivo in ('realizada', 'falta', 'cancelada_tarde')),
  em         timestamptz not null default now()
);

create unique index if not exists consumo_unico_por_sessao
  on public.pacote_consumos (sessao_id);
create index if not exists consumos_do_pacote
  on public.pacote_consumos (pacote_id, em);

/** Saldo = o que foi vendido menos o que foi consumido. Nunca uma coluna. */
create or replace function public.saldo_do_pacote(p_pacote uuid)
returns int
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((select p.quantidade from public.pacotes p where p.id = p_pacote), 0)
       - (select count(*) from public.pacote_consumos c where c.pacote_id = p_pacote);
$$;

/**
 * O pacote que vale para uma sessão: vivo, dentro da validade **na data da
 * sessão** e com saldo.
 *
 * A validade é conferida contra o dia da sessão, não contra hoje: uma sessão de
 * março lançada em abril consome o pacote que valia em março. Conferir contra
 * hoje faria o atraso de digitação mudar quanto a pessoa deve.
 */
create or replace function public.pacote_para_sessao(p_paciente uuid, p_dia date)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
    from public.pacotes p
   where p.paciente_id = p_paciente
     and p.cancelado_em is null
     and p.validade >= p_dia
     and public.saldo_do_pacote(p.id) > 0
   order by p.validade, p.vendido_em
   limit 1;
$$;

-- ------------------------------------------------------- a conta do mês

/**
 * Quantas vezes um dia da semana cai num mês. Quatro ou cinco — e é essa
 * diferença que a D15 existe para resolver.
 */
create or replace function public.ocorrencias_do_dia_no_mes(p_dia smallint, p_competencia date)
returns int
language sql
immutable
set search_path = ''
as $$
  select count(*)::int
    from generate_series(
           date_trunc('month', p_competencia)::date,
           (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date,
           interval '1 day'
         ) as d
   where extract(dow from d) = p_dia;
$$;

/**
 * As sessões daquele combinado naquele mês que **contam para o dinheiro**.
 *
 * `cancelada_cedo` fica de fora: avisar com antecedência devolve a hora para a
 * fila, e a fila é o produto. Cobrar por ela puniria exatamente o
 * comportamento que o sistema inteiro tenta produzir.
 */
create or replace function public.sessoes_do_mes(p_enquadre uuid, p_competencia date)
returns int
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)::int
    from public.sessoes s
   where s.enquadre_id = p_enquadre
     and s.estado <> 'cancelada_cedo'
     and date_trunc('month', (s.inicio at time zone 'America/Sao_Paulo')::date)
         = date_trunc('month', p_competencia);
$$;

/**
 * Quanto custa o mês.
 *
 * Valor fixo: o cheio, **proporcional às sessões só quando a vigência começa ou
 * termina dentro do mês**. Férias não entram nessa conta — ver o cabeçalho.
 * Por sessão: a multiplicação, e o mês de cinco sai maior porque é isso que
 * escolher "por sessão" quer dizer.
 */
create or replace function public.valor_da_mensalidade(p_enquadre uuid, p_competencia date)
returns numeric
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  e        record;
  primeiro date := date_trunc('month', p_competencia)::date;
  ultimo   date := (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date;
  cheio    int;
  cabem    int;
begin
  select * into e from public.enquadres where id = p_enquadre;
  if not found then return 0; end if;

  if e.mensalidade_valor is null then
    return round(e.valor * public.sessoes_do_mes(p_enquadre, p_competencia), 2);
  end if;

  cheio := public.ocorrencias_do_dia_no_mes(e.dia_semana, p_competencia);
  if cheio = 0 then return 0; end if;

  -- Mês inteiro dentro da vigência: preço cheio, com cinco terças ou com quatro.
  if e.vigencia_inicio <= primeiro
     and (e.vigencia_fim is null or e.vigencia_fim >= ultimo) then
    return e.mensalidade_valor;
  end if;

  -- Entrou ou saiu no meio: proporcional aos dias da semana que couberam.
  select count(*)::int into cabem
    from generate_series(primeiro, ultimo, interval '1 day') as d
   where extract(dow from d) = e.dia_semana
     and d::date >= e.vigencia_inicio
     and (e.vigencia_fim is null or d::date <= e.vigencia_fim);

  return round(e.mensalidade_valor * cabem / cheio, 2);
end;
$$;

-- ------------------------------------------------- a mensalidade do mês

/**
 * Gera as mensalidades do mês corrente. Idempotente pelo índice único.
 *
 * Roda na passada diária e só faz alguma coisa no dia escolhido pela conta (ou
 * depois dele, se o cron tiver falhado nos dias anteriores — a rotina que só
 * funciona no dia exato é a que perde o mês inteiro por causa de uma
 * indisponibilidade de dez minutos).
 *
 * **Não recalcula.** Uma mensalidade gerada não muda porque uma sessão foi
 * desmarcada depois: sessão desmarcada com antecedência dentro do mensal é
 * conversa de reposição (a B21), não estorno automático. Recalcular sozinho um
 * valor que já foi comunicado é a forma mais rápida de a pessoa deixar de
 * acreditar em qualquer número da tela.
 */
create or replace function public.agendar_mensalidades()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r      record;
  comp   date;
  quanto numeric;
  nova   uuid;
  n      int := 0;
begin
  comp := date_trunc('month', public.hoje_sp())::date;

  for r in
    select e.id, e.conta_id, e.paciente_id, c.mensalidade_dia
      from public.enquadres e
      join public.contas c on c.id = e.conta_id
     where e.vigencia_fim is null
       and e.modelo_cobranca = 'mensal'
       and extract(day from public.hoje_sp()) >= c.mensalidade_dia
  loop
    quanto := public.valor_da_mensalidade(r.id, comp);
    if quanto is null or quanto <= 0 then
      continue;
    end if;

    insert into public.cobrancas (
      conta_id, paciente_id, enquadre_id, tipo, motivo, valor, competencia
    )
    values (
      r.conta_id, r.paciente_id, r.id, 'mensalidade', 'mensalidade', quanto, comp
    )
    on conflict do nothing
    returning id into nova;

    if nova is not null then
      n := n + 1;
    end if;
  end loop;

  return n;
end;
$$;

-- --------------------------------------------------------------- o pacote

/**
 * Vender um pacote: uma cobrança só, na hora, e os créditos passam a existir.
 *
 * O pacote é pago adiantado por definição — é isso que o distingue de um
 * desconto por volume. A cobrança nasce aberta, e o PIX da B16 já sabe o que
 * fazer com ela.
 */
create or replace function public.vender_pacote(
  p_paciente uuid,
  p_quantidade smallint,
  p_valor numeric,
  p_validade date
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac  record;
  enq  uuid;
  novo uuid;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  if p_quantidade is null or p_quantidade < 1 then
    raise exception 'um pacote tem pelo menos uma sessão';
  end if;
  if p_validade is null or p_validade <= public.hoje_sp() then
    raise exception 'a validade tem de ser uma data futura';
  end if;

  select e.id into enq
    from public.enquadres e
   where e.paciente_id = p_paciente and e.vigencia_fim is null;

  insert into public.pacotes (conta_id, paciente_id, enquadre_id, quantidade, valor, validade)
  values (pac.conta_id, p_paciente, enq, p_quantidade, coalesce(p_valor, 0), p_validade)
  returning id into novo;

  if coalesce(p_valor, 0) > 0 then
    insert into public.cobrancas (
      conta_id, paciente_id, enquadre_id, pacote_id, tipo, motivo, valor, competencia
    )
    values (
      pac.conta_id, p_paciente, enq, novo, 'pacote', 'pacote', p_valor,
      date_trunc('month', public.hoje_sp())::date
    );
  end if;

  return novo;
end;
$$;

/**
 * Cancelar um pacote.
 *
 * Não devolve dinheiro e não apaga consumo: encerra o crédito daqui para a
 * frente e cancela a cobrança **se ela ainda estiver aberta**. Estornar
 * automaticamente o que já foi pago seria o sistema decidindo um acerto que é
 * entre duas pessoas.
 */
create or replace function public.cancelar_pacote(p_pacote uuid, p_motivo text default null)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare p record;
begin
  select * into p from public.pacotes where id = p_pacote;
  if not found then raise exception 'pacote não encontrado'; end if;
  if p.cancelado_em is not null then return; end if;

  update public.pacotes
     set cancelado_em = now(),
         motivo_cancelamento = nullif(trim(coalesce(p_motivo, '')), '')
   where id = p_pacote;

  update public.cobrancas
     set estado = 'cancelada'
   where pacote_id = p_pacote and estado = 'aberta';
end;
$$;

-- ---------------------------------------------------- o gatilho, reescrito

/**
 * A sessão mudou de estado — agora com os três modelos.
 *
 * A ordem das perguntas é a regra de negócio inteira:
 *
 *   1. saiu de cobrável ou de consumível? desfaz o que nasceu daquela sessão;
 *   2. tem pacote com saldo valendo no dia? consome um crédito e **não cobra**;
 *   3. é mensalista? a hora já está dentro do mês — só cobra se ela pediu;
 *   4. é avulso? a multa da política, como desde a B11 — e a sessão realizada
 *      vira cobrança se a conta escolheu isso.
 *
 * O que **não** mudou: nada disso mora numa função que o app escolhe chamar. É
 * gatilho desde a 0010, porque o que não pode ser burlado não pode depender de
 * qual botão foi apertado.
 *
 * **Passou a `security definer` nesta migração, e o motivo é o saldo.** Um
 * gatilho `invoker` roda com os direitos de quem apertou o botão, e então
 * `pacote_consumos` precisaria de políticas de insert e delete para o cliente —
 * ou seja, uma tela capaz de plantar e apagar créditos consumidos. Pior: sem
 * política de delete, o estorno do crédito falharia em **zero linhas e sem
 * erro**, que é exatamente o defeito que a 0023 consertou na B11.
 *
 * Com `definer`, o cliente fica sem nenhuma escrita na tabela de consumo e o
 * gatilho escreve. Nada aqui confia em entrada do cliente: todo valor vem de
 * `new` (uma linha de `sessoes`, já protegida pela RLS de lá) ou de uma consulta
 * feita aqui dentro.
 */
create or replace function public.ao_mudar_estado_da_sessao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cobravel_antes boolean;
  cobravel_agora boolean;
  quanto  numeric;
  atraso  int;
  nova    uuid;
  modelo  text;
  a_parte boolean := false;
  enq     record;
  cont    record;
  pac     uuid;
  dia     date;
begin
  cobravel_antes := old.estado in ('cancelada_tarde', 'falta');
  cobravel_agora := new.estado in ('cancelada_tarde', 'falta');

  dia := (new.inicio at time zone 'America/Sao_Paulo')::date;

  select * into cont from public.contas where id = new.conta_id;

  -- O modelo vem do combinado da sessão; sem combinado, é avulso.
  -- `modelo` e `a_parte` são variáveis escalares, e não campos de `enq`, por um
  -- motivo que um teste de regressão encontrou em dez segundos: o plpgsql
  -- **não** curto-circuita `modelo = 'mensal' and enq.falta_cobra_a_parte` —
  -- a expressão inteira vira um SELECT, e ler campo de um record não atribuído
  -- estoura ali mesmo. Numa sessão sem combinado (a maioria dos encaixes), isso
  -- derrubava o cancelamento.
  modelo := 'avulso';
  if new.enquadre_id is not null then
    select * into enq from public.enquadres where id = new.enquadre_id;
    if found then
      modelo  := enq.modelo_cobranca;
      a_parte := coalesce(enq.falta_cobra_a_parte, false);
    end if;
  end if;

  -- ------------------------------------------- deixou de ser cobrável/consumível
  if (cobravel_antes and not cobravel_agora)
     or (old.estado = 'realizada' and new.estado <> 'realizada') then

    update public.cobrancas
       set estado = 'cancelada'
     where sessao_id = new.id and estado in ('aberta', 'perdoada');

    -- O crédito do pacote volta: a sessão desfeita não foi usada.
    delete from public.pacote_consumos where sessao_id = new.id;

    update public.mensagens
       set estado = 'cancelada'
     where chave_idem like 'cobranca:%'
       and estado = 'pendente'
       and (params->>'sessao_id') = new.id::text;

    if not cobravel_agora and new.estado <> 'realizada' then
      return new;
    end if;
  end if;

  -- ------------------------------------------------------- o pacote come antes
  if modelo = 'pacote' and new.estado in ('realizada', 'falta', 'cancelada_tarde') then
    pac := public.pacote_para_sessao(new.paciente_id, dia);

    if pac is not null then
      insert into public.pacote_consumos (conta_id, pacote_id, sessao_id, motivo)
      values (new.conta_id, pac, new.id, new.estado)
      on conflict do nothing;

      -- Consumiu: a hora já estava paga. Só cobra por cima se ela pediu, e só
      -- quando houve falta — sessão realizada dentro do pacote nunca cobra.
      if not (a_parte and cobravel_agora) then
        return new;
      end if;
    end if;
    -- Sem saldo ou fora da validade: cai para o avulso, de propósito. A tela
    -- avisa antes, no painel do pacote — descobrir isso pela cobrança é o pior
    -- lugar possível.
  end if;

  -- -------------------------------------------------- o mensal já foi pago
  if modelo = 'mensal' and cobravel_agora and not a_parte then
    return new;
  end if;

  -- ------------------------------------------------ a sessão que aconteceu
  if new.estado = 'realizada' then
    if not coalesce(cont.cobra_sessao, false) or modelo <> 'avulso' then
      return new;
    end if;
    if new.valor <= 0 then return new; end if;

    insert into public.cobrancas (
      conta_id, paciente_id, sessao_id, enquadre_id, tipo, motivo, valor,
      valor_da_sessao, competencia
    )
    values (
      new.conta_id, new.paciente_id, new.id, new.enquadre_id,
      'sessao', 'sessao_realizada', new.valor, new.valor,
      date_trunc('month', dia)::date
    )
    on conflict do nothing;

    -- Sessão que aconteceu não manda mensagem: a pessoa acabou de sair da
    -- sala. O lembrete de pagamento é da régua, e ele espera os dias dela.
    return new;
  end if;

  if not cobravel_agora then
    return new;
  end if;

  -- --------------------------------------------------------- a multa (B11)
  quanto := public.multa_da_politica(new.valor, new.politica_percentual);
  if quanto <= 0 then
    return new;
  end if;

  atraso := coalesce(cont.cobranca_atraso_min, 60);

  insert into public.cobrancas (
    conta_id, paciente_id, sessao_id, enquadre_id, tipo, motivo, valor,
    politica_horas, politica_percentual, valor_da_sessao, competencia
  )
  values (
    new.conta_id, new.paciente_id, new.id, new.enquadre_id, 'falta', new.estado, quanto,
    new.politica_horas, new.politica_percentual, new.valor,
    date_trunc('month', dia)::date
  )
  on conflict do nothing
  returning id into nova;

  if nova is null then
    return new;
  end if;

  perform public.enfileirar_mensagem(
    new.paciente_id,
    'aviso_de_cobranca',
    'cobranca:' || nova::text,
    jsonb_build_object(
      'cobranca_id', nova,
      'sessao_id', new.id,
      'inicio', new.inicio,
      'valor_centavos', round(quanto * 100)::bigint
    ),
    now() + make_interval(mins => atraso)
  );

  return new;
end;
$$;

-- ---------------------------------------------------------------------- RLS

alter table public.pacotes         enable row level security;
alter table public.pacote_consumos enable row level security;

drop policy if exists "pacotes da conta: ler" on public.pacotes;
create policy "pacotes da conta: ler" on public.pacotes
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "pacotes da conta: escrever" on public.pacotes;
create policy "pacotes da conta: escrever" on public.pacotes
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "pacotes da conta: editar" on public.pacotes;
create policy "pacotes da conta: editar" on public.pacotes
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Consumo é **só leitura** para o cliente. Quem escreve é o gatilho, e nenhuma
-- tela precisa plantar um crédito consumido: um saldo que a interface consegue
-- editar deixa de ser um saldo e vira uma opinião.
drop policy if exists "consumos da conta: ler" on public.pacote_consumos;
create policy "consumos da conta: ler" on public.pacote_consumos
  for select to authenticated using (conta_id = public.conta_atual());

-- ----------------------------------------------------------------- permissões
--
-- Os três, sempre: `public`, `anon` e `authenticated` (0018, 0027, 0031).

revoke execute on function public.agendar_mensalidades() from public, anon, authenticated;
grant  execute on function public.agendar_mensalidades() to service_role;

revoke execute on function public.ocorrencias_do_dia_no_mes(smallint, date) from public, anon;
revoke execute on function public.sessoes_do_mes(uuid, date) from public, anon;
revoke execute on function public.valor_da_mensalidade(uuid, date) from public, anon;
revoke execute on function public.saldo_do_pacote(uuid) from public, anon;
revoke execute on function public.pacote_para_sessao(uuid, date) from public, anon;
revoke execute on function public.vender_pacote(uuid, smallint, numeric, date) from public, anon;
revoke execute on function public.cancelar_pacote(uuid, text) from public, anon;

grant execute on function public.ocorrencias_do_dia_no_mes(smallint, date) to authenticated, service_role;
grant execute on function public.sessoes_do_mes(uuid, date) to authenticated, service_role;
grant execute on function public.valor_da_mensalidade(uuid, date) to authenticated, service_role;
grant execute on function public.saldo_do_pacote(uuid) to authenticated, service_role;
grant execute on function public.pacote_para_sessao(uuid, date) to authenticated, service_role;
grant execute on function public.vender_pacote(uuid, smallint, numeric, date) to authenticated;
grant execute on function public.cancelar_pacote(uuid, text) to authenticated;

comment on table public.pacotes is
  'Pacote pago adiantado. Saldo e derivado de pacote_consumos, nunca coluna.';
comment on table public.pacote_consumos is
  'Uma linha por sessao consumida; unica por sessao. So o gatilho escreve.';
comment on function public.valor_da_mensalidade(uuid, date) is
  'Valor fixo (mes de cinco sai igual, proporcional so na borda da vigencia) ou por sessao do mes.';
