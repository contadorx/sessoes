-- 0037 · B23 — o mês em duas colunas (F1).
--
-- O doc 03 descreve a F1 como "paridade feita do jeito certo: a agenda **já é**
-- o faturamento, zero digitação". A parte difícil não é somar — é escolher
-- **qual** soma, e não deixar as duas virarem uma.
--
-- ## 1. Duas colunas, e elas nunca se somam
--
-- **Realizado** é o que aconteceu: sessões `realizada`, pelo valor congelado
-- naquela sessão. Responde "como foi meu mês".
-- **Recebido** é o que entrou: cobranças `paga`. Responde "quanto eu tenho".
--
-- Somar as duas conta o mesmo dinheiro duas vezes, e no mensalista dá para
-- provar num teste: as quatro terças de março aparecem em realizado (4 × 200) e
-- a mensalidade de março aparece em recebido (750). São R$ 1.550 de nada — é o
-- mesmo mês visto de dois ângulos. Por isso não existe, em lugar nenhum deste
-- arquivo nem da tela, um campo chamado "total".
--
-- ## 2. O caixa é pela data do pagamento, não pela competência
--
-- A psicóloga autônoma é tributada pelo **regime de caixa** (carnê-leão, doc
-- 07): o que ela declara é o que **entrou no mês**. Um pagamento que chegou em
-- 5 de abril por uma sessão de março é dinheiro de abril — e é assim que o
-- número bate com o extrato dela.
--
-- E o recibo continua sendo pela **competência**, porque um recibo fala do
-- período do atendimento. Duas perguntas diferentes, duas datas diferentes, de
-- propósito. Esta é a única linha deste arquivo que, se alguém "consertar" para
-- ficar igual, quebra sem fazer barulho.
--
-- ## 3. "Pago" passa a ter um lugar só — e isso fecha a assimetria da B20
--
-- A 0034 deixou escrito: o recibo de mensalidade e pacote exige pagamento
-- registrado, o do avulso não confere nada, e fechar os dois lados era trabalho
-- desta build "quando o financeiro tiver a resposta sobre o que é 'pago' para
-- quem recebe em dinheiro na hora".
--
-- A resposta é: **ela diz que recebeu, e isso vira uma cobrança paga.** Não uma
-- segunda tabela, não um campo em `sessoes`. Dois lugares guardando "pago" é a
-- definição de contabilidade paralela, e é o defeito que este produto não pode
-- ter, porque o número sai num recibo e numa declaração de imposto de renda.
--
-- `registrar_recebimento` é o mesmo botão nas duas configurações da conta: se
-- já existe cobrança aberta (conta com `cobra_sessao`), ela vira paga; se não
-- existe (o padrão — o dinheiro na mão, depois da sessão), nasce já paga. Com
-- isso o recibo do avulso passa a exigir pagamento igual ao do mensalista, e a
-- assimetria acaba.
--
-- ## 4. Despesa é o que **já saiu**
--
-- O doc 03 §7 põe contas a pagar, conciliação bancária, DRE e folha
-- explicitamente fora. Então a despesa aqui não tem vencimento, não tem
-- parcela, não tem recorrência e não gera alerta: ela tem uma data que já
-- passou, uma categoria e um valor. Lançar o aluguel do mês que vem não é
-- possível, e isso é feature.
--
-- ## 5. Não dizemos o que abate imposto
--
-- As categorias são fixas (dez) porque categoria livre vira quarenta em três
-- meses e a pasta do contador (F3, B25) fica ilegível. Mas em nenhum lugar o
-- sistema diz que uma delas é dedutível: **quem decide o que entra no livro
-- caixa é o contador dela.** O doc 07 é explícito — "o app não calcula, entrega
-- o faturamento certo ao contador". Um rótulo "isto abate imposto" numa tela
-- nossa é parecer fiscal, e errar parecer fiscal custa dinheiro dela com a
-- Receita, não bug nosso.
--
-- ## 6. A despesa não tem paciente. Nunca.
--
-- Não há `paciente_id` nesta tabela e não vai haver. É a mesma regra do F3 (o
-- contador recebe dado financeiro, nunca clínico) escrita no esquema em vez de
-- na feature: a pasta da B25 sai daqui inteira sem precisar esconder nada,
-- porque não há nada a esconder.
--
-- ## 7. O que o sistema trouxe de volta
--
-- O doc 10 pede que cada tela de relatório mostre **as métricas de valor para
-- ela**. Duas saem daqui de graça: as sessões de encaixe realizadas (a hora que
-- ia furar e não furou) e as faltas cobradas que foram pagas (o dinheiro que
-- ela não cobrava). É o produto provando o próprio ROI com dado, não com
-- promessa.
--
-- E a companhia honesta desses números: **sem registro** — as horas que
-- aconteceram e não têm recebimento nenhum. Um painel que só mostra o que
-- entrou é um painel que mente por omissão.

