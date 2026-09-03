-- =====================================================================
-- 0080 · O que está na mão dela também se cancela
-- =====================================================================
--
-- Achado rodando a suíte `0022_cobrancas.sql` — a verificação 5, que existe
-- desde a B11 e nunca tinha sido executada contra um banco de verdade:
--
--     '5 FUROU: o aviso ainda vai sair'
--
-- O diagnóstico, na conta do plano Gratuito:
--
--     plano=gratis  canal_do_plano=manual
--     aviso depois de decidir a cobrança  →  na_sua_mao
--     aviso depois de perdoar a cobrança  →  na_sua_mao
--
-- **Ela perdoa a cobrança e o aviso de cobrança continua na caixa "Na sua
-- mão", pronto para ela mandar com o dedo.** Não é uma mensagem que o sistema
-- vai enviar por engano: é pior, é uma que ele vai *pedir para ela enviar*,
-- depois de ela ter decidido que não ia cobrar. S2 pela tabela do §10 — erro
-- provável numa decisão de dinheiro —, e S1 no caso do `esquecer_contato`,
-- onde a mensagem que sobrevive é para alguém que pediu para ser esquecido.
--
-- ## Por que passou
--
-- A 0061 ("no Grátis o dedo é dela") acrescentou o estado `na_sua_mao`: no
-- plano Gratuito o canal de saída é manual, então a mensagem **nasce**
-- `na_sua_mao` em vez de `pendente`, e `mensagens_na_sua_mao()` é quem a
-- mostra para ela.
--
-- E a pergunta *"esta mensagem ainda vai sair?"* estava escrita à mão em seis
-- funções, todas de antes da 0061, todas dizendo `estado = 'pendente'`:
--
--     ao_mudar_estado_da_sessao   a sessão deixou de ser cobrável
--     arquivar_paciente           a ficha foi arquivada
--     esquecer_contato            LGPD: o contato foi apagado
--     lembrete_segue_a_sessao     a sessão saiu de prevista/confirmada
--     perdoar_cobranca            a cobrança foi perdoada
--     responder_do_whatsapp       a paciente respondeu PARAR
--
-- A 0061 corrigiu as duas que ela estava mexendo (`nao_vou_mandar` e
-- `marcar_enviada_a_mao` conhecem `na_sua_mao`). As seis não.
--
-- **É a quarta vez que este projeto aprende a mesma lição**, e a 0052d já a
-- tinha escrito palavra por palavra:
--
--     "quando uma pergunta de domínio aparece escrita em mais de um lugar, ela
--      diverge no dia em que alguém acrescenta um valor. A resposta não é
--      lembrar dos três lugares — é a lista virar função."
--
-- Então a lista vira função, e é a mesma receita da `assinatura_viva_da_conta`.
--
-- ## O que NÃO entra na função, e por quê
--
-- `reservar_mensagens`, `destravar_mensagens` e `marcar_falha` continuam com
-- `estado = 'pendente'` escrito à mão, **de propósito**. Elas respondem a outra
-- pergunta: *"o worker automático pega esta?"* — e a resposta para uma
-- mensagem `na_sua_mao` é não, que é a razão de a 0061 existir. São duas
-- perguntas que pareciam a mesma, exatamente como o `painel_do_negocio` ficou
-- de fora da 0052d. É por isso que a função se chama
-- `estados_de_mensagem_por_sair` e não `estados_vivos`.
--
-- `barrada_no_teto` também fica de fora: `lib/teto.ts` a trata como terminal
-- (`terminal("barrada_no_teto") === true`) e a frase dela diz "não saiu". Uma
-- mensagem barrada não vai sair nem pelo motor nem pelo dedo dela — cancelar
-- o que já está morto só apagaria o histórico de que a trava atuou.
--
-- ## Sobre a lei 6 e a lei 7
--
-- Os seis corpos abaixo vieram de `pg_get_functiondef` **do banco**, não das
-- migrações que os criaram — é a terceira exigência da lei 6, e este projeto
-- já foi mordido três vezes por ignorá-la. A substituição foi feita e conferida
-- no próprio banco: uma ocorrência trocada em cada função, e o único
-- `estado = 'pendente'` que sobrou é o de `propostas_de_cobranca` dentro de
-- `ao_mudar_estado_da_sessao`, que é a máquina de estados de outra tabela.
--
-- E a lei 7 não se cumpre com esta função: uma lista num lugar só continua
-- sendo uma lista. Quem cumpre é a varredura em
-- `supabase/tests/0080_a_pergunta_de_dominio_mora_num_lugar_so.sql`, que lê o
-- `pg_proc` e reprova qualquer função nova que cancele mensagem filtrando por
-- `estado = 'pendente'` cru.
--
-- Nenhuma das seis muda de assinatura, então `create or replace` preserva as
-- concessões que cada migração anterior deu — e a suíte confere isso também,
-- em vez de eu reafirmar seis `grant` de memória.
-- =====================================================================

