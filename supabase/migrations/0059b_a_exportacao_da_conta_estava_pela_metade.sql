-- 0059b · a exportação da conta estava pela metade, havia meses.
--
-- **Achado escrevendo o P5, e ele não é do P5.**
--
-- A 0059 cria `usos_do_alerta`, uma tabela com `conta_id`. A regra do projeto,
-- escrita no diário desde a B28, é que *"quando uma feature nova cria tabela com
-- dado da conta, as duas exportações mudam — e a que parece trivial é a que se
-- esquece"*. Fui acrescentá-la a `exportar_conta` e descobri que **dezessete**
-- tabelas com `conta_id` não estavam lá.
--
-- A consulta que mostra isso cabe em cinco linhas, e nunca tinha sido feita:
--
--     select c.table_name from information_schema.columns c
--      where c.table_schema = 'public' and c.column_name = 'conta_id'
--        and pg_get_functiondef('public.exportar_conta()'::regprocedure)
--            not like '%public.' || c.table_name || ' %';
--
-- O que estava de fora, e por que cada uma dói:
--
--   · **`documentos`** — recibos, declarações e informes **emitidos**, com
--     numeração queimada e guarda de cinco anos. É o que ela mais precisa levar,
--     e era o que ficava para trás;
--   · **`janelas_atendimento`** (P1) — a semana que ela declarou, que é o
--     denominador de toda métrica do produto;
--   · **`propostas_de_cobranca`** (P4) — as decisões dela sobre cobrar ou não,
--     com motivo escrito. Nasceram ontem e já estavam fora;
--   · **`pacotes`, `pacote_consumos`, `remarcacoes`** — dinheiro e crédito;
--   · **`mensagens`, `mensagens_recebidas`** — o que saiu para cada paciente e o
--     que voltou. É a prova de que um aviso foi dado;
--   · **`fila_entrada`, `vagas_fixas`, `ofertas_fixas`** — a história das duas
--     filas, que é metade do produto;
--   · **`usuarios`** — quem tem acesso à conta e com que permissão;
--   · **`assinaturas`, `faturas`, `avisos_assinatura`, `eventos_pagamento`** — a
--     relação comercial dela **comigo**. Ficaram de fora porque eu pensava nelas
--     como "minhas"; são dados pessoais dela tanto quanto os outros, e recusar
--     devolvê-los seria cobrar de alguém e não lhe dar o extrato.
--
-- **Por que passou.** `exportar_conta` foi escrita na B13, quando havia doze
-- tabelas. Cada build depois dela acrescentou tabela e ninguém voltou lá — e
-- nenhuma suíte reprovava, porque as verificações de LGPD conferem tabela por
-- tabela, **por lista**: uma tabela nova nunca reprova uma lista da qual não faz
-- parte. É exatamente o que o diário já registrou sobre as tabelas do Panorama,
-- e desta vez aconteceu dentro do maquinário, e não fora dele.
--
-- **A correção que importa não é esta migração — é a verificação.** A suíte 0024
-- ganha uma varredura que compara `information_schema` com o corpo da função e
-- falha na próxima tabela esquecida. Sem ela, esta migração seria só o conserto
-- de hoje.
--
-- **O que continua de fora, e é decisão escrita:**
--
--   · `calendarios.sync_token` e `aceites.token` — segredos operacionais, já
--     removidos desde a 0040c e a 0031. Levar o token do provedor num arquivo
--     que ela vai guardar no computador é dar a chave junto com a casa;
--   · as tabelas do Panorama — não têm `conta_id` e não são dela, por desenho.

