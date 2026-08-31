-- 0014 · O aceite reivindica antes de agir.
--
-- A 0012 fazia `select ... for update` na oferta e depois conferia o estado em
-- memória. Sob concorrência real isso funciona — no READ COMMITTED o
-- `FOR UPDATE` segue a cadeia de versões e a segunda sessão enxerga o estado
-- novo. Mas a correção passa a depender de uma sutileza do motor, e
-- **invariante que depende de sutileza não é invariante**: é uma aposta que
-- ninguém relê em seis meses.
--
-- Troca para o padrão "reivindica e depois age":
--
--   1. `update ... where id = ? and estado = 'enviada'` — atômico, e o
--      `row_count` diz quem ganhou. Duas sessões simultâneas: exatamente uma
--      recebe 1, a outra recebe 0 e erra.
--   2. só depois trava a vaga, confere que continua livre e cria a sessão.
--
-- Se qualquer passo seguinte falhar, a transação inteira volta atrás e a oferta
-- destrava sozinha. E a restrição de exclusão de `sessoes` continua como última
-- linha: mesmo que tudo o mais falhasse, duas pessoas na mesma hora é
-- impossível por construção.
--
-- Nota honesta: a corrida com duas conexões de verdade não foi exercitada em
-- teste — o `dblink` do Supabase exige senha que este ambiente não tem. Por
-- isso a mudança de desenho: a segurança passa a vir de um `row_count`, que se
-- verifica lendo, e não de uma semântica que só se verifica correndo.

create or replace function public.responder_oferta(p_oferta uuid, p_resposta text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  o record;
  s record;
  valor_do_paciente numeric(12,2);
  ganhou int;
begin
  if p_resposta not in ('aceita', 'recusada') then
    raise exception 'resposta precisa ser aceita ou recusada';
  end if;

  select * into o from public.ofertas where id = p_oferta;
  if not found then raise exception 'oferta não encontrada'; end if;

  -- ------------------------------------------------------------ recusa
  if p_resposta = 'recusada' then
    update public.ofertas
       set estado = 'recusada', respondida_em = now()
     where id = p_oferta and estado = 'enviada';
    get diagnostics ganhou = row_count;

    if ganhou = 0 then
      raise exception 'oferta já respondida (%)', o.estado;
    end if;

    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo)
    values (o.conta_id, o.sessao_id, p_oferta, 'oferta_recusada');

    perform public.avancar_fila(o.sessao_id);
    return 'recusada';
  end if;

  -- ------------------------------------------------------------ aceite
  -- PASSO 1: reivindica. Quem pegar o row_count = 1 ganhou a vaga.
  update public.ofertas
     set estado = 'aceita', respondida_em = now()
   where id = p_oferta and estado = 'enviada';
  get diagnostics ganhou = row_count;

  if ganhou = 0 then
    raise exception 'oferta já respondida (%)', o.estado;
  end if;

  -- PASSO 2: agora sim, com a oferta na mão.
  select * into s from public.sessoes where id = o.sessao_id for update;

  if s.estado not in ('cancelada_cedo', 'cancelada_tarde') then
    raise exception 'esta vaga não está mais aberta';
  end if;

  if not public.vaga_esta_livre(s.profissional_id, s.inicio, s.fim, s.id) then
    raise exception 'o horário deixou de estar livre';
  end if;

  -- Quem entra paga o próprio combinado, não o de quem desmarcou.
  select en.valor into valor_do_paciente
    from public.enquadres en
   where en.paciente_id = o.paciente_id and en.vigencia_fim is null;

  insert into public.sessoes (
    conta_id, profissional_id, paciente_id, inicio, fim,
    origem, estado, valor, politica_horas, politica_percentual
  )
  values (
    s.conta_id, s.profissional_id, o.paciente_id, s.inicio, s.fim,
    'encaixe', 'prevista',
    coalesce(valor_do_paciente, s.valor),
    s.politica_horas, s.politica_percentual
  );

  update public.ofertas
     set estado = 'cancelada', respondida_em = now()
   where sessao_id = o.sessao_id and estado = 'enviada' and id <> p_oferta;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (o.conta_id, o.sessao_id, p_oferta, 'oferta_aceita', '{}'::jsonb);

  insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
  values (o.conta_id, o.sessao_id, 'vaga_preenchida',
          jsonb_build_object('paciente_id', o.paciente_id,
                             'valor', coalesce(valor_do_paciente, s.valor)));

  return 'aceita';
end;
$$;

grant execute on function public.responder_oferta(uuid, text) to authenticated;
