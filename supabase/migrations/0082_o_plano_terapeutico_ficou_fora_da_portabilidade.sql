-- =====================================================================
-- 0082 · O plano terapêutico ficou fora da portabilidade
-- =====================================================================
--
-- Achado rodando a suíte `0024_lgpd.sql`, na verificação 15:
--
--     '15 FUROU: tabela(s) com conta_id fora da portabilidade: objetivos —
--      quem cria tabela com dado da conta acrescenta a exportação na mesma
--      build'
--
-- A 0072 criou `objetivos` — o plano terapêutico, com a data de revisão — e
-- não acrescentou a tabela a `exportar_conta()`. Das 42 tabelas do `public`
-- com `conta_id`, 41 estavam lá e essa não.
--
-- ## Por que isso importa mais do que uma linha esquecida
--
-- `exportar_conta()` é a portabilidade da LGPD: o arquivo que ela leva embora
-- se decidir sair, e o mesmo que o cenário C do plano de incidente usa para
-- responder "quem levou o quê". Um plano terapêutico que não sai no arquivo
-- é registro clínico que **só existe aqui dentro** — o oposto do que a função
-- promete, e a promessa está escrita nela mesma:
--
--     'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o
--               armário do consultório.'
--
-- Um armário que não abre inteiro.
--
-- ## A quarta mordida da mesma família
--
-- O `CLAUDE.md` cita esta função pelo nome na **lei 7**: *"`exportar_conta`
-- esqueceu 17 tabelas porque a lista era de quando havia doze"*. Depois disso
-- a 0059b e a 0059c a consertaram duas vezes, e a 0060e devolveu o registro na
-- trilha que ela tinha perdido. Esta é a quarta.
--
-- **E o conserto não é a linha: é a varredura**, que já existe e é quem achou
-- isto — a verificação 15 da 0024 varre `information_schema` e compara com o
-- corpo da função. Ela estava escrita e nunca tinha sido executada. É por isso
-- que este defeito viveu desde a 0072 sem ninguém ver, e é o argumento inteiro
-- de rodar as suítes: nenhuma das quatro foi achada lendo código.
--
-- Não transformo o corpo numa varredura genérica de propósito. Cada bloco
-- carrega uma decisão que uma varredura apagaria: quais colunas saem
-- (`- 'conta_id'`), qual a ordem, e sobretudo **quais campos nunca viajam** —
-- `aceites.token`, `remarcacoes.token`, `calendarios.sync_token`,
-- `links_do_paciente.token`. Um link mágico dentro de um anexo de e-mail é uma
-- chave viva, e a 0031, a 0059c e a 0066b são as três vezes em que isso teve
-- de ser lembrado. A lista aqui é deliberada; quem varre é a suíte.
--
-- O corpo abaixo veio de `pg_get_functiondef` do BANCO (lei 6), com o bloco de
-- `objetivos` inserido ao lado de `evolucoes` — é onde o plano terapêutico
-- mora, junto do registro clínico.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.exportar_conta()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    'remarcacoes', (select coalesce(jsonb_agg(to_jsonb(rm) - 'conta_id' - 'token'
                                    order by rm.criada_em), '[]'::jsonb)
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
                                   order by dc.emitido_em), '[]'::jsonb)
                     from public.documentos dc where dc.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'eventos_pagamento', (select coalesce(jsonb_agg(to_jsonb(ep) - 'conta_id'
                                          order by ep.recebido_em), '[]'::jsonb)
                            from public.eventos_pagamento ep where ep.conta_id = c),
    'mensagens', (select coalesce(jsonb_agg(to_jsonb(m) - 'conta_id'
                                  order by m.criado_em), '[]'::jsonb)
                    from public.mensagens m where m.conta_id = c),
    'mensagens_recebidas', (select coalesce(jsonb_agg(to_jsonb(mr) - 'conta_id'
                                            order by mr.recebida_em), '[]'::jsonb)
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
    'objetivos', (select coalesce(jsonb_agg(to_jsonb(ob) - 'conta_id' order by ob.criado_em), '[]'::jsonb)
                    from public.objetivos ob where ob.conta_id = c),
    'anamneses', (select coalesce(jsonb_agg(to_jsonb(an) - 'conta_id' order by an.criado_em), '[]'::jsonb)
                    from public.anamneses an where an.conta_id = c),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad where ad.conta_id = c),
    'assinaturas', (select coalesce(jsonb_agg(to_jsonb(asg) - 'conta_id'
                                    order by asg.criado_em), '[]'::jsonb)
                      from public.assinaturas asg where asg.conta_id = c),
    'faturas', (select coalesce(jsonb_agg(to_jsonb(ft) - 'conta_id'
                                order by ft.competencia), '[]'::jsonb)
                  from public.faturas ft where ft.conta_id = c),
    'avisos_assinatura', (select coalesce(jsonb_agg(to_jsonb(av) - 'conta_id'
                                          order by av.criado_em), '[]'::jsonb)
                            from public.avisos_assinatura av where av.conta_id = c),
    'usos_do_alerta', (select coalesce(jsonb_agg(to_jsonb(ua) - 'conta_id'), '[]'::jsonb)
                         from public.usos_do_alerta ua where ua.conta_id = c),
    'avaliacoes', (select coalesce(jsonb_agg(to_jsonb(av2) - 'conta_id'
                                   order by av2.criada_em), '[]'::jsonb)
                     from public.avaliacoes av2 where av2.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  -- As duas linhas que a 0060 perdeu. Exportar a conta inteira é a operação que
  -- tira todo o prontuário do sistema num arquivo — é a que mais precisa deixar
  -- rastro, e o cenário C do plano de incidente depende dela para responder
  -- "quem levou o quê".
  -- **A tabela nova da 0066, e o `token` NÃO vai.** É a quarta vez desta
  -- família — `aceites.token` na 0031, `remarcacoes.token` na 0059c, a lista de
  -- campos ocultos da B33. A razão é sempre a mesma: a exportação é um arquivo
  -- que ela guarda no computador e manda por e-mail para o contador, e um link
  -- mágico dentro dele é uma chave viva num anexo.
  saida := saida || jsonb_build_object(
    'links_do_paciente',
    (select coalesce(jsonb_agg(to_jsonb(l) - 'token' order by l.criado_em), '[]'::jsonb)
       from public.links_do_paciente l where l.conta_id = c)
  );

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$function$
;
