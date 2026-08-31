-- 0035 · B21 — a remarcação guiada (D11).
--
-- "Preciso remarcar" é a mensagem que hoje abre uma negociação por WhatsApp,
-- consome a psicóloga e **termina em buraco**: a hora antiga fica vazia e a
-- nova sai de um pedaço de agenda que estava livre. Duas horas mexidas, uma
-- perdida.
--
-- A D1 (a fila) reage ao furo depois que ele acontece. Esta é a irmã
-- preventiva: em vez de abrir o calendário inteiro, o sistema oferece **duas ou
-- três horas escolhidas** — as que ele quer preencher — e a troca fecha
-- sozinha. Remarcar deixa de criar furo e passa a tapar furo.
--
-- Cinco decisões, e as cinco têm consequência na agenda de alguém.
--
-- ## 1. O que é um buraco, em ordem
--
--   1. **buraco** — uma hora que já está vazia porque alguém cancelou. Encher é
--      ganho puro: o furo some.
--   2. **grade** — uma hora que é habitualmente dela (dia e hora de algum
--      combinado aberto) e que naquela semana está sem ninguém.
--   3. **adjacente** — colada na primeira ou na última sessão do dia. Não tapa
--      furo, mas também não abre: não acrescenta viagem nem ilha no meio da
--      tarde.
--
-- Nessa ordem, no máximo três, **uma por dia**. Três opções na mesma tarde é
-- uma opção só; e uma parede de horários é a negociação do WhatsApp com outro
-- nome.
--
-- ## 2. Nunca um dia que ela não trabalharia
--
-- A regra que corta mais candidatos, e a mais importante: **a opção só existe
-- em dia que já tem outra sessão viva**. Encher o buraco de uma quinta que
-- ficou vazia significa ela atravessar a cidade para atender uma pessoa. O
-- sistema não pode economizar o furo dela cobrando uma viagem.
--
-- ## 3. Remarcar não apaga a política
--
-- A hora antiga é cancelada pela **mesma classificação de sempre** (0009/0011):
-- se faltavam menos horas do que o combinado pede, é tardia e a cobrança nasce.
-- Sem isso, "remarcar" viraria a porta dos fundos da D2 — bastaria remarcar
-- para nunca pagar falta, e a política inteira deixaria de existir na prática.
--
-- A tela mostra o valor com o botão de perdoar ao lado. Quem decide perdoar é
-- ela, como em todo o resto do produto; o sistema não inventa uma isenção que
-- ninguém combinou.
--
-- ## 4. A hora que vagou vai para a fila, na mesma transação
--
-- É o que faz a remarcação ser **líquida positiva**: um buraco fechado e um
-- buraco oferecido à lista de espera, num movimento só. Sem isso, remarcar
-- apenas moveria o problema de lugar.
--
-- ## 5. Não há reserva
--
-- As opções não travam a agenda. Um link vive 48 horas; segurar três horas por
-- 48 horas, para cada remarcação, congelaria a agenda inteira — e travaria
-- justamente a fila, que é o produto. A escolha confere disponibilidade **no
-- instante do clique**, dentro de uma transação, e a restrição de exclusão da
-- 0006 é o árbitro final. Perder uma opção para a fila é possível e a tela diz
-- isso com todas as letras; duas pessoas na mesma hora, não.

-- ---------------------------------------------------------------- a tabela

create table if not exists public.remarcacoes (
  id           uuid primary key default gen_random_uuid(),
  conta_id     uuid not null references public.contas (id) on delete cascade,
  paciente_id  uuid not null references public.pacientes (id) on delete cascade,

  -- A sessão que sai do lugar.
  sessao_id    uuid not null references public.sessoes (id) on delete cascade,
  -- A que nasce no lugar novo. Nula até alguém escolher.
  nova_sessao_id uuid references public.sessoes (id) on delete set null,

  token        text not null unique check (token ~ '^[0-9a-f]{32}$'),

  -- As opções congeladas: [{"inicio":…,"fim":…,"motivo":"buraco"}]. Congelar
  -- importa porque a escolha só aceita o que está aqui — senão o link viraria
  -- uma porta para marcar qualquer hora na agenda dela.
  opcoes       jsonb not null,

  criada_em    timestamptz not null default now(),
  expira_em    timestamptz not null,

  escolhida_em     timestamptz,
  escolhido_inicio timestamptz,
  origem       text check (origem is null or origem in ('link', 'presencial')),

  cancelada_em timestamptz,

  check (escolhida_em is null or escolhido_inicio is not null)
);

