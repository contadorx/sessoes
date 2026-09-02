-- 0060 · A unidade cobrada é a sessão — e a nota é do produto (OP8).
--
-- Esta migração desfaz comportamento que a 0046 construiu, e pela mesma razão
-- que o P4 desfez a 0022: **não por defeito, por decisão.** A 0046 se chama
-- `o_teto_nasce_com_quem_o_aplica` e ela estava certa dentro da própria
-- premissa. O que mudou foi a premissa, e ela está escrita no `claude/25`.
--
-- ## 1 · Por que a mensagem deixa de ser a unidade
--
-- Hoje o plano Grátis tem **60 mensagens de fila e cobrança por mês**. Quando
-- estoura, a fila **para** e o aviso de cobrança **não sai**. Três coisas
-- estão erradas nisso, e nenhuma é técnica:
--
--   · **a unidade é nossa, não dela.** "Quantas sessões você atende por mês" é
--     a língua da psicóloga; "quantos disparos você faz" é a nossa. Ela não
--     tem como saber quantas mensagens um mês dela gasta antes de o mês
--     acabar, e um limite que só se conhece depois de estourar não é um plano,
--     é uma surpresa;
--   · **quem paga o limite é a paciente.** A oferta de vaga que não sai é uma
--     vaga que ninguém soube que abriu; o aviso de cobrança que não sai é um
--     dinheiro que atrasa. A 0046 protegeu o essencial — lembrete, desmarque,
--     confirmação de encaixe nunca foram barrados, e continuam não sendo —,
--     mas parar a fila é parar exatamente a coisa que o produto promete fazer,
--     no mês em que ela mais precisou;
--   · **o número não fecha com o custo.** 60 mensagens são cerca de R$ 3,70 ao
--     câmbio de 02/09/2026. O limite não estava protegendo margem; estava
--     produzindo uma experiência ruim para economizar três reais e setenta.
--
-- A régua nova, do `claude/25`, em uma linha: **não se vende limite de
-- disparo, vende-se limite de sessão.** O volume de mensagem é função quase
-- determinística do número de sessões — lembrete, confirmação, recibo e fila
-- pendem todos da sessão. Limitar sessão limita mensagem sem que ela precise
-- pensar em mensagem uma única vez.
--
-- ## 2 · E a faixa de sessões **não é uma cerca**
--
-- Este é o ponto em que a migração podia trocar uma armadilha por outra, e não
-- troca. A 0046 já tinha recusado o teto de sessões, e a recusa continua
-- válida palavra por palavra:
--
--   > "Não há ponto de aplicação honesto: quem cria sessão é a materialização
--   > da recorrência, e uma materialização que para no meio deixa a agenda dela
--   > mentindo sobre a própria semana. Barrar a agenda para proteger a minha
--   > margem é cobrar o preço no lugar errado."
--
-- O que a 0046 concluiu daí foi que o teto tinha de ser de mensagens. A
-- conclusão certa era outra: **a faixa existe e não se aplica.** Ela é a
-- unidade de preço, medida e dita — não um gatilho que recusa `insert`.
--
-- Nenhum gatilho desta migração barra sessão. A verificação 2 da suíte 0060
-- cria a nona sessão de uma conta Grátis e exige que ela entre.
--
-- **A consequência comercial está declarada e é desconfortável:** com a faixa
-- medida e não aplicada, nada impede uma conta Grátis de atender quarenta
-- sessões por mês para sempre. O que sustenta o pedido não é a trava — é o
-- fato de que uma conta acima da faixa está visivelmente usando o produto para
-- trabalhar, e é isso que a função `contas_acima_da_faixa()` põe na minha
-- frente. Se o pedido não funcionar, o que se revisa é o preço ou a faixa, e
-- não a decisão de não travar a agenda de ninguém.
--
-- ## 3 · O que sobra de teto, e ele muda de eixo
--
-- Um teto ainda é necessário — não contra a cliente, contra o **laço**. Um bug
-- que reenfileira a mesma oferta mil vezes gasta dinheiro de verdade e queima
-- o número no WhatsApp.
--
-- A mudança é de eixo, e é a parte mais bonita desta migração: **o mesmo
-- mecanismo, medido por hora e por dia em vez de por mês.** Um mês cheio nunca
-- estoura um teto horário; um laço estoura em segundos. Foi o que a linha 5 da
-- política do `claude/25` já dizia — *"tetos técnicos são invisíveis: por
-- paciente/dia, por conta/hora. Proteção contra bug e abuso, não produto"* — e
-- o que faltava era mover a máquina para lá.
--
-- `planos.limite_mensagens_mes` **não é apagada**, pelo mesmo critério da 0048
-- com `limite_pacientes_ativos`: a máquina está provada por suíte, e nenhum
-- plano a usa. É `update`, não `drop`. Se um dia um plano precisar de teto
-- mensal, ele volta a valer no mesmo instante.
--
-- ## 4 · A nota, e por que ela entra nesta migração e não em outra
--
-- O doc `04` exige, no portão 1→2, *"NPS informal ≥ 8 nas 5"*. Isso nunca
-- existiu no produto: não há nenhum lugar onde uma psicóloga diga o que acha
-- do Sessões, e o portão que decide se o produto continua depende de um número
-- que hoje se produziria de memória.
--
-- Ela entra **junto com o preço** porque a pergunta é a mesma. Cobrar de
-- alguém sem saber se o produto vale o que cobra é a definição de vender no
-- escuro — e a faixa de sessões só é defensável se a conta que estoura a faixa
-- estiver dizendo que o produto serve.
--
-- **Cinco regras, e cada uma tem verificação:**
--
--   1. **a nota é do produto, não da pessoa.** Nada que ela responda muda o que
--      o sistema faz por ela: nem faixa, nem teto, nem preço, nem tela. A
--      verificação 21 dá nota 0 e nota 10 em duas contas idênticas e exige que
--      tudo o mais responda igual;
--   2. **não se pede num momento de dor.** `momento` é lista fechada de três
--      lugares, e nenhum deles é dentro de um cancelamento, de uma cobrança ou
--      de um erro. E `avaliacao_pendente` cala para quem está com assinatura em
--      atraso — pedir nota a quem está devendo é pedir a nota errada pela razão
--      errada;
--   3. **nota baixa não some.** Não existe função que leia `avaliacoes` e
--      escreva em `contas`, `assinaturas`, `planos` ou `faturas` — a
--      verificação 24 varre o `pg_proc` atrás de uma;
--   4. **não se troca nota por nada.** Sem desconto por nota, sem
--      funcionalidade destravada por nota. É corolário da 3, e a mesma
--      varredura o cobre;
--   5. **o texto é dela.** `avaliacoes` sai na exportação da conta, pelo mesmo
--      motivo que `usos_do_alerta` sai desde a 0059b: coletar sobre alguém e
--      não devolver é exatamente o que aquele arquivo existe para não ser.
--
-- ## 5 · O que esta migração NÃO faz
--
--   · **não cria excedente por mensagem.** É o atrito da iClinic (R$ 0,31 por
--     mensagem excedente) que o `claude/25` ataca de frente. Estourar a faixa
--     não gera cobrança nenhuma, em nenhum lugar;
--   · **não muda o canal por plano.** A escada `wa.me` manual no Grátis contra
--     envio automático no pago é o degrau seguinte, e ele mexe no adaptador de
--     canal. Enquanto ela não existir, o Grátis envia como sempre enviou;
--   · **não pede a nota sozinha em lugar nenhum.** Nenhum cron, nenhuma
--     mensagem, nenhum e-mail. `avaliacao_pendente` responde a quem pergunta;
--     quem pergunta é uma tela que ela abriu;
--   · **não classifica ninguém.** Não há segmento, não há perfil, não há
--     "conta de risco". A leitura agregada é minha e é sobre o produto.

