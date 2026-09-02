-- =====================================================================
-- 0057 · P3 · a confirmação ativa
--
-- Lembrete é empurrado e não pede nada. Confirmação **exige resposta e muda
-- estado** — e é o sinal mais barato de vaga provável. "Barato" aqui é relativo
-- ao radar preditivo que o doc 30 matou; não é grátis: custa mensagem, custa
-- incômodo, e a taxa de resposta era desconhecida.
--
-- ESTE BUILD FOI REESCRITO POR UMA RESPOSTA DE CAMPO
--
-- A pergunta 14 do roteiro voltou em 02/09:
--
--   *"Ela confirma um dia antes por WhatsApp, e libera o horário quando há uma
--   resposta para desmarcar. De toda forma esse comportamento deve ser opção
--   para o psicólogo."*
--
-- Três coisas que eram palpite meu viraram fato, e uma delas encolheu o build:
--
--   1. **24 horas**, e o canal é WhatsApp. O padrão de quem liga nasce em 24 —
--      e não em 48, que era o outro chute plausível.
--   2. **Ela nunca libera por silêncio.** Libera quando **há resposta** dizendo
--      que não vem. Isto confirma a decisão que já estava escrita, agora com
--      prática por trás.
--   3. **É opção, não comportamento.** `null` continua sendo o padrão.
--
-- INVARIANTE 1 · O SISTEMA NUNCA LIBERA UM HORÁRIO
--
-- Nem por silêncio, nem por recusa. **Não existe nesta migração uma única
-- função que cancele sessão**, e a suíte reprova o dia em que aparecer.
--
-- Erro de agendamento é responsabilidade dela perante o paciente e perante o
-- CRP, e o produto não tem CRP. Além disso, cancelar tem consequência em
-- dinheiro — a política da B11 nasce da hora que sai — e um cancelamento
-- automático seria o software cobrando alguém por uma decisão que ele tomou
-- sozinho.
--
-- O que a recusa faz é mover o **eixo**. Quem cancela é ela, com o custo à
-- vista, num toque.
--
-- INVARIANTE 2 · SILÊNCIO É SINAL, E SINAL NÃO TEM BOTÃO
--
-- `silenciosa` aparece na tela e **não vem com proposta de liberar**. O doc 17
-- previa uma segunda tentativa e uma pergunta ("a Ana não confirmou. Liberar o
-- horário?"). O campo diz que ela nunca fez isso — então oferecer a ação seria
-- ensinar um comportamento que a prática não tem, sobre um sinal que é fraco
-- por natureza: quem não respondeu pode estar sem bateria.
--
-- **E não há segunda tentativa.** Uma segunda mensagem para quem não respondeu
-- a primeira tem mais chance de irritar do que de converter, e consome teto de
-- plano. Ela volta a existir no dia em que `resposta_das_confirmacoes` mostrar
-- taxa de resposta alta com antecedência curta — ou seja, quando o número
-- justificar. Hoje não há número.
--
-- INVARIANTE 3 · A RESPOSTA NÃO MEXE NO EIXO AGENDA
--
-- Confirmar move `eixo_confirmacao`, e **não** `estado`. A agenda não mudou: a
-- hora continua reservada, e só passou a ser reservada *com confirmação*.
--
-- Isto é o primeiro passo da aposentadoria do valor `confirmada` dentro de
-- `estado`, prevista no cabeçalho da 0056. Ele continua lá por compatibilidade
-- — dezenas de funções o leem —, mas a partir de agora **quem responde ao
-- paciente é o eixo**, e as telas leem o eixo.
--
-- INVARIANTE 4 · A RESPOSTA CHEGA POR UM CANAL SÓ, E ELE JÁ EXISTE
--
-- `responder_do_whatsapp` (B10) é a única porta de entrada. Ela agora resolve
-- **duas** coisas: oferta de vaga e confirmação de sessão. Quando as duas
-- estão vivas para o mesmo telefone, ganha **a mais recente** — porque quem
-- responde está olhando a última mensagem que chegou, que é a mesma regra que a
-- 0021 já usava entre ofertas.
--
-- O QUE ESTA MIGRAÇÃO **NÃO** FAZ
--
-- **Não liga confirmação para ninguém.** `confirmacao_horas_antes` nasce nulo
-- em todo enquadre que existe hoje. Quem não pede confirmação não passa a pedir
-- porque o software achou bom.
--
-- **Não manda mensagem sozinha para quem pediu para parar.** Isso já é do
-- `enfileirar_mensagem` (B9), e continua valendo.
-- =====================================================================

-- ================================================ 1 · o ajuste, por paciente

alter table public.enquadres
  add column if not exists confirmacao_horas_antes smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'enquadres_confirmacao_faixa') then
    alter table public.enquadres add constraint enquadres_confirmacao_faixa
      check (confirmacao_horas_antes is null
             or confirmacao_horas_antes between 2 and 168);
  end if;