create index if not exists remarcacoes_da_conta on public.remarcacoes (conta_id, criada_em desc);
create index if not exists remarcacoes_do_paciente on public.remarcacoes (paciente_id, criada_em desc);

-- Uma remarcação viva por sessão. Duas convidariam a mesma pessoa a escolher
-- duas horas para o mesmo encontro.
create unique index if not exists remarcacao_viva_por_sessao
  on public.remarcacoes (sessao_id)
  where escolhida_em is null and cancelada_em is null;

-- ------------------------------------------------------------ as opções

/**
 * As horas que o sistema **quer** preencher, para esta sessão.
 *
 * Devolve no máximo `p_max`, uma por dia, na ordem buraco → grade → adjacente e
 * depois pela data. Só dias em que a profissional já tem outra sessão viva.
 *
 * `security invoker`: a RLS prende tudo à conta de quem pergunta. Uma versão
 * `definer` disto responderia sobre a agenda de qualquer pessoa — foi
 * exatamente o defeito que a 0015 consertou na B7.
 */
create or replace function public.opcoes_de_remarcacao(
  p_sessao uuid,
  p_max int default 3
)
returns table (inicio timestamptz, fim timestamptz, motivo text)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  s        record;
  dur      interval;
  -- Doze horas de antecedência mínima. Oferecer "hoje daqui a vinte minutos"
  -- não é uma opção, é um susto — e a pessoa que pediu para remarcar
  -- provavelmente pediu porque o dia está impossível.
  cedo     timestamptz;
  -- Três semanas. Além disso a agenda ainda vai mudar, e uma opção que muda
  -- não é uma opção.
  tarde    timestamptz;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then return; end if;

  dur   := s.fim - s.inicio;
  cedo  := now() + interval '12 hours';
  tarde := now() + interval '21 days';

  return query
  with dias as (
    -- Os dias em que ela já vem trabalhar. Fora deles, nenhuma opção existe.
    select distinct (o.inicio at time zone 'America/Sao_Paulo')::date as d
      from public.sessoes o
     where o.profissional_id = s.profissional_id
       and o.id <> s.id
       and o.estado in ('prevista', 'confirmada')
       and o.inicio between cedo and tarde
  ),
  buracos as (
    -- Hora que ficou vazia porque alguém desmarcou.
    select c.inicio as ini, c.inicio + dur as f, 'buraco'::text as m, 1 as r
      from public.sessoes c
      join dias on dias.d = (c.inicio at time zone 'America/Sao_Paulo')::date
     where c.profissional_id = s.profissional_id
       and c.id <> s.id
       and c.estado in ('cancelada_cedo', 'cancelada_tarde')
       and c.inicio between cedo and tarde
  ),
  grade as (
    -- Dia e hora que são habitualmente dela, vazios naquela semana.
    select ((dias.d + e.hora) at time zone 'America/Sao_Paulo') as ini,
           ((dias.d + e.hora) at time zone 'America/Sao_Paulo') + dur as f,
           'grade'::text as m, 2 as r
      from public.enquadres e
      join public.pacientes p on p.id = e.paciente_id
      cross join dias
     where p.profissional_id = s.profissional_id
       and e.vigencia_fim is null
       and extract(dow from dias.d) = e.dia_semana
  ),
  bordas as (
    -- A primeira e a última sessão de cada dia: é nelas que se encosta.
    select dias.d,
           min(o.inicio) as primeira,
           max(o.fim)    as ultima
      from dias
      join public.sessoes o
        on (o.inicio at time zone 'America/Sao_Paulo')::date = dias.d
       and o.profissional_id = s.profissional_id
       and o.id <> s.id
       and o.estado in ('prevista', 'confirmada')
     group by dias.d
  ),
  adjacentes as (
    select b.primeira - dur as ini, b.primeira as f, 'adjacente'::text as m, 3 as r from bordas b
    union all
    select b.ultima as ini, b.ultima + dur as f, 'adjacente'::text as m, 3 as r from bordas b
  ),
  todas as (
    select * from buracos
    union all select * from grade
    union all select * from adjacentes
  ),
  livres as (
    select t.ini, t.f, t.m, t.r,
           row_number() over (
             partition by (t.ini at time zone 'America/Sao_Paulo')::date
             order by t.r, t.ini
           ) as no_dia
      from todas t
     where t.ini between cedo and tarde
       and t.ini <> s.inicio
       and public.vaga_esta_livre(s.profissional_id, t.ini, t.f, s.id)
  )
  select l.ini, l.f, l.m
    from livres l
   where l.no_dia = 1          -- uma por dia: três na mesma tarde é uma só
   order by l.r, l.ini
   limit greatest(coalesce(p_max, 3), 1);
