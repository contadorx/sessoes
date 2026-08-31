-- 0007 · A materialização cede ao horário já ocupado.
--
-- A restrição de exclusão da 0006 torna agenda dupla impossível — inclusive
-- para o próprio motor. Aparece no reajuste feito no mesmo dia da semana da
-- sessão: o enquadre antigo é fechado hoje (e a sessão de hoje continua de pé,
-- porque já estava combinada nos termos antigos), o novo começa hoje, e os dois
-- disputam o mesmo horário.
--
-- A regra: **o motor cede**. Ele nunca briga com a restrição — se o horário já
-- está ocupado por uma sessão viva daquele profissional, ele simplesmente não
-- materializa aquela ocorrência. Assim o reajuste no mesmo dia funciona, a
-- sessão de hoje mantém o valor combinado, e a semana seguinte já sai no valor
-- novo.

create or replace function public.materializar_enquadre(p_enquadre uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  de date;
  ate date;
  criadas int := 0;
begin
  select en.*, p.profissional_id, p.conta_id as conta
    into e
    from public.enquadres en
    join public.pacientes p on p.id = en.paciente_id
   where en.id = p_enquadre;

  if not found then return 0; end if;

  de  := greatest(public.hoje_sp(), e.vigencia_inicio);
  ate := least(public.hoje_sp() + (public.janela_semanas() * 7),
               coalesce(e.vigencia_fim, date '9999-12-31'));

  -- Limpa previsões que não deveriam existir: fora da vigência, fora da janela,
  -- ou cobertas por exceção. Nunca toca no que já aconteceu.
  delete from public.sessoes s
   where s.enquadre_id = p_enquadre
     and s.origem = 'recorrencia'
     and s.estado = 'prevista'
     and s.inicio >= (public.hoje_sp()::timestamp at time zone 'America/Sao_Paulo')
     and (
       (s.inicio at time zone 'America/Sao_Paulo')::date not between de and ate
       or exists (
         select 1 from public.excecoes_agenda x
          where x.profissional_id = e.profissional_id
            and (s.inicio at time zone 'America/Sao_Paulo')::date between x.inicio and x.fim
       )
     );

  if e.vigencia_fim is not null and e.vigencia_fim < public.hoje_sp() then
    return 0;
  end if;

  with ocorrencias as (
    select d::date as dia
      from generate_series(de, ate, interval '1 day') d
     where extract(dow from d) = e.dia_semana
  ),
  candidatas as (
    select o.dia,
           ((o.dia + e.hora) at time zone 'America/Sao_Paulo') as inicio,
           ((o.dia + e.hora) at time zone 'America/Sao_Paulo')
             + make_interval(mins => e.duracao_min) as fim
      from ocorrencias o
     where not exists (
       select 1 from public.excecoes_agenda x
        where x.profissional_id = e.profissional_id
          and o.dia between x.inicio and x.fim
     )
  )
  insert into public.sessoes (
    conta_id, profissional_id, paciente_id, enquadre_id,
    inicio, fim, origem, estado, valor, politica_horas, politica_percentual
  )
  select
    e.conta, e.profissional_id, e.paciente_id, e.id,
    c.inicio, c.fim,
    'recorrencia', 'prevista', e.valor, e.politica_horas, e.politica_percentual
  from candidatas c
  where c.inicio >= now()
    -- O motor cede: horário já ocupado por sessão viva não é disputado.
    and not exists (
      select 1
        from public.sessoes s2
       where s2.profissional_id = e.profissional_id
         and s2.estado in ('prevista', 'confirmada', 'realizada', 'falta')
         and tstzrange(s2.inicio, s2.fim, '[)') && tstzrange(c.inicio, c.fim, '[)')
    )
  on conflict (enquadre_id, inicio) where origem = 'recorrencia' do nothing;

  get diagnostics criadas = row_count;
  return criadas;
end;
$$;

revoke execute on function public.materializar_enquadre(uuid) from public, anon;
