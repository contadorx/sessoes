-- 0032 · B19 — o contrato entra nas duas portabilidades.
--
-- Uma tabela nova que não entra na exportação é um dado que existe e que a
-- pessoa não consegue levar. Aqui isso seria pior que uma omissão técnica: o
-- contrato aceito é justamente o documento que o paciente tem direito de
-- receber (PR12, direito de acesso da Res. CFP 001/2009) e que ela tem direito
-- de levar embora se sair do produto (LGPD, portabilidade dos dois lados,
-- doc 07). Deixar de fora seria guardar a prova e devolver o resto.
--
-- **O token não sai em nenhuma das duas.** Ele não é um dado, é uma chave: um
-- link de aceite ainda pendente continua funcionando, e um arquivo exportado
-- circula — vai para o e-mail do contador, para o computador novo, para a nuvem
-- de alguém. Quem tivesse o arquivo poderia aceitar um contrato no lugar da
-- pessoa. O texto, a data, quem aceitou e de onde: tudo isso vai. O endereço da
-- porta, não.

create or replace function public.exportar_paciente(
  p_paciente uuid,
  p_ciente_da_restricao boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  saida jsonb;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  if pac.restricao_judicial and not coalesce(p_ciente_da_restricao, false) then
    raise exception 'há restrição judicial nesta ficha: confirme que você conhece a decisão antes de exportar';
  end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Cópia de documento sigiloso. Res. CFP 001/2009.',
    'paciente', to_jsonb(pac) - 'conta_id' - 'profissional_id',
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e) - 'conta_id'), '[]'::jsonb)
                    from public.enquadres e where e.paciente_id = p_paciente),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) - 'conta_id' - 'profissional_id' order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.paciente_id = p_paciente),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(c) - 'conta_id'), '[]'::jsonb)
                    from public.cobrancas c where c.paciente_id = p_paciente),
    -- O texto exato de cada combinado aceito, com a data. É o que a pessoa
    -- pediria se pedisse "uma cópia do que eu assinei".
    'combinados_por_escrito',
      (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
         from public.aceites a where a.paciente_id = p_paciente)
  ) into saida;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'exportou_paciente',
          jsonb_build_object('restricao_judicial', pac.restricao_judicial));

  return saida;
end;
$$;

create or replace function public.exportar_conta()
returns jsonb
language plpgsql
security invoker
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
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

-- Os três, sempre. `create or replace` reabre o EXECUTE a PUBLIC.
revoke execute on function public.exportar_paciente(uuid, boolean) from public, anon;
revoke execute on function public.exportar_conta() from public, anon;
grant  execute on function public.exportar_paciente(uuid, boolean) to authenticated;
grant  execute on function public.exportar_conta() to authenticated;
