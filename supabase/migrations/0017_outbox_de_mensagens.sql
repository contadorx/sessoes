-- 0017 · O outbox.
--
-- Nenhum envio sai de dentro de uma regra de negócio. Tudo passa por aqui, e é
-- isto que torna "trocar de provedor" uma edição de um arquivo — a mitigação
-- real do risco R4 (template reprovado, preço da Meta mudando, BSP caindo).
--
-- Quatro regras, e as quatro moram no banco, não na lembrança de quem chama:
--
--  1. **Idempotência por chave, não por tentativa.** `chave_idem` é evento +
--     destinatário. Um retry que estourou timeout mas na verdade entregou não
--     pode mandar a oferta duas vezes — oferta duplicada quebra a garantia de
--     "uma oferta viva por vaga" da B7, que é onde mora a confiança.
--  2. **A reserva é atômica.** O worker reivindica com `for update skip locked`
--     antes de falar com o provedor. Dois workers simultâneos nunca pegam a
--     mesma mensagem.
--  3. **A janela de silêncio é invariante de tabela.** Não é o chamador que
--     lembra de respeitá-la: um gatilho empurra qualquer envio que caia dentro
--     do silêncio para o fim dele. Vale para a função e vale para um PATCH
--     direto no PostgREST.
--  4. **O destino é retrato do cadastro, e quem tira o retrato é o banco.** O
--     mesmo gatilho recalcula canal e destino a partir do paciente e descarta o
--     que veio na linha. Ninguém enfileira mensagem para um número inventado.
--
-- É a mesma postura da 0010: o que não pode ser burlado não pode depender de
-- quem chama estar bem-intencionado.