/**
 * Os estados de mensagem que ainda vão sair — por motor ou pelo dedo dela.
 *
 * A pergunta é: "se o fato que gerou esta mensagem deixou de existir, ela
 * precisa ser cancelada?". `pendente` é a que o worker vai pegar; `na_sua_mao`
 * é a que espera ela apertar o botão no plano Gratuito (0061). As duas ainda
 * chegam na paciente, e é isso que faz delas a mesma pergunta.
 *
 * Não confundir com "quais o worker reserva" — essa é só `pendente`, e mora
 * escrita à mão em `reservar_mensagens` porque é outra pergunta.
 */
create or replace function public.estados_de_mensagem_por_sair()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['pendente', 'na_sua_mao']::text[];
$$;

comment on function public.estados_de_mensagem_por_sair() is
  'Estados de mensagem que ainda chegam na paciente: pendente (o motor pega) e na_sua_mao (o dedo dela, 0061). E a lista que todo cancelamento consulta. NAO e a lista do que o worker reserva — essa e so pendente, e e outra pergunta.';

revoke all on function public.estados_de_mensagem_por_sair() from public, anon;
grant execute on function public.estados_de_mensagem_por_sair() to authenticated, service_role;


-- ---------------------------------------------------------------------
-- perdoar_cobranca — a que a suíte 0022 pegou
-- 
-- Ela perdoa, e o aviso de cobrança fica na caixa dela esperando um toque.
-- É a mesma cobrança, com a mesma frase, depois de a decisão ter sido tomada
-- no sentido contrário.

