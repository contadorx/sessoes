-- 0013 · Tira o fuso da sessão do caminho da materialização.
--
-- Armadilha encontrada escrevendo os testes da B7: no Postgres,
-- `date_trunc('week', <date>)` e `generate_series(<date>, <date>, interval)`
-- resolvem para a sobrecarga de **timestamptz**, não de timestamp. O `date` é
-- promovido usando o `TimeZone` da conexão — e a partir dali toda conta de dia
-- depende de uma configuração de sessão que ninguém controla.
--
-- Na 0006 isso ficava correto por acidente: os valores caem à meia-noite do
-- fuso da sessão e voltam para o mesmo dia no `::date`. Funciona hoje, com
-- qualquer TimeZone, e quebraria no dia em que alguém somasse meio dia à série
-- ou trocasse o passo. Regra do doc 05: fuso é decisão, não acidente.
--
-- A correção é um `::timestamp` que força a sobrecarga certa. Nada muda no
-- resultado — o teste da B5 continua verde —, mas a conta deixa de depender do
-- ambiente.

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
    -- `::timestamp` força a sobrecarga sem fuso: a série é de dias civis, e
    -- não de instantes lidos no TimeZone da conexão.
    select d::date as dia
      from generate_series(de::timestamp, ate::timestamp, interval '1 day') d
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

revoke execute on function public.materializar_enquadre(uuid) from public, anon, authenticated;
