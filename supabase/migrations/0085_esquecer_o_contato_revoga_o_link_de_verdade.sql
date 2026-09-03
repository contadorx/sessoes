-- =====================================================================
-- 0085 · Esquecer o contato revoga o link de verdade
-- =====================================================================
--
-- O S1-2 da auditoria de 03/09, e ele reproduz em produção. A prova, rodada
-- no banco antes de qualquer conserto:
--
--     ANTES   · revogado_em = (vazio)
--     RETORNO · "Contato apagado, envios cancelados e o link do paciente
--                revogado. O registro clínico continua guardado até
--                03/09/2031 porque o Conselho obriga…"
--     DEPOIS  · revogado_em = (vazio)
--
-- E, com o token na mão, um visitante `anon`: `estado_da_pagina = aberta`.
--
-- ## O mecanismo
--
-- A 0066 escreveu a decisão no próprio cabeçalho: `links_do_paciente` **não
-- tem policy de insert, update ou delete** — *"quem cria e revoga são as
-- funções abaixo"*, e as duas (`abrir_link_do_paciente`,
-- `revogar_link_do_paciente`) são `security definer`.
--
-- A 0076 acrescentou um terceiro escritor que não é nenhuma delas:
--
--     update public.links_do_paciente
--        set revogado_em = now()
--      where paciente_id = p_paciente and revogado_em is null;
--
-- dentro de `esquecer_contato`, que é `security invoker`. **A RLS não recusa —
-- ela filtra.** O `update` casa com zero linhas, `row_count` é zero, nenhuma
-- exceção sobe, e a função devolve a frase que promete a revogação.
--
-- É a **lei 8 com o banco no lugar do adaptador**: *adaptador ausente recusa,
-- não finge*. O `insert` grita; o `update` mente.
--
-- ## Por que é S1 e não S2
--
-- O contato **é** apagado — telefone e e-mail ficam em branco —, e é isso que
-- torna a falha invisível: a tela mostra a ficha limpa. O que continua de pé é
-- a página do paciente, por 30 dias: cobranças com valor e Pix copia-e-cola,
-- sessões esperando confirmação, documentos dos últimos 90 dias e o botão de
-- confirmar. Ela atendeu a um pedido de exclusão da LGPD, o sistema confirmou
-- por escrito, e a porta continuou aberta. §10: *conclui errado sem saber*.
--
-- ## O conserto, e o que ele NÃO é
--
-- Não é dar policy de escrita a `links_do_paciente`: isso desfaria a decisão
-- da 0066 e abriria a tabela do token para todo `update` que passar. É chamar
-- a função que a 0066 escreveu exatamente para isto, e que já é `definer` e já
-- confere `conta_atual()` por dentro.
--
-- ## A classe inteira, que era o pedido da auditoria — e ela encolhe
--
-- A auditoria varreu as funções `security invoker` que escrevem em tabela sem
-- policy de escrita e achou **doze**. Refiz a varredura e cheguei às mesmas
-- doze — e depois acrescentei a pergunta que muda o resultado: **`authenticated`
-- alcança esta função?** Se só `service_role` a chama, não há mentira nenhuma,
-- porque `service_role` não passa por RLS.
--
-- Das doze, sobram **duas**:
--
--     esquecer_contato          → links_do_paciente    ← esta, e é a S1
--     marcar_espelho_feito      → espelhos_calendario
--     marcar_espelho_falhou     → espelhos_calendario
--
-- As outras nove — `conciliar_pagamento`, `responder_do_whatsapp`,
-- `expurgar_mensagens`, `marcar_pasta_enviada`, `marcar_pasta_falhou`,
-- `esquecer_contato_da_pesquisa` — são todas `auth = false, srv = true`:
-- webhook e cron, e ali a RLS não está no caminho.
--
-- E as duas do espelho também não mentem hoje, pelo mesmo teste:
-- `lib/calendario/sincronia.ts` usa `supabaseServico`, e o único chamador é o
-- cron `/api/mensageria`. O que sobra nelas é uma concessão larga demais —
-- `authenticated` tem `execute` numa função que nenhuma tela chama e que, se
-- fosse chamada, não faria nada. A concessão sai aqui, e com ela a varredura
-- fica limpa em vez de ficar com duas exceções para alguém decorar.
--
-- O corpo veio de `pg_get_functiondef` do BANCO (lei 6).
-- =====================================================================

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
  -- Pela porta que funciona. `esquecer_contato` e `security invoker`, e
  -- `links_do_paciente` nao tem policy de escrita: a 0066 decidiu que quem cria
  -- e revoga sao as funcoes. A 0076 acrescentou este `update` cru, que afeta
  -- zero linhas e nao levanta erro nenhum — e a frase de retorno diz que o link
  -- foi revogado. `revogar_link_do_paciente` e `security definer`, confere
  -- `conta_atual()` por dentro e e uma das funcoes que a 0066 escreveu para isso.
  perform public.revogar_link_do_paciente(p_paciente);

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
-- E as duas do espelho param de ser alcançáveis por quem não as chama.
--
-- Só o cron as chama, como `service_role`, e ali a RLS não está no caminho.
-- Manter `authenticated` com `execute` numa função que, chamada por ela,
-- afetaria zero linhas em silêncio é guardar a próxima ocorrência desta
-- migração dentro do banco.
revoke execute on function public.marcar_espelho_feito(uuid, text)  from authenticated;
revoke execute on function public.marcar_espelho_falhou(uuid, text) from authenticated;
