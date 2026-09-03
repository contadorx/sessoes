-- 0089 · B50 · A trilha dizia "Oferta enviada" e nada tinha saído
--
-- O QUE FOI MEDIDO ANTES DE ESCREVER
--
-- `select count(*) from eventos_fila where tipo = 'oferta_enviada'` → **11**.
-- Dessas onze, quantas têm mensagem que chegou a `enviada` ou `entregue`?
-- **Zero.** A trilha afirmava um envio onze vezes e ele não aconteceu nenhuma.
--
-- A causa é o momento da escrita: `avancar_fila` grava `oferta_enviada` no
-- instante em que **cria** a oferta — antes de a mensagem sequer entrar na fila
-- de envio, e muito antes da janela de silêncio deixá-la sair. O nome do evento
-- descrevia a intenção, não o fato.
--
-- Isto não é só rótulo de tela: `eventos_fila` É a trilha da fila. Uma trilha
-- que diz "enviada" sobre o que não saiu é a mesma classe de defeito que a
-- `0088` conserta do lado do relógio — e as duas juntas eram o que fazia a
-- cascata parecer viva enquanto ninguém era convidado.
--
-- A SEPARAÇÃO
--
--   `oferta_preparada`  a oferta existe e a mensagem entrou na fila de envio
--   `oferta_enviada`    a mensagem SAIU — e quem escreve isso é quem a viu sair
--
-- Só dois lugares marcam mensagem como enviada, e agora os dois gravam o
-- evento: `marcar_enviada` (o worker, com resposta do provedor) e
-- `marcar_enviada_a_mao` (ela, dizendo que mandou pelo WhatsApp dela — a OP9
-- separa o clique do registro justamente porque só ela sabe).
--
-- OS ONZE EVENTOS ANTIGOS
--
-- Reetiquetados para `oferta_preparada`, **por derivação e não por lista**: o
-- critério é "não existe mensagem desta oferta em enviada/entregue", que é o
-- mesmo teste que os contou. Não é reescrever história — é corrigir um rótulo
-- que sempre esteve errado, e o fato que ele agora descreve é o que aconteceu.
-- Evento de fila fixa não entra: ele não guardava o id da oferta, então não há
-- como ligá-lo a mensagem nenhuma. Hoje não existe nenhum; daqui em diante o
-- id vai no `detalhe`, e é a segunda coisa que esta migração conserta.

-- ------------------------------------------------------- o tipo novo no check

alter table public.eventos_fila drop constraint if exists eventos_fila_tipo_check;
alter table public.eventos_fila add constraint eventos_fila_tipo_check
  check (tipo in ('vaga_aberta', 'oferta_preparada', 'oferta_enviada', 'oferta_aceita',
                  'oferta_recusada', 'oferta_expirada', 'vaga_preenchida',
                  'vaga_sem_takers', 'resposta_nao_entendida', 'vaga_fixa_aberta',
                  'vaga_fixa_preenchida', 'fila_pausada_no_teto'));

-- ------------------------------------------- a fila da vaga prepara, não envia

create or replace function public.avancar_fila(p_sessao uuid)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v record;
  proximo record;
  nova uuid;
  quando timestamptz;
  n int;
begin
  select se.id, se.conta_id, se.inicio, se.valor, ct.oferta_timeout_min
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

  -- A guarda de teto de plano da 0046 saiu na 0060: a fila é o que o produto
  -- promete, e pará-la para economizar mensagem é parar a promessa. O freio
  -- que sobrou é técnico e mora no envio, não aqui.

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

  -- `oferta_preparada`, e não `oferta_enviada`: neste ponto a mensagem ainda
  -- não entrou na fila (a linha abaixo é que a põe), e com a janela de silêncio
  -- ela pode só sair às 8h. Quem grava `oferta_enviada` é quem viu sair.
  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (v.conta_id, p_sessao, nova, 'oferta_preparada',
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'enviar_em', quando));

  -- A linha que a 0046 perdeu e a 0060 perdeu de novo. Sem ela a oferta é o
  -- registro de que alguém foi convidado sem ninguém ter sido convidado.
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
$function$;

-- ------------------------------------------------- a mesma coisa na vaga fixa

create or replace function public.avancar_fila_fixa(p_vaga uuid)
returns uuid
language plpgsql
set search_path = ''
as $function$
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
    values (v.conta_id, 'vaga_sem_takers', p_vaga, jsonb_build_object('fila', 'entrada'));
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  ate    := quando + make_interval(hours => v.oferta_fixa_horas);
  select count(*) + 1 into n from public.ofertas_fixas where vaga_id = p_vaga;

  insert into public.ofertas_fixas (conta_id, vaga_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_vaga, proximo.paciente_id, n, quando, ate)
  returning id into nova;

  -- O `oferta` no detalhe é novo: sem ele este evento não tinha como ser ligado
  -- à mensagem, e foi por isso que os eventos antigos da fila fixa não puderam
  -- ser reetiquetados.
  insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
  values (v.conta_id, 'oferta_preparada', p_vaga,
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'fila', 'entrada', 'enviar_em', quando,
                             'oferta', nova));

  perform public.enfileirar_mensagem(
    proximo.paciente_id,
    'oferta_de_vaga_fixa',
    'ofertafixa:' || nova::text,
    jsonb_build_object(
      'oferta_id', nova,
      'horario_fixo', public.rotulo_horario(v.dia_semana, v.hora),
      'expira_em', ate
    ),
    quando
  );

  return nova;