end $$;

comment on column public.enquadres.confirmacao_horas_antes is
  'Quantas horas antes pedir confirmacao. NULL = nao pede, e e o padrao. 24 e o que a pratica de campo mostrou (02/09). Menos de 2h nao da tempo de reagir; mais de uma semana ninguem lembra.';

-- Quando o pedido saiu, e quando a resposta chegou. Os dois carimbos existem
-- para os dois números que justificam o bloco — sem eles, a taxa de resposta
-- seria um palpite sobre a própria feature.
alter table public.sessoes
  add column if not exists confirmacao_pedida_em     timestamptz,
  add column if not exists confirmacao_respondida_em timestamptz;

comment on column public.sessoes.confirmacao_pedida_em is
  'Quando o pedido de confirmacao saiu. Serve de idempotencia (nao pede duas vezes) e de base para a antecedencia media.';

create index if not exists sessoes_confirmacao_pendente
  on public.sessoes (inicio)
  where eixo_confirmacao = 'pendente';

-- ==================================================== 2 · o template, e o teto

/**
 * Essencial, e o motivo importa mais que a classificação.
 *
 * Uma confirmação que não sai por teto de plano faria a psicóloga ver uma hora
 * "silenciosa" que na verdade nunca foi perguntada — e decidir sobre um
 * silêncio que o próprio sistema causou. É o pior tipo de defeito: o que
 * fabrica o dado que ela vai usar para decidir.
 */
insert into public.templates (codigo, descricao, essencial, motivo) values
  ('confirmacao_de_sessao', 'Pedido de confirmação da véspera', true,
   'Se ela não sair por teto, a hora aparece como "não respondeu" sem nunca ter sido perguntada — e a psicóloga decide sobre um silêncio que o sistema inventou.')
on conflict (codigo) do update
  set descricao = excluded.descricao,
      essencial = excluded.essencial,
      motivo    = excluded.motivo;

-- ============================================================ 3 · o pedido

/**
 * Pede as confirmações que chegaram a hora de pedir.
 *
 * Roda no mesmo cron diário da mensageria. Idempotente por dois caminhos: o
 * `confirmacao_pedida_em is null` aqui e a `chave_idem` do outbox lá — rodar
 * duas vezes no mesmo dia não manda duas mensagens.
 *
 * `security definer` porque quem chama é o cron, sem sessão. E a conta de cada
 * sessão vem da própria linha, não de `conta_atual()`.
 */
create or replace function public.pedir_confirmacoes()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record;
  n integer := 0;
  msg uuid;
