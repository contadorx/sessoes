-- 0021 · B10 — a resposta que chega de fora.
--
-- Até aqui a fila só andava porque alguém clicava numa tela. A partir daqui ela
-- anda porque uma pessoa respondeu SIM no celular dela, às onze e meia da noite,
-- sem que ninguém estivesse olhando. É o marco do produto.
--
-- Quatro coisas que este arquivo resolve, e todas são de banco porque nenhuma
-- pode depender de o webhook ser chamado só uma vez:
--
--  1. **A Meta reentrega.** Timeout, 500, instabilidade — a mesma mensagem
--     chega duas, cinco vezes. `provedor_msg_id` é único: a segunda chegada
--     encontra a porta fechada e sai sem fazer nada. Sem isso, um SIM
--     reentregue viraria dois encaixes, ou um erro na cara de quem respondeu.
--  2. **O texto humano não é um enum.** "sim", "Sim!", "SIM", "quero",
--     "pode ser", "1" — todos querem dizer a mesma coisa. E o que não dá para
--     entender é registrado como não entendido, nunca chutado: chutar aqui
--     marca a agenda de alguém errado.
--  3. **O opt-out é imediato e vale em todo lugar.** Quem pede para parar está
--     falando do próprio celular, não da conta de uma psicóloga específica.
--     Para em todas, e o que já estava na fila de envio é cancelado.
--  4. **Quem responde não escolhe a que oferta responde.** O vínculo é feito
--     aqui, pela oferta viva mais recente daquele telefone. O cliente não manda
--     `oferta_id` nenhum.

-- A trilha da fila ganha um evento: alguém respondeu algo que o sistema não
-- entendeu. É informação de produto, não ruído — se este evento for comum, o
-- texto do template está pedindo mal.
alter table public.eventos_fila drop constraint if exists eventos_fila_tipo_check;
alter table public.eventos_fila add constraint eventos_fila_tipo_check
  check (tipo in (
    'vaga_aberta', 'oferta_enviada', 'oferta_aceita',
    'oferta_recusada', 'oferta_expirada',
    'vaga_preenchida', 'vaga_sem_takers',
    'resposta_nao_entendida'));

-- --------------------------------------------------------------- a chegada

create table if not exists public.mensagens_recebidas (
  id          uuid primary key default gen_random_uuid(),

  provedor        text not null,
  provedor_msg_id text not null,
  de              text not null,
  texto           text not null,

  intencao    text not null check (intencao in
                ('aceitar', 'recusar', 'parar', 'indefinida')),

  -- Preenchidos quando dá para resolver. Nulos são informação: significam
  -- "chegou uma resposta e não achamos de quem" — e isso precisa ser visível.
  conta_id    uuid references public.contas (id) on delete set null,
  paciente_id uuid references public.pacientes (id) on delete set null,
  oferta_id   uuid references public.ofertas (id) on delete set null,

  resultado   text,
  recebida_em timestamptz not null default now()
);

create unique index if not exists recebidas_do_provedor
  on public.mensagens_recebidas (provedor, provedor_msg_id);
create index if not exists recebidas_da_conta
  on public.mensagens_recebidas (conta_id, recebida_em desc);
create index if not exists recebidas_orfas
  on public.mensagens_recebidas (recebida_em desc) where conta_id is null;

-- ------------------------------------------------------------ só os dígitos

/**
 * "+55 (11) 90000-0001" e "5511900000001" são o mesmo telefone.
 *
 * O cadastro guarda o que a psicóloga digitou; o provedor manda o que a
 * operadora conhece. Comparar cru erraria quase sempre.
 */