-- ============================================================ 1 · a faixa

alter table public.planos
  add column if not exists limite_sessoes_mes integer
    check (limite_sessoes_mes is null or limite_sessoes_mes > 0);

alter table public.planos
  add column if not exists faixa_e_fair_use boolean not null default false;

comment on column public.planos.limite_sessoes_mes is
  'A faixa de sessoes do mes, POR PROFISSIONAL QUE ATENDE. NULL = sem faixa. E MEDIDA, NAO PORTEIRO: nenhum gatilho recusa sessao por causa dela, e a suite 0060 verificacao 2 exige que a sessao acima da faixa entre. Barrar a agenda para proteger margem cobra o preco no lugar errado — quem ficaria sem agenda e a paciente que ja tem hora marcada.';
comment on column public.planos.faixa_e_fair_use is
  'true = o numero e fair-use meu, e nao faixa vendida: a pagina de precos diz "sem faixa" e o numero so serve para eu enxergar a clinica disfarcada de autonoma. false = e a faixa que a pagina anuncia.';

-- Free 8 · Solo 60 · Pro sem faixa vendida, com fair-use em 200 · Clínica 60
-- por profissional. Os números são do `claude/25`.
update public.planos set limite_sessoes_mes = 8,   faixa_e_fair_use = false where codigo = 'gratis';
update public.planos set limite_sessoes_mes = 60,  faixa_e_fair_use = false where codigo = 'solo';
update public.planos set limite_sessoes_mes = 200, faixa_e_fair_use = true  where codigo = 'pro';
update public.planos set limite_sessoes_mes = 60,  faixa_e_fair_use = false where codigo = 'clinica';

