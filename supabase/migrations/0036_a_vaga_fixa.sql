-- 0036 · B22 — a fila de vaga fixa (D13).
--
-- A D1 preenche o buraco **de uma semana**. Esta preenche o buraco **para
-- sempre**: quando alguém recebe alta ou abandona, o que abre não é uma hora —
-- é uma hora *toda semana*, pelos próximos meses ou anos. É o ativo mais
-- valioso do consultório, e é o que os oito concorrentes tratam como se fosse
-- um buraco qualquer.
--
-- A diferença entre as duas filas, para a psicóloga, é um LTV inteiro.
--
-- Seis decisões.
--
-- ## 1. São duas filas, e confundi-las seria o erro do build
--
-- A `fila_encaixe` é de quem **já está em atendimento** e topa uma hora extra
-- esta semana. A `fila_entrada` é de quem **ligou quando não havia horário** e
-- está esperando uma vaga existir. São pessoas diferentes, esperando coisas
-- diferentes, e ofertas com significados opostos: uma é "quer essa terça?", a
-- outra é "quer as terças?".
--
-- ## 2. Reajustar não abre vaga
--
-- Reajuste e mudança de horário fecham um combinado e abrem outro no mesmo
-- instante (D14). Se o gatilho olhasse só para `vigencia_fim`, todo reajuste
-- ofereceria o horário da pessoa para a lista de espera — e alguém receberia
-- "abriu uma vaga nas terças" sobre a terça de quem continua sendo atendido.
-- Só `motivo_fim = 'encerramento'` abre vaga. É a verificação nº 1 da suíte.
--
-- ## 3. Arquivar passa a fechar o combinado
--
-- Defeito encontrado escrevendo esta build: `arquivar_paciente` (0024) tirava a
-- pessoa da fila e parava as mensagens, mas **deixava o combinado aberto** — a
-- materialização seguia criando sessões toda semana para uma ficha arquivada, e
-- o horário mais valioso da agenda continuava ocupado por quem não vem mais.
-- Agora arquivar encerra o combinado, e encerrar abre a vaga.
--
-- ## 4. Aceitar **não** cria o combinado
--
-- Um "SIM" no encaixe marca uma sessão. Um "SIM" aqui significaria valor,
-- política de falta, contrato e uma relação que começa — decidir tudo isso por
-- uma palavra no WhatsApp seria o sistema combinando enquadre no lugar dela, e
-- o enquadre é a fronteira que o produto não atravessa (doc 11).
--
-- O aceite **reserva a vaga** e devolve o assunto para ela, que já ia precisar
-- ter essa conversa. O texto da oferta diz isso: "responda SIM e eu falo com
-- você para combinar o começo". Ninguém fica esperando uma confirmação que não
-- vem.
--
-- ## 5. Uma noite para pensar, não quarenta minutos
--
-- O encaixe expira em 40 minutos porque a hora é semana que vem. Uma vaga fixa
-- é o horário da pessoa pelo próximo ano: 24 horas por padrão. Responder isso
-- em quarenta minutos, no meio do expediente, não é escolher — é reagir.
--
-- ## 6. Tabelas próprias, e não a `ofertas` da B7
--
-- A 0012 deixou uma coluna `fila` em `ofertas` prevendo reuso aqui. Foi uma
-- previsão errada, e vale dizer por quê: `ofertas.sessao_id` é `not null` e as
-- duas invariantes do motor (uma oferta viva por vaga, ninguém recebe a mesma
-- vaga duas vezes) são índices sobre ela. Reusar exigiria afrouxar a coluna,
-- reescrever os dois índices e ramificar o `responder_oferta` — mexendo no
-- código mais testado e mais crítico do produto para economizar uma tabela.
-- A coluna `fila` fica onde está, sem uso, como registro do palpite.

-- ---------------------------------------------------------- ajuste da conta

alter table public.contas
  add column if not exists oferta_fixa_horas smallint not null default 24
    check (oferta_fixa_horas between 1 and 168);

comment on column public.contas.oferta_fixa_horas is
  'Prazo da oferta de vaga fixa. Padrao 24h: o encaixe e uma hora, isto e o horario de alguem pelo proximo ano.';

-- ------------------------------------------------------------- a fila de entrada