CREATE OR REPLACE FUNCTION public.perdoar_cobranca(p_cobranca uuid, p_motivo text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c record;
begin
  select * into c from public.cobrancas where id = p_cobranca;
  if not found then raise exception 'cobrança não encontrada'; end if;
  if c.estado <> 'aberta' then
    raise exception 'só dá para perdoar cobrança aberta (esta está %)', c.estado;
  end if;

  update public.cobrancas
     set estado = 'perdoada',
         perdoada_em = now(),
         perdoada_motivo = nullif(btrim(coalesce(p_motivo, '')), '')
   where id = p_cobranca;

  update public.mensagens
     set estado = 'cancelada'
   where chave_idem = 'cobranca:' || p_cobranca::text
     and estado = any(public.estados_de_mensagem_por_sair());

  return 'perdoada';
end;
$function$
;

-- ---------------------------------------------------------------------
-- ao_mudar_estado_da_sessao — a sessão deixou de ser cobrável
-- 
-- A sessão volta de falta para realizada (ou de cancelada_tarde para
-- cancelada a tempo) e a cobrança some. O aviso dela não somia junto.
-- 
-- O segundo `estado = 'pendente'` desta função fica: ele é de
-- `propostas_de_cobranca`, que tem máquina de estados própria e não conhece
-- `na_sua_mao` — não é a mesma pergunta.

CREATE OR REPLACE FUNCTION public.ao_mudar_estado_da_sessao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cobravel_antes boolean;
  cobravel_agora boolean;
  quanto  numeric;
  modelo  text;
  a_parte boolean := false;
  enq     record;
  cont    record;
  pac     uuid;
  dia     date;
begin
  cobravel_antes := old.estado in ('cancelada_tarde', 'falta');
  cobravel_agora := new.estado in ('cancelada_tarde', 'falta');

  dia := (new.inicio at time zone 'America/Sao_Paulo')::date;

  select * into cont from public.contas where id = new.conta_id;

  -- `modelo` e `a_parte` são escalares, e não campos de `enq`, porque o plpgsql
  -- **não** curto-circuita: `modelo = 'mensal' and enq.falta_cobra_a_parte`
  -- vira um SELECT inteiro, e ler campo de record não atribuído estoura ali
  -- mesmo. Numa sessão sem combinado — a maioria dos encaixes —, isso derrubava
  -- o cancelamento. Lição da 0033, mantida palavra por palavra.
  modelo := 'avulso';
  if new.enquadre_id is not null then
    select * into enq from public.enquadres where id = new.enquadre_id;
    if found then
      modelo  := enq.modelo_cobranca;
      a_parte := coalesce(enq.falta_cobra_a_parte, false);
    end if;
  end if;

  -- ------------------------------------------ deixou de ser cobrável/consumível
  if (cobravel_antes and not cobravel_agora)
     or (old.estado = 'realizada' and new.estado <> 'realizada') then

    update public.cobrancas
       set estado = 'cancelada'
     where sessao_id = new.id and estado in ('aberta', 'perdoada');

    delete from public.pacote_consumos where sessao_id = new.id;

    update public.mensagens
       set estado = 'cancelada'
     where chave_idem like 'cobranca:%'
       and estado = any(public.estados_de_mensagem_por_sair())
       and (params->>'sessao_id') = new.id::text;

    -- P4: a pergunta some junto com o fato que a gerou. Uma decisão pendente
    -- sobre uma falta que deixou de existir é pior que nenhuma — ela é uma
    -- cobrança esperando um clique distraído.
    update public.propostas_de_cobranca
       set estado = 'descartada'
     where sessao_id = new.id and estado = 'pendente';

    if not cobravel_agora and new.estado <> 'realizada' then
      return new;
    end if;
  end if;

  -- ------------------------------------------------------- o pacote come antes
  if modelo = 'pacote' and new.estado in ('realizada', 'falta', 'cancelada_tarde') then
    pac := public.pacote_para_sessao(new.paciente_id, dia);

    if pac is not null then
      insert into public.pacote_consumos (conta_id, pacote_id, sessao_id, motivo)
      values (new.conta_id, pac, new.id, new.estado)
      on conflict do nothing;

      if not (a_parte and cobravel_agora) then
        return new;
      end if;
    end if;
  end if;

  -- -------------------------------------------------- o mensal já foi pago
  if modelo = 'mensal' and cobravel_agora and not a_parte then
    return new;
  end if;

  -- ------------------------------------------------ a sessão que aconteceu
  --
  -- Não passa por decisão, e a razão está no cabeçalho: hora prestada é preço
  -- combinado, não juízo sobre o motivo de ninguém. Segue igual à 0033.
  if new.estado = 'realizada' then
    if not coalesce(cont.cobra_sessao, false) or modelo <> 'avulso' then
      return new;
    end if;
    if new.valor <= 0 then return new; end if;

    insert into public.cobrancas (
      conta_id, paciente_id, sessao_id, enquadre_id, tipo, motivo, valor,
      valor_da_sessao, competencia
    )
    values (
      new.conta_id, new.paciente_id, new.id, new.enquadre_id,
      'sessao', 'sessao_realizada', new.valor, new.valor,
      date_trunc('month', dia)::date
    )
    on conflict do nothing;

    return new;
  end if;

  if not cobravel_agora then
    return new;
  end if;

  -- --------------------------------------------------------- a multa (P4)
  quanto := public.multa_da_politica(new.valor, new.politica_percentual);

  -- Política de 0% continua não gerando nada — nem cobrança nem pergunta.
  -- Perguntar "quer cobrar R$ 0,00?" seria pior que a cobrança zerada que a
  -- B11 já recusava: é interromper alguém para nada.
  if quanto <= 0 then
    return new;
  end if;

  insert into public.propostas_de_cobranca (
    conta_id, paciente_id, sessao_id, enquadre_id, motivo, valor_sugerido,
    politica_horas, politica_percentual, valor_da_sessao, competencia
  )
  values (
    new.conta_id, new.paciente_id, new.id, new.enquadre_id, new.estado, quanto,
    new.politica_horas, new.politica_percentual, new.valor,
    date_trunc('month', dia)::date
  )
  on conflict do nothing;

  -- E aqui acaba. Nenhuma mensagem sai deste gatilho — é a linha inteira do
  -- build numa ausência.
  return new;
end;
$function$
;

-- ---------------------------------------------------------------------
-- lembrete_segue_a_sessao — a sessão saiu de prevista/confirmada
-- 
-- Um lembrete de véspera para uma sessão que foi desmarcada. No Gratuito ele
-- ficava na mão dela, e o que ela mandaria é um lembrete de uma sessão que
-- não vai acontecer — o antipadrão da "promessa que o software não cumpre",
-- só que dita pela própria psicóloga.

CREATE OR REPLACE FUNCTION public.lembrete_segue_a_sessao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.estado in ('prevista', 'confirmada') then return new; end if;

  update public.mensagens
     set estado = 'cancelada'
   where chave_idem = 'lembrete:' || new.id::text
     and estado = any(public.estados_de_mensagem_por_sair());

  return new;
end;
$function$
;

-- ---------------------------------------------------------------------
-- arquivar_paciente — a ficha foi arquivada
-- 
-- O bloco 4 fecha, o enquadre encerra, as filas esvaziam. E sobrava mensagem
-- para quem acabou de ser encerrado.

CREATE OR REPLACE FUNCTION public.arquivar_paciente(p_paciente uuid, p_encerramento text, p_tipo text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  pac record;
  reg record;
begin
  if p_encerramento is null or length(btrim(p_encerramento)) < 10 then
    raise exception 'o encerramento precisa dizer como o acompanhamento terminou';
  end if;

  -- O tipo é do bloco 4, e o `check` de `registros` recusa data sem tipo. Pedir
  -- aqui é o que impede a ficha de ser arquivada com o registro pela metade.
  if p_tipo is null or p_tipo not in ('alta', 'abandono', 'encaminhamento') then
    raise exception 'escolha como terminou: alta, abandono ou encaminhamento';
  end if;

  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;
  if pac.estado = 'arquivado' then raise exception 'esta ficha já está arquivada'; end if;

  update public.pacientes
     set estado = 'arquivado',
         arquivado_em = now(),
         encerramento = btrim(p_encerramento)
   where id = p_paciente;

  -- `registros` pode não existir ainda: ela nasce quando a demanda é escrita
  -- (bloco 2). Arquivar alguém que nunca teve demanda registrada é legítimo —
  -- uma pessoa que veio uma vez e não voltou — e o encerramento dela também é
  -- conteúdo mínimo.
  select * into reg from public.registros where paciente_id = p_paciente;

  if found then
    update public.registros
       set encerrado_em = now(),
           encerramento_tipo = p_tipo,
           atualizado_em = now()
     where id = reg.id;
  else
    insert into public.registros
      (conta_id, paciente_id, profissional_id, encerrado_em, encerramento_tipo)
    values
      (pac.conta_id, p_paciente, pac.profissional_id, now(), p_tipo);
  end if;

  update public.enquadres
     set vigencia_fim = public.hoje_sp(), motivo_fim = 'encerramento'
   where paciente_id = p_paciente and vigencia_fim is null;

  delete from public.fila_encaixe where paciente_id = p_paciente;
  delete from public.fila_entrada where paciente_id = p_paciente;
  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente
     and estado = any(public.estados_de_mensagem_por_sair());

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'arquivou',
          jsonb_build_object('tipo', p_tipo));

  return 'arquivada';
end;
$function$
;

-- ---------------------------------------------------------------------
-- esquecer_contato — LGPD, e o pior dos seis
-- 
-- A função apaga telefone, e-mail e responsáveis, revoga o link vivo e
-- devolve a frase "envios cancelados". No Gratuito os envios NÃO estavam
-- cancelados: ficavam na caixa dela, com o texto já montado.
-- 
-- O telefone já tinha sido apagado da ficha, mas `mensagens.destino` guarda
-- o número do momento em que a mensagem foi montada. A frase de retorno
-- prometia uma coisa e o banco fazia outra, que é a definição de S1 do §10:
-- ela conclui a tarefa errado sem saber.

CREATE OR REPLACE FUNCTION public.esquecer_contato(p_paciente uuid)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  pac record;
  anos smallint;
  ate date;
  ultimo date;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  select retencao_anos into anos from public.contas where id = pac.conta_id;

  update public.pacientes
     set telefone = null,
         email = null,
         responsaveis = '[]'::jsonb,
         msg_canal = 'nao_avisar',
         contato_esquecido_em = now()
   where id = p_paciente;

  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente
     and estado = any(public.estados_de_mensagem_por_sair());

  delete from public.fila_encaixe where paciente_id = p_paciente;

  -- Novo na 0076: o link vivo morre junto. Deixá-lo de pé depois de um pedido
  -- de exclusão é deixar a porta que a exclusão veio fechar.
  update public.links_do_paciente
     set revogado_em = now()
   where paciente_id = p_paciente and revogado_em is null;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'esqueceu_contato', '{}'::jsonb);

  select greatest(
           coalesce(max(s.inicio at time zone 'America/Sao_Paulo'), pac.criado_em at time zone 'America/Sao_Paulo'),
           pac.criado_em at time zone 'America/Sao_Paulo'
         )::date
    into ultimo
    from public.sessoes s where s.paciente_id = p_paciente;

  ate := (coalesce(ultimo, (pac.criado_em at time zone 'America/Sao_Paulo')::date)
          + make_interval(years => coalesce(anos, 5)))::date;

  return 'Contato apagado, envios cancelados e o link do paciente revogado. O registro clínico continua '
      || 'guardado até ' || to_char(ate, 'DD/MM/YYYY')
      || ' porque o Conselho obriga — não é escolha do sistema.';
end;
$function$
;

-- ---------------------------------------------------------------------
-- responder_do_whatsapp — a paciente escreveu PARAR
-- 
-- O opt-out. `msg_canal` vira `nao_avisar` e a fila para. Mas o que já
-- estava montado seguia na caixa dela — e mandar à mão para quem pediu para
-- parar é a mesma quebra, com a assinatura dela em cima.

CREATE OR REPLACE FUNCTION public.responder_do_whatsapp(p_provedor text, p_provedor_msg_id text, p_de text, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
       and m.estado = any(public.estados_de_mensagem_por_sair());

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
$function$
;
