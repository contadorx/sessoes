-- 0060e · A exportação deixou de se registrar na trilha.
--
-- Terceira reescrita de função defeituosa nesta mesma build, e as três pela
-- mesma causa: **eu li a migração e não o banco.**
--
--   · a 0060b consertou variável que colidia com coluna;
--   · a 0060d devolveu a `enfileirar_mensagem` a `avancar_fila`;
--   · esta devolve a `exportar_conta` as duas linhas do fim, que gravam na
--     `trilha_acesso` que a conta foi exportada.
--
-- O corpo que eu copiei foi o da 0059c — a versão certa —, mas **eu o copiei do
-- arquivo, e o arquivo eu li truncado**: parei em `'trilha_acesso'`, que é a
-- última chave do objeto, sem ver que depois do `into saida` vinha um `insert`
-- e só então o `return`.
--
-- ## Por que isto importa mais do que parece
--
-- A trilha é a única coisa deste produto que **não é editável nem por quem está
-- sendo acusado** — é o que a página `/seguranca` diz e o que o `claude/15`
-- promete em voz alta: *"se um dia alguém alegar que houve acesso indevido, o
-- registro que responde não é editável por quem está sendo acusado."*
--
-- Exportar a conta inteira é a operação que tira **todo** o prontuário de
-- dentro do sistema, num arquivo. É a operação da lista que mais precisa
-- aparecer na trilha, e foi a que parou de aparecer.
--
-- Não é hipótese: o plano de resposta a incidente (`claude/26`, cenário C)
-- manda "ler a trilha" para delimitar o que foi acessado. Com este defeito no
-- ar, uma exportação feita por alguém com login não deixaria linha nenhuma —
-- e o cenário C responderia "ninguém acessou nada".
--
-- ## E foi a suíte 0024 que pegou, de novo
--
-- É a segunda vez seguida que a verificação da LGPD encontra o defeito de uma
-- build que não era sobre LGPD: na 0059b ela achou dezessete tabelas fora da
-- exportação, e aqui achou a trilha que não se grava. **O critério de regressão
-- continua sendo "que funções a migração reescreve", e não "que assunto ela
-- trata"** — e `exportar_conta` foi reescrita nas duas.
--
-- Esta migração é a 0060 com o `insert` de volta, e nada mais.

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
  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

comment on function public.exportar_conta() is
  'Portabilidade da conta inteira. Toda tabela com conta_id entra — a suite 0024 compara o corpo desta funcao com o information_schema e falha na proxima esquecida. Ficam de fora apenas segredos operacionais (sync_token, token de aceite e de remarcacao). E ela SE REGISTRA na trilha: a 0060 perdeu o insert e a suite 0024 verificacao 11 pegou.';
