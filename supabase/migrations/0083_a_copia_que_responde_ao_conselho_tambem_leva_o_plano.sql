-- =====================================================================
-- 0083 · A cópia que responde ao Conselho também leva o plano terapêutico
-- =====================================================================
--
-- A 0082 pôs `objetivos` em `exportar_conta()` e fechou a verificação 15 da
-- suíte `0024_lgpd.sql`. Ela fechou **metade** do defeito.
--
-- `exportar_paciente()` — a cópia que ela entrega quando o CRP pede, ou quando
-- a paciente pede a dela — carrega enquadres, sessões, cobranças, registro,
-- anamnese, adendos e evoluções. Das seis tabelas com `le_clinico()` na
-- policy, cinco. `objetivos` não estava lá.
--
-- ## Por que esta metade é a pior
--
-- `eliminar_conta()` (0062) **não tem lista**: ela varre o `information_schema`
-- e apaga tudo. E antes de apagar exige uma exportação nas últimas 24 h, com
-- esta frase:
--
--     "o arquivo que você exportou é a sua cópia, e é ele que responde se o
--      Conselho pedir"
--
-- Então o produto: obriga a tirar a cópia, promete que a cópia responde ao
-- Conselho, e apaga o plano terapêutico — que a própria 0072 classificou na
-- linha 27 como *"Camada: clínico. Objetivo terapêutico é conteúdo do
-- prontuário."* A eliminação varre e leva tudo; a exportação lista e deixa
-- para trás. **A assimetria entre as duas é o defeito**, e ela é exatamente a
-- lei 7: o lado que enumera esquece, o lado que varre não.
--
-- ## A varredura que faltava, e que é o conserto de verdade
--
-- A 0024 verificação 15 varre `information_schema` para `exportar_conta` e não
-- tinha irmã do lado clínico — `exportar_paciente` não tinha varredura
-- nenhuma. A suíte `0083` acrescenta a que faltava, e a regra é simples de
-- enunciar e impossível de esquecer:
--
--     toda tabela com `le_clinico()` na policy sai em `exportar_paciente`
--
-- `trilha_acesso` fica de fora por decisão: é o registro de **quem leu**, é da
-- conta e não do paciente, e sai em `exportar_conta`. Pôr a trilha na cópia da
-- paciente entregaria a ela o histórico de acessos da psicóloga.
--
-- O corpo veio de `pg_get_functiondef` do BANCO (lei 6), com o bloco de
-- `objetivos` ao lado de `evolucoes`.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.exportar_paciente(p_paciente uuid, p_ciente_da_restricao boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    'registro', (select to_jsonb(rg) - 'conta_id' - 'profissional_id'
                   from public.registros rg where rg.paciente_id = p_paciente),
    'anamnese', (select to_jsonb(an) - 'conta_id' - 'profissional_id'
                   from public.anamneses an where an.paciente_id = p_paciente),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad
                           join public.anamneses an2 on an2.id = ad.anamnese_id
                          where an2.paciente_id = p_paciente),
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev) - 'conta_id' order by ev.criado_em), '[]'::jsonb)
                    from public.evolucoes ev
                   where ev.paciente_id = p_paciente and ev.camada = 'prontuario'),
    'objetivos', (select coalesce(jsonb_agg(to_jsonb(ob) - 'conta_id' order by ob.criado_em), '[]'::jsonb)
                    from public.objetivos ob
                   where ob.paciente_id = p_paciente),
    'nota_sobre_o_que_nao_esta_aqui',
      'O Registro Documental (art. 1º, Res. CFP 001/2009) — testes, protocolos e material de acesso exclusivo da psicóloga — não integra esta cópia.'
  ) into saida;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'exportou_paciente',
          jsonb_build_object('restricao_judicial', pac.restricao_judicial));

  return saida;
end;
$function$
;