create table if not exists public.fila_entrada (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  paciente_id   uuid not null references public.pacientes (id) on delete cascade,

  -- [] = qualquer horário. Senão: [{"dias":[2,4],"de":"14:00","ate":"20:00"}]
  -- Mesmo formato da fila de encaixe, de propósito: é a mesma pergunta.
  janelas       jsonb not null default '[]'::jsonb,

  prioridade    int not null default 0,
  ativo         boolean not null default true,
  entrou_em     timestamptz not null default now(),
  observacao    text check (observacao is null or length(observacao) <= 300),

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  unique (paciente_id)
);

create index if not exists fila_entrada_conta on public.fila_entrada (conta_id) where ativo;

create or replace function public.checa_conta_da_fila_entrada()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare c uuid;
begin
  select conta_id into c from public.pacientes where id = new.paciente_id;
  if c is null then raise exception 'paciente não encontrado'; end if;
  new.conta_id := c;
  return new;
end;
$$;

drop trigger if exists fila_entrada_conta_derivada on public.fila_entrada;
create trigger fila_entrada_conta_derivada before insert or update on public.fila_entrada
  for each row execute function public.checa_conta_da_fila_entrada();

drop trigger if exists fila_entrada_atualizado_em on public.fila_entrada;
create trigger fila_entrada_atualizado_em before update on public.fila_entrada
  for each row execute function public.tocar_atualizado_em();

-- --------------------------------------------------------------- as vagas

create table if not exists public.vagas_fixas (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,

  -- De onde veio. `restrict` porque a vaga conta uma história, e apagar o
  -- combinado que a originou deixaria a história sem começo.
  enquadre_id       uuid references public.enquadres (id) on delete restrict,
  paciente_anterior uuid references public.pacientes (id) on delete set null,

  dia_semana   smallint not null check (dia_semana between 0 and 6),
  hora         time not null,
  duracao_min  smallint not null check (duracao_min between 15 and 240),
  valor_anterior numeric(12,2),

  motivo       text not null check (motivo in ('alta', 'abandono', 'mudanca', 'outro')),

  aberta_em    timestamptz not null default now(),
  fechada_em   timestamptz,
  fechada_por  text check (fechada_por in ('preenchida', 'sem_takers', 'cancelada')),
  novo_paciente uuid references public.pacientes (id) on delete set null,

  check ((fechada_em is null) = (fechada_por is null))
);

-- Uma vaga viva por dia e hora do profissional: duas seriam a mesma vaga
-- oferecida duas vezes, e alguém receberia a hora que outra pessoa acabou de
-- aceitar.
create unique index if not exists vaga_fixa_viva
  on public.vagas_fixas (profissional_id, dia_semana, hora)
  where fechada_em is null;

create index if not exists vagas_fixas_da_conta
  on public.vagas_fixas (conta_id, aberta_em desc);

-- ------------------------------------------------------------- as ofertas

create table if not exists public.ofertas_fixas (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  vaga_id       uuid not null references public.vagas_fixas (id) on delete cascade,
  paciente_id   uuid not null references public.pacientes (id) on delete cascade,

  ordem         int not null default 1,
  criada_em     timestamptz not null default now(),
  enviar_em     timestamptz not null default now(),
  expira_em     timestamptz not null,
  respondida_em timestamptz,

  estado        text not null default 'enviada'
                check (estado in ('enviada', 'aceita', 'recusada', 'expirada', 'cancelada')),

  check (expira_em > enviar_em),
  check ((estado = 'enviada') = (respondida_em is null))
);

-- As mesmas duas invariantes do motor da B7, aqui na versão da vaga fixa.
create unique index if not exists oferta_fixa_viva
  on public.ofertas_fixas (vaga_id) where estado = 'enviada';
create unique index if not exists oferta_fixa_por_pessoa
  on public.ofertas_fixas (vaga_id, paciente_id);
create index if not exists ofertas_fixas_vivas
  on public.ofertas_fixas (expira_em) where estado = 'enviada';

-- Dois tipos de evento novos na trilha da fila.
alter table public.eventos_fila drop constraint if exists eventos_fila_tipo_check;
alter table public.eventos_fila add constraint eventos_fila_tipo_check
  check (tipo in (
    'vaga_aberta', 'oferta_enviada', 'oferta_aceita',
    'oferta_recusada', 'oferta_expirada',
    'vaga_preenchida', 'vaga_sem_takers', 'resposta_nao_entendida',
    'vaga_fixa_aberta', 'vaga_fixa_preenchida'
  ));