end;
$$;

-- ------------------------------------------------------------ abrir

/**
 * O que o servidor calcula, o cliente não digita.
 *
 * Mesma doutrina da 0017 e da 0031: um INSERT direto no PostgREST não escolhe
 * token nem opções. Aqui isso decide o que a pessoa do outro lado consegue
 * marcar na agenda dela.
 */
create or replace function public.remarcacao_monta()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s    record;
  ops  jsonb;
begin
  new.conta_id := public.conta_atual();
  if new.conta_id is null then
    raise exception 'sem conta na sessão';
  end if;

  select * into s
    from public.sessoes
   where id = new.sessao_id and conta_id = new.conta_id;
  if not found then raise exception 'sessão não encontrada nesta conta'; end if;

  if s.estado not in ('prevista', 'confirmada') then
    raise exception 'só dá para remarcar uma sessão que ainda vai acontecer';
  end if;
  if s.inicio <= now() then
    raise exception 'esta hora já passou';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'inicio', o.inicio, 'fim', o.fim, 'motivo', o.motivo
         ) order by o.inicio), '[]'::jsonb)
    into ops
    from public.opcoes_de_remarcacao(new.sessao_id, 3) o;

  if jsonb_array_length(ops) = 0 then
    raise exception 'não há hora que caiba: nenhum dia da próxima quinzena tem buraco nem borda livre';
  end if;

  new.paciente_id      := s.paciente_id;
  new.token            := replace(gen_random_uuid()::text, '-', '');
  new.opcoes           := ops;
  new.criada_em        := now();
  new.expira_em        := now() + interval '48 hours';
  new.nova_sessao_id   := null;
  new.escolhida_em     := null;
  new.escolhido_inicio := null;
  new.origem           := null;
  new.cancelada_em     := null;

  return new;
end;
$$;

/**
 * Escolhida não se edita; cancelada não volta atrás.
 *
 * A escolha é o instante em que a agenda de duas pessoas mudou. Reescrever a
 * opção depois faria a linha contar uma história diferente da que está na
 * agenda.
 */
create or replace function public.remarcacao_congela()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if row(new.conta_id, new.paciente_id, new.sessao_id)
     is distinct from row(old.conta_id, old.paciente_id, old.sessao_id)
  then
    raise exception 'remarcação não muda de dono nem de sessão';
  end if;

  if old.escolhida_em is not null then
    if row(new.opcoes, new.token, new.escolhida_em, new.escolhido_inicio,
           new.origem, new.nova_sessao_id)
       is distinct from
       row(old.opcoes, old.token, old.escolhida_em, old.escolhido_inicio,
           old.origem, old.nova_sessao_id)
    then
      raise exception 'remarcação já fechada não se edita';
    end if;
    return new;
  end if;

  -- O relógio é do servidor, aqui como em todo lugar.
  if new.escolhida_em is not null then
    new.escolhida_em := now();
    if (select auth.uid()) is not null then
      new.origem := 'presencial';
    else
      new.origem := 'link';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists remarcacoes_montagem on public.remarcacoes;
create trigger remarcacoes_montagem before insert on public.remarcacoes
  for each row execute function public.remarcacao_monta();

drop trigger if exists remarcacoes_congelamento on public.remarcacoes;
create trigger remarcacoes_congelamento before update on public.remarcacoes
  for each row execute function public.remarcacao_congela();