create or replace function public.exportar_conta()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  saida jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o armário do consultório.',
    'conta', (select to_jsonb(x) from public.contas x where x.id = c),
    'usuarios', (select coalesce(jsonb_agg(to_jsonb(u) - 'conta_id'), '[]'::jsonb)
                   from public.usuarios u where u.conta_id = c),
    'profissionais', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                        from public.profissionais p where p.conta_id = c),
    'pacientes', (select coalesce(jsonb_agg(to_jsonb(p) order by p.nome), '[]'::jsonb)
                    from public.pacientes p where p.conta_id = c),
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                    from public.enquadres e where e.conta_id = c),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.conta_id = c),
    'excecoes_agenda', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                          from public.excecoes_agenda x where x.conta_id = c),
    'janelas_atendimento', (select coalesce(jsonb_agg(to_jsonb(ja) - 'conta_id'
                                            order by ja.dia_semana, ja.inicio), '[]'::jsonb)
                              from public.janelas_atendimento ja where ja.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'fila_entrada', (select coalesce(jsonb_agg(to_jsonb(fe) - 'conta_id'), '[]'::jsonb)
                       from public.fila_entrada fe where fe.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'vagas_fixas', (select coalesce(jsonb_agg(to_jsonb(vf) - 'conta_id'), '[]'::jsonb)
                      from public.vagas_fixas vf where vf.conta_id = c),
    'ofertas_fixas', (select coalesce(jsonb_agg(to_jsonb(of2) - 'conta_id'), '[]'::jsonb)
                        from public.ofertas_fixas of2 where of2.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'remarcacoes', (select coalesce(jsonb_agg(to_jsonb(rm) - 'conta_id'
                                    order by rm.criado_em), '[]'::jsonb)
                      from public.remarcacoes rm where rm.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'propostas_de_cobranca', (select coalesce(jsonb_agg(to_jsonb(pr) - 'conta_id'
                                              order by pr.criado_em), '[]'::jsonb)
                                from public.propostas_de_cobranca pr where pr.conta_id = c),
    'pacotes', (select coalesce(jsonb_agg(to_jsonb(pk) - 'conta_id'), '[]'::jsonb)
                  from public.pacotes pk where pk.conta_id = c),
    'pacote_consumos', (select coalesce(jsonb_agg(to_jsonb(pcs) - 'conta_id'), '[]'::jsonb)
                          from public.pacote_consumos pcs where pcs.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'documentos', (select coalesce(jsonb_agg(to_jsonb(dc) - 'conta_id'
                                   order by dc.criado_em), '[]'::jsonb)
                     from public.documentos dc where dc.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'eventos_pagamento', (select coalesce(jsonb_agg(to_jsonb(ep) - 'conta_id'
                                          order by ep.criado_em), '[]'::jsonb)
                            from public.eventos_pagamento ep where ep.conta_id = c),
    'mensagens', (select coalesce(jsonb_agg(to_jsonb(m) - 'conta_id'
                                  order by m.criado_em), '[]'::jsonb)
                    from public.mensagens m where m.conta_id = c),
    'mensagens_recebidas', (select coalesce(jsonb_agg(to_jsonb(mr) - 'conta_id'
                                            order by mr.criado_em), '[]'::jsonb)
                              from public.mensagens_recebidas mr where mr.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'calendarios', (select coalesce(jsonb_agg(to_jsonb(cl) - 'conta_id' - 'sync_token'), '[]'::jsonb)
                      from public.calendarios cl where cl.conta_id = c),
    'ocupacoes_externas', (select coalesce(jsonb_agg(to_jsonb(oc) - 'conta_id' order by oc.inicio), '[]'::jsonb)
                             from public.ocupacoes_externas oc where oc.conta_id = c),
    'espelhos_calendario', (select coalesce(jsonb_agg(to_jsonb(ec) - 'conta_id' order by ec.criado_em), '[]'::jsonb)
                              from public.espelhos_calendario ec where ec.conta_id = c),
    'registros', (select coalesce(jsonb_agg(to_jsonb(rg) - 'conta_id' order by rg.criado_em), '[]'::jsonb)
                    from public.registros rg where rg.conta_id = c),
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev2) - 'conta_id' order by ev2.criado_em), '[]'::jsonb)
                    from public.evolucoes ev2 where ev2.conta_id = c),
    'anamneses', (select coalesce(jsonb_agg(to_jsonb(an) - 'conta_id' order by an.criado_em), '[]'::jsonb)
                    from public.anamneses an where an.conta_id = c),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad where ad.conta_id = c),

    -- A relação comercial dela comigo. Cobrar de alguém e não lhe dar o extrato
    -- é o tipo de omissão que só se percebe do lado de fora.
    'assinaturas', (select coalesce(jsonb_agg(to_jsonb(asg) - 'conta_id'
                                    order by asg.criado_em), '[]'::jsonb)
                      from public.assinaturas asg where asg.conta_id = c),
    'faturas', (select coalesce(jsonb_agg(to_jsonb(ft) - 'conta_id'
                                order by ft.competencia), '[]'::jsonb)
                  from public.faturas ft where ft.conta_id = c),
    'avisos_assinatura', (select coalesce(jsonb_agg(to_jsonb(av) - 'conta_id'
                                          order by av.criado_em), '[]'::jsonb)
                            from public.avisos_assinatura av where av.conta_id = c),

    -- Quantas vezes cada alerta foi usado. É medida do produto, e mesmo assim
    -- sai: coletar sobre alguém e não devolver é a definição do que este
    -- arquivo existe para não ser.
    'usos_do_alerta', (select coalesce(jsonb_agg(to_jsonb(ua) - 'conta_id'), '[]'::jsonb)
                         from public.usos_do_alerta ua where ua.conta_id = c),

    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

comment on function public.exportar_conta() is
  'Portabilidade da conta inteira. Toda tabela com conta_id entra — a suite 0024 compara o corpo desta funcao com o information_schema e falha na proxima esquecida. Ficam de fora apenas segredos operacionais (sync_token, token de aceite).';
