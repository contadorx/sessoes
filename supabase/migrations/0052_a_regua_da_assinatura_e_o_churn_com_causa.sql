-- =====================================================================
-- 0052 · OP6 · A régua da minha assinatura, e o churn com causa
-- =====================================================================
--
-- POR QUE ESTA MIGRAÇÃO EXISTE
--
-- A OP5 deixou duas coisas escritas como pendência, e as duas são de dinheiro:
-- *"a régua de cobrança da minha assinatura"* e *"a retenção com lista e causa —
-- hoje o churn é um número sozinho no painel"*.
--
-- Fui escrever a segunda e encontrei a primeira coisa desta migração que não
-- estava prevista.
--
--
-- O DEFEITO: TODA SUBIDA DE PLANO ESTAVA SENDO CONTADA COMO CHURN
--
-- `mudar_plano` (0050) cancela a assinatura atual e abre outra — decisão
-- correta, e o cabeçalho da 0050 explica por quê: um `update plano_codigo`
-- apagaria a história, e a conta que subiu de Grátis para Solo em março e para
-- Pro em julho passaria a parecer sempre Pro.
--
-- Só que `churn_do_mes` (0045) conta assim:
--
--     select count(*) ... where a.cancelada_em >= ini and a.cancelada_em < fim
--
-- **Toda** assinatura cancelada no mês. Inclusive a que `mudar_plano` cancelou
-- meio segundo antes de abrir a nova. Ou seja: promover uma cliente de Solo
-- para Pro registrava um churn. Com doze contas, uma promoção viraria ~8% de
-- churn no mês — e o número mais importante do doc 10 (churn < 5%) mediria o
-- contrário do que aconteceu.
--
-- Nenhum teste pegaria: a suíte 0050 confere que mudar de plano preserva o
-- histórico, e ele preserva. O churn é um número que ninguém confere contra a
-- realidade porque ele **é** a medida da realidade.
--
-- **Regra que ficou:** quando uma operação é implementada como outra
-- (`mudar_plano` como `cancelar` + `abrir`), toda métrica que conta a segunda
-- passa a contar a primeira. A conta certa não é sobre a linha; é sobre o
-- **motivo** de ela existir.
--
-- E é isso que a coluna nova conserta, além de responder ao pedido original.
--
--
-- A CAUSA, E POR QUE ELA NÃO SUBSTITUI A FRASE
--
-- `motivo_cancelamento` existe desde a 0045 e é obrigatório desde a 0050. É
-- texto livre, e continua sendo — o que entra ali é **o que aconteceu, com as
-- palavras de quem disse**. `causa_cancelamento` é uma lista fechada, e é a
-- minha classificação daquilo.
--
-- Duas colunas porque juntar as duas perde uma das duas. Uma lista sozinha
-- perde a frase que diz **o que construir** ("achou caro" e "achou caro porque
-- só usa a agenda" mandam fazer coisas diferentes). Uma frase sozinha não se
-- conta, e churn que não se conta não muda decisão nenhuma.
--
-- A frase é dela; a categoria é minha. E a tela diz isso.
--
--
-- A RÉGUA, E O QUE ELA NÃO PODE FAZER
--
-- A régua da B18 cobra **paciente**, e por isso ela não endurece: o devedor é
-- alguém em dificuldade, o texto é o mesmo em todos os degraus, e há um teste
-- comparando o primeiro lembrete com o terceiro para exigir que sejam a mesma
-- string. Aqui o devedor é um negócio, e endurecer é legítimo.
--
-- Mas há uma coisa que esta régua **não faz**, e é a decisão inteira desta
-- metade da migração:
--
--     Suspender uma conta nunca tira o registro dela.
--
-- Agenda, prontuário, anamnese, evolução, linha do tempo e exportação
-- continuam de pé numa conta suspensa. Três motivos, e cada um bastaria:
--
--   1. **A guarda de cinco anos é obrigação dela, não minha.** Res. CFP
--      001/2009. Trancar o prontuário por uma dívida comigo põe uma
--      profissional em descumprimento de um dever perante o Conselho dela —
--      por causa de uma fatura minha.
--
--   2. **O paciente não tem contrato comigo.** Usar o registro dele como
--      alavanca de cobrança é transformar dado de terceiro em garantia. É a
--      mesma família da fronteira 10 do doc 11 ("a fila nunca vira leilão"):
--      dinheiro não decide quem é atendido, e não decide quem fica registrado.
--
--   3. **A exportação é o que ela precisa exatamente na hora em que não pode
--      pagar.** Uma exportação bloqueada por inadimplência é sequestro de
--      arquivo — e é o momento em que ela mais precisa levar o prontuário para
--      onde for continuar.
--
-- COMO A SUSPENSÃO É EXPRESSA, E POR QUE ASSIM
--
-- Suspender **devolve a conta ao plano Grátis**. Só isso.
--
-- Não é atalho: é a única forma que torna a decisão acima uma consequência em
-- vez de uma promessa. O plano Grátis foi desenhado, na OP3, exatamente como
-- *"tudo o que é registro"* — a régua do cardápio é a frase que organiza o
-- produto inteiro. Então não existe caminho de código que a suspensão possa
-- percorrer para tirar prontuário: para tirar, alguém teria de primeiro tirar
-- do Grátis, que é uma decisão de produto visível, com landing, preço e teste.
--
-- E o que a suspensão de fato tira é o que se cobra: a fila que oferece a vaga
-- sozinha e a régua que cobra sem ela mandar a mensagem. A máquina para; o
-- registro fica.
--
-- **E o paciente nunca sente.** Lembrete de véspera, aviso de desmarque e
-- confirmação de encaixe são essenciais (0046) e saem em qualquer plano,
-- inclusive no Grátis, inclusive estourado. Senão alguém iria ao consultório
-- encontrar a porta fechada porque **eu** não fui pago — e essa pessoa não
-- escolheu nada disto e nem sabe que eu existo.
--
-- **A volta é imediata e não custa nada.** Baixar a fatura devolve o plano no
-- mesmo instante, e não há taxa de religamento em lugar nenhum desta migração.
-- Cobrar para religar é lucrar com a dificuldade.
--
-- **E a régua não passa em conta de cortesia nem de teste.** Senão eu receberia
-- aviso de atraso de uma conta que eu mesmo dei.
--
--
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
--
-- Não envia e-mail. Não existe provedor de e-mail com anexo neste projeto, e é
-- a mesma fronteira das outras três peças não escritas (Asaas, pasta do
-- contador, Google Agenda): **não dá para exercitar o que não tem provedor.**
-- Os avisos nascem numa fila com estado, do mesmo jeito que o outbox da B9, e
-- quem os manda hoje sou eu, à mão, marcando na tela. No dia em que houver
-- provedor, muda um arquivo.
-- =====================================================================

-- ============================================ 1 · o estado novo da assinatura

/**
 * `suspensa` entra na lista, e a lista é lida **do banco**.
 *
 * Lição da B26 (0040f), que apagou a remarcação inteira por copiar a lista de
 * uma migração antiga: `drop constraint` + `add constraint` reescreve o todo.
 * A lista viva, conferida agora, é: trial · ativa · em_atraso · cancelada.
 */
alter table public.assinaturas drop constraint if exists assinaturas_estado_check;
alter table public.assinaturas add constraint assinaturas_estado_check
  check (estado in ('trial', 'ativa', 'em_atraso', 'suspensa', 'cancelada'));

/**
 * A causa, como lista fechada — e `mudanca_de_plano` está nela de propósito.
 *
 * É o que conserta o defeito do cabeçalho: a troca de plano é uma linha
 * cancelada que **não é churn**, e a única forma de o churn saber disso é a
 * própria linha dizer por que existe.
 */
alter table public.assinaturas
  add column if not exists causa_cancelamento text
  check (causa_cancelamento is null or causa_cancelamento in (
    'preco',
    'parou_de_atender',
    'foi_para_outro',
    'faltou_recurso',
    'nao_usou',
    'problema_no_produto',
    'inadimplencia',
    'mudanca_de_plano',
    'outra'
  ));

comment on column public.assinaturas.causa_cancelamento is
  'A minha classificacao do cancelamento. A frase de quem cancelou fica em motivo_cancelamento, com as palavras dela — as duas colunas existem porque juntar as duas perde uma das duas. mudanca_de_plano NAO e churn.';

/**
 * Quais causas são churn de verdade.
 *
 * Mora numa função, e não numa lista dentro de cada consulta, pela mesma
 * manobra da B7, da B25 e do `sessoes_ate_fechar_anamnese` da B29: uma regra
 * que aparece em três lugares diverge em três velocidades diferentes.
 *
 * E `inadimplencia` **conta** como churn: é perda de verdade. Separá-la das
 * outras é o que responde a pergunta que muda o roadmap — estou perdendo
 * gente, ou estou perdendo pagamento?
 */
create or replace function public.causas_de_churn()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'preco', 'parou_de_atender', 'foi_para_outro', 'faltou_recurso',
    'nao_usou', 'problema_no_produto', 'inadimplencia', 'outra'
  ]::text[];