alter table public.eventos_fila
  add column if not exists vaga_fixa_id uuid references public.vagas_fixas (id) on delete cascade;

-- --------------------------------------------------- abrir a vaga, e quando

/**
 * Só encerramento abre vaga.
 *
 * Roda **depois** da transição, e olha o motivo — não só a data. Um reajuste
 * fecha e reabre o combinado no mesmo segundo; oferecer aquele horário à lista
 * de espera seria oferecer a terça de quem continua sendo atendido.
 */
create or replace function public.ao_encerrar_enquadre()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pac record;
begin
  if old.vigencia_fim is not null or new.vigencia_fim is null then
    return new;
  end if;
  if new.motivo_fim is distinct from 'encerramento' then
    return new;
  end if;

  select p.*, p.profissional_id as prof into pac
    from public.pacientes p where p.id = new.paciente_id;
  if not found then return new; end if;

  insert into public.vagas_fixas (
    conta_id, profissional_id, enquadre_id, paciente_anterior,
    dia_semana, hora, duracao_min, valor_anterior, motivo
  )
  values (
    new.conta_id, pac.prof, new.id, new.paciente_id,
    new.dia_semana, new.hora, new.duracao_min, new.valor,
    case when pac.estado = 'arquivado' then 'alta' else 'outro' end
  )
  on conflict do nothing;

  insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
  select new.conta_id, 'vaga_fixa_aberta', v.id,
         jsonb_build_object('dia_semana', new.dia_semana, 'hora', new.hora,
                            'de', pac.nome)
    from public.vagas_fixas v
   where v.enquadre_id = new.id and v.fechada_em is null;

  return new;
end;
$$;

drop trigger if exists enquadres_abrem_vaga_fixa on public.enquadres;
create trigger enquadres_abrem_vaga_fixa after update on public.enquadres
  for each row execute function public.ao_encerrar_enquadre();

/**
 * Arquivar agora encerra o combinado.
 *
 * Sem isto — e era assim até aqui — a materialização seguia criando sessões
 * toda semana para uma ficha arquivada, e o horário continuava ocupado por
 * quem não vem mais. O defeito não aparecia em lugar nenhum: a agenda apenas
 * ficava cheia de gente que saiu.
 */
create or replace function public.arquivar_paciente(
  p_paciente uuid,
  p_encerramento text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare pac record;
begin
  if p_encerramento is null or length(btrim(p_encerramento)) < 10 then
    raise exception 'o encerramento precisa dizer como o acompanhamento terminou';
  end if;

  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;
  if pac.estado = 'arquivado' then raise exception 'esta ficha já está arquivada'; end if;

  update public.pacientes
     set estado = 'arquivado',
         arquivado_em = now(),
         encerramento = btrim(p_encerramento)
   where id = p_paciente;

  -- O combinado aberto encerra junto — e é o encerramento que abre a vaga
  -- fixa, pelo gatilho acima.
  update public.enquadres
     set vigencia_fim = public.hoje_sp(), motivo_fim = 'encerramento'
   where paciente_id = p_paciente and vigencia_fim is null;

  -- Sai das duas filas e para de receber.
  delete from public.fila_encaixe where paciente_id = p_paciente;
  delete from public.fila_entrada where paciente_id = p_paciente;
  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente and estado = 'pendente';

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'arquivou', '{}'::jsonb);

  return 'arquivada';
end;
$$;

