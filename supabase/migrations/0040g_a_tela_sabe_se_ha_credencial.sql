-- 0040g · A tela precisa saber se existe credencial — sem ver a credencial.
--
-- A decisão 3 da 0040 é firme: `calendarios_segredo` não tem política nenhuma,
-- e nem a dona da conta lê a própria linha. Isso resolve o vazamento e cria um
-- problema de honestidade na tela: sem enxergar o segredo, o app não sabe
-- distinguir "conectado" de "configurado, mas sem autorização" — e mostraria
-- *ligado* para um calendário que não sincroniza coisa alguma.
--
-- A saída é a de sempre quando um dado é sensível e a resposta não é: devolver
-- **o fato, não o dado**. `calendario_do_profissional` ganha `tem_credencial`,
-- um booleano calculado dentro de uma função `definer` que olha a tabela
-- fechada e não devolve nada dela. A tela passa a poder dizer "falta autorizar"
-- em vez de mentir, e continua sem ter como ler um token.
--
-- Também entra `pendentes_antigas`: quantas linhas estão esperando para sair há
-- mais de um dia. Fila que só cresce é fila quebrada, e a diferença entre "duas
-- esperando" e "duas esperando desde a semana passada" é a diferença entre
-- normal e avariado.

create or replace function public.calendario_do_profissional(p_profissional uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  cal record;
  prof uuid := p_profissional;
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;

  if prof is null then
    select id into prof from public.profissionais
     where conta_id = c order by criado_em limit 1;
  end if;
  if prof is null then return jsonb_build_object('ligado', false); end if;

  -- `definer` obriga a conferir a conta na mão: sem isto, passar o uuid de um
  -- profissional de fora devolveria o painel dele. É a lição da 0015 aplicada
  -- a uma função que, ao contrário da `vaga_esta_livre`, não pode ser invoker
  -- (precisa enxergar a tabela do segredo).
  if not exists (
    select 1 from public.profissionais pr where pr.id = prof and pr.conta_id = c
  ) then
    raise exception 'esse profissional não é desta conta';
  end if;

  select * into cal from public.calendarios where profissional_id = prof;

  if not found then
    return jsonb_build_object('ligado', false, 'profissional_id', prof);
  end if;

  return jsonb_build_object(
    'ligado', cal.estado <> 'revogado',
    'profissional_id', prof,
    'calendario_id', cal.id,
    'estado', cal.estado,
    'direcao', cal.direcao,
    'modo_titulo', cal.modo_titulo,
    'email_externo', cal.email_externo,
    'sincronizado_em', cal.sincronizado_em,
    'lido_ate', cal.lido_ate,
    'erro', cal.erro,
    -- O fato, não o dado.
    'tem_credencial', exists (
      select 1 from public.calendarios_segredo s where s.calendario_id = cal.id),
    'ocupacoes', (select count(*) from public.ocupacoes_externas o
                   where o.calendario_id = cal.id and o.fim >= now()),
    'pendentes', (select count(*) from public.espelhos_calendario e
                   where e.calendario_id = cal.id and e.estado = 'pendente'),
    'pendentes_antigas', (select count(*) from public.espelhos_calendario e
                           where e.calendario_id = cal.id and e.estado = 'pendente'
                             and e.criado_em < now() - interval '1 day'),
    'falhados', (select count(*) from public.espelhos_calendario e
                  where e.calendario_id = cal.id and e.estado = 'falhou'),
    'espelhados', (select count(*) from public.espelhos_calendario e
                    where e.calendario_id = cal.id and e.estado = 'espelhada')
  );
end;
$$;

revoke execute on function public.calendario_do_profissional(uuid) from public, anon;
grant execute on function public.calendario_do_profissional(uuid) to authenticated;

comment on function public.calendario_do_profissional(uuid) is
  'Painel da tela. definer para poder responder SE existe credencial sem devolver a credencial; por isso confere conta_atual() na mao.';