begin
  for s in
    select ss.id, ss.paciente_id, ss.inicio, e.confirmacao_horas_antes as horas
      from public.sessoes ss
      join public.enquadres e on e.id = ss.enquadre_id
     where ss.estado in ('prevista', 'confirmada')
       and ss.confirmacao_pedida_em is null
       and e.confirmacao_horas_antes is not null
       and ss.inicio > now()
       and ss.inicio <= now() + make_interval(hours => e.confirmacao_horas_antes::int)
     order by ss.inicio
     limit 500
  loop
    msg := public.enfileirar_mensagem(
      s.paciente_id,
      'confirmacao_de_sessao',
      'confirma:' || s.id::text,
      jsonb_build_object(
        'sessao', s.id,
        'quando', to_char(s.inicio at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI')
      )
    );

    -- `enfileirar_mensagem` devolve nulo quando a pessoa pediu para não
    -- receber, ou quando a chave já existia. Carimbar mesmo assim é o certo:
    -- o pedido **foi processado**, e o que não saiu não vai sair. Sem o
    -- carimbo, esta função tentaria de novo amanhã, e depois de amanhã.
    update public.sessoes
       set confirmacao_pedida_em = now(),
           eixo_confirmacao = case when msg is null then 'nao_pedida' else 'pendente' end
     where id = s.id;

    if msg is not null then n := n + 1; end if;
  end loop;

  return n;
end;
$$;

-- ============================================================ 4 · o silêncio

/**
 * O que não foi respondido vira sinal — e para por aí.
 *
 * **Não cancela nada, não propõe nada, não manda segunda mensagem.** Só troca
 * o eixo para que a tela consiga mostrar. É a invariante 2 inteira, e ela cabe
 * num `update`.
 *
 * A janela é de duas horas antes: até aí a resposta ainda serve para alguma
 * coisa. Depois disso, o que existe é a sessão acontecendo ou não.
 */
create or replace function public.marcar_silenciosas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  update public.sessoes
     set eixo_confirmacao = 'silenciosa'
   where eixo_confirmacao = 'pendente'
     and estado in ('prevista', 'confirmada')
     and inicio <= now() + interval '2 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ================================================= 5 · a resposta que chega

/**
 * A porta de entrada, agora com duas coisas para resolver.
 *
 * Corpo copiado da definição viva da 0021, com **um bloco novo** antes do
 * despacho de oferta e nada mais removido.
 *
 * A REGRA DA COLISÃO
 *
 * Uma pessoa pode ter, ao mesmo tempo, uma oferta de vaga viva e uma
 * confirmação pendente. Ganha **a mais recente** — a oferta pelo `enviar_em`,
 * a confirmação pelo `confirmacao_pedida_em`. É a mesma lógica que a 0021 já
 * usava para escolher entre duas ofertas: *quem responde está olhando a última
 * mensagem que chegou*.
 *
 * Sem essa regra, um "sim" destinado à confirmação da sessão de amanhã
 * aceitaria uma vaga de encaixe que ela nem lembrava ter recebido — e aí duas
 * pessoas ficariam com o mesmo horário na cabeça.
 */
create or replace function public.responder_do_whatsapp(
  p_provedor text,
  p_provedor_msg_id text,
  p_de text,
  p_texto text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  nova uuid;
  intencao text;
  fone text;
  -- Escalares, e não `record`: em plpgsql, ler um campo de um record que o
  -- `select into` não preencheu levanta "record not assigned yet". A lição da
  -- 0052c e da 0056, cobrada de novo — aqui **os dois** selects podem não achar
  -- nada, e é justamente isso que o código precisa perguntar.
  of_id uuid; of_conta uuid; of_paciente uuid; of_quando timestamptz;
  cf_id uuid; cf_conta uuid; cf_paciente uuid; cf_quando timestamptz;
  desfecho text;
  quantos int;
begin
  intencao := public.interpretar_resposta(p_texto);
  fone := public.so_digitos(p_de);

  insert into public.mensagens_recebidas
    (provedor, provedor_msg_id, de, texto, intencao)
  values
    (p_provedor, p_provedor_msg_id, p_de, coalesce(p_texto, ''), intencao)
  on conflict (provedor, provedor_msg_id) do nothing
  returning id into nova;

  if nova is null then
    return jsonb_build_object('estado', 'repetida');
  end if;

  -- ------------------------------------------------------------ parar
  if intencao = 'parar' then
    update public.pacientes
       set msg_canal = 'nao_avisar'
     where public.so_digitos(telefone) = fone
       and msg_canal <> 'nao_avisar';
    get diagnostics quantos = row_count;

    update public.mensagens m
       set estado = 'cancelada'
      from public.pacientes p
     where p.id = m.paciente_id
       and public.so_digitos(p.telefone) = fone
       and m.estado = 'pendente';

    update public.mensagens_recebidas
       set resultado = 'parou em ' || quantos || ' cadastro(s)'
     where id = nova;

    return jsonb_build_object('estado', 'parou', 'cadastros', quantos);
  end if;

  -- ------------------------------------------- de que oferta se trata (B10)
  select o.id, o.conta_id, o.paciente_id, o.enviar_em
    into of_id, of_conta, of_paciente, of_quando
    from public.ofertas o
    join public.pacientes p on p.id = o.paciente_id
   where o.estado = 'enviada'
     and public.so_digitos(p.telefone) = fone
   order by o.enviar_em desc
   limit 1;

  -- --------------------------------- e de que confirmação se trata (0057)
  select ss.id, ss.conta_id, ss.paciente_id, ss.confirmacao_pedida_em
    into cf_id, cf_conta, cf_paciente, cf_quando
    from public.sessoes ss
    join public.pacientes p on p.id = ss.paciente_id
   where ss.eixo_confirmacao = 'pendente'
     and ss.estado in ('prevista', 'confirmada')
     and ss.inicio > now()
     and public.so_digitos(p.telefone) = fone
   order by ss.confirmacao_pedida_em desc nulls last
   limit 1;

  -- A colisão: ganha a mensagem mais recente.
  if cf_id is not null
     and (of_id is null
          or coalesce(cf_quando, '-infinity'::timestamptz)
             >= coalesce(of_quando, '-infinity'::timestamptz))
  then
    update public.mensagens_recebidas
       set conta_id = cf_conta,
           paciente_id = cf_paciente
     where id = nova;

    if intencao = 'indefinida' then
      -- Mesma doutrina da 0021: robô não insiste com quem escreveu uma frase.
      -- A confirmação segue pendente e ela vê na tela.
      update public.mensagens_recebidas
         set resultado = 'não entendida — a confirmação segue pendente'
       where id = nova;
      return jsonb_build_object('estado', 'nao_entendi', 'sessao', cf_id);
    end if;

    -- Invariante 3: mexe no eixo, **nunca** no estado da agenda.
    -- Invariante 1: nem a recusa cancela. Quem cancela é ela, com o custo à
    -- vista — e a tela oferece isso num toque.
    update public.sessoes
       set eixo_confirmacao = case intencao when 'aceitar' then 'confirmada' else 'recusada' end,
           confirmacao_respondida_em = now()
     where id = cf_id;

    desfecho := case intencao when 'aceitar' then 'confirmou' else 'avisou que não vem' end;

    update public.mensagens_recebidas set resultado = desfecho where id = nova;
    return jsonb_build_object('estado', desfecho, 'sessao', cf_id);
  end if;

  if of_id is null then
    update public.mensagens_recebidas
       set resultado = 'sem oferta viva nem confirmação pendente para este telefone'
     where id = nova;
    return jsonb_build_object('estado', 'sem_oferta', 'intencao', intencao);
  end if;

  update public.mensagens_recebidas
     set conta_id = of_conta,
         paciente_id = of_paciente,
         oferta_id = of_id
   where id = nova;

  -- ------------------------------------------------------------ indefinida
  if intencao = 'indefinida' then
    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
    select of_conta, o.sessao_id, of_id, 'resposta_nao_entendida',
           jsonb_build_object('texto', left(coalesce(p_texto, ''), 200))
      from public.ofertas o where o.id = of_id;

    update public.mensagens_recebidas
       set resultado = 'não entendida — a oferta segue viva'
     where id = nova;

    return jsonb_build_object('estado', 'nao_entendi', 'oferta', of_id);
  end if;

  -- --------------------------------------------------------- aceite/recusa
  begin
    select public.responder_oferta(
      of_id,
      case intencao when 'aceitar' then 'aceita' else 'recusada' end
    ) into desfecho;
  exception when others then
    update public.mensagens_recebidas
       set resultado = 'não deu: ' || left(sqlerrm, 200)
     where id = nova;
    return jsonb_build_object('estado', 'tarde_demais', 'motivo', sqlerrm);
  end;

  update public.mensagens_recebidas set resultado = desfecho where id = nova;
  return jsonb_build_object('estado', desfecho, 'oferta', of_id);
end;
$$;

-- ============================== 6 · o eixo não se apaga quando outra coisa muda

/**
 * Conserta o `recalcular_eixos` da 0056 antes que ele apague uma resposta.
 *
 * O `case` de lá caía em `'nao_pedida'` sempre que o eixo estivesse
 * `'confirmada'` e o `estado` não fosse `confirmada` — e a partir desta
 * migração é exatamente o que acontece com quem responde "sim" (invariante 3:
 * a resposta não mexe no estado).
 *
 * Efeito prático do defeito: a paciente confirmava, e a primeira cobrança
 * gravada depois disso — qualquer coisa que disparasse `recalcular_eixos` —
 * apagava a confirmação em silêncio.
 *
 * Corpo copiado da 0056, com este `case` corrigido e nada mais.
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
    v_fin := 'credito';
  else
    if s.enquadre_id is not null and exists (
      select 1 from public.enquadres e
       where e.id = s.enquadre_id and e.modelo_cobranca = 'mensal'
    ) then
      v_fin := 'credito';
    else
      v_fin := 'nao_cobrada';
    end if;
  end if;

  -- A correção da 0057: o que a máquina de confirmação escreveu **manda**.
  -- Antes, `'confirmada'` não estava nesta lista, e a resposta do paciente era
  -- apagada pelo primeiro recálculo que passasse.
  v_conf := case
              when s.eixo_confirmacao in ('pendente', 'confirmada', 'recusada', 'silenciosa')
                then s.eixo_confirmacao
              when s.estado = 'confirmada' then 'confirmada'
              else 'nao_pedida'
            end;

  select r.nova_sessao_id into nova
    from public.remarcacoes r
   where r.sessao_id = p_sessao and r.nova_sessao_id is not null
   order by r.escolhida_em desc nulls last
   limit 1;

  if s.estado = 'realizada' then
    v_cap := 'vendida';
  elsif s.estado in ('falta', 'cancelada_cedo', 'cancelada_tarde') then
    v_cap := case when nova is not null then 'reposta' else 'perdida' end;
  else
    v_cap := null;
  end if;

  if s.estado <> 'realizada' then
    v_valor := case when v_cap is null then null else 0 end;
  elsif v_fin in ('perdoada', 'estornada') then
    v_valor := 0;
  else
    v_valor := s.valor;
  end if;

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

-- ================================================ 7 · os dois números do bloco

/**
 * A taxa de resposta e a antecedência média — os números que decidem se este
 * bloco se paga.
 *
 * Estão aqui desde o primeiro dia de propósito. O critério de pronto do P3 diz
 * que **se a taxa for baixa, o bloco não se paga, e isso aparece no primeiro
 * mês** — e uma feature que não traz consigo o instrumento que a mediria é uma
 * feature que ninguém desliga depois.
 *
 * `antecedencia_media_h` é a distância entre a **resposta** e o horário da
 * sessão, não entre o pedido e o horário. É a que interessa: ela mede quanto
 * tempo útil a resposta deu para reagir.
 */
create or replace function public.resposta_das_confirmacoes(p_de date, p_ate date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select s.*
      from public.sessoes s
     where s.confirmacao_pedida_em is not null
       and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
  )
  select jsonb_build_object(
    'de', p_de,
    'ate', p_ate,
    'pedidas',     (select count(*) from base),
    'confirmadas', (select count(*) from base where eixo_confirmacao = 'confirmada'),
    'recusadas',   (select count(*) from base where eixo_confirmacao = 'recusada'),
    'silenciosas', (select count(*) from base where eixo_confirmacao = 'silenciosa'),
    'pendentes',   (select count(*) from base where eixo_confirmacao = 'pendente'),
    'antecedencia_media_h', (
      select round(avg(extract(epoch from (inicio - confirmacao_respondida_em)) / 3600)::numeric, 1)
        from base where confirmacao_respondida_em is not null
    )
  );
$$;

-- ============================================================ 8 · os grants

revoke execute on function public.resposta_das_confirmacoes(date, date) from public, anon;
grant  execute on function public.resposta_das_confirmacoes(date, date) to authenticated;

-- O cron chama, e ninguém mais. Uma tela que pudesse "pedir confirmação agora"
-- mandaria a mensagem fora da hora combinada, que é o oposto de confirmar.
revoke execute on function public.pedir_confirmacoes()  from public, anon, authenticated;
revoke execute on function public.marcar_silenciosas()  from public, anon, authenticated;
grant  execute on function public.pedir_confirmacoes()  to service_role;
grant  execute on function public.marcar_silenciosas()  to service_role;
