-- 0092 · B52 · A classe decide por onde sai, e a urgente fura a fila
--
-- O EIXO QUE FALTAVA
--
-- `templates.essencial` responde *"quem se machuca se não for?"* e governa o
-- **teto de plano**. Roteamento precisa de outra pergunta: *"quanto valor a
-- mensagem perde com atraso?"* — e ela não existia em lugar nenhum.
--
--   urgente    perde valor em minutos. Fura a fila e tem cascata automática.
--   rotina     tolera horas. Pode cair na mão dela sem prejuízo.
--   documento  recibo, informe, declaração. NUNCA por canal não oficial.
--
-- **Cuidado para não ler errado:** `documento` é o *arquivo*, não o *valor*. Uma
-- cobrança que diz "seu pagamento combinado: R$ 200" **pode** ir por WhatsApp —
-- valor não é dado de saúde, e a mensagem discreta não nomeia terapia. O que não
-- vai é o recibo, que nomeia o serviço e existe para reembolso e Receita Saúde.
-- **Valor pode; documento não.**
--
-- O SMS É MEDIDA DE CRISE
--
-- Decisão de 03/09: construído, testado, e **fora da vitrine**. `precos_canal`
-- está no banco desde sempre e diz por quê, em milésimos de centavo: e-mail
-- **200** · WhatsApp **4.500** · SMS **8.000**. Quarenta vezes o e-mail para
-- chegar ao mesmo lugar em quase todo caso. Como último degrau antes do
-- silêncio, vale; como opção de menu, é conta que estoura sem ninguém ter
-- pedido nada. A ordem dos degraus mora em `lib/mensageria/roteamento.ts`, que
-- é puro e testado.

alter table public.templates
  add column if not exists classe text not null default 'rotina'
    check (classe in ('urgente', 'rotina', 'documento')),
  add column if not exists tolera_atraso_min integer
    check (tolera_atraso_min is null or tolera_atraso_min > 0);

comment on column public.templates.classe is
  'Quanto valor a mensagem perde com atraso — o eixo do ROTEAMENTO, irmao e nao sinonimo de essencial (que e o eixo do TETO). urgente fura a fila e tem cascata; rotina pode cair na mao dela; documento NUNCA sai por canal nao oficial.';
comment on column public.templates.tolera_atraso_min is
  'Quantos minutos a mensagem aguenta esperar. Urgente cuja vaga expira antes do fim da janela de silencio nao espera as 8h.';

update public.templates set classe = 'urgente', tolera_atraso_min = 10   where codigo = 'oferta_de_vaga';
update public.templates set classe = 'urgente', tolera_atraso_min = 30   where codigo = 'oferta_de_vaga_fixa';
update public.templates set classe = 'urgente', tolera_atraso_min = 5    where codigo = 'encaixe_confirmado';
update public.templates set classe = 'urgente', tolera_atraso_min = 15   where codigo = 'aviso_de_desmarque';
update public.templates set classe = 'urgente', tolera_atraso_min = 60   where codigo = 'lembrete_de_sessao';
update public.templates set classe = 'rotina',  tolera_atraso_min = 240  where codigo = 'confirmacao_de_sessao';
update public.templates set classe = 'rotina',  tolera_atraso_min = 1440 where codigo in
  ('aviso_de_cobranca', 'lembrete_de_pagamento', 'aviso_de_pausa');
update public.templates set classe = 'rotina',  tolera_atraso_min = 2880 where codigo = 'aviso_de_reajuste';

-- ------------------------------------------------------- a urgente fura a fila
--
-- Uma oferta expira em `contas.oferta_timeout_min` (40 min). FIFO com duzentos
-- lembretes na frente mata a métrica-norte do produto **sem nenhum erro
-- aparecer**: a fila estaria funcionando, e a vaga fecharia vazia.
--
-- `for update of x` e não `for update`: a junção com `templates` é externa, e
-- travar a linha do template além de errado seria recusado pelo Postgres.

