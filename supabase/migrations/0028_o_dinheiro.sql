-- 0028 · B16 — o dinheiro.
--
-- O doc 13 já escolheu o provedor (Asaas, por aceitar pessoa física — psicologia
-- é profissão regulamentada e não pode ser MEI). Esta migração **não** implementa
-- o Asaas: implementa o domínio onde ele vai encaixar, e o caminho que funciona
-- antes dele existir.
--
-- ## A decisão de sequência
--
-- Antes de qualquer intermediário, a cobrança vira o **PIX da chave dela**. O
-- dinheiro vai direto para a conta dela: sem tarifa, sem KYC, sem subconta, sem
-- esperar avaliação regulatória. E não é gambiarra — é o "caminho alternativo"
-- que o doc 10 exige que exista **sempre**, feito bem em vez de feito de
-- qualquer jeito. Se um dia a conta dela travar no provedor (é a queixa mais
-- comum do Reclame Aqui sobre o Asaas), isto continua de pé.
--
-- Enquanto o dinheiro não passa por nós, nada do peso regulatório do doc 10
-- existe: nem conta nominal por recebedora, nem KYC herdado, nem MED em quatro
-- dias, nem disputa sobrando para o suporte.
--
-- ## O que este arquivo prepara para quando o Asaas entrar
--
--  1. **O webhook não é a fonte da verdade.** O do Asaas é "at least once", sem
--     assinatura HMAC, e a fila dele pausa depois de 15 falhas com os eventos
--     apagados em 14 dias (doc 10). Então: caixa de entrada com dedupe por id do
--     evento, **e** uma varredura diária que confere estado por conta própria.
--     Um pagamento que o webhook perdeu tem de ser encontrado de qualquer forma.
--  2. **Idempotência é nossa.** A API do Asaas não tem chave de idempotência
--     para POST. `chave_idem` na cobrança do provedor faz esse papel deste lado.
--  3. **A chave de API da subconta só é devolvida uma vez.** Ela nunca fica em
--     coluna de tabela: vai para o Vault do Supabase, e o que a tabela guarda é
--     o **nome do segredo**, não o segredo.

-- ------------------------------------------------------------ o recebimento

alter table public.contas
  add column if not exists pix_chave text,
  add column if not exists pix_nome text,
  add column if not exists pix_cidade text,
  add column if not exists provedor_pagamento text not null default 'nenhum'
    check (provedor_pagamento in ('nenhum', 'asaas')),
  add column if not exists provedor_conta_id text,
  -- Nome do segredo no Vault. **Nunca** a chave.
  add column if not exists provedor_segredo text,
  add column if not exists provedor_estado text not null default 'sem_conta'
    check (provedor_estado in ('sem_conta', 'em_analise', 'ativa', 'bloqueada'));

comment on column public.contas.pix_chave is
  'Chave PIX da propria psicologa. O dinheiro nao passa por nos.';
comment on column public.contas.provedor_segredo is
  'Nome do segredo no Vault. A chave de API nunca fica em coluna.';

-- --------------------------------------------------------- na cobrança

alter table public.cobrancas
  add column if not exists txid text,
  add column if not exists pix_copia_cola text,
  add column if not exists provedor text
    check (provedor is null or provedor in ('pix_direto', 'asaas')),
  add column if not exists provedor_cobranca_id text,
  add column if not exists link_pagamento text,
  add column if not exists taxa numeric(12,2),
  add column if not exists confirmado_por text
    check (confirmado_por is null or confirmado_por in ('ela', 'provedor'));

create unique index if not exists cobrancas_do_provedor
  on public.cobrancas (provedor, provedor_cobranca_id)
  where provedor_cobranca_id is not null;

comment on column public.cobrancas.confirmado_por is
  'Quem disse que foi pago. "ela" no PIX direto; "provedor" quando o webhook confirmou.';

-- --------------------------------------------------------------- o txid

/**
 * O identificador que vai no extrato dela.
 *
 * Curto, sem ambiguidade visual, e derivado do id da cobrança — assim o PIX que
 * cai na conta dela pode ser casado com a sessão sem que ninguém anote nada.
 * `SES` na frente porque, no meio de trinta linhas de extrato, ela precisa
 * reconhecer o que é do sistema.
 */
create or replace function public.txid_da_cobranca(p_cobranca uuid)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select 'SES' || upper(replace(p_cobranca::text, '-', ''));
$$;

-- --------------------------------------------- a caixa de entrada do provedor

create table if not exists public.eventos_pagamento (
  id          uuid primary key default gen_random_uuid(),
  provedor    text not null,
  evento_id   text not null,
  tipo        text not null,
  cobranca_id uuid references public.cobrancas (id) on delete set null,
  conta_id    uuid references public.contas (id) on delete cascade,
  corpo       jsonb not null default '{}'::jsonb,
  resultado   text,
  recebido_em timestamptz not null default now()
);

-- A dedupe. O webhook do Asaas é "at least once" e não assina nada; sem isto,
-- uma reentrega marcaria a mesma cobrança como paga duas vezes.
create unique index if not exists eventos_pagamento_unico
  on public.eventos_pagamento (provedor, evento_id);
create index if not exists eventos_pagamento_conta
  on public.eventos_pagamento (conta_id, recebido_em desc);

-- ------------------------------------------------------------- a conciliação

