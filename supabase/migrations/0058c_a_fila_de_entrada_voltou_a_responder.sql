-- 0058c · a fila de entrada voltou a responder pelo WhatsApp.
--
-- **Defeito da 0057, achado pela regressão do P4, e ele é grande.**
--
-- `responder_do_whatsapp` é a única porta de entrada das respostas. Até a B22
-- (0036) ela olhava **duas** filas — o encaixe (`ofertas`) e a entrada
-- (`ofertas_fixas`, o horário fixo que vagou) —, escolhendo a oferta viva mais
-- recente daquele telefone e chamando `responder_oferta` ou
-- `responder_oferta_fixa` conforme o caso.
--
-- A 0057 reescreveu a função para acrescentar a confirmação de sessão e, ao
-- reescrever, **copiou só metade**: o `union all` virou um `select` sobre
-- `ofertas`. `responder_oferta_fixa` deixou de ser chamada por alguém. A partir
-- dali, quem recebeu a oferta de um horário fixo e respondeu "sim" caía num de
-- dois desfechos, os dois errados:
--
--   · com nenhuma outra oferta viva, recebia `sem_oferta` — a vaga fixa nunca
--     era preenchida, e a pessoa que esperava por aquele horário ficava
--     esperando um horário que já tinha sido oferecido a ela;
--   · com uma oferta de encaixe viva no mesmo telefone, o "sim" era consumido
--     **pela oferta errada** — a pessoa aceitava, sem saber, uma hora avulsa
--     de outro dia, enquanto o horário fixo que ela queria seguia aberto.
--
-- O segundo é pior que o primeiro e é o que a suíte 0036 pegou: a verificação
-- 18 encontrou uma sessão marcada para quem só tinha dito "sim" para uma vaga
-- fixa. *"A pessoa apareceria num dia que ninguém combinou"* é a frase que
-- estava escrita naquele teste desde a B22, e ela deixou de ser hipotética.
--
-- **Por que passou despercebido:** a 0057 rodou a regressão das suítes que ela
-- tocava — 0017, 0021, 0012, 0046 e 0056 — e a 0036 não estava na lista, porque
-- "vaga fixa" não parece assunto de confirmação de sessão. O critério certo não
-- é *que assunto a migração trata*, é **que funções ela reescreve**: toda suíte
-- que exercita uma função reescrita entra na regressão, ainda que o tema seja
-- outro. Fica registrado.
--
-- E a verificação 17 da 0036 não acusou nada porque comparava `j->>'fila'` com
-- `'entrada'`, e a chave tinha **sumido** do retorno: em SQL, `null <>
-- 'entrada'` não é verdadeiro, é nulo — e um `if` sobre nulo não dispara. Uma
-- asserção sobre uma chave que deixou de existir vira silêncio. A suíte ganha
-- uma verificação nova para isso.
--
-- ---------------------------------------------------------------------------
-- O que esta migração faz: devolve o `union all` da 0036 **dentro** da função
-- da 0057, preservando inteira a regra de colisão da confirmação. Nada mais
-- muda: a confirmação continua ganhando quando é a mensagem mais recente, e
-- continua sem mexer no estado da agenda.
--
-- Os campos das duas filas viram **escalares**, e não um `record` — a lição da
-- 0052c e da 0056, que a própria 0057 já tinha aplicado aqui: os dois `select`
-- podem não achar nada, e ler campo de record não atribuído estoura na hora.

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
  -- A oferta viva mais recente do telefone, **das duas filas**.
  of_id uuid; of_conta uuid; of_paciente uuid; of_sessao uuid; of_vaga uuid;
  of_quando timestamptz; of_fila text;
  -- E a confirmação pendente, se houver.
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

  -- ------------------------------- de que oferta se trata (B10 + B22)
  select t.id, t.conta_id, t.paciente_id, t.sessao_id, t.vaga_id, t.enviar_em, t.fila
    into of_id, of_conta, of_paciente, of_sessao, of_vaga, of_quando, of_fila
    from (
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
      update public.mensagens_recebidas
         set resultado = 'não entendida — a confirmação segue pendente'
       where id = nova;
      return jsonb_build_object('estado', 'nao_entendi', 'sessao', cf_id);
    end if;

    -- Invariante 3 da 0057: mexe no eixo, **nunca** no estado da agenda.
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
         -- `oferta_id` referencia `ofertas`; para a fila de entrada fica nulo e
         -- o texto do resultado diz de qual fila se tratava.
         oferta_id = case when of_fila = 'encaixe' then of_id end
   where id = nova;

  -- ------------------------------------------------------------ indefinida
  if intencao = 'indefinida' then
    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, vaga_fixa_id, tipo, detalhe)
    values (of_conta, of_sessao,
            case when of_fila = 'encaixe' then of_id end,
            of_vaga, 'resposta_nao_entendida',
            jsonb_build_object('texto', left(coalesce(p_texto, ''), 200), 'fila', of_fila));

    update public.mensagens_recebidas
       set resultado = 'não entendida — a oferta segue viva'
     where id = nova;

    return jsonb_build_object('estado', 'nao_entendi', 'oferta', of_id, 'fila', of_fila);
  end if;

  -- --------------------------------------------------------- aceite/recusa
  begin
    if of_fila = 'encaixe' then
      select public.responder_oferta(
        of_id, case intencao when 'aceitar' then 'aceita' else 'recusada' end
      ) into desfecho;
    else
      select public.responder_oferta_fixa(
        of_id, case intencao when 'aceitar' then 'aceita' else 'recusada' end
      ) into desfecho;
    end if;
  exception when others then
    update public.mensagens_recebidas
       set resultado = 'não deu: ' || left(sqlerrm, 200)
     where id = nova;
    return jsonb_build_object('estado', 'tarde_demais', 'motivo', sqlerrm);
  end;

  update public.mensagens_recebidas
     set resultado = desfecho || ' (' || of_fila || ')'
   where id = nova;

  return jsonb_build_object('estado', desfecho, 'oferta', of_id, 'fila', of_fila);
end;
$$;

revoke execute on function public.responder_do_whatsapp(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.responder_do_whatsapp(text, text, text, text) to service_role;

comment on function public.responder_do_whatsapp(text, text, text, text) is
  'A porta unica das respostas: encaixe, fila de entrada e confirmacao de sessao. Ganha a mensagem mais recente. Nada aqui cancela sessao.';