$$;

-- ============================================ 2 · a régua, e os prazos dela

/**
 * Os prazos, num lugar só, e ditos como palpite.
 *
 * Três avisos e uma suspensão. Os dias são escolha minha, sem base em dado
 * nenhum — não existe uma cliente inadimplente ainda —, e é por isso que eles
 * moram numa função em vez de estarem escritos em quatro lugares: quando a
 * primeira cobrança real acontecer, muda aqui.
 *
 * É a mesma manobra do "3" da anamnese: um número que não se apresenta como
 * palpite vira regra por hábito antes de alguém opinar sobre ele.
 */
create or replace function public.regua_da_assinatura()
returns table (degrau smallint, dias smallint, assunto text, corpo text)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    (1::smallint, 3::smallint,
     'A fatura do Sessões venceu',
     'A fatura venceu há três dias. Se já pagou, ignore — pode ser cruzamento de datas, e eu dou baixa assim que vejo. Se não deu, me responda que a gente resolve.'),
    (2::smallint, 10::smallint,
     'A fatura do Sessões segue em aberto',
     'A fatura está em aberto há dez dias. Nada mudou na sua conta e nada vai mudar sem aviso — só quero saber se houve algum problema.'),
    (3::smallint, 20::smallint,
     'Em cinco dias a parte automática do Sessões pausa',
     'A fatura está em aberto há vinte dias. Em cinco dias a conta volta ao plano Grátis: a fila deixa de oferecer vaga sozinha e a régua de cobrança pausa. Agenda, prontuário e exportação continuam inteiros — isso não se toca. Pagando, tudo volta no mesmo instante.')
  ) as t(degrau, dias, assunto, corpo);