/**
 * Registra o pagamento e concilia a cobrança.
 *
 * Uma porta só, chamada tanto pelo webhook quanto pela varredura diária — e é
 * por isso que ela é idempotente por `evento_id`. Duas fontes contando a mesma
 * coisa é o desenho, não um acidente: o doc 10 é explícito em não depender do
 * webhook, porque a fila dele pausa e os eventos somem em 14 dias.
 *
 * Devolve o que aconteceu, em texto, para o log e para os testes.
 */
create or replace function public.conciliar_pagamento(
  p_provedor text,
  p_evento_id text,
  p_tipo text,
  p_cobranca_provedor_id text,
  p_corpo jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  novo uuid;
  cob record;
begin
  select * into cob
    from public.cobrancas
   where provedor = p_provedor and provedor_cobranca_id = p_cobranca_provedor_id;

  insert into public.eventos_pagamento
    (provedor, evento_id, tipo, cobranca_id, conta_id, corpo)
  values
    (p_provedor, p_evento_id, p_tipo, cob.id, cob.conta_id, coalesce(p_corpo, '{}'::jsonb))
  on conflict (provedor, evento_id) do nothing
  returning id into novo;

  if novo is null then
    return jsonb_build_object('estado', 'repetido');
  end if;

  if cob.id is null then
    update public.eventos_pagamento
       set resultado = 'cobrança não encontrada'
     where id = novo;
    return jsonb_build_object('estado', 'sem_cobranca');
  end if;

  -- Confirmado. Marcar de novo não é erro: é a varredura diária encontrando o
  -- que o webhook já tinha resolvido.
  if p_tipo in ('PAYMENT_RECEIVED', 'PAYMENT_CONFIRMED') then
    if cob.estado = 'paga' then
      update public.eventos_pagamento set resultado = 'já estava paga' where id = novo;
      return jsonb_build_object('estado', 'ja_paga', 'cobranca', cob.id);
    end if;

    if cob.estado <> 'aberta' then
      -- Perdoada ou cancelada e o dinheiro caiu mesmo assim. Não sobrescrever:
      -- é conversa entre duas pessoas, não decisão de sistema. Fica registrado.
      update public.eventos_pagamento
         set resultado = 'pagamento chegou numa cobrança ' || cob.estado
       where id = novo;
      return jsonb_build_object('estado', 'fora_de_estado', 'cobranca', cob.id);
    end if;

    update public.cobrancas
       set estado = 'paga', paga_em = now(), confirmado_por = 'provedor'
     where id = cob.id;

    update public.eventos_pagamento set resultado = 'paga' where id = novo;
    return jsonb_build_object('estado', 'paga', 'cobranca', cob.id);
  end if;

  -- Estorno, devolução, chargeback: a cobrança volta a existir. Não se apaga o
  -- histórico — ela reabre, e a psicóloga vê.
  if p_tipo in ('PAYMENT_REFUNDED', 'PAYMENT_CHARGEBACK_REQUESTED', 'PAYMENT_DELETED') then
    if cob.estado = 'paga' then
      update public.cobrancas
         set estado = 'aberta', paga_em = null, confirmado_por = null
       where id = cob.id;
    end if;
    update public.eventos_pagamento set resultado = 'reaberta' where id = novo;
    return jsonb_build_object('estado', 'reaberta', 'cobranca', cob.id);
  end if;

  update public.eventos_pagamento set resultado = 'ignorado' where id = novo;
  return jsonb_build_object('estado', 'ignorado', 'tipo', p_tipo);
end;
$$;

/**
 * O que a varredura diária precisa conferir no provedor.
 *
 * Cobranças abertas, com id no provedor, criadas nos últimos 60 dias. É a rede
 * embaixo do webhook: se a fila dele pausou (15 falhas) ou o evento expirou (14
 * dias), o pagamento aparece por aqui.
 */
create or replace function public.cobrancas_a_conciliar(p_limite int default 200)
returns table (
  cobranca_id uuid,
  conta_id uuid,
  provedor text,
  provedor_cobranca_id text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.conta_id, c.provedor, c.provedor_cobranca_id
    from public.cobrancas c
   where c.estado = 'aberta'
     and c.provedor_cobranca_id is not null
     and c.criado_em > now() - interval '60 days'
   order by c.criado_em
   limit p_limite;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.eventos_pagamento enable row level security;

drop policy if exists "eventos de pagamento da conta: ler" on public.eventos_pagamento;
create policy "eventos de pagamento da conta: ler" on public.eventos_pagamento
  for select to authenticated
  using (conta_id is not null and conta_id = public.conta_atual());

-- Escrever é do worker. Ninguém marca o próprio pagamento como recebido pelo
-- provedor — para isso existe `marcar_cobranca_paga`, que registra "ela".

revoke execute on function public.conciliar_pagamento(text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.cobrancas_a_conciliar(int) from public, anon, authenticated;
grant execute on function public.conciliar_pagamento(text, text, text, text, jsonb) to service_role;
grant execute on function public.cobrancas_a_conciliar(int) to service_role;

revoke execute on function public.txid_da_cobranca(uuid) from public, anon;
grant  execute on function public.txid_da_cobranca(uuid) to authenticated, service_role;

comment on table public.eventos_pagamento is
  'Caixa de entrada do provedor. Unico por (provedor, evento_id): reentrega nao paga duas vezes.';