create table if not exists public.mensagens (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  -- Nula só depois: o apagamento da LGPD (B13) solta o vínculo sem perder a
  -- trilha de que houve envio. Na inserção o gatilho exige o paciente.
  paciente_id   uuid references public.pacientes (id) on delete set null,

  canal         text not null check (canal in ('whatsapp', 'sms', 'email')),

  -- A lista fechada de famílias. Template novo é migração, não string solta no
  -- código do app — é o que impede alguém mandar texto arbitrário com a
  -- infraestrutura da conta.
  template      text not null check (template in (
                  'oferta_de_vaga',
                  'encaixe_confirmado',
                  'lembrete_de_sessao',
                  'aviso_de_desmarque')),
  params        jsonb not null default '{}'::jsonb,

  -- Retrato do contato no momento do enfileiramento.
  destino       text not null,

  -- Evento + destinatário. É o que impede mandar duas vezes.
  chave_idem    text not null,

  estado        text not null default 'pendente' check (estado in (
                  'pendente', 'enviando', 'enviada', 'entregue', 'falhou', 'cancelada')),

  tentativas    smallint not null default 0 check (tentativas >= 0),
  agendada_para timestamptz not null default now(),

  provedor        text,
  provedor_msg_id text,
  erro            text,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists mensagens_idem on public.mensagens (chave_idem);
create index if not exists mensagens_conta on public.mensagens (conta_id, criado_em desc);
create index if not exists mensagens_paciente on public.mensagens (paciente_id);
create index if not exists mensagens_a_enviar
  on public.mensagens (agendada_para)
  where estado = 'pendente';

drop trigger if exists mensagens_atualizado_em on public.mensagens;
create trigger mensagens_atualizado_em before update on public.mensagens
  for each row execute function public.tocar_atualizado_em();

-- ------------------------------------------------- o retrato e o silêncio

/**
 * Invariante de inserção. Roda para todo mundo: a função abaixo, o worker com
 * service_role, e um PATCH direto de quem estiver logado.
 *
 * O que a linha diz sobre conta, canal, destino e estado de envio é ignorado —
 * tudo é recalculado a partir do cadastro do paciente e do relógio do servidor.
 */
create or replace function public.mensagem_confere_retrato()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
begin
  if new.paciente_id is null then
    raise exception 'mensagem precisa de paciente';
  end if;

  select p.id, p.conta_id, p.nome, p.telefone, p.email, p.msg_canal, p.msg_modo
    into pac
    from public.pacientes p
   where p.id = new.paciente_id;

  if not found then raise exception 'paciente não encontrado'; end if;

  -- Quem pediu para não ser avisado não entra na fila. A decisão é dele, e não
  -- se contorna por conveniência de quem está enfileirando.
  if pac.msg_canal = 'nao_avisar' then
    raise exception 'este paciente pediu para não ser avisado';
  end if;

  new.conta_id := pac.conta_id;
  new.canal := pac.msg_canal;
  new.destino := case pac.msg_canal when 'email' then pac.email else pac.telefone end;

  if new.destino is null or new.destino = '' then
    raise exception 'paciente sem % para avisar',
      case pac.msg_canal when 'email' then 'e-mail' else 'telefone' end;
  end if;

  -- O modo de discrição (D3) viaja com a mensagem: quem renderiza não precisa
  -- voltar ao cadastro, e editar o cadastro depois não muda o que já saiu.
  new.params := coalesce(new.params, '{}'::jsonb)
                || jsonb_build_object('modo', pac.msg_modo, 'nome', pac.nome);

  -- Nunca no passado, e nunca dentro da janela de silêncio da conta.
  new.agendada_para := greatest(coalesce(new.agendada_para, now()), now());
  new.agendada_para := public.proximo_envio(pac.conta_id, new.agendada_para);

  -- Estado de envio é do worker. Ninguém nasce entregue.
  new.estado := 'pendente';
  new.tentativas := 0;
  new.provedor := null;
  new.provedor_msg_id := null;
  new.erro := null;

  return new;
end;
$$;

drop trigger if exists mensagens_retrato on public.mensagens;
create trigger mensagens_retrato before insert on public.mensagens
  for each row execute function public.mensagem_confere_retrato();

-- ---------------------------------------------------------------- enfileirar

/**
 * Põe uma mensagem na fila de envio.
 *
 * Devolve o id, ou null quando a chave já existe — repetir a chamada é seguro e
 * é exatamente o que um retry vai fazer.
 *
 * A função é conveniência: canal, destino e horário quem decide é o gatilho.
 */
create or replace function public.enfileirar_mensagem(
  p_paciente uuid,
  p_template text,
  p_chave text,
  p_params jsonb default '{}'::jsonb,
  p_agendar_para timestamptz default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  novo uuid;
begin
  select p.conta_id, p.msg_canal, p.telefone, p.email
    into pac
    from public.pacientes p
   where p.id = p_paciente;

  if not found then raise exception 'paciente não encontrado'; end if;

  -- Silêncio pedido pelo paciente não é erro de quem chama: a cascata segue
  -- para o próximo da fila em vez de estourar.
  if pac.msg_canal = 'nao_avisar' then
    return null;
  end if;

  insert into public.mensagens (
    conta_id, paciente_id, canal, template, params, destino, chave_idem, agendada_para
  )
  values (
    pac.conta_id, p_paciente, pac.msg_canal, p_template, coalesce(p_params, '{}'::jsonb),
    coalesce(pac.telefone, pac.email, 'x'), p_chave, coalesce(p_agendar_para, now())
  )
  on conflict (chave_idem) do nothing
  returning id into novo;

  return novo;
end;
$$;

-- ---------------------------------------------------------------- o worker

/**
 * Reivindica até `p_limite` mensagens prontas para sair.
 *
 * `for update skip locked` é o que permite mais de um worker sem coordenação:
 * cada um pega um lote diferente. A mensagem sai de `pendente` antes de o
 * provedor ser chamado — se o processo morrer no meio, ela fica em `enviando` e
 * a varredura de presos (abaixo) a devolve para a fila.
 */
create or replace function public.reservar_mensagens(p_limite int default 20)
returns setof public.mensagens
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
  update public.mensagens m
     set estado = 'enviando', tentativas = m.tentativas + 1
   where m.id in (
     select x.id from public.mensagens x
      where x.estado = 'pendente'
        and x.agendada_para <= now()
      order by x.agendada_para
      for update skip locked
      limit p_limite
   )
  returning m.*;
end;
$$;

create or replace function public.marcar_enviada(
  p_mensagem uuid,
  p_provedor text,
  p_provedor_msg_id text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.mensagens
     set estado = 'enviada', provedor = p_provedor,
         provedor_msg_id = p_provedor_msg_id, erro = null
   where id = p_mensagem;
$$;

/** Falhou: volta para a fila com espera crescente, ou desiste depois de 5. */
create or replace function public.marcar_falha(p_mensagem uuid, p_erro text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare m record; novo_estado text;
begin
  select * into m from public.mensagens where id = p_mensagem;
  if not found then raise exception 'mensagem não encontrada'; end if;

  if m.tentativas >= 5 then
    novo_estado := 'falhou';
    update public.mensagens
       set estado = 'falhou', erro = left(p_erro, 500)
     where id = p_mensagem;
  else
    novo_estado := 'pendente';
    update public.mensagens
       set estado = 'pendente',
           erro = left(p_erro, 500),
           -- 1, 4, 9, 16 minutos: cresce sem virar espera eterna.
           agendada_para = now() + make_interval(mins => (m.tentativas * m.tentativas))
     where id = p_mensagem;
  end if;

  return novo_estado;
end;
$$;

/** Devolve para a fila o que ficou preso em `enviando` (processo morto no meio). */
create or replace function public.destravar_mensagens(p_minutos int default 10)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare n int;
begin
  update public.mensagens
     set estado = 'pendente'
   where estado = 'enviando'
     and atualizado_em < now() - make_interval(mins => p_minutos);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------- a fila usa

/**
 * A cascata passa a enfileirar de verdade. A chave é a própria oferta: uma
 * oferta, uma mensagem, para sempre — mesmo que a função seja chamada de novo.
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
  select s.id, s.conta_id, s.inicio, s.valor, c.oferta_timeout_min
    into v
    from public.sessoes s
    join public.contas c on c.id = s.conta_id
   where s.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  if exists (select 1 from public.ofertas o
              where o.sessao_id = p_sessao and o.estado = 'enviada') then
    return null;
  end if;

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

  -- E agora a mensagem existe de verdade.
  perform public.enfileirar_mensagem(
    proximo.paciente_id,
    'oferta_de_vaga',
    'oferta:' || nova::text,
    jsonb_build_object(
      'oferta_id', nova,
      'inicio', v.inicio,
      'expira_em', quando + make_interval(mins => v.oferta_timeout_min)
    ),
    quando
  );

  return nova;
end;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.mensagens enable row level security;

drop policy if exists "mensagens da conta: ler" on public.mensagens;
create policy "mensagens da conta: ler" on public.mensagens for select to authenticated
  using (conta_id = public.conta_atual());

-- Inserir é da conta — mas o gatilho acima já reescreveu tudo que importa, então
-- o que passa por aqui é sempre um retrato honesto do cadastro.
drop policy if exists "mensagens da conta: enfileirar" on public.mensagens;
create policy "mensagens da conta: enfileirar" on public.mensagens for insert to authenticated
  with check (conta_id = public.conta_atual());

-- Não há política de update nem de delete: estado de envio é do worker
-- (service_role), e trilha de mensagem não se apaga pelo app.

grant execute on function public.enfileirar_mensagem(uuid, text, text, jsonb, timestamptz) to authenticated;
revoke execute on function public.reservar_mensagens(int) from anon, authenticated;
revoke execute on function public.marcar_enviada(uuid, text, text) from anon, authenticated;
revoke execute on function public.marcar_falha(uuid, text) from anon, authenticated;
revoke execute on function public.destravar_mensagens(int) from anon, authenticated;
revoke execute on function public.mensagem_confere_retrato() from anon, authenticated;

comment on table public.mensagens is
  'Outbox. Idempotencia por chave_idem; reserva atomica pelo worker; destino e horario sao invariantes de gatilho.';