create or replace function public.reservar_mensagens(p_limite integer default 20)
returns setof public.mensagens
language plpgsql
set search_path = ''
as $function$
begin
  -- Passo 1: barrar o que bateu num freio técnico.
  update public.mensagens ms
     set estado = 'barrada_no_teto',
         erro = 'trava de segurança: ' || public.teto_tecnico(ms.conta_id, ms.paciente_id)
   where ms.estado = 'pendente'
     and ms.agendada_para <= now()
     and public.teto_tecnico(ms.conta_id, ms.paciente_id) is not null;

  -- Passo 2: a reserva de sempre, atômica desde a B9 — agora na ordem da classe.
  --
  -- **São dois `order by`, e a suíte exigiu o segundo.** O de dentro escolhe
  -- **quais** linhas entram no lote; a ordem do `RETURNING` de um `update` é
  -- arbitrária. Com só o primeiro, a fila escolhia certo e **devolvia errado**
  -- — o worker mandava a rotina antes da urgente dentro do mesmo lote.
  return query
  with reservadas as (
    update public.mensagens ms
       set estado = 'enviando', tentativas = ms.tentativas + 1
     where ms.id in (
       select x.id from public.mensagens x
         left join public.templates tp on tp.codigo = x.template
        where x.estado = 'pendente'
          and x.agendada_para <= now()
        order by
          case coalesce(tp.classe, 'rotina')
            when 'urgente' then 0 when 'rotina' then 1 else 2 end,
          x.agendada_para
        for update of x skip locked
        limit p_limite
     )
    returning ms.*
  )
  select r.* from reservadas r
    left join public.templates tp on tp.codigo = r.template
   order by
     case coalesce(tp.classe, 'rotina')
       when 'urgente' then 0 when 'rotina' then 1 else 2 end,
     r.agendada_para;
end;
$function$;

comment on function public.reservar_mensagens(integer) is
  'Reserva atomica do lote na ordem da CLASSE antes da data — e DEVOLVE nessa ordem. O order by de dentro escolhe QUAIS linhas entram; sem o de fora, a ordem do RETURNING e arbitraria e o worker mandaria a rotina antes da urgente dentro do mesmo lote. Template sem classe conta como rotina.';

-- ------------------------------------------ o canal explícito, e a fronteira 8
--
-- O gatilho cravava `new.canal := pac.msg_canal` **sempre**, e isso tornava a
-- cascata impossível: um degrau de e-mail inserido pelo worker voltava a nascer
-- WhatsApp, com o telefone no destino.
--
-- Agora um canal explícito é respeitado — e só quando existe contato para ele.
-- O que **não** muda: `nao_avisar` continua recusando a mensagem inteira. A
-- cascata não atravessa a decisão da paciente de não ser avisada.

create or replace function public.mensagem_confere_retrato()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  pac     record;
  alvo    text;
  escrito text;
  classe  text;