/** Abre (ou renova) a remarcação da sessão e devolve o token. */
create or replace function public.abrir_remarcacao(p_sessao uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  atual record;
  saida text;
begin
  select * into atual
    from public.remarcacoes
   where sessao_id = p_sessao and escolhida_em is null and cancelada_em is null;

  -- Renovar em vez de recusar: o caso comum é ela reenviar o link porque a
  -- pessoa perdeu a mensagem, e as opções de ontem podem já não existir.
  if found then
    update public.remarcacoes set cancelada_em = now() where id = atual.id;
  end if;

  -- Os valores abaixo são descartáveis: o gatilho `remarcacao_monta` recalcula
  -- todos antes de a linha existir.
  insert into public.remarcacoes (sessao_id, conta_id, paciente_id, token, opcoes, expira_em)
  values (p_sessao, p_sessao, p_sessao, 'placeholder', '[]'::jsonb, now())
  returning token into saida;

  return saida;
end;
$$;

create or replace function public.cancelar_remarcacao(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.remarcacoes
     set cancelada_em = now()
   where id = p_id and escolhida_em is null and cancelada_em is null;
end;
$$;

-- ------------------------------------------------------- o lado do visitante

/**
 * O que o link mostra. `security definer` porque quem clica não tem sessão.
 *
 * Devolve o mínimo: primeiro nome, a hora que sai, e as opções **reconferidas
 * agora** — porque não há reserva, e mostrar uma hora que a fila já levou seria
 * mentir para quem está prestes a clicar.
 */
create or replace function public.remarcacao_por_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r    record;
  s    record;
  dur  interval;
  ops  jsonb;
begin
  if p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  select * into r from public.remarcacoes where token = p_token;
  if not found then return jsonb_build_object('estado', 'inexistente'); end if;

  select * into s from public.sessoes where id = r.sessao_id;
  dur := s.fim - s.inicio;

  select coalesce(jsonb_agg(x order by (x->>'inicio')), '[]'::jsonb)
    into ops
    from (
      select jsonb_build_object(
               'inicio', o->>'inicio',
               'motivo', o->>'motivo',
               'livre', public.vaga_esta_livre(
                          s.profissional_id,
                          (o->>'inicio')::timestamptz,
                          (o->>'inicio')::timestamptz + dur,
                          s.id)
                        and (o->>'inicio')::timestamptz > now()
             ) as x
        from jsonb_array_elements(r.opcoes) o
    ) t;

  return jsonb_build_object(
    'estado', case
                when r.cancelada_em is not null then 'cancelada'
                when r.escolhida_em is not null then 'escolhida'
                when now() > r.expira_em        then 'expirada'
                else 'aberta'
              end,
    -- Só o primeiro nome, como nas mensagens: a tela é lida por quem passa.
    'nome',   split_part(coalesce((select nome from public.pacientes where id = r.paciente_id), ''), ' ', 1),
    'atual',  s.inicio,
    'escolhido', r.escolhido_inicio,
    'opcoes', ops
  );
end;
$$;

/**
 * A troca, inteira, numa transação.
 *
 * Trava a remarcação, confere que a hora escolhida é **uma das congeladas**,
 * confere que ela continua livre, cria a sessão nova, cancela a antiga pela
 * classificação de sempre e joga a hora que vagou na fila.
 *
 * A ordem importa: a sessão nova nasce **antes** de a antiga ser cancelada. Se
 * nascesse depois, a fila poderia ser acordada por um cancelamento cuja
 * contrapartida ainda não existe — e, num erro no meio, a pessoa ficaria sem
 * hora nenhuma em vez de continuar com a que tinha.
 */
create or replace function public.escolher_remarcacao(p_token text, p_inicio timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r     record;
  s     record;
  dur   interval;
  nova  uuid;
  achou boolean;
begin
  if p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('ok', false, 'motivo', 'inexistente');
  end if;

  select * into r from public.remarcacoes where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'inexistente'); end if;

  if r.cancelada_em is not null then
    return jsonb_build_object('ok', false, 'motivo', 'cancelada');
  end if;
  if r.escolhida_em is not null then
    return jsonb_build_object('ok', true, 'motivo', 'ja_escolhida', 'inicio', r.escolhido_inicio);
  end if;
  if now() > r.expira_em then
    return jsonb_build_object('ok', false, 'motivo', 'expirada');
  end if;

  -- A hora tem de ser uma das que o sistema ofereceu. Sem isto, o token seria
  -- permissão para marcar qualquer horário na agenda dela.
  select exists (
    select 1 from jsonb_array_elements(r.opcoes) o
     where (o->>'inicio')::timestamptz = p_inicio
  ) into achou;
  if not achou then
    return jsonb_build_object('ok', false, 'motivo', 'nao_oferecida');
  end if;

  select * into s from public.sessoes where id = r.sessao_id for update;
  if s.estado not in ('prevista', 'confirmada') then
    return jsonb_build_object('ok', false, 'motivo', 'sessao_mudou');
  end if;
  if p_inicio <= now() then
    return jsonb_build_object('ok', false, 'motivo', 'passou');
  end if;

  dur := s.fim - s.inicio;

  if not public.vaga_esta_livre(s.profissional_id, p_inicio, p_inicio + dur, s.id) then
    return jsonb_build_object('ok', false, 'motivo', 'ocupada');
  end if;

  -- A sessão nova carrega o mesmo retrato: é o mesmo combinado, mudou de hora.
  insert into public.sessoes (
    conta_id, profissional_id, paciente_id, enquadre_id, inicio, fim,
    origem, estado, valor, politica_horas, politica_percentual
  )
  values (
    s.conta_id, s.profissional_id, s.paciente_id, s.enquadre_id,
    p_inicio, p_inicio + dur, 'remarcada', 'prevista',
    s.valor, s.politica_horas, s.politica_percentual
  )
  returning id into nova;

  -- A hora antiga cai pela classificação de sempre. Remarcar não é atalho para
  -- fugir da política: se está em cima da hora, a cobrança nasce — e a tela
  -- dela mostra o valor com o botão de perdoar ao lado.
  perform public.cancelar_sessao(s.id, 'paciente');

  update public.remarcacoes
     set escolhida_em = now(),
         escolhido_inicio = p_inicio,
         nova_sessao_id = nova
   where id = r.id;

  -- E a hora que vagou vira vaga: um buraco fechado, um buraco oferecido.
  begin
    perform public.abrir_vaga(s.id);
  exception when others then
    -- A fila não pode derrubar a remarcação. Se ela falhar, a troca está feita
    -- e a hora aparece na agenda como vaga aberta de qualquer jeito.
    null;
  end;

  return jsonb_build_object('ok', true, 'motivo', 'remarcada', 'sessao', nova);
end;
$$;

/**
 * Ela remarca na sala, com a pessoa na frente.
 *
 * `security invoker` de propósito: a RLS precisa continuar valendo na abertura,
 * porque é ela que garante que a sessão é desta conta. A troca em si acontece
 * dentro da `escolher_remarcacao`, que é `definer` — e é lá, e só lá, que uma
 * sessão de origem `remarcada` consegue nascer.
 *
 * O gatilho vê uma sessão autenticada e rotula a origem como presencial. Como
 * na B19: a procedência é deduzida de quem está no teclado, não digitada.
 */
create or replace function public.remarcar_presencial(p_sessao uuid, p_inicio timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare tok text;
begin
  tok := public.abrir_remarcacao(p_sessao);
  return public.escolher_remarcacao(tok, p_inicio);
end;
$$;

/**
 * O que esta remarcação vai custar, **antes** de o link sair.
 *
 * Existe porque a consequência de remarcar em cima da hora muda com o modelo de
 * cobrança (B20), e porque descobrir isso depois é o pior lugar possível — para
 * ela e para quem recebe a conta.
 *
 * Não decide nada: informa. Perdoar continua sendo um toque, e é dela.
 */
create or replace function public.custo_da_remarcacao(p_sessao uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  s      record;
  modelo text := 'avulso';
  aparte boolean := false;
  horas  numeric;
  tardia boolean;
  multa  numeric;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then return jsonb_build_object('erro', 'sessão não encontrada'); end if;

  if s.enquadre_id is not null then
    select e.modelo_cobranca, coalesce(e.falta_cobra_a_parte, false)
      into modelo, aparte
      from public.enquadres e where e.id = s.enquadre_id;
  end if;

  horas  := extract(epoch from (s.inicio - now())) / 3600.0;
  tardia := horas < s.politica_horas;
  multa  := public.multa_da_politica(s.valor, s.politica_percentual);

  if not tardia then
    return jsonb_build_object('tardia', false, 'modelo', modelo, 'valor', 0,
      'texto', 'Dentro do prazo combinado: nada é cobrado pela hora que sai.');
  end if;

  if modelo = 'mensal' and not aparte then
    return jsonb_build_object('tardia', true, 'modelo', modelo, 'valor', 0,
      'texto', 'Em cima da hora, mas a mensalidade do mês já cobre esta hora — nada a mais é cobrado.');
  end if;

  if modelo = 'pacote' and not aparte then
    return jsonb_build_object('tardia', true, 'modelo', modelo, 'valor', 0,
      'texto', 'Em cima da hora: a hora que sai consome um crédito do pacote, como uma falta.');
  end if;

  if multa <= 0 then
    return jsonb_build_object('tardia', true, 'modelo', modelo, 'valor', 0,
      'texto', 'Em cima da hora, mas a política deste combinado não cobra falta.');
  end if;

  return jsonb_build_object('tardia', true, 'modelo', modelo, 'valor', multa,
    'texto', 'Em cima da hora: pela política, a hora que sai gera cobrança. Você pode perdoar em Em aberto.');
end;
$$;

-- --------------------------------------------------------------- a origem

-- A sessão que nasce de uma remarcação tem nome próprio: sem isso ela viraria
-- "avulsa" e a agenda perderia a informação de que aquela hora é uma troca.
alter table public.sessoes drop constraint if exists sessoes_origem_check;
alter table public.sessoes add constraint sessoes_origem_check
  check (origem in ('recorrencia', 'encaixe', 'avulsa', 'remarcada'));

-- E o cliente continua sem poder criá-la à mão: quem cria `remarcada` é o motor
-- da remarcação, e mais ninguém.
drop policy if exists "sessoes da conta: criar" on public.sessoes;
create policy "sessoes da conta: criar" on public.sessoes
  for insert to authenticated
  with check (conta_id = public.conta_atual() and origem in ('encaixe', 'avulsa'));

-- ---------------------------------------------------------------------- RLS

alter table public.remarcacoes enable row level security;

drop policy if exists "remarcacoes da conta: ler" on public.remarcacoes;
create policy "remarcacoes da conta: ler" on public.remarcacoes
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "remarcacoes da conta: escrever" on public.remarcacoes;
create policy "remarcacoes da conta: escrever" on public.remarcacoes
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "remarcacoes da conta: editar" on public.remarcacoes;
create policy "remarcacoes da conta: editar" on public.remarcacoes
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- ----------------------------------------------------------------- permissões
--
-- Os três, sempre: `public`, `anon` e `authenticated` (0018, 0027, 0031).

revoke execute on function public.remarcacao_monta()   from public, anon, authenticated;
revoke execute on function public.remarcacao_congela() from public, anon, authenticated;

revoke execute on function public.opcoes_de_remarcacao(uuid, int) from public, anon;
revoke execute on function public.abrir_remarcacao(uuid) from public, anon;
revoke execute on function public.cancelar_remarcacao(uuid) from public, anon;
revoke execute on function public.remarcar_presencial(uuid, timestamptz) from public, anon;
revoke execute on function public.custo_da_remarcacao(uuid) from public, anon;

grant execute on function public.opcoes_de_remarcacao(uuid, int) to authenticated;
grant execute on function public.abrir_remarcacao(uuid) to authenticated;
grant execute on function public.cancelar_remarcacao(uuid) to authenticated;
grant execute on function public.remarcar_presencial(uuid, timestamptz) to authenticated;
grant execute on function public.custo_da_remarcacao(uuid) to authenticated;

-- As duas do visitante. `security definer`, então o que devolvem é toda a
-- superfície que `anon` tem — e as duas devolvem o mínimo.
grant execute on function public.remarcacao_por_token(text) to anon, authenticated;
grant execute on function public.escolher_remarcacao(text, timestamptz) to anon, authenticated;

comment on table public.remarcacoes is
  'D11. Opcoes congeladas e token do servidor; sem reserva; a hora que vaga vai para a fila.';
comment on function public.opcoes_de_remarcacao(uuid, int) is
  'buraco > grade > adjacente, uma por dia, so em dia que ja tem sessao viva.';