$$;

/** O dia da suspensão. Separado da régua porque não é um aviso, é um efeito. */
create or replace function public.dias_para_suspender()
returns smallint
language sql
immutable
set search_path = ''
as $$ select 25::smallint; $$;

create table if not exists public.avisos_assinatura (
  id         uuid primary key default gen_random_uuid(),
  conta_id   uuid not null references public.contas(id) on delete cascade,
  fatura_id  uuid not null references public.faturas(id) on delete cascade,
  degrau     smallint not null check (degrau between 1 and 3),

  assunto    text not null,
  corpo      text not null,

  -- Mesma forma do outbox da B9: a linha nasce pendente, e quem a marca como
  -- enviada é quem enviou. Hoje sou eu, à mão, porque não há provedor.
  estado     text not null default 'pendente'
             check (estado in ('pendente', 'enviado', 'cancelado')),

  criado_em  timestamptz not null default now(),
  enviado_em timestamptz,

  -- Um aviso por degrau por fatura. Sem isto, uma passada repetida do cron
  -- produziria o mesmo aviso todo dia — e uma caixa de entrada com trinta
  -- cópias do mesmo texto é pior que nenhum aviso.
  unique (fatura_id, degrau)
);

comment on table public.avisos_assinatura is
  'A regua da MINHA assinatura — nao a da paciente (B18). Nasce pendente e espera provedor de e-mail; ate la eu marco como enviado na tela.';

create index if not exists avisos_pendentes
  on public.avisos_assinatura (criado_em)
  where estado = 'pendente';

alter table public.avisos_assinatura enable row level security;
-- Sem política nenhuma: isto é meu, e se lê por função com `e_operador()`.