end;
$function$;

-- ------------------------------------ quem vê a mensagem sair grava o evento

-- O evento de envio, no único lugar onde o envio é observado.
--
-- Guarda contra repetição: `not exists`. Duas chamadas para a mesma mensagem —
-- retentativa do worker, webhook duplicado — não podem virar duas linhas de
-- trilha dizendo que a mesma oferta saiu duas vezes.
create or replace function public.registrar_oferta_enviada(p_mensagem uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  ms   record;
  alvo uuid;
begin
  select mn.conta_id, mn.chave_idem into ms
    from public.mensagens mn where mn.id = p_mensagem;
  if not found then return; end if;

  if ms.chave_idem like 'oferta:%' then
    alvo := substring(ms.chave_idem from 8)::uuid;

    if not exists (select 1 from public.eventos_fila e
                    where e.oferta_id = alvo and e.tipo = 'oferta_enviada') then
      insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
      select ms.conta_id, o.sessao_id, o.id, 'oferta_enviada',
             jsonb_build_object('saiu_em', now())
        from public.ofertas o where o.id = alvo;
    end if;

  elsif ms.chave_idem like 'ofertafixa:%' then
    alvo := substring(ms.chave_idem from 12)::uuid;

    if not exists (select 1 from public.eventos_fila e
                    where e.tipo = 'oferta_enviada'
                      and e.detalhe->>'oferta' = alvo::text) then
      insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
      select ms.conta_id, 'oferta_enviada', o.vaga_id,
             jsonb_build_object('fila', 'entrada', 'oferta', o.id, 'saiu_em', now())
        from public.ofertas_fixas o where o.id = alvo;
    end if;
  end if;
end;
$function$;

revoke all on function public.registrar_oferta_enviada(uuid) from public, anon;
grant execute on function public.registrar_oferta_enviada(uuid) to authenticated, service_role;

comment on function public.registrar_oferta_enviada(uuid) is
  'Grava eventos_fila.oferta_enviada quando a mensagem de uma oferta SAIU. Chamada por marcar_enviada (worker) e marcar_enviada_a_mao (ela). Idempotente.';

-- `marcar_enviada` era `language sql`; virou plpgsql para chamar o registro.
-- A assinatura e o efeito na mensagem são os mesmos, linha por linha.
create or replace function public.marcar_enviada(
  p_mensagem uuid, p_provedor text, p_provedor_msg_id text default null::text)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  update public.mensagens
     set estado = 'enviada', provedor = p_provedor,
         provedor_msg_id = p_provedor_msg_id, erro = null
   where id = p_mensagem;

  perform public.registrar_oferta_enviada(p_mensagem);
end;
$function$;

create or replace function public.marcar_enviada_a_mao(p_mensagem uuid)
returns boolean
language plpgsql
set search_path = ''
as $function$
declare
  c        uuid := public.conta_atual();
  ms       record;
  timeout  smallint;
  alvo     uuid;
begin
  if c is null then raise exception 'sem conta'; end if;

  select mn.id, mn.conta_id, mn.estado, mn.chave_idem
    into ms
    from public.mensagens mn
   where mn.id = p_mensagem;

  if not found then raise exception 'mensagem não encontrada'; end if;
  if ms.conta_id <> c then raise exception 'a mensagem é de outra conta'; end if;
  if ms.estado <> 'na_sua_mao' then return false; end if;

  update public.mensagens
     set estado = 'enviada', enviada_a_mao = true
   where id = p_mensagem;

  select ct.oferta_timeout_min into timeout
    from public.contas ct where ct.id = c;

  if ms.chave_idem like 'oferta:%' then
    alvo := substring(ms.chave_idem from 8)::uuid;
    update public.ofertas
       set enviar_em = now(),
           expira_em = now() + make_interval(mins => timeout)
     where id = alvo and estado = 'enviada';
  elsif ms.chave_idem like 'ofertafixa:%' then
    alvo := substring(ms.chave_idem from 12)::uuid;
    update public.ofertas_fixas
       set enviar_em = now(),
           expira_em = now() + make_interval(mins => timeout)
     where id = alvo and estado = 'enviada';
  end if;

  -- Ela mandou pelo número dela, e isso é saída de verdade: o evento nasce
  -- aqui pelo mesmo motivo que nasce no worker.
  perform public.registrar_oferta_enviada(p_mensagem);

  return true;
end;
$function$;

-- --------------------------------------------- os eventos antigos, por derivação

update public.eventos_fila e
   set tipo = 'oferta_preparada'
 where e.tipo = 'oferta_enviada'
   and e.oferta_id is not null
   and not exists (
     select 1 from public.mensagens m
      where m.chave_idem = 'oferta:' || e.oferta_id::text
        and m.estado in ('enviada', 'entregue'));