-- ============================================================ as despesas

create table if not exists public.despesas (
  id        uuid primary key default gen_random_uuid(),
  conta_id  uuid not null references public.contas (id) on delete cascade,

  -- A data em que o dinheiro saiu. Regime de caixa, igual ao recebido.
  paga_em   date not null,

  categoria text not null check (categoria in (
    'aluguel',        -- sala, condomínio, coworking por hora
    'supervisao',     -- supervisão clínica
    'formacao',       -- cursos, congressos, livros
    'conselho',       -- anuidade do CRP
    'software',       -- sistemas e assinaturas (este inclusive)
    'material',       -- material de consumo do consultório
    'contabilidade',  -- honorário do contador
    'deslocamento',   -- ir e voltar do consultório
    'impostos',       -- DARF, ISS, taxas
    'outra'
  )),

  descricao text not null check (length(btrim(descricao)) between 2 and 120),
  valor     numeric(12,2) not null check (valor > 0),

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists despesas_da_conta
  on public.despesas (conta_id, paga_em desc);
create index if not exists despesas_por_categoria
  on public.despesas (conta_id, categoria, paga_em desc);

drop trigger if exists despesas_atualizado_em on public.despesas;
create trigger despesas_atualizado_em before update on public.despesas
  for each row execute function public.tocar_atualizado_em();

/**
 * Despesa é passado.
 *
 * Gatilho e não `check`, por dois motivos: `now()` num check não é reavaliado
 * num restore (e a 0037 tem de sobreviver ao ensaio de restauração da B13), e a
 * regra da casa desde a 0010 é que invariante mora em gatilho, nunca numa
 * função que o cliente escolhe chamar.
 */
create or replace function public.despesa_nao_e_do_futuro()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.paga_em > public.hoje_sp() then
    raise exception 'despesa com data no futuro: aqui só entra o que já saiu (% > %)',
      new.paga_em, public.hoje_sp();
  end if;
  return new;
end;
$$;

drop trigger if exists despesa_no_passado on public.despesas;
create trigger despesa_no_passado before insert or update on public.despesas
  for each row execute function public.despesa_nao_e_do_futuro();

alter table public.despesas enable row level security;

drop policy if exists "despesas da conta: ler" on public.despesas;
create policy "despesas da conta: ler" on public.despesas for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "despesas da conta: criar" on public.despesas;
create policy "despesas da conta: criar" on public.despesas for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "despesas da conta: editar" on public.despesas;
create policy "despesas da conta: editar" on public.despesas for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Apagar **é** permitido aqui, e é o contrário do que vale para `cobrancas`.
-- Uma cobrança perdoada é informação sobre uma segunda pessoa e um combinado;
-- uma despesa lançada errada é só um engano dela sobre o próprio dinheiro, sem
-- ninguém do outro lado. Obrigá-la a conviver com a linha errada não protege
-- nada — só suja o número que ela manda para o contador.
drop policy if exists "despesas da conta: apagar" on public.despesas;
create policy "despesas da conta: apagar" on public.despesas for delete to authenticated
  using (conta_id = public.conta_atual());

comment on table public.despesas is
  'F1: o que ja saiu. Sem vencimento, sem parcela, sem paciente. Categoria organiza, nao opina sobre deducao.';

-- ==================================================== o recebimento da sessão

/**
 * "Recebi."
 *
 * Uma porta só para o dinheiro da sessão, nas duas configurações de conta:
 *
 *  - existe cobrança aberta (conta com `cobra_sessao` ligado) → ela vira paga;
 *  - não existe (o padrão) → nasce uma, já paga, com `confirmado_por = 'ela'`.
 *
 * `p_quando` permite registrar o que foi recebido ontem sem inventar um
 * carimbo de hoje — e o carimbo vai ao meio-dia de São Paulo, não à
 * meia-noite, para que nenhuma conversão de fuso empurre o dinheiro para o
 * dia anterior.
 */
create or replace function public.registrar_recebimento(
  p_sessao uuid,
  p_quando date default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s       record;
  cob     record;
  modelo  text := 'avulso';
  enq     record;
  dia     date;
  carimbo timestamptz;
  consumiu boolean;
  novo    uuid;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then raise exception 'sessão não encontrada'; end if;

  if s.estado <> 'realizada' then
    raise exception 'só sessão realizada tem recebimento (esta está %)', s.estado;
  end if;

  if s.valor is null or s.valor <= 0 then
    raise exception 'esta sessão não tem valor: um recebimento de zero não é um registro, é ruído';
  end if;

  dia := coalesce(p_quando, public.hoje_sp());
  if dia > public.hoje_sp() then
    raise exception 'recebimento com data no futuro';
  end if;

  -- Parênteses obrigatórios: `at time zone` liga mais forte que `+`, e sem eles
  -- a soma acontece depois da conversão — o carimbo sai no dia errado.
  carimbo := ((dia + time '12:00') at time zone 'America/Sao_Paulo');

  if s.enquadre_id is not null then
    select * into enq from public.enquadres where id = s.enquadre_id;
    if found then modelo := enq.modelo_cobranca; end if;
  end if;

  if modelo = 'mensal' then
    raise exception 'esta sessão é de mensalidade: o dinheiro dela está na cobrança do mês, não aqui';
  end if;

  select exists (select 1 from public.pacote_consumos where sessao_id = p_sessao)
    into consumiu;
  if consumiu then
    raise exception 'esta sessão consumiu um crédito de pacote: o dinheiro dela entrou na venda do pacote';
  end if;

  select * into cob
    from public.cobrancas
   where sessao_id = p_sessao and estado <> 'cancelada'
   limit 1;

  if found then
    if cob.estado = 'paga' then
      raise exception 'esta sessão já está registrada como recebida';
    end if;
    if cob.estado = 'perdoada' then
      raise exception 'esta cobrança foi perdoada: reverter é decisão sua, não efeito de um botão de recebimento';
    end if;

    update public.cobrancas
       set estado = 'paga', paga_em = carimbo, confirmado_por = 'ela'
     where id = cob.id;
    return cob.id;
  end if;

  insert into public.cobrancas (
    conta_id, paciente_id, sessao_id, enquadre_id, tipo, motivo, valor,
    valor_da_sessao, competencia, estado, paga_em, confirmado_por
  )
  values (
    s.conta_id, s.paciente_id, s.id, s.enquadre_id, 'sessao', 'sessao_realizada',
    s.valor, s.valor,
    date_trunc('month', (s.inicio at time zone 'America/Sao_Paulo')::date)::date,
    'paga', carimbo, 'ela'
  )
  returning id into novo;

  return novo;
end;
$$;

/**
 * Desfazer.
 *
 * O que acontece com a cobrança depende de a conta cobrar por sessão ou não, e
 * a diferença tem consequência no celular de um paciente: numa conta que **não**
 * cobra pelo sistema, reabrir a cobrança colocaria a pessoa na régua de
 * inadimplência (B18) por um dinheiro que nunca esteve sendo cobrado por aqui.
 * Um clique de desfazer não pode virar mensagem para outra pessoa.
 *
 * Pagamento confirmado pelo provedor não se desfaz aqui: esconder dinheiro que
 * entrou de verdade não é desfazer, é errar o extrato.
 */
create or replace function public.desfazer_recebimento(p_sessao uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cob  record;
  cont record;
begin
  select * into cob
    from public.cobrancas
   where sessao_id = p_sessao and estado = 'paga'
   limit 1;

  if not found then raise exception 'esta sessão não tem recebimento registrado'; end if;

  if cob.confirmado_por = 'provedor' then
    raise exception 'este pagamento foi confirmado pelo provedor e não se desfaz por aqui';
  end if;

  select * into cont from public.contas where id = cob.conta_id;

  if coalesce(cont.cobra_sessao, false) then
    update public.cobrancas
       set estado = 'aberta', paga_em = null, confirmado_por = null
     where id = cob.id;
    return 'reaberta';
  end if;

  update public.cobrancas
     set estado = 'cancelada', paga_em = null, confirmado_por = null
   where id = cob.id;
  return 'cancelada';
end;
$$;

-- ================================================== as horas sem registro

/**
 * As sessões que aconteceram e não têm recebimento nenhum.
 *
 * Só as que **deveriam** ter: mensalidade e pacote não entram, porque o
 * dinheiro delas está em outra linha, e listá-las aqui faria a psicóloga
 * registrar duas vezes o mesmo mês.
 */
create or replace function public.sessoes_sem_registro(p_de date, p_ate date)
returns table (
  sessao_id   uuid,
  paciente_id uuid,
  nome        text,
  dia         date,
  inicio      timestamptz,
  valor       numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select s.id, s.paciente_id, p.nome,
         (s.inicio at time zone 'America/Sao_Paulo')::date,
         s.inicio, s.valor
    from public.sessoes s
    join public.pacientes p on p.id = s.paciente_id
    left join public.enquadres e on e.id = s.enquadre_id
   where s.estado = 'realizada'
     and s.valor > 0
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and coalesce(e.modelo_cobranca, 'avulso') <> 'mensal'
     and not exists (select 1 from public.pacote_consumos pc where pc.sessao_id = s.id)
     and not exists (
       select 1 from public.cobrancas c
        where c.sessao_id = s.id and c.estado <> 'cancelada'
     )
   order by s.inicio;
$$;

-- ==================================================== o painel do mês

/**
 * O mês, em duas colunas que não se somam.
 *
 * `realizado` é competência (a data da sessão); `recebido` é caixa (a data do
 * pagamento). `em_aberto` e `perdoado` não têm data de pagamento — por isso
 * usam a competência da cobrança, e é a única forma de a soma do mês fechar
 * com o que a tela "Em aberto" mostra.
 */
create or replace function public.financeiro_do_mes(p_de date, p_ate date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  realizado_valor numeric := 0;  realizado_n int := 0;
  recebido_valor  numeric := 0;  recebido_n  int := 0;
  aberto_valor    numeric := 0;  aberto_n    int := 0;
  perdoado_valor  numeric := 0;  perdoado_n  int := 0;
  despesa_valor   numeric := 0;  despesa_n   int := 0;
  encaixe_valor   numeric := 0;  encaixe_n   int := 0;
  falta_valor     numeric := 0;  falta_n     int := 0;
  sem_valor       numeric := 0;  sem_n       int := 0;
  por_tipo        jsonb;
  por_categoria   jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  -- ------------------------------------------------- realizado (competência)
  select coalesce(sum(s.valor), 0), count(*)
    into realizado_valor, realizado_n
    from public.sessoes s
   where s.conta_id = c
     and s.estado = 'realizada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ------------------------------------------------------- recebido (caixa)
  select coalesce(sum(cb.valor), 0), count(*)
    into recebido_valor, recebido_n
    from public.cobrancas cb
   where cb.conta_id = c
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  select coalesce(jsonb_object_agg(t.tipo, t.soma), '{}'::jsonb)
    into por_tipo
    from (
      select cb.tipo, sum(cb.valor) as soma
        from public.cobrancas cb
       where cb.conta_id = c
         and cb.estado = 'paga'
         and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
       group by cb.tipo
    ) t;

  -- -------------------------------------------- em aberto e perdoado (comp.)
  select coalesce(sum(cb.valor), 0), count(*)
    into aberto_valor, aberto_n
    from public.cobrancas cb
   where cb.conta_id = c and cb.estado = 'aberta'
     and cb.competencia between date_trunc('month', p_de)::date and p_ate;

  select coalesce(sum(cb.valor), 0), count(*)
    into perdoado_valor, perdoado_n
    from public.cobrancas cb
   where cb.conta_id = c and cb.estado = 'perdoada'
     and cb.competencia between date_trunc('month', p_de)::date and p_ate;

  -- ------------------------------------------------------------- despesas
  select coalesce(sum(d.valor), 0), count(*)
    into despesa_valor, despesa_n
    from public.despesas d
   where d.conta_id = c and d.paga_em between p_de and p_ate;

  select coalesce(jsonb_agg(x order by x->>'categoria'), '[]'::jsonb)
    into por_categoria
    from (
      select jsonb_build_object(
               'categoria', d.categoria,
               'valor', sum(d.valor),
               'lancamentos', count(*)
             ) as x
        from public.despesas d
       where d.conta_id = c and d.paga_em between p_de and p_ate
       group by d.categoria
    ) g;

  -- ------------------------------------------------------- o que voltou
  select coalesce(sum(s.valor), 0), count(*)
    into encaixe_valor, encaixe_n
    from public.sessoes s
   where s.conta_id = c
     and s.estado = 'realizada'
     and s.origem = 'encaixe'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  select coalesce(sum(cb.valor), 0), count(*)
    into falta_valor, falta_n
    from public.cobrancas cb
   where cb.conta_id = c
     and cb.tipo = 'falta'
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- ---------------------------------------------------------- sem registro
  select coalesce(sum(x.valor), 0), count(*)
    into sem_valor, sem_n
    from public.sessoes_sem_registro(p_de, p_ate) x;

  return jsonb_build_object(
    'de', p_de,
    'ate', p_ate,
    'realizado', jsonb_build_object('valor', realizado_valor, 'sessoes', realizado_n),
    'recebido',  jsonb_build_object('valor', recebido_valor, 'cobrancas', recebido_n,
                                    'por_tipo', por_tipo),
    'em_aberto', jsonb_build_object('valor', aberto_valor, 'cobrancas', aberto_n),
    'perdoado',  jsonb_build_object('valor', perdoado_valor, 'cobrancas', perdoado_n),
    'despesas',  jsonb_build_object('valor', despesa_valor, 'lancamentos', despesa_n,
                                    'por_categoria', por_categoria),
    -- Sobra, não lucro: é caixa menos despesa lançada, e não pretende ser
    -- resultado contábil. DRE está fora do produto por decisão (doc 03 §7).
    'sobra', recebido_valor - despesa_valor,
    'recuperado', jsonb_build_object(
      'encaixes', encaixe_n, 'valor_encaixes', encaixe_valor,
      'faltas', falta_n, 'valor_faltas', falta_valor
    ),
    'sem_registro', jsonb_build_object('sessoes', sem_n, 'valor', sem_valor)
  );
end;
$$;

-- ================================================ o recibo, agora simétrico

/**
 * A 0034 fez o recibo de mensalidade e pacote exigir pagamento registrado e
 * deixou o do avulso sem conferência nenhuma, porque não havia como registrar
 * "recebi em dinheiro" sem ligar a cobrança por sessão. Agora há
 * (`registrar_recebimento`), então a regra passa a ser uma só:
 *
 *   **recibo e informe anual só saem sobre dinheiro que entrou.**
 *
 * O que muda de fato: a psicóloga que emitia recibo direto das sessões passa a
 * ter um passo a mais — dizer que recebeu. É um clique, e é o clique que separa
 * "atendi" de "recebi". Sem ele, o documento assina que entrou dinheiro que
 * pode não ter entrado, com o nome dela no papel.
 *
 * A declaração de comparecimento continua saindo das **sessões**: ela fala de
 * presença, não de dinheiro, e exigir pagamento para provar que alguém esteve
 * na sala seria confundir duas coisas que a Res. CFP 06/2019 separa.
 *
 * O período continua sendo o do **atendimento** (competência), não o do
 * pagamento — ver a decisão nº 2 do cabeçalho desta migração.
 */
create or replace function public.emitir_documento(
  p_paciente uuid,
  p_tipo text,
  p_de date,
  p_ate date
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  cont record;
  itens_sessoes jsonb;
  quantos_sessoes int;
  itens jsonb;
  total numeric(12,2);
  quantos int;
  proximo int;
  novo uuid;
  por_cobranca boolean;
  pagas numeric(12,2);
  quantas_pagas int;
  base text;
begin
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  select p.*, pr.crp, pr.assina_como, pr.documento as prof_documento,
         u.nome as prof_nome
    into pac
    from public.pacientes p
    join public.profissionais pr on pr.id = p.profissional_id
    join public.usuarios u on u.id = pr.usuario_id
   where p.id = p_paciente;

  if not found then raise exception 'paciente não encontrado'; end if;

  select * into cont from public.contas where id = pac.conta_id;

  -- As sessões que de fato aconteceram. Falta cobrada não entra: não é
  -- atendimento prestado, e convênio nenhum reembolsa.
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'inicio', s.inicio,
        'dia', (s.inicio at time zone 'America/Sao_Paulo')::date,
        'valor', s.valor
      ) order by s.inicio
    ), '[]'::jsonb),
    count(*)
    into itens_sessoes, quantos_sessoes
    from public.sessoes s
   where s.paciente_id = p_paciente
     and s.estado = 'realizada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  -- Antes de falar de dinheiro: houve atendimento? A ordem das recusas importa
  -- — foi um teste de regressão da B17 que mostrou o porquê. Um período vazio
  -- respondendo "marque a sessão como recebida" manda a psicóloga procurar um
  -- pagamento que não existe, quando o que falta é a sessão.
  if quantos_sessoes = 0 then
    raise exception 'não há sessão realizada neste período';
  end if;

  if p_tipo = 'declaracao_comparecimento' then
    total   := 0;
    quantos := quantos_sessoes;
    base    := 'sessoes';
    select coalesce(jsonb_agg(x - 'valor'), '[]'::jsonb) into itens
      from jsonb_array_elements(itens_sessoes) x;
  else
    -- Houve mensalidade ou pacote tocando este período? Então a lista de
    -- sessões sai sem valor por linha: o total é do combinado do mês, e duas
    -- contas diferentes no mesmo papel é o que faz alguém desconfiar do
    -- documento inteiro.
    select exists (
      select 1 from public.cobrancas cb
       where cb.paciente_id = p_paciente
         and cb.tipo in ('mensalidade', 'pacote')
         and cb.estado <> 'cancelada'
         and cb.competencia between date_trunc('month', p_de)::date and p_ate
    ) into por_cobranca;

    select coalesce(sum(cb.valor), 0), count(*)
      into pagas, quantas_pagas
      from public.cobrancas cb
     where cb.paciente_id = p_paciente
       and cb.tipo in ('mensalidade', 'pacote', 'sessao')
       and cb.estado = 'paga'
       and cb.competencia between date_trunc('month', p_de)::date and p_ate;

    if pagas <= 0 then
      raise exception 'não há pagamento registrado neste período: marque a sessão como recebida antes de emitir o recibo';
    end if;

    total := pagas;

    if por_cobranca then
      quantos := quantos_sessoes;
      base    := 'cobrancas_pagas';
      select coalesce(jsonb_agg(x - 'valor'), '[]'::jsonb) into itens
        from jsonb_array_elements(itens_sessoes) x;
    else
      -- Avulso: cada linha é uma sessão paga, com o valor **da cobrança**, que
      -- é o que entrou — e não o valor da sessão, que é o que foi combinado.
      quantos := quantas_pagas;
      base    := 'cobrancas_por_sessao';
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'inicio', s.inicio,
                 'dia', (s.inicio at time zone 'America/Sao_Paulo')::date,
                 'valor', cb.valor
               ) order by s.inicio
             ), '[]'::jsonb)
        into itens
        from public.cobrancas cb
        join public.sessoes s on s.id = cb.sessao_id
       where cb.paciente_id = p_paciente
         and cb.tipo = 'sessao'
         and cb.estado = 'paga'
         and cb.competencia between date_trunc('month', p_de)::date and p_ate;
    end if;
  end if;

  -- A numeração serializa na linha da conta: sem isto, duas emissões
  -- simultâneas pegariam o mesmo número.
  select * into cont from public.contas where id = pac.conta_id for update;

  select coalesce(max(d.numero), 0) + 1 into proximo
    from public.documentos d where d.conta_id = pac.conta_id;

  insert into public.documentos (
    conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
    valor_total, quantidade, retrato
  )
  values (
    pac.conta_id, p_paciente, proximo, p_tipo, p_de, p_ate,
    total, quantos,
    jsonb_build_object(
      'profissional', jsonb_build_object(
        'nome', coalesce(pac.assina_como, pac.prof_nome),
        'crp', pac.crp,
        'documento', pac.prof_documento
      ),
      'conta', jsonb_build_object('nome', cont.nome, 'cidade', cont.cidade),
      'paciente', jsonb_build_object('nome', pac.nome, 'cpf', pac.cpf),
      -- Quem lê o documento daqui a dois anos precisa saber de onde saiu o
      -- número, sem ter de reconstituir o modelo de cobrança da época.
      'base', base,
      'itens', itens
    )
  )
  returning id into novo;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (pac.conta_id, p_paciente, 'exportou_paciente',
          jsonb_build_object('documento', p_tipo, 'numero', proximo));

  return novo;
