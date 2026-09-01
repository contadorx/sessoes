-- 0040 · A agenda que já existe.
--
-- Metade das psicólogas vive na Google Agenda (doc 02b: 4 dos 8 concorrentes
-- já sincronizam). Sem isso, o sistema **mente** para elas: mostra a terça das
-- 15h livre porque nesta base ela está livre, enquanto no celular dela aquela
-- hora é a consulta do dentista. A fila então oferece a hora, alguém aceita, e
-- a psicóloga descobre o conflito na véspera. É o pior desfecho possível deste
-- produto — a fila existe para produzir confiança, e uma fila que marca por
-- cima de um compromisso destrói exatamente isso.
--
-- O doc 05 reservou a linha em que essa correção cabe, ainda na fase 1:
--
--   "O motor da fila nunca pergunta 'existe sessão nesta hora?' direto na
--    tabela. Pergunta a vaga_esta_livre(). Hoje ela consulta sessoes e
--    excecoes_agenda; quando o sync entrar, ganha uma terceira fonte e a fila
--    não muda uma linha."
--
-- Esta migração é o resgate dessa promessa. A `vaga_esta_livre` ganha a
-- terceira fonte, e `elegiveis_para_vaga`, `avancar_fila`, `responder_oferta`,
-- `horarios_para_remarcar` e `remarcar_sessao` passam a respeitar o calendário
-- dela sem que uma linha delas seja tocada.
--
--
-- ============================================================ as seis decisões
--
-- **1. O que sai daqui não diz quem.**
--
-- A Google é um terceiro fora da nossa fronteira de LGPD. Num consultório de
-- psicologia, a lista de quem tem hora marcada **é** a lista de quem faz
-- terapia — dado sensível do art. 5º, II. Por isso o evento que espelhamos
-- nasce escrito "Sessão", sem nome, sem telefone, sem a palavra terapia: é o
-- mesmo modo discreto do D3, aplicado a outro canal.
--
-- Os três modos existem (`discreto`, `iniciais`, `completo`) porque a
-- psicóloga que trabalha sozinha e olha a própria agenda no celular tem
-- motivo legítimo para querer saber de quem é a hora. Mas o padrão é o
-- discreto, e trocá-lo é ato dela, com a consequência escrita na tela. O que
-- não fazemos é decidir por ela **e** decidir errado por omissão.
--
-- **2. O que entra de lá não guarda o quê.**
--
-- `ocupacoes_externas` tem início e fim. Não tem título, não tem convidado,
-- não tem local, não tem descrição. A fila só precisa saber que a hora está
-- ocupada; o nome do dentista dela não é assunto deste banco, e guardá-lo
-- seria trazer a vida privada da usuária para dentro de um sistema que promete
-- minimizar dado. `registrar_ocupacoes` **ignora** qualquer chave a mais que
-- venha no jsonb — a minimização é da função, não da boa vontade de quem
-- chama.
--
-- **3. Token não é dado da conta.**
--
-- O refresh token da Google dá acesso ao calendário inteiro dela, para sempre,
-- fora daqui. Ele mora em `calendarios_segredo`, uma tabela com RLS ligada e
-- **zero políticas**: nem a dona da conta lê pelo PostgREST. Só o service_role
-- alcança, e só de dentro do servidor. E `exportar_conta` carrega a conexão
-- (para ela saber o que estava ligado) e **nunca** o segredo — exportação de
-- conta é direito de portabilidade, não cópia de credencial.
--
-- **4. Calendário defasado bloqueia; não libera.**
--
-- Se a leitura parou (token expirou, ela pausou), as ocupações que temos são
-- velhas. Velhas para menos, nunca para mais: o compromisso que existia ontem
-- provavelmente ainda existe, e o que apareceu hoje nós não vimos. Então
-- continuamos bloqueando o que sabemos. O erro para o lado de **oferecer
-- menos**, que custa uma vaga; o erro para o outro lado custa a confiança.
--
-- Desligar é diferente de pausar: desligar apaga as ocupações (não há mais
-- calendário, não há mais bloqueio) e apaga o segredo. Pausar congela.
--
-- **5. Desligar não apaga o que já está lá.**
--
-- Ao desconectar, não removemos os eventos que já foram para a agenda dela.
-- Duzentos eventos sumindo do calendário de alguém porque ela clicou em
-- "desconectar" é destruição por efeito colateral. O que fazemos é marcar as
-- pendências como falhas, com o motivo escrito — nada sai com um token que não
-- existe mais, e a tela diz isso em vez de fingir.
--
-- **6. Histórico importado é memória, não dinheiro.**
--
-- A migração de outro sistema traz sessões que já aconteceram. Elas entram com
-- `origem = 'importada'` e servem para a linha do tempo do paciente — e só.
-- Não geram cobrança, não geram pendência de Receita Saúde, não entram no
-- `realizado` do mês nem na lista de "sem registro" do financeiro.
--
-- O motivo é aritmético e é grave: uma planilha com dois anos de atendimento
-- despejaria dezenas de milhares de reais de "realizado" em meses já fechados,
-- encheria a lista de "recebi?" com sessões de 2024 e — se alguém marcasse
-- recebido — inventaria recibo de Receita Saúde para dinheiro que a Receita já
-- viu por outro caminho. O carnê-leão dela é escriturado pelo que passou pelo
-- caixa **deste** sistema; o que veio de fora veio como memória.
--
-- E isso não é convenção: é gatilho. Cobrança ou consumo de pacote apontando
-- para sessão importada **estoura**.