/** Ela abre a vaga à mão: abandono, ou um horário que nunca teve dono. */
create or replace function public.abrir_vaga_fixa(
  p_profissional uuid,
  p_dia smallint,
  p_hora time,
  p_duracao smallint default 50,
  p_motivo text default 'outro'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  nova uuid;
begin
  if c is null then raise exception 'sem conta na sessão'; end if;
  if not exists (select 1 from public.profissionais where id = p_profissional and conta_id = c) then
    raise exception 'profissional não é desta conta';
  end if;

  insert into public.vagas_fixas (
    conta_id, profissional_id, dia_semana, hora, duracao_min, motivo
  )
  values (c, p_profissional, p_dia, p_hora, p_duracao, coalesce(p_motivo, 'outro'))
  returning id into nova;

  insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
  values (c, 'vaga_fixa_aberta', nova,
          jsonb_build_object('dia_semana', p_dia, 'hora', p_hora, 'a_mao', true));

  return nova;
end;
$$;

create or replace function public.fechar_vaga_fixa(p_vaga uuid, p_motivo text default 'cancelada')
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.vagas_fixas
     set fechada_em = now(), fechada_por = coalesce(p_motivo, 'cancelada')
   where id = p_vaga and fechada_em is null;

  update public.ofertas_fixas
     set estado = 'cancelada', respondida_em = now()
   where vaga_id = p_vaga and estado = 'enviada';
end;
$$;

-- ------------------------------------------------------- quem é elegível

/**
 * A elegibilidade da vaga fixa, explicável.
 *
 * Devolve **todo mundo** com `elegivel` e o motivo — não uma lista filtrada. É
 * a mesma decisão da B7, e é o que faz a psicóloga confiar na fila: ela vê por
 * que a pessoa que ela tinha em mente não foi chamada.
 *
 * A janela é conferida contra a **próxima ocorrência** daquele dia e hora: é o
 * jeito de perguntar "terça às 15h te serve?" com a mesma função que a B7 usa
 * para uma hora específica.
 */
create or replace function public.elegiveis_para_vaga_fixa(p_vaga uuid)
returns table (
  paciente_id uuid,
  nome text,
  elegivel boolean,
  motivo text,
  ordem bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with vaga as (
    select v.id, v.conta_id, v.dia_semana, v.hora, c.regra_prioridade,
           -- A próxima vez que esse dia e hora acontecem, para a janela ter
           -- contra o que ser conferida.
           (((public.hoje_sp()
              + ((v.dia_semana - extract(dow from public.hoje_sp())::int + 7) % 7))
             + v.hora) at time zone 'America/Sao_Paulo') as proxima
      from public.vagas_fixas v
      join public.contas c on c.id = v.conta_id
     where v.id = p_vaga
  ),
  candidatos as (
    select f.paciente_id, p.nome, f.prioridade, f.entrou_em, f.janelas,
           p.estado as estado_paciente, p.msg_canal, v.*,
           (select o.estado from public.ofertas_fixas o
             where o.vaga_id = p_vaga and o.paciente_id = f.paciente_id) as ja_ofertado,
           exists (
             select 1 from public.enquadres e
              where e.paciente_id = f.paciente_id and e.vigencia_fim is null
           ) as ja_tem_combinado
      from public.fila_entrada f
      join public.pacientes p on p.id = f.paciente_id
      cross join vaga v
     where f.ativo and f.conta_id = v.conta_id
  )
  select
    c.paciente_id,
    c.nome,
    (c.motivo_calculado is null) as elegivel,
    coalesce(c.motivo_calculado, 'na fila de entrada') as motivo,
    row_number() over (
      order by
        (c.motivo_calculado is null) desc,
        c.prioridade desc,
        -- Nas duas regras a ordem de chegada é o desempate: quem esperou mais
        -- vai primeiro. A fila **nunca** ordena por dinheiro — é a fronteira do
        -- doc 11, e não existe coluna que permita isso.
        c.entrou_em asc
    ) as ordem
  from (
    select cc.*,
      case
        when cc.estado_paciente = 'arquivado'                 then 'ficha arquivada'
        when cc.msg_canal = 'nao_avisar'                      then 'pediu para não ser avisado'
        when cc.ja_ofertado = 'recusada'                      then 'já recusou esta vaga'
        when cc.ja_ofertado is not null                       then 'já recebeu esta oferta'
        when cc.ja_tem_combinado                              then 'já tem horário fixo'
        when not public.cabe_na_janela(cc.janelas, cc.proxima) then 'fora da janela'
        else null
      end as motivo_calculado
    from candidatos cc
  ) c
  order by ordem;
$$;

-- ---------------------------------------------------------------- a cascata

create or replace function public.avancar_fila_fixa(p_vaga uuid)
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
  ate timestamptz;
  n int;
begin
  select vf.id, vf.conta_id, vf.dia_semana, vf.hora, vf.fechada_em, c.oferta_fixa_horas
    into v
    from public.vagas_fixas vf
    join public.contas c on c.id = vf.conta_id
   where vf.id = p_vaga;

  if not found then raise exception 'vaga fixa não encontrada'; end if;
  if v.fechada_em is not null then return null; end if;

  -- Uma oferta viva por vaga, conferida antes de tentar.
  if exists (select 1 from public.ofertas_fixas o
              where o.vaga_id = p_vaga and o.estado = 'enviada') then
    return null;
  end if;

  select * into proximo
    from public.elegiveis_para_vaga_fixa(p_vaga)
   where elegivel
   order by ordem
   limit 1;

  if not found then
    update public.vagas_fixas
       set fechada_em = now(), fechada_por = 'sem_takers'
     where id = p_vaga and fechada_em is null;

    insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
    values (v.conta_id, 'vaga_sem_takers', p_vaga,
            jsonb_build_object('fila', 'entrada'));
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  ate    := quando + make_interval(hours => v.oferta_fixa_horas);
  select count(*) + 1 into n from public.ofertas_fixas where vaga_id = p_vaga;

  insert into public.ofertas_fixas (conta_id, vaga_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_vaga, proximo.paciente_id, n, quando, ate)
  returning id into nova;

  insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
  values (v.conta_id, 'oferta_enviada', p_vaga,
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'fila', 'entrada', 'enviar_em', quando));

  perform public.enfileirar_mensagem(
    proximo.paciente_id,
    'oferta_de_vaga_fixa',
    'ofertafixa:' || nova::text,
    jsonb_build_object(
      'oferta_id', nova,
      -- O rótulo já sai pronto do banco (`rotulo_horario`, da 0031): "terça, 15h".
      'horario_fixo', public.rotulo_horario(v.dia_semana, v.hora),
      'expira_em', ate
    ),
    quando
  );

  return nova;
end;
$$;

/**
 * O aceite, transacional — e o que ele **não** faz.
 *
 * Trava a oferta, confere que ela ainda está viva, trava a vaga, confere que
 * ela ainda está aberta, e fecha as duas. Dois aceites simultâneos: o segundo
 * encontra a oferta já respondida.
 *
 * **Não cria enquadre.** A vaga fica reservada no nome da pessoa e o assunto
 * volta para a psicóloga, que precisa combinar valor, política e contrato — a
 * conversa que ela ia ter de qualquer jeito, e que o sistema não tem como ter
 * por ela.
 */
create or replace function public.responder_oferta_fixa(p_oferta uuid, p_resposta text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  o record;
  v record;
begin
  if p_resposta not in ('aceita', 'recusada') then
    raise exception 'resposta precisa ser aceita ou recusada';
  end if;

  select * into o from public.ofertas_fixas where id = p_oferta for update;
  if not found then raise exception 'oferta não encontrada'; end if;
  if o.estado <> 'enviada' then raise exception 'esta oferta já foi respondida (%)', o.estado; end if;
  if now() > o.expira_em then raise exception 'esta oferta expirou'; end if;

  select * into v from public.vagas_fixas where id = o.vaga_id for update;
  if v.fechada_em is not null then raise exception 'esta vaga já foi preenchida'; end if;

  update public.ofertas_fixas
     set estado = p_resposta, respondida_em = now()
   where id = p_oferta;

  if p_resposta = 'recusada' then
    insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
    values (o.conta_id, 'oferta_recusada', o.vaga_id,
            jsonb_build_object('oferta', p_oferta, 'fila', 'entrada'));

    perform public.avancar_fila_fixa(o.vaga_id);
    return 'recusada';
  end if;

  update public.vagas_fixas
     set fechada_em = now(), fechada_por = 'preenchida', novo_paciente = o.paciente_id
   where id = o.vaga_id;

  -- Sai da fila de entrada: conseguiu o que estava esperando.
  update public.fila_entrada set ativo = false where paciente_id = o.paciente_id;

  insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
  values (o.conta_id, 'vaga_fixa_preenchida', o.vaga_id,
          jsonb_build_object('oferta', p_oferta, 'paciente', o.paciente_id));

  return 'aceita';
end;
$$;

/** O prazo venceu: passa para a próxima. Roda no cron de cinco minutos. */
create or replace function public.expirar_ofertas_fixas()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id, vaga_id, conta_id from public.ofertas_fixas
     where estado = 'enviada' and expira_em <= now()
     for update skip locked
  loop
    update public.ofertas_fixas
       set estado = 'expirada', respondida_em = now()
     where id = r.id;

    insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
    values (r.conta_id, 'oferta_expirada', r.vaga_id,
            jsonb_build_object('oferta', r.id, 'fila', 'entrada'));

    perform public.avancar_fila_fixa(r.vaga_id);
    n := n + 1;
  end loop;

  return n;
end;
$$;

-- --------------------------------------------------- a resposta que vem de fora

/**
 * O webhook passa a conhecer as duas filas.
 *
 * Uma pessoa pode ter uma oferta de encaixe e uma de vaga fixa vivas ao mesmo
 * tempo — e o "SIM" dela é sobre **a última mensagem que chegou**, não sobre a
 * que o código olhar primeiro. Por isso as duas entram na mesma consulta,
 * ordenadas por `enviar_em`, e ganha a mais recente.
 *
 * Sem isso, quem estivesse nas duas filas responderia SIM para a vaga fixa e o
 * sistema marcaria um encaixe — a pessoa apareceria numa quarta-feira que
 * ninguém combinou.
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
  alvo record;
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

  -- A oferta viva mais recente daquele telefone, **das duas filas**.
  select * into alvo from (
    select o.id, o.conta_id, o.paciente_id, o.sessao_id, null::uuid as vaga_id,
           o.enviar_em, 'encaixe'::text as fila
      from public.ofertas o
      join public.pacientes p on p.id = o.paciente_id
     where o.estado = 'enviada' and public.so_digitos(p.telefone) = fone
    union all
    select f.id, f.conta_id, f.paciente_id, null::uuid, f.vaga_id,
           f.enviar_em, 'entrada'::text
      from public.ofertas_fixas f
      join public.pacientes p on p.id = f.paciente_id
     where f.estado = 'enviada' and public.so_digitos(p.telefone) = fone
  ) t
  order by t.enviar_em desc
  limit 1;

  if not found then
    update public.mensagens_recebidas
       set resultado = 'sem oferta viva para este telefone'
     where id = nova;
    return jsonb_build_object('estado', 'sem_oferta', 'intencao', intencao);
  end if;

  update public.mensagens_recebidas
     set conta_id = alvo.conta_id,
         paciente_id = alvo.paciente_id,
         -- `oferta_id` referencia `ofertas`; para a fila de entrada fica nulo e
         -- o texto do resultado diz de qual fila se tratava.
         oferta_id = case when alvo.fila = 'encaixe' then alvo.id end
   where id = nova;

  if intencao = 'indefinida' then
    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, vaga_fixa_id, tipo, detalhe)
    values (alvo.conta_id, alvo.sessao_id,
            case when alvo.fila = 'encaixe' then alvo.id end,
            alvo.vaga_id, 'resposta_nao_entendida',
            jsonb_build_object('texto', left(coalesce(p_texto, ''), 200), 'fila', alvo.fila));

    update public.mensagens_recebidas
       set resultado = 'não entendida — a oferta segue viva'
     where id = nova;

    return jsonb_build_object('estado', 'nao_entendi', 'oferta', alvo.id);
  end if;

  begin
    if alvo.fila = 'encaixe' then
      select public.responder_oferta(
        alvo.id, case intencao when 'aceitar' then 'aceita' else 'recusada' end
      ) into desfecho;
    else
      select public.responder_oferta_fixa(
        alvo.id, case intencao when 'aceitar' then 'aceita' else 'recusada' end
      ) into desfecho;
    end if;
  exception when others then
    update public.mensagens_recebidas
       set resultado = 'não deu: ' || left(sqlerrm, 200)
     where id = nova;
    return jsonb_build_object('estado', 'tarde_demais', 'motivo', sqlerrm);
  end;

  update public.mensagens_recebidas
     set resultado = desfecho || ' (' || alvo.fila || ')'
   where id = nova;

  return jsonb_build_object('estado', desfecho, 'oferta', alvo.id, 'fila', alvo.fila);
end;
$$;

-- ---------------------------------------------------------- a sétima família

alter table public.mensagens drop constraint if exists mensagens_template_check;
alter table public.mensagens add constraint mensagens_template_check
  check (template in (
    'oferta_de_vaga',
    'encaixe_confirmado',
    'lembrete_de_sessao',
    'aviso_de_desmarque',
    'aviso_de_cobranca',
    'lembrete_de_pagamento',
    'oferta_de_vaga_fixa'
  ));

-- ---------------------------------------------------------------------- RLS

alter table public.fila_entrada  enable row level security;
alter table public.vagas_fixas   enable row level security;
alter table public.ofertas_fixas enable row level security;

drop policy if exists "fila de entrada da conta: ler" on public.fila_entrada;
create policy "fila de entrada da conta: ler" on public.fila_entrada
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "fila de entrada da conta: escrever" on public.fila_entrada;
create policy "fila de entrada da conta: escrever" on public.fila_entrada
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "fila de entrada da conta: editar" on public.fila_entrada;
create policy "fila de entrada da conta: editar" on public.fila_entrada
  for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

drop policy if exists "fila de entrada da conta: sair" on public.fila_entrada;
create policy "fila de entrada da conta: sair" on public.fila_entrada
  for delete to authenticated using (conta_id = public.conta_atual());

drop policy if exists "vagas fixas da conta: ler" on public.vagas_fixas;
create policy "vagas fixas da conta: ler" on public.vagas_fixas
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "vagas fixas da conta: escrever" on public.vagas_fixas;
create policy "vagas fixas da conta: escrever" on public.vagas_fixas
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "vagas fixas da conta: editar" on public.vagas_fixas;
create policy "vagas fixas da conta: editar" on public.vagas_fixas
  for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Ofertas são **só leitura** para o cliente, como as da B7: quem responde é a
-- função, que confere o prazo e a corrida. Uma tela capaz de escrever `aceita`
-- aqui poderia dar a vaga a quem não foi chamado.
drop policy if exists "ofertas fixas da conta: ler" on public.ofertas_fixas;
create policy "ofertas fixas da conta: ler" on public.ofertas_fixas
  for select to authenticated using (conta_id = public.conta_atual());

-- ----------------------------------------------------------------- permissões
--
-- Os três, sempre: `public`, `anon` e `authenticated` (0018, 0027, 0031).

revoke execute on function public.ao_encerrar_enquadre() from public, anon, authenticated;
revoke execute on function public.checa_conta_da_fila_entrada() from public, anon, authenticated;
revoke execute on function public.expirar_ofertas_fixas() from public, anon, authenticated;
grant  execute on function public.expirar_ofertas_fixas() to service_role;

revoke execute on function public.abrir_vaga_fixa(uuid, smallint, time, smallint, text) from public, anon;
revoke execute on function public.fechar_vaga_fixa(uuid, text) from public, anon;
revoke execute on function public.elegiveis_para_vaga_fixa(uuid) from public, anon;
revoke execute on function public.avancar_fila_fixa(uuid) from public, anon;
revoke execute on function public.responder_oferta_fixa(uuid, text) from public, anon;

grant execute on function public.abrir_vaga_fixa(uuid, smallint, time, smallint, text) to authenticated;
grant execute on function public.fechar_vaga_fixa(uuid, text) to authenticated;
grant execute on function public.elegiveis_para_vaga_fixa(uuid) to authenticated;
grant execute on function public.avancar_fila_fixa(uuid) to authenticated;
grant execute on function public.responder_oferta_fixa(uuid, text) to authenticated, service_role;

revoke execute on function public.responder_do_whatsapp(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.responder_do_whatsapp(text, text, text, text) to service_role;

revoke execute on function public.arquivar_paciente(uuid, text) from public, anon;
grant  execute on function public.arquivar_paciente(uuid, text) to authenticated;

comment on table public.fila_entrada is
  'Quem ligou quando nao havia horario. Outra fila, outra espera: aqui se espera uma vaga fixa.';
comment on table public.vagas_fixas is
  'O horario recorrente que vagou. So encerramento abre; reajuste e mudanca de horario nao.';
comment on function public.responder_oferta_fixa(uuid, text) is
  'Aceitar reserva a vaga e NAO cria enquadre: valor, politica e contrato sao conversa dela.';