end;
$$;

-- ============================================ a despesa sai junto (LGPD/B13)

/**
 * A exportação da conta é a portabilidade dela (doc 07): sai levando tudo.
 * Despesa é dado dela sobre o próprio dinheiro — se ficasse de fora, "tudo"
 * viraria "quase tudo", e é justamente o pedaço que o contador vai querer.
 */
create or replace function public.exportar_conta()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  saida jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o armário do consultório.',
    'conta', (select to_jsonb(x) from public.contas x where x.id = c),
    'profissionais', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                        from public.profissionais p where p.conta_id = c),
    'pacientes', (select coalesce(jsonb_agg(to_jsonb(p) order by p.nome), '[]'::jsonb)
                    from public.pacientes p where p.conta_id = c),
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                    from public.enquadres e where e.conta_id = c),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.conta_id = c),
    'excecoes_agenda', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                          from public.excecoes_agenda x where x.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

-- ==================================================================== grants

revoke execute on function public.despesa_nao_e_do_futuro() from public, anon, authenticated;

revoke execute on function public.registrar_recebimento(uuid, date) from public, anon;
revoke execute on function public.desfazer_recebimento(uuid) from public, anon;
revoke execute on function public.sessoes_sem_registro(date, date) from public, anon;
revoke execute on function public.financeiro_do_mes(date, date) from public, anon;
revoke execute on function public.emitir_documento(uuid, text, date, date) from public, anon;
revoke execute on function public.exportar_conta() from public, anon;

grant execute on function public.registrar_recebimento(uuid, date) to authenticated;
grant execute on function public.desfazer_recebimento(uuid) to authenticated;
grant execute on function public.sessoes_sem_registro(date, date) to authenticated;
grant execute on function public.financeiro_do_mes(date, date) to authenticated;
grant execute on function public.emitir_documento(uuid, text, date, date) to authenticated;
grant execute on function public.exportar_conta() to authenticated;

comment on function public.financeiro_do_mes(date, date) is
  'F1: realizado (competencia) e recebido (caixa) lado a lado. Nao existe total: somar os dois conta o mesmo dinheiro duas vezes.';
comment on function public.registrar_recebimento(uuid, date) is
  'Recebi. Cobranca aberta vira paga; sem cobranca, nasce ja paga. "Pago" tem um lugar so.';