create or replace function public.so_digitos(p text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g');
$$;

-- --------------------------------------------------------- o que ela quis

/**
 * Interpreta o texto humano.
 *
 * Deliberadamente conservadora: o conjunto de palavras é pequeno e exato. Um
 * "sim, mas só se for depois das 16h" **não** é aceite — é conversa, e conversa
 * é da psicóloga, não do robô. Marcar como indefinida deixa o horário livre
 * mais tempo; chutar marca a agenda de alguém errado. O primeiro erro se
 * conserta com um telefonema.
 */
create or replace function public.interpretar_resposta(p_texto text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  t text;
begin
  -- Minúsculas, sem acento, sem pontuação, sem espaço sobrando.
  t := lower(coalesce(p_texto, ''));
  t := translate(t, 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
  t := regexp_replace(t, '[^a-z0-9 ]', '', 'g');
  t := btrim(regexp_replace(t, '\s+', ' ', 'g'));

  if t in ('parar', 'parar de receber', 'pare', 'sair', 'stop',
           'descadastrar', 'cancelar inscricao', 'nao quero mais receber')
  then return 'parar'; end if;

  if t in ('sim', 's', 'si', 'quero', 'aceito', 'aceita', 'confirmo',
           'confirmado', 'pode ser', 'pode', 'ok', 'claro', 'bora', 'vou',
           'eu quero', 'sim quero', 'topo', '1')
  then return 'aceitar'; end if;

  if t in ('nao', 'n', 'nao posso', 'nao quero', 'nao vou', 'recuso',
           'infelizmente nao', 'hoje nao', 'dessa vez nao', 'passo', '2')
  then return 'recusar'; end if;

  return 'indefinida';
end;
$$;

-- ------------------------------------------------------------- o despacho

/**
 * Recebe uma resposta do provedor e faz o que ela pede.
 *
 * Devolve um jsonb com o que aconteceu — é o que o webhook registra no log e o
 * que os testes conferem. Nunca levanta exceção por resposta estranha: mensagem
 * que não dá para entender é um fato a registrar, não um erro a estourar.
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

  -- A porta. Segunda chegada da mesma mensagem para aqui.
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

    -- O que ainda não saiu, não sai. Pedir para parar e receber mais uma
    -- mensagem dez minutos depois é a pior forma de descobrir que o pedido
    -- foi registrado.
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

  -- ------------------------------------------------- de que oferta se trata
  --
  -- A viva mais recente daquele telefone. Uma pessoa pode estar na fila de
  -- duas psicólogas; quem respondeu está olhando a última mensagem que chegou.
  select o.id, o.conta_id, o.paciente_id
    into alvo
    from public.ofertas o
    join public.pacientes p on p.id = o.paciente_id
   where o.estado = 'enviada'
     and public.so_digitos(p.telefone) = fone
   order by o.enviar_em desc
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
         oferta_id = alvo.id
   where id = nova;

  -- ------------------------------------------------------------ indefinida
  if intencao = 'indefinida' then
    -- Não responde nada automático de propósito: a psicóloga vê na trilha e
    -- fala com a pessoa. Robô insistindo com quem escreveu uma frase inteira é
    -- o oposto do que este produto promete.
    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
    select alvo.conta_id, o.sessao_id, alvo.id, 'resposta_nao_entendida',
           jsonb_build_object('texto', left(coalesce(p_texto, ''), 200))
      from public.ofertas o where o.id = alvo.id;

    update public.mensagens_recebidas
       set resultado = 'não entendida — a oferta segue viva'
     where id = nova;

    return jsonb_build_object('estado', 'nao_entendi', 'oferta', alvo.id);
  end if;

  -- --------------------------------------------------------- aceite/recusa
  begin
    select public.responder_oferta(
      alvo.id,
      case intencao when 'aceitar' then 'aceita' else 'recusada' end
    ) into desfecho;
  exception when others then
    -- A oferta pode ter expirado ou sido respondida entre a leitura e agora.
    -- Isso não é falha do webhook: é a corrida normal de quem responde tarde.
    update public.mensagens_recebidas
       set resultado = 'não deu: ' || left(sqlerrm, 200)
     where id = nova;
    return jsonb_build_object('estado', 'tarde_demais', 'motivo', sqlerrm);
  end;

  update public.mensagens_recebidas set resultado = desfecho where id = nova;
  return jsonb_build_object('estado', desfecho, 'oferta', alvo.id);
end;
$$;

-- ------------------------------------------------------- recibo do provedor

/** O provedor avisa que entregou. É só trilha — não muda decisão nenhuma. */
create or replace function public.marcar_entregue(
  p_provedor_msg_id text,
  p_estado text default 'entregue'
)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare n int;
begin
  if p_estado not in ('entregue', 'falhou') then
    raise exception 'estado de entrega desconhecido: %', p_estado;
  end if;

  update public.mensagens
     set estado = p_estado
   where provedor_msg_id = p_provedor_msg_id
     and estado in ('enviada', 'entregue');
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.mensagens_recebidas enable row level security;

-- A psicóloga vê o que é da conta dela. As respostas que não casaram com
-- ninguém ficam só para o worker — são um telefone e um texto sem dono, e
-- mostrá-las a alguém seria mostrar o dado de outra pessoa.
drop policy if exists "respostas da conta: ler" on public.mensagens_recebidas;
create policy "respostas da conta: ler" on public.mensagens_recebidas
  for select to authenticated
  using (conta_id is not null and conta_id = public.conta_atual());

revoke execute on function public.responder_do_whatsapp(text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.marcar_entregue(text, text)
  from public, anon, authenticated;
grant execute on function public.responder_do_whatsapp(text, text, text, text) to service_role;
grant execute on function public.marcar_entregue(text, text) to service_role;

revoke execute on function public.interpretar_resposta(text) from public, anon;
revoke execute on function public.so_digitos(text) from public, anon;

comment on table public.mensagens_recebidas is
  'Tudo que chega do provedor. Unico por (provedor, provedor_msg_id): a reentrega nao age duas vezes.';