-- ====================================================== a origem que faltava

alter table public.sessoes drop constraint if exists sessoes_origem_check;
alter table public.sessoes add constraint sessoes_origem_check
  check (origem in ('recorrencia', 'encaixe', 'avulsa', 'importada'));

-- ============================================================== a conexão

create table if not exists public.calendarios (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,

  provedor        text not null default 'google' check (provedor in ('google')),

  -- Qual conta Google está ligada. Serve para ela reconhecer na tela — muita
  -- gente tem duas, e "ligado" sem dizer a qual é informação inútil.
  email_externo      text check (email_externo is null or length(email_externo) <= 200),
  calendario_externo text check (calendario_externo is null or length(calendario_externo) <= 400),

  estado   text not null default 'ligado'
           check (estado in ('ligado', 'pausado', 'expirado', 'revogado')),

  -- `ler`: só trago as ocupações dela para cá (não escrevo nada lá).
  -- `escrever`: só mando as sessões para lá.
  -- `duas_vias`: os dois.
  direcao  text not null default 'duas_vias'
           check (direcao in ('ler', 'escrever', 'duas_vias')),

  modo_titulo text not null default 'discreto'
              check (modo_titulo in ('discreto', 'iniciais', 'completo')),

  -- O cursor incremental do provedor. Guardado porque a alternativa é reler a
  -- janela inteira toda vez, e isso é cota queimada por preguiça.
  sync_token      text,
  lido_de         date,
  lido_ate        date,
  sincronizado_em timestamptz,
  erro            text,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Um calendário por profissional. Numa clínica, cada uma liga o seu — e o
-- calendário de uma nunca bloqueia a agenda da outra.
create unique index if not exists calendario_por_profissional
  on public.calendarios (profissional_id);
create index if not exists calendarios_da_conta on public.calendarios (conta_id);

drop trigger if exists calendarios_atualizado_em on public.calendarios;
create trigger calendarios_atualizado_em before update on public.calendarios
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ o segredo

create table if not exists public.calendarios_segredo (
  calendario_id uuid primary key references public.calendarios (id) on delete cascade,
  refresh_token text not null,
  access_token  text,
  expira_em     timestamptz,
  atualizado_em timestamptz not null default now()
);

comment on table public.calendarios_segredo is
  'Token do provedor. RLS ligada e nenhuma politica: invisivel pelo PostgREST, inclusive para a dona da conta. So service_role, so do servidor. Nunca entra em exportar_conta.';

-- ===================================================== o que entra (ocupações)

create table if not exists public.ocupacoes_externas (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  calendario_id   uuid not null references public.calendarios (id) on delete cascade,

  evento_externo  text not null,

  inicio      timestamptz not null,
  fim         timestamptz not null,
  dia_inteiro boolean not null default false,

  visto_em  timestamptz not null default now(),
  criado_em timestamptz not null default now(),

  check (fim > inicio)
);

comment on table public.ocupacoes_externas is
  'Horas ocupadas na agenda externa. Sem titulo, sem convidado, sem local, sem descricao: a fila precisa saber que esta ocupado, nao de quem e o compromisso.';

create unique index if not exists ocupacao_por_evento
  on public.ocupacoes_externas (calendario_id, evento_externo);
create index if not exists ocupacoes_do_profissional
  on public.ocupacoes_externas (profissional_id, inicio, fim);
create index if not exists ocupacoes_da_conta on public.ocupacoes_externas (conta_id);

-- ======================================================= o que sai (espelhos)

create table if not exists public.espelhos_calendario (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  calendario_id uuid not null references public.calendarios (id) on delete cascade,

  -- `set null`, não `cascade`: quando férias apagam a sessão prevista, o
  -- espelho precisa **sobreviver** para conseguir remover o evento lá fora.
  -- Um cascade aqui deixaria a agenda dela cheia de sessões que já não existem.
  sessao_id      uuid references public.sessoes (id) on delete set null,
  evento_externo text,

  acao   text not null check (acao in ('criar', 'atualizar', 'remover')),
  estado text not null default 'pendente'
         check (estado in ('pendente', 'espelhada', 'removida', 'falhou')),

  tentativas smallint not null default 0,
  erro       text,
  enviado_em timestamptz,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists espelho_por_sessao
  on public.espelhos_calendario (calendario_id, sessao_id)
  where sessao_id is not null;
create index if not exists espelhos_pendentes
  on public.espelhos_calendario (criado_em) where estado = 'pendente';
create index if not exists espelhos_da_conta on public.espelhos_calendario (conta_id);

drop trigger if exists espelhos_atualizado_em on public.espelhos_calendario;
create trigger espelhos_atualizado_em before update on public.espelhos_calendario
  for each row execute function public.tocar_atualizado_em();

-- ============================================================ o título

/**
 * O que o evento diz.
 *
 * Espelhada aqui e em `lib/calendario.ts` com os mesmos valores esperados,
 * porque a tela precisa mostrar a prévia **antes** de ela ligar — decidir o
 * modo depois de ver duzentos nomes no celular é tarde.
 */
create or replace function public.iniciais_do_nome(p_nome text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(
      trim(
        (select string_agg(upper(left(w, 1)) || '.', ' ')
           from unnest(regexp_split_to_array(coalesce(p_nome, ''), '\s+')) as w
          where w <> ''
            and lower(w) not in ('de', 'da', 'do', 'dos', 'das', 'e'))
      ),
      ''),
    '');
$$;

create or replace function public.titulo_do_evento(p_modo text, p_nome text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_modo
    when 'completo' then
      case when coalesce(trim(p_nome), '') = '' then 'Sessão'
           else 'Sessão · ' || trim(p_nome) end
    when 'iniciais' then
      case when public.iniciais_do_nome(p_nome) = '' then 'Sessão'
           else 'Sessão · ' || public.iniciais_do_nome(p_nome) end
    else 'Sessão'
  end;
$$;

-- ================================================ a terceira fonte da vaga

/**
 * A linha que o doc 05 reservou.
 *
 * Continua `security invoker` (lição da 0015): perguntar sobre a agenda de
 * outra conta não é proibido, é **inútil** — a RLS não deixa a função enxergar
 * nada e ela responde sobre o vazio.
 *
 * `revogado` não bloqueia porque desligar apaga as ocupações; os outros três
 * estados bloqueiam, inclusive `expirado`, pelo motivo da decisão 4.
 */
create or replace function public.vaga_esta_livre(
  p_profissional uuid,
  p_inicio timestamptz,
  p_fim timestamptz,
  p_ignorar uuid default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select not exists (
    select 1 from public.sessoes s
     where s.profissional_id = p_profissional
       and s.id is distinct from p_ignorar
       and s.estado in ('prevista', 'confirmada', 'realizada', 'falta')
       and tstzrange(s.inicio, s.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
  )
  and not exists (
    select 1 from public.excecoes_agenda x
     where x.profissional_id = p_profissional
       and (p_inicio at time zone 'America/Sao_Paulo')::date between x.inicio and x.fim
  )
  and not exists (
    select 1
      from public.ocupacoes_externas o
      join public.calendarios cal on cal.id = o.calendario_id
     where o.profissional_id = p_profissional
       and cal.estado in ('ligado', 'pausado', 'expirado')
       and cal.direcao in ('ler', 'duas_vias')
       and tstzrange(o.inicio, o.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
  );
$$;

-- =================================================== ligar, pausar, desligar

create or replace function public.ligar_calendario(
  p_profissional uuid,
  p_email text default null,
  p_calendario_externo text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  achado uuid;
begin
  if c is null then raise exception 'sem conta'; end if;

  if not exists (
    select 1 from public.profissionais pr
     where pr.id = p_profissional and pr.conta_id = c
  ) then
    raise exception 'esse profissional não é desta conta';
  end if;

  select id into achado from public.calendarios where profissional_id = p_profissional;

  if achado is null then
    insert into public.calendarios (conta_id, profissional_id, email_externo, calendario_externo)
    values (c, p_profissional, p_email, coalesce(p_calendario_externo, 'primary'))
    returning id into achado;
  else
    update public.calendarios
       set estado = 'ligado',
           erro = null,
           email_externo = coalesce(p_email, email_externo),
           calendario_externo = coalesce(p_calendario_externo, calendario_externo, 'primary')
     where id = achado;
  end if;

  return achado;
end;
$$;

create or replace function public.ajustar_calendario(
  p_profissional uuid,
  p_direcao text,
  p_modo_titulo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_direcao not in ('ler', 'escrever', 'duas_vias') then
    raise exception 'direção inválida';
  end if;
  if p_modo_titulo not in ('discreto', 'iniciais', 'completo') then
    raise exception 'modo de título inválido';
  end if;

  update public.calendarios
     set direcao = p_direcao, modo_titulo = p_modo_titulo
   where profissional_id = p_profissional and conta_id = c;

  if not found then raise exception 'não há calendário ligado para esse profissional'; end if;
end;
$$;

create or replace function public.pausar_calendario(p_profissional uuid, p_pausar boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;

  update public.calendarios
     set estado = case when p_pausar then 'pausado' else 'ligado' end
   where profissional_id = p_profissional
     and conta_id = c
     and estado in ('ligado', 'pausado', 'expirado');

  if not found then raise exception 'não há calendário para pausar'; end if;
end;
$$;

/**
 * Desligar.
 *
 * Apaga o segredo (a credencial não fica guardada depois de revogada), apaga
 * as ocupações (sem calendário não há bloqueio de calendário) e **não toca**
 * nos eventos que já foram para a agenda dela — ver a decisão 5.
 *
 * As pendências viram falha com o motivo escrito, porque nada sai com um token
 * que não existe mais e a tela precisa dizer isso.
 */
create or replace function public.desligar_calendario(p_profissional uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  cal uuid;
begin
  if c is null then raise exception 'sem conta'; end if;

  select id into cal from public.calendarios
   where profissional_id = p_profissional and conta_id = c;
  if cal is null then raise exception 'não há calendário ligado'; end if;

  delete from public.calendarios_segredo where calendario_id = cal;
  delete from public.ocupacoes_externas where calendario_id = cal;

  update public.espelhos_calendario
     set estado = 'falhou', erro = 'calendário desconectado'
   where calendario_id = cal and estado = 'pendente';

  update public.calendarios
     set estado = 'revogado', sync_token = null, sincronizado_em = null, erro = null
   where id = cal;
end;
$$;

-- ============================================== o segredo entra pelo servidor

create or replace function public.guardar_segredo_do_calendario(
  p_calendario uuid,
  p_refresh text,
  p_access text default null,
  p_expira timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(trim(p_refresh), '') = '' then
    raise exception 'sem refresh token não adianta guardar';
  end if;

  insert into public.calendarios_segredo (calendario_id, refresh_token, access_token, expira_em)
  values (p_calendario, p_refresh, p_access, p_expira)
  on conflict (calendario_id) do update
    set refresh_token = excluded.refresh_token,
        access_token  = excluded.access_token,
        expira_em     = excluded.expira_em,
        atualizado_em = now();

  update public.calendarios set estado = 'ligado', erro = null where id = p_calendario;
end;
$$;

-- ==================================================== a leitura (o que entra)

/**
 * Substitui a janela lida, inteira.
 *
 * Não é upsert evento a evento: é `delete` da janela + `insert` do que veio.
 * O motivo é o evento **apagado lá fora** — um upsert nunca aprende que algo
 * sumiu, e a hora ficaria bloqueada aqui para sempre por um compromisso que
 * não existe mais.
 *
 * Cada item do jsonb é lido por chave, e **só** as quatro chaves que
 * interessam. Se vier `titulo`, `descricao` ou `convidados`, some aqui — a
 * minimização é da função, não da educação de quem chama (decisão 2).
 */
create or replace function public.registrar_ocupacoes(
  p_calendario uuid,
  p_de date,
  p_ate date,
  p_eventos jsonb,
  p_sync_token text default null
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  cal record;
  de_ts timestamptz;
  ate_ts timestamptz;
  gravadas int := 0;
begin
  select * into cal from public.calendarios where id = p_calendario;
  if not found then raise exception 'calendário não encontrado'; end if;
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  de_ts  := ((p_de + time '00:00') at time zone 'America/Sao_Paulo');
  ate_ts := (((p_ate + 1) + time '00:00') at time zone 'America/Sao_Paulo');

  delete from public.ocupacoes_externas
   where calendario_id = p_calendario
     and inicio >= de_ts and inicio < ate_ts;

  insert into public.ocupacoes_externas
    (conta_id, profissional_id, calendario_id, evento_externo, inicio, fim, dia_inteiro)
  select cal.conta_id,
         cal.profissional_id,
         p_calendario,
         e->>'id',
         (e->>'inicio')::timestamptz,
         (e->>'fim')::timestamptz,
         coalesce((e->>'dia_inteiro')::boolean, false)
    from jsonb_array_elements(coalesce(p_eventos, '[]'::jsonb)) as e
   where e->>'id' is not null
     and e->>'inicio' is not null
     and e->>'fim' is not null
     and (e->>'fim')::timestamptz > (e->>'inicio')::timestamptz
     and (e->>'inicio')::timestamptz >= de_ts
     and (e->>'inicio')::timestamptz <  ate_ts
  on conflict (calendario_id, evento_externo) do update
    set inicio = excluded.inicio,
        fim = excluded.fim,
        dia_inteiro = excluded.dia_inteiro,
        visto_em = now();

  get diagnostics gravadas = row_count;

  update public.calendarios
     set sincronizado_em = now(),
         lido_de = least(coalesce(lido_de, p_de), p_de),
         lido_ate = greatest(coalesce(lido_ate, p_ate), p_ate),
         sync_token = coalesce(p_sync_token, sync_token),
         estado = case when estado = 'expirado' then 'ligado' else estado end,
         erro = null
   where id = p_calendario;

  return gravadas;
end;
$$;

create or replace function public.calendario_falhou(p_calendario uuid, p_erro text, p_expirou boolean default false)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.calendarios
     set erro = left(coalesce(p_erro, ''), 300),
         estado = case when p_expirou then 'expirado' else estado end
   where id = p_calendario;
$$;

-- ================================================== a escrita (o que sai)

/**
 * A sessão mudou; o espelho acompanha.
 *
 * Cuidado que já custou duas builds: **plpgsql não faz curto-circuito.**
 * `tg_op = 'UPDATE' and old.estado = 'x'` vira um SELECT só e estoura com
 * "record old is not assigned yet" no INSERT. Por isso os estados antigos são
 * lidos para escalares **dentro** do `if`, e não na condição.
 */
create or replace function public.sessao_espelha()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  quem_prof uuid;   -- o profissional da linha relevante (new ou old)
  cal record;
  tem_cal boolean := false;
  antes_inicio timestamptz := null;
  antes_fim    timestamptz := null;
  antes_estado text := null;
  mudou boolean := false;
  sai boolean;      -- este estado ocupa a hora lá fora?
  existente record;
  tem_espelho boolean := false;
begin
  -- Nada de `case when tg_op = 'DELETE' then old else new end`: plpgsql não faz
  -- curto-circuito e avaliaria os dois lados, estourando no registro que ainda
  -- não existe. Cada caminho é um `if` de verdade, do começo ao fim.
  if tg_op = 'DELETE' then
    quem_prof := old.profissional_id;
  else
    quem_prof := new.profissional_id;
  end if;

  select * into cal
    from public.calendarios
   where profissional_id = quem_prof
     and estado in ('ligado', 'pausado')
     and direcao in ('escrever', 'duas_vias');
  tem_cal := found;

  if not tem_cal then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  -- --------------------------------------------------------------- apagada
  if tg_op = 'DELETE' then
    select * into existente
      from public.espelhos_calendario
     where calendario_id = cal.id and sessao_id = old.id;
    tem_espelho := found;

    if not tem_espelho then
      return old;
    end if;

    if existente.evento_externo is null then
      -- Nunca chegou a existir lá fora: não há o que remover.
      delete from public.espelhos_calendario where id = existente.id;
    else
      update public.espelhos_calendario
         set acao = 'remover', estado = 'pendente', sessao_id = null,
             tentativas = 0, erro = null
       where id = existente.id;
    end if;

    return old;
  end if;

  -- Sessão importada é memória: não vai para a agenda de ninguém.
  if new.origem = 'importada' then
    return new;
  end if;

  -- Cancelada devolve a hora; realizada e falta consumiram a hora e ficam.
  sai := new.estado in ('prevista', 'confirmada', 'realizada', 'falta');

  if tg_op = 'UPDATE' then
    antes_inicio := old.inicio;
    antes_fim    := old.fim;
    antes_estado := old.estado;
    mudou := new.inicio is distinct from antes_inicio
          or new.fim    is distinct from antes_fim
          or new.estado is distinct from antes_estado;
    if not mudou then
      return new;
    end if;
  end if;

  select * into existente
    from public.espelhos_calendario
   where calendario_id = cal.id and sessao_id = new.id;
  tem_espelho := found;

  if sai then
    if not tem_espelho then
      insert into public.espelhos_calendario (conta_id, calendario_id, sessao_id, acao)
      values (cal.conta_id, cal.id, new.id, 'criar');
    else
      update public.espelhos_calendario
         set acao = case when evento_externo is null then 'criar' else 'atualizar' end,
             estado = 'pendente', tentativas = 0, erro = null
       where id = existente.id;
    end if;
  else
    if tem_espelho then
      if existente.evento_externo is null then
        delete from public.espelhos_calendario where id = existente.id;
      else
        update public.espelhos_calendario
           set acao = 'remover', estado = 'pendente', tentativas = 0, erro = null
         where id = existente.id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists sessao_espelha on public.sessoes;
create trigger sessao_espelha
  after insert or update or delete on public.sessoes
  for each row execute function public.sessao_espelha();

/**
 * Trocar o modo de título reescreve o que ainda está por vir.
 *
 * Se ela mudou de `completo` para `discreto`, foi porque alguém viu a tela
 * dela — deixar a semana que vem com os nomes lá seria não atender ao pedido.
 * O passado fica como foi: reescrever um ano de eventos é ruído, e apagar o
 * histórico da agenda dela é decisão dela, no Google.
 */
create or replace function public.modo_reescreve_o_futuro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  virou boolean := false;
begin
  virou := new.modo_titulo is distinct from old.modo_titulo;
  if not virou then return new; end if;

  update public.espelhos_calendario e
     set acao = 'atualizar', estado = 'pendente', tentativas = 0, erro = null
    from public.sessoes s
   where e.sessao_id = s.id
     and e.calendario_id = new.id
     and e.evento_externo is not null
     and s.inicio >= (public.hoje_sp() + time '00:00') at time zone 'America/Sao_Paulo';

  return new;
end;
$$;

drop trigger if exists modo_reescreve_o_futuro on public.calendarios;
create trigger modo_reescreve_o_futuro
  after update on public.calendarios
  for each row execute function public.modo_reescreve_o_futuro();

-- ==================================================== a fila dos espelhos

create or replace function public.espelhos_a_enviar(p_limite int default 50)
returns table (
  id                 uuid,
  acao               text,
  calendario_externo text,
  evento_externo     text,
  titulo             text,
  inicio             timestamptz,
  fim                timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select e.id,
         e.acao,
         coalesce(cal.calendario_externo, 'primary'),
         e.evento_externo,
         case when s.id is null then null
              else public.titulo_do_evento(cal.modo_titulo, p.nome) end,
         s.inicio,
         s.fim
    from public.espelhos_calendario e
    join public.calendarios cal on cal.id = e.calendario_id
    left join public.sessoes s on s.id = e.sessao_id
    left join public.pacientes p on p.id = s.paciente_id
   where e.estado = 'pendente'
     and e.tentativas < 5
     and cal.estado = 'ligado'
     and cal.direcao in ('escrever', 'duas_vias')
   order by e.criado_em
   limit p_limite;
$$;

create or replace function public.marcar_espelho_feito(p_espelho uuid, p_evento text default null)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.espelhos_calendario
     set estado = case when acao = 'remover' then 'removida' else 'espelhada' end,
         evento_externo = case when acao = 'remover' then evento_externo
                               else coalesce(p_evento, evento_externo) end,
         enviado_em = now(),
         erro = null
   where id = p_espelho and estado = 'pendente';
$$;

create or replace function public.marcar_espelho_falhou(p_espelho uuid, p_erro text)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.espelhos_calendario
     set tentativas = tentativas + 1,
         erro = left(coalesce(p_erro, ''), 300),
         estado = case when tentativas + 1 >= 5 then 'falhou' else 'pendente' end
   where id = p_espelho;
$$;

-- ======================================================= o painel da tela

create or replace function public.calendario_do_profissional(p_profissional uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  cal record;
  prof uuid := p_profissional;
begin
  if prof is null then
    select id into prof from public.profissionais order by criado_em limit 1;
  end if;
  if prof is null then return jsonb_build_object('ligado', false); end if;

  select * into cal from public.calendarios where profissional_id = prof;

  if not found then
    return jsonb_build_object('ligado', false, 'profissional_id', prof);
  end if;

  return jsonb_build_object(
    'ligado', cal.estado <> 'revogado',
    'profissional_id', prof,
    'calendario_id', cal.id,
    'estado', cal.estado,
    'direcao', cal.direcao,
    'modo_titulo', cal.modo_titulo,
    'email_externo', cal.email_externo,
    'sincronizado_em', cal.sincronizado_em,
    'lido_ate', cal.lido_ate,
    'erro', cal.erro,
    'ocupacoes', (select count(*) from public.ocupacoes_externas o
                   where o.calendario_id = cal.id and o.fim >= now()),
    'pendentes', (select count(*) from public.espelhos_calendario e
                   where e.calendario_id = cal.id and e.estado = 'pendente'),
    'falhados', (select count(*) from public.espelhos_calendario e
                  where e.calendario_id = cal.id and e.estado = 'falhou'),
    'espelhados', (select count(*) from public.espelhos_calendario e
                    where e.calendario_id = cal.id and e.estado = 'espelhada')
  );
end;
$$;

/**
 * Os calendários que precisam de leitura, para o cron.
 *
 * Sem `conta_atual()`: percorre todas as contas, e por isso só service_role.
 */
create or replace function public.calendarios_a_ler(p_limite int default 50)
returns table (
  id                 uuid,
  calendario_externo text,
  sync_token         text,
  refresh_token      text,
  lido_ate           date
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, coalesce(c.calendario_externo, 'primary'), c.sync_token,
         s.refresh_token, c.lido_ate
    from public.calendarios c
    join public.calendarios_segredo s on s.calendario_id = c.id
   where c.estado in ('ligado', 'expirado')
     and c.direcao in ('ler', 'duas_vias')
   order by coalesce(c.sincronizado_em, c.criado_em)
   limit p_limite;
$$;

-- ============================================= o histórico que veio de fora

/**
 * Trazer o que já aconteceu.
 *
 * Cada linha é `{paciente_id, inicio, fim, estado, valor}`. Recusa data no
 * futuro (histórico é passado, e sessão futura se cria pela agenda), recusa
 * estado que não seja desfecho, e pula o que já existe naquele instante para
 * aquele paciente — colar a mesma planilha duas vezes não duplica o passado.
 *
 * O `valor` entra porque a linha do tempo do paciente merece dizer quanto
 * custava a sessão dele em 2024. Ele **não** vira dinheiro: ver decisão 6 e o
 * gatilho logo abaixo.
 */
create or replace function public.importar_historico(p_linhas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  prof uuid;
  linha jsonb;
  n int := 0;
  n_pulou int := 0;
  erros jsonb := '[]'::jsonb;
  i int := 0;
  pac uuid;
  ini timestamptz;
  f timestamptz;
  est text;
  val numeric;
begin
  if c is null then raise exception 'sem conta'; end if;

  for linha in select * from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) loop
    i := i + 1;
    begin
      pac := (linha->>'paciente_id')::uuid;
      ini := (linha->>'inicio')::timestamptz;
      f   := coalesce((linha->>'fim')::timestamptz, ini + interval '50 minutes');
      est := coalesce(linha->>'estado', 'realizada');
      val := coalesce((linha->>'valor')::numeric, 0);

      select p.profissional_id into prof
        from public.pacientes pa
        join public.profissionais p on p.id = pa.profissional_id
       where pa.id = pac and pa.conta_id = c;

      if prof is null then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'paciente não é desta conta');
        continue;
      end if;

      if est not in ('realizada', 'falta', 'cancelada_cedo', 'cancelada_tarde') then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'estado não é um desfecho');
        continue;
      end if;

      if ini >= now() then
        erros := erros || jsonb_build_object('linha', i, 'motivo', 'histórico é passado');
        continue;
      end if;

      if exists (
        select 1 from public.sessoes s
         where s.paciente_id = pac and s.inicio = ini
      ) then
        n_pulou := n_pulou + 1;
        continue;
      end if;

      insert into public.sessoes
        (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
      values (c, prof, pac, ini, f, 'importada', est, val);

      n := n + 1;
    exception when others then
      erros := erros || jsonb_build_object('linha', i, 'motivo', 'não consegui ler esta linha');
    end;
  end loop;

  return jsonb_build_object('importadas', n, 'repetidas', n_pulou, 'erros', erros);
end;
$$;

/**
 * Histórico importado não vira dinheiro.
 *
 * Isto é gatilho e não convenção porque a convenção some com quem a escreveu.
 * Uma cobrança apontando para sessão importada colocaria dinheiro de outro
 * sistema no caixa deste — e, se paga, criaria um recibo de Receita Saúde para
 * um pagamento que a Receita já viu por outro caminho. Multa de R$ 100 por
 * recibo, do lado errado.
 */
create or replace function public.importada_nao_vira_dinheiro()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  org text := null;
begin
  if new.sessao_id is null then return new; end if;

  select s.origem into org from public.sessoes s where s.id = new.sessao_id;

  if org = 'importada' then
    raise exception 'sessão importada é memória, não dinheiro: ela não gera cobrança nem consumo de pacote';
  end if;

  return new;
end;
$$;

drop trigger if exists cobranca_nao_e_de_importada on public.cobrancas;
create trigger cobranca_nao_e_de_importada
  before insert on public.cobrancas
  for each row execute function public.importada_nao_vira_dinheiro();

drop trigger if exists consumo_nao_e_de_importada on public.pacote_consumos;
create trigger consumo_nao_e_de_importada
  before insert on public.pacote_consumos
  for each row execute function public.importada_nao_vira_dinheiro();

-- ================================ o financeiro não conta o que veio de fora

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
     and s.origem <> 'importada'
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

-- ================================================================ RLS

alter table public.calendarios enable row level security;
alter table public.calendarios_segredo enable row level security;
alter table public.ocupacoes_externas enable row level security;
alter table public.espelhos_calendario enable row level security;

-- Leitura apenas, em toda a família. Ligar, ajustar, pausar e desligar passam
-- por função `definer` que confere a conta; escrever direto pelo PostgREST não
-- é caminho para nenhuma das quatro tabelas. Uma política de update em
-- `calendarios` deixaria qualquer sessão logada trocar o próprio
-- `modo_titulo` para `completo` — que é o oposto do que a decisão 1 protege.
drop policy if exists "calendarios da conta: ler" on public.calendarios;
create policy "calendarios da conta: ler" on public.calendarios
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "ocupacoes da conta: ler" on public.ocupacoes_externas;
create policy "ocupacoes da conta: ler" on public.ocupacoes_externas
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "espelhos da conta: ler" on public.espelhos_calendario;
create policy "espelhos da conta: ler" on public.espelhos_calendario
  for select to authenticated using (conta_id = (select public.conta_atual()));

-- `calendarios_segredo` fica **sem nenhuma política**, de propósito. Ver o
-- comentário da tabela.

-- ============================================================ os privilégios

revoke execute on function public.iniciais_do_nome(text) from public, anon;
revoke execute on function public.titulo_do_evento(text, text) from public, anon;
revoke execute on function public.ligar_calendario(uuid, text, text) from public, anon;
revoke execute on function public.ajustar_calendario(uuid, text, text) from public, anon;
revoke execute on function public.pausar_calendario(uuid, boolean) from public, anon;
revoke execute on function public.desligar_calendario(uuid) from public, anon;
revoke execute on function public.guardar_segredo_do_calendario(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.registrar_ocupacoes(uuid, date, date, jsonb, text) from public, anon, authenticated;
revoke execute on function public.calendario_falhou(uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public.calendarios_a_ler(int) from public, anon, authenticated;
revoke execute on function public.espelhos_a_enviar(int) from public, anon;
revoke execute on function public.marcar_espelho_feito(uuid, text) from public, anon;
revoke execute on function public.marcar_espelho_falhou(uuid, text) from public, anon;
revoke execute on function public.calendario_do_profissional(uuid) from public, anon;
revoke execute on function public.importar_historico(jsonb) from public, anon;

grant execute on function public.iniciais_do_nome(text) to authenticated;
grant execute on function public.titulo_do_evento(text, text) to authenticated;
grant execute on function public.ligar_calendario(uuid, text, text) to authenticated;
grant execute on function public.ajustar_calendario(uuid, text, text) to authenticated;
grant execute on function public.pausar_calendario(uuid, boolean) to authenticated;
grant execute on function public.desligar_calendario(uuid) to authenticated;
grant execute on function public.calendario_do_profissional(uuid) to authenticated;
grant execute on function public.importar_historico(jsonb) to authenticated;

grant execute on function public.guardar_segredo_do_calendario(uuid, text, text, timestamptz) to service_role;
grant execute on function public.registrar_ocupacoes(uuid, date, date, jsonb, text) to service_role;
grant execute on function public.calendario_falhou(uuid, text, boolean) to service_role;
grant execute on function public.calendarios_a_ler(int) to service_role;
grant execute on function public.espelhos_a_enviar(int) to service_role;
grant execute on function public.marcar_espelho_feito(uuid, text) to service_role;
grant execute on function public.marcar_espelho_falhou(uuid, text) to service_role;

-- ================================================================ comentários

comment on function public.vaga_esta_livre(uuid, timestamptz, timestamptz, uuid) is
  'Tres fontes: sessoes, excecoes_agenda e ocupacoes_externas. Calendario defasado bloqueia; so revogado deixa de bloquear (porque desligar apaga as ocupacoes).';
comment on function public.titulo_do_evento(text, text) is
  'O que sai para o provedor externo. Nasce discreto: a lista de quem tem hora marcada e a lista de quem faz terapia.';
comment on function public.importar_historico(jsonb) is
  'Sessoes que ja aconteceram, com origem importada. Memoria, nao dinheiro: nao gera cobranca, nao entra no realizado do mes.';
comment on table public.espelhos_calendario is
  'Fila do que precisa ir para a agenda externa. sessao_id e ON DELETE SET NULL de proposito: o espelho sobrevive a sessao para conseguir remover o evento la fora.';
