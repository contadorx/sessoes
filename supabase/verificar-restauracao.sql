-- A prova de que o restore voltou inteiro.
--
-- Rodar no SQL Editor da base **restaurada**, não na de produção.
-- Levanta exceção no primeiro furo. Silêncio = passou.
--
-- O que se verifica aqui não é "tem dado". Dado quase sempre volta. O que some
-- num restore mal feito são as **defesas**: RLS desligada, política que não
-- veio, gatilho ausente, extensão faltando. Uma base restaurada sem gatilho
-- continua respondendo a todas as telas — e para de classificar cancelamento,
-- de recalcular destino de mensagem e de gerar cobrança. Ninguém percebe até o
-- primeiro cancelamento tardio não ser cobrado.

do $$
declare
  faltando text;
  n int;
begin
  -- ------------------------------------------------- 1. as tabelas existem
  select string_agg(t, ', ') into faltando
    from unnest(array[
      'contas','usuarios','profissionais','pacientes','enquadres','sessoes',
      'excecoes_agenda','fila_encaixe','ofertas','eventos_fila','mensagens',
      'mensagens_recebidas','cobrancas','trilha_acesso','interessados',
      'documentos','contratos','aceites'
    ]) as t
   where to_regclass('public.' || t) is null;

  if faltando is not null then
    raise exception 'RESTORE INCOMPLETO — faltam tabelas: %', faltando;
  end if;

  -- --------------------------------------- 2. RLS ligada em todas elas
  -- Uma tabela restaurada com RLS desligada não dá erro em lugar nenhum: ela
  -- só devolve os dados de todo mundo para qualquer um.
  select string_agg(c.relname, ', ') into faltando
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

  if faltando is not null then
    raise exception 'SEM RLS — tabelas abertas: %', faltando;
  end if;

  -- ------------------------------------------ 3. as políticas voltaram
  -- RLS ligada e zero política é uma tabela fechada; RLS ligada com política
  -- errada é pior. Aqui se confere a presença; as suítes de teste conferem o
  -- comportamento.
  select string_agg(t, ', ') into faltando
    from unnest(array[
      'pacientes','enquadres','sessoes','fila_encaixe','ofertas',
      'eventos_fila','mensagens','cobrancas','trilha_acesso',
      'documentos','contratos','aceites'
    ]) as t
   where not exists (
     select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = t
   );

  if faltando is not null then
    raise exception 'SEM POLÍTICA — RLS ligada sem regra em: %', faltando;
  end if;

  -- ------------------------------------------ 4. as funções voltaram
  select string_agg(f, ', ') into faltando
    from unnest(array[
      'conta_atual','papel_atual','hoje_sp','proximo_envio',
      'materializar_conta','materializar_enquadre','cancelar_sessao',
      'abrir_vaga','avancar_fila','responder_oferta','expirar_ofertas',
      'elegiveis_para_vaga','vaga_esta_livre','taxa_de_preenchimento',
      'enfileirar_mensagem','reservar_mensagens','marcar_enviada',
      'marcar_falha','desistir_mensagem','destravar_mensagens',
      'responder_do_whatsapp','interpretar_resposta','marcar_entregue',
      'multa_da_politica','perdoar_cobranca','marcar_cobranca_paga',
      'registrar_acesso','arquivar_paciente','esquecer_contato',
      'exportar_paciente','exportar_conta','expurgar_mensagens',
      'emitir_documento','cancelar_documento','conciliar_pagamento',
      'agendar_lembretes','agendar_regua','regua_pendente',
      'publicar_contrato','preparar_aceite','montar_contrato',
      'contrato_por_token','aceitar_contrato','registrar_aceite_presencial',
      'revogar_aceite','reais','rotulo_horario','rotulo_politica'
    ]) as f
   where not exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f
   );

  if faltando is not null then
    raise exception 'FALTAM FUNÇÕES: %', faltando;
  end if;

  -- ------------------------------------------ 5. os gatilhos voltaram
  -- São eles que carregam as invariantes que não podem ser burladas. Sem eles a
  -- base funciona e mente.
  select string_agg(g, ', ') into faltando
    from unnest(array[
      'sessoes_transicao','sessoes_retrato','sessoes_geram_cobranca',
      'mensagens_retrato','trilha_carimbada','pacientes_arquivados',
      'pacientes_conta','enquadres_conta','enquadres_materializa',
      'excecoes_materializa','fila_conta_derivada',
      'documentos_imutaveis','contratos_imutaveis','contratos_carimbo',
      'aceites_montagem','aceites_congelamento'
    ]) as g
   where not exists (
     select 1 from pg_trigger t
      where not t.tgisinternal and t.tgname = g
   );

  if faltando is not null then
    raise exception 'FALTAM GATILHOS: % — a base responde, mas não aplica as regras', faltando;
  end if;

  -- ------------------------------------------ 6. os índices das invariantes
  select string_agg(i, ', ') into faltando
    from unnest(array[
      'enquadre_aberto_unico','mensagens_idem','cobranca_viva_por_sessao',
      'recebidas_do_provedor','documentos_numero','contratos_versao',
      'contrato_rascunho_unico','aceite_vivo_do_enquadre'
    ]) as i
   where to_regclass('public.' || i) is null;

  if faltando is not null then
    raise exception 'FALTAM ÍNDICES DE INVARIANTE: %', faltando;
  end if;

  -- ------------------------------------------ 7. a extensão da exclusão
  -- Sem btree_gist, a restrição que torna impossível duas pessoas no mesmo
  -- horário simplesmente não existe.
  if not exists (select 1 from pg_extension where extname = 'btree_gist') then
    raise exception 'FALTA btree_gist — duas pessoas na mesma hora voltou a ser possível';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.sessoes'::regclass and contype = 'x'
  ) then
    raise exception 'FALTA a restrição de exclusão em sessoes';
  end if;

  raise notice 'ESTRUTURA OK — tabelas, RLS, políticas, funções, gatilhos, índices e extensões voltaram.';
end $$;

-- ---------------------------------------------------------------- as contagens
--
-- Compare com o que você anotou antes do restore. Diferença aqui não é
-- necessariamente erro (o backup é de um instante anterior), mas **zero onde
-- havia dado é sempre erro**.

select 'contas' as tabela, count(*) from public.contas
union all select 'profissionais', count(*) from public.profissionais
union all select 'pacientes', count(*) from public.pacientes
union all select 'enquadres', count(*) from public.enquadres
union all select 'sessoes', count(*) from public.sessoes
union all select 'ofertas', count(*) from public.ofertas
union all select 'eventos_fila', count(*) from public.eventos_fila
union all select 'mensagens', count(*) from public.mensagens
union all select 'cobrancas', count(*) from public.cobrancas
union all select 'contratos', count(*) from public.contratos
union all select 'aceites', count(*) from public.aceites
union all select 'trilha_acesso', count(*) from public.trilha_acesso
union all select 'auth.users', count(*) from auth.users
order by 1;