-- ============================================ 3 · a passada da régua

/**
 * A passada diária: vence, atrasa, avisa, suspende — nessa ordem.
 *
 * A ordem tem motivo, e é a mesma disciplina da passada diária da B14: cada
 * passo depende do estado que o anterior escreveu. Vencer a fatura antes de
 * marcar a assinatura evita que uma fatura vencida hoje só apareça amanhã; e
 * suspender por último garante que o degrau 3 sempre saiu antes da suspensão —
 * uma conta que pausa sem ter sido avisada é a versão comercial do 307 mudo.
 *
 * **Não passa em conta de teste nem em assinatura de cortesia.** As duas
 * existem porque eu as criei; cobrar delas é cobrar de mim.
 */
create or replace function public.passar_a_regua_das_assinaturas()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_vencidas   integer := 0;
  n_atraso     integer := 0;
  n_avisos     integer := 0;
  n_suspensas  integer := 0;
  f            record;
  d            record;
  hoje         date := public.hoje_sp();
begin
  -- 1 · a fatura pendente cujo vencimento passou vira vencida.
  update public.faturas set estado = 'vencida'
   where estado = 'pendente' and vencimento < hoje;
  get diagnostics n_vencidas = row_count;

  -- 2 · a assinatura viva com fatura vencida entra em atraso.
  --
  -- `ativa` e `trial` entram; `suspensa` não volta para `em_atraso`, porque
  -- seria regressão de estado — quem estava suspensa continua suspensa até
  -- alguém pagar.
  update public.assinaturas a
     set estado = 'em_atraso'
   where a.estado in ('ativa', 'trial')
     and exists (
       select 1 from public.faturas f
        where f.assinatura_id = a.id and f.estado = 'vencida'
     );
  get diagnostics n_atraso = row_count;

  -- 3 · os avisos, um por degrau por fatura.
  for f in
    select fa.id as fatura, fa.conta_id, fa.vencimento, fa.competencia,
           (hoje - fa.vencimento) as dias
      from public.faturas fa
      join public.contas ct on ct.id = fa.conta_id
      join public.assinaturas a on a.id = fa.assinatura_id
     where fa.estado = 'vencida'
       and not ct.is_teste
       and a.origem <> 'cortesia'
  loop
    for d in select * from public.regua_da_assinatura() where dias <= f.dias
    loop
      insert into public.avisos_assinatura (conta_id, fatura_id, degrau, assunto, corpo)
      values (f.conta_id, f.fatura, d.degrau, d.assunto, d.corpo)
      on conflict (fatura_id, degrau) do nothing;

      if found then n_avisos := n_avisos + 1; end if;
    end loop;
  end loop;

  -- 4 · a suspensão, e ela é o plano Grátis de volta.
  for f in
    select distinct a.id as assinatura, a.conta_id
      from public.assinaturas a
      join public.contas ct on ct.id = a.conta_id
      join public.faturas fa on fa.assinatura_id = a.id
     where a.estado = 'em_atraso'
       and fa.estado = 'vencida'
       and not ct.is_teste
       and a.origem <> 'cortesia'
       and (hoje - fa.vencimento) >= public.dias_para_suspender()
  loop
    update public.assinaturas set estado = 'suspensa' where id = f.assinatura;
    -- É aqui que a decisão inteira acontece, e ela cabe numa linha: a conta
    -- volta ao piso, e o piso foi desenhado para ser habitável.
    update public.contas set plano = 'gratis' where id = f.conta_id;
    n_suspensas := n_suspensas + 1;
  end loop;

  return jsonb_build_object(
    'dia', hoje,
    'faturas_vencidas', n_vencidas,
    'assinaturas_em_atraso', n_atraso,
    'avisos_criados', n_avisos,
    'contas_suspensas', n_suspensas
  );
end;
$$;

/**
 * Marcar um aviso como enviado — o passo que hoje é meu e um dia é do provedor.
 */