begin
  if new.paciente_id is null then
    raise exception 'mensagem precisa de paciente';
  end if;

  select p.id, p.conta_id, p.nome, p.telefone, p.email, p.msg_canal, p.msg_modo
    into pac
    from public.pacientes p
   where p.id = new.paciente_id;

  if not found then raise exception 'paciente não encontrado'; end if;

  if pac.msg_canal = 'nao_avisar' then
    raise exception 'este paciente pediu para não ser avisado';
  end if;

  new.conta_id := pac.conta_id;

  select tp.classe into classe from public.templates tp where tp.codigo = new.template;

  escrito := nullif(btrim(coalesce(new.canal, '')), '');
  alvo := case
            when escrito in ('whatsapp', 'sms') and coalesce(pac.telefone, '') <> '' then escrito
            when escrito = 'email' and coalesce(pac.email, '') <> '' then escrito
            else pac.msg_canal
          end;

  /*
    A fronteira 8, **na porta e não no degrau** — e foi a suíte que mostrou a
    diferença.

    `documento` — recibo, informe, declaração — nunca sai por canal não oficial.
    A cascata já recusava o degrau, e isso **não bastava**: a mensagem nasce com
    o canal da paciente, então um documento para quem escolheu WhatsApp nascia
    no WhatsApp e a cascata nunca era chamada. O caminho principal passava por
    fora da fronteira, e a verificação que só olhava a cascata passava junto.

    Sem e-mail cadastrado a mensagem **não nasce**. É recusa dura de propósito:
    a alternativa seria mandar o recibo por WhatsApp, que é exatamente o que a
    fronteira proíbe.
  */
  if coalesce(classe, 'rotina') = 'documento' then
    if coalesce(pac.email, '') = '' then
      raise exception 'documento só sai por e-mail, e este paciente não tem e-mail cadastrado';
    end if;
    alvo := 'email';
  end if;

  new.canal := alvo;
  new.destino := case alvo when 'email' then pac.email else pac.telefone end;

  if new.destino is null or new.destino = '' then
    raise exception 'paciente sem % para avisar',
      case alvo when 'email' then 'e-mail' else 'telefone' end;
  end if;

  -- O modo de discrição (D3) viaja com a mensagem: quem renderiza não precisa
  -- voltar ao cadastro, e editar o cadastro depois não muda o que já saiu.
  new.params := coalesce(new.params, '{}'::jsonb)
                || jsonb_build_object('modo', pac.msg_modo, 'nome', pac.nome);

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
$function$;

-- ------------------------------------------------------- o degrau da cascata

create or replace function public.reencaminhar_mensagem(p_mensagem uuid, p_canal text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  m      record;
  classe text;
  novo   uuid;
begin
  select * into m from public.mensagens where id = p_mensagem;
  if not found then raise exception 'mensagem não encontrada'; end if;

  if p_canal not in ('whatsapp', 'sms', 'email') then
    raise exception 'canal inválido: %', p_canal;
  end if;

  if p_canal = m.canal then return null; end if;

  -- A fronteira 8 em código: documento não desce para canal não oficial, nem
  -- por cascata, nem por urgência. Se o e-mail não puder, espera a mão dela.
  select tp.classe into classe from public.templates tp where tp.codigo = m.template;
  if coalesce(classe, 'rotina') = 'documento' and p_canal <> 'email' then
    raise exception 'template de documento não sai por %', p_canal;
  end if;

  -- A chave de entrega é (mensagem original, canal). Sem ela a cascata manda a
  -- mesma oferta duas vezes para a mesma pessoa — que é o jeito mais rápido de
  -- a psicóloga desligar o canal inteiro.
  if exists (
    select 1 from public.mensagens x
     where x.reenvio_de = coalesce(m.reenvio_de, m.id)
       and x.canal = p_canal
  ) then
    return null;
  end if;

  insert into public.mensagens (
    conta_id, paciente_id, canal, template, params, chave_idem, agendada_para, reenvio_de
  )
  values (
    m.conta_id, m.paciente_id, p_canal, m.template, m.params,
    m.chave_idem || '#c' || p_canal, now(), coalesce(m.reenvio_de, m.id)
  )
  returning id into novo;

  update public.mensagens
     set estado = 'reenviada',
         erro = 'sem caminho por ' || m.canal || '; seguiu por ' || p_canal
   where id = p_mensagem;

  return novo;
end;
$function$;

revoke all on function public.reencaminhar_mensagem(uuid, text) from public, anon, authenticated;
grant execute on function public.reencaminhar_mensagem(uuid, text) to service_role;

comment on function public.reencaminhar_mensagem(uuid, text) is
  'O degrau seguinte da cascata: cria a tentativa em outro canal, com destino recomputado do paciente e chave de entrega (original, canal) para nao mandar a mesma coisa duas vezes. Template de documento so aceita email — a fronteira 8 em codigo.';
