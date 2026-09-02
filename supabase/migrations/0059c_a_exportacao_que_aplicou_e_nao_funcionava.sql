-- 0059c · a exportação que aplicou e não funcionava.
--
-- A 0059b foi aplicada com sucesso e **quebrou `exportar_conta` para todo
-- mundo**. Quatro `order by` apontavam para colunas que não existem —
-- `remarcacoes.criado_em` (é `criada_em`), `documentos.criado_em` (é
-- `emitido_em`), `eventos_pagamento.criado_em` (é `recebido_em`) e
-- `mensagens_recebidas.criado_em` (é `recebida_em`).
--
-- **A lição é sobre o que "aplicou com sucesso" significa.** `create or replace
-- function` em plpgsql **não valida nomes de coluna do corpo**: o SQL de dentro
-- só é analisado na primeira execução. Uma migração de função pode entrar
-- inteira, sem um aviso, e estar quebrada. A 0040f ensinou que `drop constraint`
-- + `add constraint` reescreve o todo; a OP2 ensinou que `create or replace` é
-- `drop` + `create` disfarçado. Esta acrescenta a terceira: **migração de função
-- não está aplicada enquanto alguém não a chamar** — e quem chamou foi a
-- verificação 11 da suíte 0024, três minutos depois.
--
-- Duas correções, e a segunda não é de digitação:
--
--   · os quatro `order by`;
--   · **`remarcacoes.token` sai da exportação.** Ele abre a página pública que
--     remarca a sessão de um paciente. A 0059b o teria colocado num arquivo que
--     ela guarda no computador e manda por e-mail para o contador — mesma
--     família do `aceites.token` e do `calendarios.sync_token`, que já saem
--     desde a 0031 e a 0040c, e que eu lembrei dos dois e esqueci do terceiro.

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
    -- `criada_em`, e não `criado_em`. E **sem o token**: o link mágico da
    -- remarcação abre uma página que remarca a sessão de alguém, e ele não
    -- viaja num arquivo que ela vai guardar no computador. Mesma regra do
    -- `aceites.token` desde a 0031.
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