/**
 * Quanto da faixa o mês já gastou.
 *
 * **`cancelada_cedo` não conta**, e é a decisão que mais muda o número. Uma
 * sessão desmarcada dentro do prazo não foi vendida — contá-la faria a paciente
 * que desmarca três vezes empurrar a psicóloga para um plano maior por sessões
 * que nunca aconteceram. É o mesmo recorte que a 0033 já usa para competência.
 *
 * A faixa é **por profissional que atende**: é o que faz a linha da Clínica ser
 * "por profissional" sem uma segunda coluna.
 */
create or replace function public.faixa_da_conta(p_conta uuid)
returns table (
  tem_faixa     boolean,
  limite        integer,
  profissionais integer,
  limite_total  integer,
  usadas        integer,
  restantes     integer,
  acima         boolean,
  pct           integer,
  e_fair_use    boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim      integer;
  fair     boolean;
  n_prof   integer;
  n_sess   integer;
  total    integer;
  ini      date := date_trunc('month', public.hoje_sp())::date;
  fim      date := (date_trunc('month', public.hoje_sp()) + interval '1 month')::date;
  papel    text := coalesce(current_setting('role', true), 'none');
begin
  -- Mesma tranca da `teto_da_conta` desde a 0046b: a faixa é da conta de quem
  -- pergunta, e não uma sonda do plano alheio.
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'a faixa é da conta de quem pergunta';
  end if;

  select pl.limite_sessoes_mes, pl.faixa_e_fair_use
    into lim, fair
    from public.planos pl
    join public.contas ct on ct.plano = pl.codigo
   where ct.id = p_conta;

  select greatest(count(*), 1)::integer into n_prof
    from public.profissionais pr
   where pr.conta_id = p_conta;

  select count(*)::integer into n_sess
    from public.sessoes se
   where se.conta_id = p_conta
     and (se.inicio at time zone 'America/Sao_Paulo')::date >= ini
     and (se.inicio at time zone 'America/Sao_Paulo')::date <  fim
     and se.estado <> 'cancelada_cedo';

  if lim is null then
    return query select false, null::integer, n_prof, null::integer,
                        n_sess, null::integer, false, 0, coalesce(fair, false);
    return;
  end if;

  total := lim * n_prof;

  return query select
    true,
    lim,
    n_prof,
    total,
    n_sess,
    greatest(total - n_sess, 0),
    n_sess > total,
    least(999, (100 * n_sess / greatest(total, 1)))::integer,
    fair;
end;
$$;

comment on function public.faixa_da_conta(uuid) is
  'Quanto da faixa de sessoes o mes corrente ja gastou. NAO barra nada — e a unidade de preco, medida e dita. `cancelada_cedo` fica de fora: sessao desmarcada no prazo nao foi vendida.';

/**
 * As contas acima da faixa — e é a função que substitui a trava.
 *
 * Com a faixa medida e não aplicada, o que sustenta o pedido de subir de plano
 * é alguém olhar. Esta função é esse alguém. Ela é do operador, não da conta.
 */
create or replace function public.contas_acima_da_faixa()
returns table (
  conta_id  uuid,
  nome      text,
  plano     text,
  limite    integer,
  usadas    integer,
  excedente integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'só o operador';
  end if;

  return query
  select ct.id, ct.nome, ct.plano, fx.limite_total, fx.usadas,
         (fx.usadas - fx.limite_total)
    from public.contas ct
    cross join lateral public.faixa_da_conta(ct.id) fx
   where not ct.is_teste
     and fx.tem_faixa
     and fx.acima
   order by (fx.usadas - fx.limite_total) desc;
end;
$$;

-- ============================================================ 2 · o teto de mensagens sai do produto

-- Mesmo movimento da 0048 com `limite_pacientes_ativos`: `update`, não `drop`.
-- A máquina fica, provada por suíte, e nenhum plano a usa.
update public.planos set limite_mensagens_mes = null;

comment on column public.planos.limite_mensagens_mes is
  'Teto MENSAL de mensagens nao-essenciais. NULL = sem teto, e desde a 0060 NENHUM PLANO USA. A unidade cobrada passou a ser a sessao (planos.limite_sessoes_mes): limitar disparo e falar a nossa lingua, e parar a fila no mes cheio e parar exatamente o que o produto promete. A coluna e a maquinaria ficam porque estao provadas por suite — se um plano precisar de teto mensal um dia, e um update. O teto que sobrou e tecnico e mora em limites_tecnicos, medido por hora e por dia.';

-- ============================================================ 3 · os tetos técnicos

/**
 * Os tetos que existem contra o laço, e não contra a cliente.
 *
 * Em tabela, e não em constante no corpo da função, pelo mesmo motivo que os
 * planos estão em tabela desde a 0045: um número que só muda com deploy não é
 * ajustável no dia em que ele estiver errado. E com `motivo` obrigatório, pela
 * mesma razão de `templates.motivo` — quem for mexer no número precisa
 * encontrar escrito por que ele é aquele.
 */
create table if not exists public.limites_tecnicos (
  codigo     text primary key,
  valor      integer not null check (valor > 0),
  motivo     text not null,
  criado_em  timestamptz not null default now()
);

comment on table public.limites_tecnicos is
  'Freio contra laco e abuso, NAO produto. Nao aparece em tela nenhuma da cliente, nao aparece na pagina de precos, e nenhum plano o altera. Medido por hora e por dia de proposito: mes cheio nunca estoura teto horario, laco estoura em segundos.';

insert into public.limites_tecnicos (codigo, valor, motivo) values
  ('mensagens_por_conta_hora', 60,
   'Uma conta real nao manda sessenta mensagens numa hora: a passada diaria enfileira o dia inteiro de uma vez, e mesmo uma agenda de doze sessoes fica muito abaixo. Sessenta numa hora e laco, nao trabalho.'),
  ('mensagens_por_paciente_dia', 8,
   'Um paciente recebe, num dia ruim, lembrete + confirmacao + oferta de vaga + aviso de cobranca = quatro. Oito e o dobro do pior dia legitimo. Acima disso alguem esta sendo incomodado por defeito nosso.')
on conflict (codigo) do nothing;

/**
 * Qual teto técnico estourou — ou nulo, que é o caso normal.
 *
 * Devolve o `codigo` em vez de um booleano de propósito: a mensagem barrada
 * carrega no `erro` **qual** freio a segurou, e um booleano me faria abrir o
 * banco para descobrir isso no dia em que importasse.
 *
 * Conta o que **saiu** (`enviada_em`), e não o que está reservado. É freio, não
 * medidor: a janela de uma hora perdoa alguns envios em voo e continua pegando
 * um laço, que produz centenas.
 */
create or replace function public.teto_tecnico(p_conta uuid, p_paciente uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim_hora integer;
  lim_dia  integer;
  n_hora   integer;
  n_dia    integer;
  hoje     date := public.hoje_sp();
begin
  select lt.valor into lim_hora from public.limites_tecnicos lt
   where lt.codigo = 'mensagens_por_conta_hora';
  select lt.valor into lim_dia  from public.limites_tecnicos lt
   where lt.codigo = 'mensagens_por_paciente_dia';

  select count(*)::integer into n_hora
    from public.mensagens ms
   where ms.conta_id = p_conta
     and ms.enviada_em is not null
     and ms.enviada_em >= now() - interval '1 hour';

  if lim_hora is not null and n_hora >= lim_hora then
    return 'mensagens_por_conta_hora';
  end if;

  if p_paciente is null then
    return null;
  end if;

  select count(*)::integer into n_dia
    from public.mensagens ms
   where ms.paciente_id = p_paciente
     and ms.enviada_em is not null
     and (ms.enviada_em at time zone 'America/Sao_Paulo')::date = hoje;

  if lim_dia is not null and n_dia >= lim_dia then
    return 'mensagens_por_paciente_dia';
  end if;

  return null;
end;
$$;

comment on function public.teto_tecnico(uuid, uuid) is
  'Devolve o codigo do freio que estourou, ou NULL. NAO le a tabela de planos: e proposital, e a suite 0060 verificacao 12 varre o corpo para provar. Teto tecnico que consulta plano vira produto disfarcado.';

/**
 * `cabe_no_teto` muda de significado sem mudar de nome.
 *
 * Ela era "cabe no teto do plano" e passa a ser "não bateu num freio técnico".
 * O nome continua honesto porque o que ela responde continua sendo a mesma
 * pergunta do ponto de vista de quem chama: esta mensagem pode sair agora?
 */
create or replace function public.cabe_no_teto(p_conta uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.teto_tecnico(p_conta, null) is null;
$$;

/**
 * A fila deixa de parar por causa de plano.
 *
 * É o resto da função da 0046 com o bloco do teto **removido** — e nada mais
 * mudado. O evento `fila_pausada_no_teto` continua existindo no check de
 * `eventos_fila.tipo`, porque apagar um valor de check apagaria a leitura dos
 * eventos antigos, que aconteceram de verdade e explicam vagas que não foram
 * oferecidas em agosto.
 */
create or replace function public.avancar_fila(p_sessao uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v record;
  proximo record;
  nova uuid;
  quando timestamptz;
  n int;
begin
  select se.id, se.conta_id, ct.oferta_timeout_min
    into v
    from public.sessoes se
    join public.contas ct on ct.id = se.conta_id
   where se.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  -- INVARIANTE 1: já existe oferta viva?
  if exists (select 1 from public.ofertas of3
              where of3.sessao_id = p_sessao and of3.estado = 'enviada') then
    return null;
  end if;

  -- A INVARIANTE 2 da 0046 (cabe no teto do plano?) saiu aqui. A fila é o que
  -- o produto promete; pará-la para economizar mensagem é parar a promessa.

  select * into proximo
    from public.elegiveis_para_vaga(p_sessao)
   where elegivel
   order by ordem
   limit 1;

  if not found then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'vaga_sem_takers', '{}'::jsonb);
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  select count(*) + 1 into n from public.ofertas where sessao_id = p_sessao;

  insert into public.ofertas (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_sessao, proximo.paciente_id, n,
          quando, quando + make_interval(mins => v.oferta_timeout_min))
  returning id into nova;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (v.conta_id, p_sessao, nova, 'oferta_enviada',
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'enviar_em', quando));

  return nova;
end;
$$;

/**
 * A reserva do worker, com o freio técnico no lugar do teto de plano.
 *
 * Três diferenças em relação à 0046, e a terceira é a que mudou de doutrina:
 *
 *   1. o que barra deixou de ser o plano e passou a ser o freio técnico;
 *   2. o freio vale para **template essencial também**. Parece contradizer a
 *      0046, e não contradiz: lá o que barrava era um limite comercial, e
 *      deixar a paciente sem lembrete para proteger a minha margem é cobrar de
 *      quem não escolheu plano nenhum. Aqui o que barra é a suspeita de laço, e
 *      um laço que manda oitenta lembretes para a mesma pessoa numa noite é
 *      pior para ela do que um lembrete que não chega;
 *   3. o estado terminal continua sendo `barrada_no_teto` — o valor do check
 *      não muda —, mas o `erro` passa a dizer **qual freio**, e a tela passa a
 *      chamar isso de trava de segurança, que é o que virou.
 */
create or replace function public.reservar_mensagens(p_limite int default 20)
returns setof public.mensagens
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Passo 1: barrar o que bateu num freio técnico.
  update public.mensagens ms
     set estado = 'barrada_no_teto',
         erro = 'trava de segurança: ' || public.teto_tecnico(ms.conta_id, ms.paciente_id)
   where ms.estado = 'pendente'
     and ms.agendada_para <= now()
     and public.teto_tecnico(ms.conta_id, ms.paciente_id) is not null;

  -- Passo 2: a reserva de sempre, atômica desde a B9.
  return query
  update public.mensagens ms
     set estado = 'enviando', tentativas = ms.tentativas + 1
   where ms.id in (
     select x.id from public.mensagens x
      where x.estado = 'pendente'
        and x.agendada_para <= now()
      order by x.agendada_para
      for update skip locked
      limit p_limite
   )
  returning ms.*;
end;
$$;

-- ============================================================ 4 · a avaliação do produto

create table if not exists public.avaliacoes (
  id             uuid primary key default gen_random_uuid(),
  conta_id       uuid not null references public.contas (id) on delete cascade,

  nota           smallint not null check (nota between 0 and 10),
  texto          text check (texto is null or length(texto) between 1 and 2000),

  -- Lista fechada, e é ela que carrega a regra 2. Nenhum destes três é dentro
  -- de um cancelamento, de uma cobrança, de uma fila que falhou ou de um erro.
  -- Acrescentar um momento passa a exigir migração, que é onde a pergunta "e
  -- este é um momento de dor?" tem chance de ser feita.
  momento        text not null check (momento in ('perfil', 'convite', 'fim_do_mes')),

  -- Retratos do dia da resposta. Sem eles a nota vira um número sem contexto:
  -- 6 de quem atende oito sessões no Grátis e 6 de quem atende oitenta no Pro
  -- são dois problemas diferentes.
  plano          text not null references public.planos (codigo) on update cascade,
  sessoes_no_mes integer not null default 0,
  dias_de_uso    integer not null default 0,

  criada_em      timestamptz not null default now()
);

comment on table public.avaliacoes is
  'A nota que ela da ao Sessoes. E instrumento sobre o PRODUTO: nada aqui muda o que o sistema faz por ela — nem faixa, nem teto, nem preco, nem tela. Nenhuma funcao le esta tabela e escreve em contas, assinaturas, planos ou faturas, e a suite 0060 verificacao 24 varre o pg_proc para provar.';
comment on column public.avaliacoes.momento is
  'Onde a nota foi dada. Lista fechada de proposito: e ela que impede pedir nota dentro de um cancelamento, de uma cobranca ou de um erro. Momento novo e migracao, e a migracao e onde a pergunta e feita.';
comment on column public.avaliacoes.nota is
  '0 a 10. Nota baixa nao some, nao muda nada e nao dispara nada — nem para mim. O que ela faz e aparecer na distribuicao de nota_do_produto().';

create index if not exists avaliacoes_da_conta
  on public.avaliacoes (conta_id, criada_em desc);

/**
 * Registrar a nota — e é `security invoker`, então a RLS decide.
 *
 * Os retratos são tirados aqui dentro, e não recebidos por parâmetro: um
 * cliente que informasse o próprio plano poderia informar outro.
 */
create or replace function public.registrar_avaliacao(
  p_nota    smallint,
  p_texto   text default null,
  p_momento text default 'perfil'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c        uuid := public.conta_atual();
  v_plano  text;
  v_sess   integer;
  v_dias   integer;
  novo     uuid;
  ini      date := date_trunc('month', public.hoje_sp())::date;
  fim      date := (date_trunc('month', public.hoje_sp()) + interval '1 month')::date;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_nota is null or p_nota < 0 or p_nota > 10 then
    raise exception 'a nota vai de 0 a 10';
  end if;

  select ct.plano, greatest(0, (public.hoje_sp() - ct.criado_em::date))
    into v_plano, v_dias
    from public.contas ct where ct.id = c;

  select count(*)::integer into v_sess
    from public.sessoes se
   where se.conta_id = c
     and (se.inicio at time zone 'America/Sao_Paulo')::date >= ini
     and (se.inicio at time zone 'America/Sao_Paulo')::date <  fim
     and se.estado <> 'cancelada_cedo';

  insert into public.avaliacoes (conta_id, nota, texto, momento, plano, sessoes_no_mes, dias_de_uso)
  values (c, p_nota, nullif(btrim(coalesce(p_texto, '')), ''), p_momento, v_plano, v_sess, v_dias)
  returning id into novo;

  return novo;
end;
$$;

/**
 * Vale pedir a nota agora?
 *
 * Quatro portões, e três deles são silêncios:
 *
 *   · **menos de 30 dias de conta**: ainda não há do que ter opinião, e a nota
 *     mediria o onboarding;
 *   · **menos de 10 sessões realizadas na vida da conta**: idem, e é o portão
 *     que separa quem usa de quem espiou;
 *   · **avaliou nos últimos 90 dias**: perguntar de novo é insistir;
 *   · **assinatura em atraso**: pedir nota a quem está devendo é pedir a nota
 *     errada pela razão errada — e ainda por cima misturar a conversa da
 *     cobrança com a conversa do produto.
 *
 * Nunca "pede" sozinha: responde a quem pergunta, e quem pergunta é uma tela
 * que ela abriu.
 */
create or replace function public.avaliacao_pendente()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c        uuid := public.conta_atual();
  v_dias   integer;
  v_sess   integer;
  v_ult    timestamptz;
  v_atraso boolean;
begin
  if c is null then raise exception 'sem conta'; end if;

  select greatest(0, (public.hoje_sp() - ct.criado_em::date))
    into v_dias from public.contas ct where ct.id = c;

  select count(*)::integer into v_sess
    from public.sessoes se
   where se.conta_id = c and se.estado = 'realizada';

  select max(av.criada_em) into v_ult
    from public.avaliacoes av where av.conta_id = c;

  select exists (select 1 from public.assinaturas asg
                  where asg.conta_id = c and asg.estado = 'em_atraso')
    into v_atraso;

  return jsonb_build_object(
    'dias_de_uso', v_dias,
    'sessoes_realizadas', v_sess,
    'ultima', v_ult,
    'pedir', (v_dias >= 30
              and v_sess >= 10
              and not v_atraso
              and (v_ult is null or v_ult < now() - interval '90 days')),
    'motivo', case
                when v_dias < 30 then 'conta nova'
                when v_sess < 10 then 'pouco uso'
                when v_atraso then 'assinatura em atraso'
                when v_ult is not null and v_ult >= now() - interval '90 days' then 'avaliou há pouco'
                else 'pode perguntar'
              end
  );
end;
$$;

/**
 * A leitura, e ela é minha.
 *
 * Devolve a **distribuição inteira**, e não só a média. Uma média de 7,4 pode
 * ser dez notas 7 ou cinco notas 10 e cinco notas 5 — e são dois produtos
 * diferentes. É a mesma razão pela qual o P5 devolve os quatro números num
 * objeto só: quem escolhe o recorte na tela acaba escolhendo o recorte
 * confortável.
 */
create or replace function public.nota_do_produto(p_de date, p_ate date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  n         integer;
  media     numeric;
  prom      integer;
  neu       integer;
  det       integer;
  dist      jsonb;
  por_plano jsonb;
begin
  if not public.e_operador() then
    raise exception 'só o operador';
  end if;

  select count(*)::integer,
         round(avg(av.nota), 2),
         count(*) filter (where av.nota >= 9)::integer,
         count(*) filter (where av.nota between 7 and 8)::integer,
         count(*) filter (where av.nota <= 6)::integer
    into n, media, prom, neu, det
    from public.avaliacoes av
    join public.contas ct on ct.id = av.conta_id
   where not ct.is_teste
     and av.criada_em::date between p_de and p_ate;

  select coalesce(jsonb_object_agg(x.nota, x.quantas), '{}'::jsonb) into dist
    from (select av.nota, count(*)::integer as quantas
            from public.avaliacoes av
            join public.contas ct on ct.id = av.conta_id
           where not ct.is_teste
             and av.criada_em::date between p_de and p_ate
           group by av.nota) x;

  select coalesce(jsonb_object_agg(y.plano, jsonb_build_object(
           'n', y.quantas, 'media', y.media)), '{}'::jsonb) into por_plano
    from (select av.plano, count(*)::integer as quantas, round(avg(av.nota), 2) as media
            from public.avaliacoes av
            join public.contas ct on ct.id = av.conta_id
           where not ct.is_teste
             and av.criada_em::date between p_de and p_ate
           group by av.plano) y;

  return jsonb_build_object(
    'de', p_de, 'ate', p_ate,
    'n', n,
    'media', media,
    'promotores', prom,
    'neutros', neu,
    'detratores', det,
    -- NPS só existe com amostra. Com três respostas ele varia 66 pontos por
    -- pessoa, e um número que se move assim vira decisão errada com cara de
    -- medida. O portão 1→2 do doc 04 pede cinco.
    'nps', case when n >= 5 then round(100.0 * (prom - det) / n) else null end,
    'distribuicao', dist,
    'por_plano', por_plano
  );
end;
$$;

-- ============================================================ 5 · as trancas

alter table public.limites_tecnicos enable row level security;
-- Ninguém lê: é freio meu, não é produto. Sem policy = zero linhas para
-- `anon` e `authenticated`, e as funções que precisam são `security definer`.

alter table public.avaliacoes enable row level security;

drop policy if exists "a avaliação é da conta: ler" on public.avaliacoes;
create policy "a avaliação é da conta: ler" on public.avaliacoes
  for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "a avaliação é da conta: escrever" on public.avaliacoes;
create policy "a avaliação é da conta: escrever" on public.avaliacoes
  for insert to authenticated
  with check (conta_id = public.conta_atual());

-- Sem `update` e sem `delete`, e é decisão: a nota de agosto é o que ela
-- achava em agosto. Mudar de opinião registra uma nota nova.

revoke execute on function public.faixa_da_conta(uuid)         from public, anon;
revoke execute on function public.contas_acima_da_faixa()      from public, anon, authenticated;
revoke execute on function public.teto_tecnico(uuid, uuid)     from public, anon, authenticated;
revoke execute on function public.cabe_no_teto(uuid)           from public, anon, authenticated;
revoke execute on function public.registrar_avaliacao(smallint, text, text) from public, anon;
revoke execute on function public.avaliacao_pendente()         from public, anon;
revoke execute on function public.nota_do_produto(date, date)  from public, anon, authenticated;

grant execute on function public.faixa_da_conta(uuid)          to authenticated;
grant execute on function public.registrar_avaliacao(smallint, text, text) to authenticated;
grant execute on function public.avaliacao_pendente()          to authenticated;

-- As duas do operador seguem o padrão da 0045: revogadas de todos acima e
-- devolvidas a `authenticated`, porque o porteiro é o `e_operador()` de dentro
-- e não o grant. Grant é grosso demais para dizer "só eu".
grant execute on function public.contas_acima_da_faixa()       to authenticated;
grant execute on function public.nota_do_produto(date, date)   to authenticated;

-- ============================================================ 6 · a exportação

/**
 * `avaliacoes` entra na exportação.
 *
 * A 0059b esqueceu dezessete tabelas porque a conferência era por lista, e uma
 * lista escrita à mão nunca reprova o item que ninguém pôs nela. Desde a 0059c
 * a verificação 15 da suíte 0024 compara o `information_schema` com o corpo
 * desta função — então esquecer aqui reprova em três minutos, e é assim que
 * esta linha nasceu.
 */
create or replace function public.exportar_conta()
returns jsonb
language plpgsql
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
    'usuarios', (select coalesce(jsonb_agg(to_jsonb(u) - 'conta_id'), '[]'::jsonb)
                   from public.usuarios u where u.conta_id = c),
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
    'janelas_atendimento', (select coalesce(jsonb_agg(to_jsonb(ja) - 'conta_id'
                                            order by ja.dia_semana, ja.inicio), '[]'::jsonb)
                              from public.janelas_atendimento ja where ja.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'fila_entrada', (select coalesce(jsonb_agg(to_jsonb(fe) - 'conta_id'), '[]'::jsonb)
                       from public.fila_entrada fe where fe.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'vagas_fixas', (select coalesce(jsonb_agg(to_jsonb(vf) - 'conta_id'), '[]'::jsonb)
                      from public.vagas_fixas vf where vf.conta_id = c),
    'ofertas_fixas', (select coalesce(jsonb_agg(to_jsonb(of2) - 'conta_id'), '[]'::jsonb)
                        from public.ofertas_fixas of2 where of2.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'remarcacoes', (select coalesce(jsonb_agg(to_jsonb(rm) - 'conta_id' - 'token'
                                    order by rm.criada_em), '[]'::jsonb)
                      from public.remarcacoes rm where rm.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'propostas_de_cobranca', (select coalesce(jsonb_agg(to_jsonb(pr) - 'conta_id'
                                              order by pr.criado_em), '[]'::jsonb)
                                from public.propostas_de_cobranca pr where pr.conta_id = c),
    'pacotes', (select coalesce(jsonb_agg(to_jsonb(pk) - 'conta_id'), '[]'::jsonb)
                  from public.pacotes pk where pk.conta_id = c),
    'pacote_consumos', (select coalesce(jsonb_agg(to_jsonb(pcs) - 'conta_id'), '[]'::jsonb)
                          from public.pacote_consumos pcs where pcs.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'documentos', (select coalesce(jsonb_agg(to_jsonb(dc) - 'conta_id'
                                   order by dc.emitido_em), '[]'::jsonb)
                     from public.documentos dc where dc.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'eventos_pagamento', (select coalesce(jsonb_agg(to_jsonb(ep) - 'conta_id'
                                          order by ep.recebido_em), '[]'::jsonb)
                            from public.eventos_pagamento ep where ep.conta_id = c),
    'mensagens', (select coalesce(jsonb_agg(to_jsonb(m) - 'conta_id'
                                  order by m.criado_em), '[]'::jsonb)
                    from public.mensagens m where m.conta_id = c),
    'mensagens_recebidas', (select coalesce(jsonb_agg(to_jsonb(mr) - 'conta_id'
                                            order by mr.recebida_em), '[]'::jsonb)
                              from public.mensagens_recebidas mr where mr.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'calendarios', (select coalesce(jsonb_agg(to_jsonb(cl) - 'conta_id' - 'sync_token'), '[]'::jsonb)
                      from public.calendarios cl where cl.conta_id = c),
    'ocupacoes_externas', (select coalesce(jsonb_agg(to_jsonb(oc) - 'conta_id' order by oc.inicio), '[]'::jsonb)
                             from public.ocupacoes_externas oc where oc.conta_id = c),
    'espelhos_calendario', (select coalesce(jsonb_agg(to_jsonb(ec) - 'conta_id' order by ec.criado_em), '[]'::jsonb)
                              from public.espelhos_calendario ec where ec.conta_id = c),
    'registros', (select coalesce(jsonb_agg(to_jsonb(rg) - 'conta_id' order by rg.criado_em), '[]'::jsonb)
                    from public.registros rg where rg.conta_id = c),
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev2) - 'conta_id' order by ev2.criado_em), '[]'::jsonb)
                    from public.evolucoes ev2 where ev2.conta_id = c),
    'anamneses', (select coalesce(jsonb_agg(to_jsonb(an) - 'conta_id' order by an.criado_em), '[]'::jsonb)
                    from public.anamneses an where an.conta_id = c),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad where ad.conta_id = c),
    'assinaturas', (select coalesce(jsonb_agg(to_jsonb(asg) - 'conta_id'
                                    order by asg.criado_em), '[]'::jsonb)
                      from public.assinaturas asg where asg.conta_id = c),
    'faturas', (select coalesce(jsonb_agg(to_jsonb(ft) - 'conta_id'
                                order by ft.competencia), '[]'::jsonb)
                  from public.faturas ft where ft.conta_id = c),
    'avisos_assinatura', (select coalesce(jsonb_agg(to_jsonb(av) - 'conta_id'
                                          order by av.criado_em), '[]'::jsonb)
                            from public.avisos_assinatura av where av.conta_id = c),
    'usos_do_alerta', (select coalesce(jsonb_agg(to_jsonb(ua) - 'conta_id'), '[]'::jsonb)
                         from public.usos_do_alerta ua where ua.conta_id = c),

    -- A nota que ela deu ao produto, com o texto que escreveu. Mesma regra do
    -- `usos_do_alerta`: é medida do produto e sai assim mesmo.
    'avaliacoes', (select coalesce(jsonb_agg(to_jsonb(av2) - 'conta_id'
                                   order by av2.criada_em), '[]'::jsonb)
                     from public.avaliacoes av2 where av2.conta_id = c),

    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  return saida;
end;
$$;