create or replace function public.marcar_aviso_enviado(p_aviso uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  update public.avisos_assinatura
     set estado = 'enviado', enviado_em = now()
   where id = p_aviso and estado = 'pendente';

  if not found then
    raise exception 'este aviso já saiu da fila';
  end if;
end;
$$;

/** Os avisos que ainda não saíram, com o nome da conta. Nada de paciente. */
create or replace function public.avisos_pendentes()
returns table (
  id          uuid,
  conta_id    uuid,
  conta       text,
  competencia date,
  vencimento  date,
  dias        integer,
  degrau      smallint,
  assunto     text,
  corpo       text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'só o operador vê a régua das assinaturas';
  end if;

  return query
    select av.id, av.conta_id, ct.nome, fa.competencia, fa.vencimento,
           (public.hoje_sp() - fa.vencimento)::integer,
           av.degrau, av.assunto, av.corpo
      from public.avisos_assinatura av
      join public.contas ct on ct.id = av.conta_id
      join public.faturas fa on fa.id = av.fatura_id
     where av.estado = 'pendente'
     order by fa.vencimento;
end;
$$;

-- ============================================ 4 · a volta, e ela é imediata

/**
 * Baixar a fatura — agora com a volta da suspensão junto.
 *
 * Lida do banco antes de reescrever (`pg_get_functiondef`), que é a lição da
 * OP2: `create or replace function` é `drop` + `create` disfarçado, e a versão
 * viva pode ter sido reescrita por três builds desde a que criou a função.
 *
 * O que ficou igual: só fatura pendente ou vencida é baixada, e a data do
 * pagamento é a do servidor.
 *
 * O que entrou: se **nenhuma outra** fatura vencida sobrou, a assinatura volta
 * ao ar e a conta volta ao plano dela — no mesmo instante, e sem taxa nenhuma.
 * E os avisos daquela fatura que ainda não saíram são cancelados: mandar o
 * degrau 3 no dia seguinte ao pagamento é o tipo de coisa que faz alguém
 * cancelar de raiva um serviço que já pagou.
 */
create or replace function public.baixar_fatura(p_fatura uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  a_assinatura uuid;
  a_conta      uuid;
  o_plano      text;
  o_estado     text;
  sobrou       integer;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  update public.faturas set estado = 'paga'
   where id = p_fatura and estado in ('pendente', 'vencida')
  returning assinatura_id, conta_id into a_assinatura, a_conta;

  if not found then
    raise exception 'só fatura pendente ou vencida é baixada';
  end if;

  -- Aviso pendente de uma fatura paga não sai.
  update public.avisos_assinatura
     set estado = 'cancelado'
   where fatura_id = p_fatura and estado = 'pendente';

  if a_assinatura is null then
    return;
  end if;

  -- plpgsql não curto-circuita: o estado é lido numa variável escalar antes de
  -- qualquer condição sobre ele. É a armadilha da B20, da B24 e da B25.
  select estado, plano_codigo into o_estado, o_plano
    from public.assinaturas where id = a_assinatura;

  if o_estado not in ('em_atraso', 'suspensa') then
    return;
  end if;

  select count(*) into sobrou
    from public.faturas
   where assinatura_id = a_assinatura and estado = 'vencida';

  if sobrou > 0 then
    return;
  end if;

  update public.assinaturas set estado = 'ativa' where id = a_assinatura;
  update public.contas set plano = o_plano where id = a_conta;
end;
$$;

-- ============================================ 5 · o cancelamento com causa

/**
 * Cancelar — agora com a categoria além da frase.
 *
 * A frase continua obrigatória e continua sendo dela. A causa é minha, é
 * obrigatória, e é o que faz o churn ser contável.
 *
 * O padrão do parâmetro é `'outra'` para que nenhuma chamada antiga quebre — e
 * `'outra'` é uma resposta honesta, ao contrário de `null`, que se lê como
 * "ninguém decidiu" e é indistinguível de "esqueci".
 */
create or replace function public.cancelar_assinatura(
  p_assinatura uuid,
  p_motivo     text,
  p_causa      text default 'outra'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare a_conta uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'cancelamento sem motivo escrito é churn sem causa — escreva o porquê';
  end if;

  if p_causa is null or p_causa not in (
    'preco', 'parou_de_atender', 'foi_para_outro', 'faltou_recurso',
    'nao_usou', 'problema_no_produto', 'inadimplencia', 'mudanca_de_plano', 'outra'
  ) then
    raise exception 'causa desconhecida: % — a lista é fechada porque churn que não se conta não muda decisão nenhuma', p_causa;
  end if;

  select conta_id into a_conta from public.assinaturas where id = p_assinatura;
  if a_conta is null then raise exception 'assinatura não encontrada'; end if;

  update public.assinaturas
     set estado = 'cancelada',
         motivo_cancelamento = btrim(p_motivo),
         causa_cancelamento = p_causa
   where id = p_assinatura and estado <> 'cancelada';

  update public.contas set plano = 'gratis' where id = a_conta;
end;
$$;

/**
 * Mudar de plano — e a troca declara a própria causa.
 *
 * Esta linha é a correção do defeito do cabeçalho. A assinatura antiga
 * continua sendo cancelada (é o que preserva a história), e agora ela sai
 * marcada como `mudanca_de_plano`, que o churn não conta.
 */
create or replace function public.mudar_plano(p_conta uuid, p_plano text, p_motivo text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare atual uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select id into atual from public.assinaturas
   where conta_id = p_conta and estado in ('trial', 'ativa', 'em_atraso', 'suspensa') limit 1;

  if atual is not null then
    perform public.cancelar_assinatura(
      atual,
      coalesce(nullif(btrim(p_motivo), ''), 'mudança de plano'),
      'mudanca_de_plano');
  end if;

  return public.abrir_assinatura(p_conta, p_plano);
end;
$$;

-- ============================================ 6 · o churn, contado direito

/**
 * `churn_do_mes`, sem contar troca de plano.
 *
 * Lida do banco antes de reescrever. O que mudou é uma cláusula em cada
 * metade: a base inicial não conta como "viva" uma assinatura que foi
 * substituída por outra da mesma conta, e o numerador só conta causa que é
 * churn de verdade.
 *
 * O `coalesce(causa, 'outra')` existe para as linhas anteriores a esta
 * migração: elas não têm causa, e tratá-las como churn é o comportamento
 * antigo — mudar o passado para trás seria reescrever a série histórica, que é
 * exatamente o que a regra do preço de canal proíbe do outro lado.
 */
create or replace function public.churn_do_mes(p_mes date)
returns table (base_inicial integer, cancelaram integer, pct numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ini timestamptz := date_trunc('month', p_mes);
  fim timestamptz := date_trunc('month', p_mes) + interval '1 month';
  b integer; c integer;
begin
  select count(*) into b
    from public.assinaturas a
    join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste
     and a.criado_em < ini
     and (a.cancelada_em is null or a.cancelada_em >= ini)
     and a.estado <> 'trial'
     and coalesce(a.causa_cancelamento, 'outra') <> 'mudanca_de_plano';

  select count(*) into c
    from public.assinaturas a
    join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste
     and a.cancelada_em >= ini and a.cancelada_em < fim
     and a.criado_em < ini
     and coalesce(a.causa_cancelamento, 'outra') = any (public.causas_de_churn());

  return query select b, c,
    case when b > 0 then round(100.0 * c / b, 1) else null end;
end;
$$;

/**
 * A retenção com lista e causa — o pedido literal da OP5.
 *
 * Devolve **contagem e dinheiro**, não porcentagem por causa. Com uma dúzia de
 * contas, "33% saíram por preço" são duas pessoas, e uma porcentagem sobre dois
 * é um número que parece saber mais do que sabe. A tela mostra o inteiro; a
 * porcentagem entra quando a base sustentar uma.
 *
 * `dias_de_vida` é a mediana, e não a média: uma cliente que ficou um ano entre
 * cinco que ficaram um mês puxa a média para cima e some do retrato.
 */
create or replace function public.retencao_do_painel(p_desde date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  desde timestamptz := coalesce(p_desde, (public.hoje_sp() - interval '12 months')::date);
  v_causas jsonb;
  v_lista  jsonb;
  v_total  integer;
  v_perdido bigint;
  v_mediana numeric;
begin
  if not public.e_operador() then
    raise exception 'só o operador vê a retenção';
  end if;

  select
      count(*)::integer,
      coalesce(sum(a.valor_centavos), 0),
      percentile_cont(0.5) within group (
        order by extract(epoch from (a.cancelada_em - a.criado_em)) / 86400)
    into v_total, v_perdido, v_mediana
    from public.assinaturas a
    join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste
     and a.cancelada_em >= desde
     and coalesce(a.causa_cancelamento, 'outra') = any (public.causas_de_churn());

  select coalesce(jsonb_agg(x order by x->>'causa'), '[]'::jsonb) into v_causas
    from (
      select jsonb_build_object(
               'causa', coalesce(a.causa_cancelamento, 'outra'),
               'quantas', count(*)::integer,
               'mrr_perdido_centavos', coalesce(sum(a.valor_centavos), 0)
             ) as x
        from public.assinaturas a
        join public.contas ct on ct.id = a.conta_id
       where not ct.is_teste
         and a.cancelada_em >= desde
         and coalesce(a.causa_cancelamento, 'outra') = any (public.causas_de_churn())
       group by coalesce(a.causa_cancelamento, 'outra')
    ) s;

  -- A lista é nominal por conta, e isso é legítimo: conta é cliente minha, e
  -- nome de conta não é nome de paciente. A fronteira 9 continua onde estava —
  -- nada aqui toca tabela clínica, e é o que a verificação 1 da 0045 confere.
  select coalesce(jsonb_agg(x order by x->>'cancelada_em' desc), '[]'::jsonb) into v_lista
    from (
      select jsonb_build_object(
               'conta_id', ct.id,
               'conta', ct.nome,
               'plano', a.plano_codigo,
               'valor_centavos', a.valor_centavos,
               'causa', coalesce(a.causa_cancelamento, 'outra'),
               'motivo', a.motivo_cancelamento,
               'inicio', a.inicio,
               'cancelada_em', a.cancelada_em,
               'dias_de_vida', greatest(0, (a.cancelada_em::date - a.inicio))
             ) as x
        from public.assinaturas a
        join public.contas ct on ct.id = a.conta_id
       where not ct.is_teste
         and a.cancelada_em >= desde
         and coalesce(a.causa_cancelamento, 'outra') = any (public.causas_de_churn())
    ) s;

  return jsonb_build_object(
    'desde', desde::date,
    'quantas', v_total,
    'mrr_perdido_centavos', v_perdido,
    'dias_de_vida_mediana', case when v_mediana is null then null else round(v_mediana) end,
    'por_causa', v_causas,
    'lista', v_lista
  );
end;
$$;

-- ============================================ 7 · os grants

revoke execute on function public.regua_da_assinatura()            from public, anon, authenticated;
revoke execute on function public.dias_para_suspender()            from public, anon, authenticated;
revoke execute on function public.causas_de_churn()                from public, anon;
revoke execute on function public.passar_a_regua_das_assinaturas() from public, anon, authenticated;
revoke execute on function public.marcar_aviso_enviado(uuid)       from public, anon;
revoke execute on function public.avisos_pendentes()               from public, anon;
revoke execute on function public.retencao_do_painel(date)         from public, anon;
revoke execute on function public.cancelar_assinatura(uuid, text, text) from public, anon;
revoke execute on function public.mudar_plano(uuid, text, text)    from public, anon;
revoke execute on function public.baixar_fatura(uuid)              from public, anon;
revoke execute on function public.churn_do_mes(date)               from public, anon;

-- A passada é do cron, que chega como `service_role`. `authenticated` fica de
-- fora: nenhuma tela precisa disparar a régua, e uma função que suspende conta
-- não pode estar publicada em `/rest/v1/rpc` para quem tem qualquer login.
grant execute on function public.passar_a_regua_das_assinaturas() to service_role;

grant execute on function public.marcar_aviso_enviado(uuid)            to authenticated;
grant execute on function public.avisos_pendentes()                    to authenticated;
grant execute on function public.retencao_do_painel(date)              to authenticated;
grant execute on function public.cancelar_assinatura(uuid, text, text) to authenticated;
grant execute on function public.mudar_plano(uuid, text, text)         to authenticated;
grant execute on function public.baixar_fatura(uuid)                   to authenticated;
grant execute on function public.churn_do_mes(date)                    to authenticated;
grant execute on function public.causas_de_churn()                     to authenticated;
