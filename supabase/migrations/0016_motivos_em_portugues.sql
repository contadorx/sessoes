-- 0016 · Os motivos da fila, escritos como aparecem na tela.
--
-- Deriva do meu próprio processo, e o teste da B7 pegou: as migrations vinham
-- sendo aplicadas com os acentos removidos, enquanto o arquivo do repositório
-- os tinha. Nas policies isso era cosmético; aqui não — estes textos são
-- **conteúdo de produto**: é o que a psicóloga lê ao lado de cada nome quando
-- a fila explica por que alguém ficou de fora.
--
-- A lei do doc 05 diz que nada se aplica no Supabase que não esteja no repo. A
-- leitura correta é mais forte: o que se aplica tem de ser **idêntico** ao que
-- está no repo. Daqui em diante, migration se aplica verbatim.

create or replace function public.elegiveis_para_vaga(p_sessao uuid)
returns table (
  paciente_id uuid,
  nome text,
  elegivel boolean,
  motivo text,
  ordem bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with vaga as (
    select s.id, s.conta_id, s.profissional_id, s.inicio, s.fim,
           c.regra_prioridade
      from public.sessoes s
      join public.contas c on c.id = s.conta_id
     where s.id = p_sessao
  ),
  candidatos as (
    select
      f.paciente_id,
      p.nome,
      f.prioridade,
      f.entrou_em,
      f.janelas,
      f.topa_antecipar,
      p.estado as estado_paciente,
      p.msg_canal,
      v.*,
      (select max(s2.inicio)
         from public.sessoes s2
        where s2.paciente_id = f.paciente_id
          and s2.estado = 'realizada'
          and s2.inicio < now()) as ultima_sessao,
      exists (
        select 1 from public.sessoes s3
         where s3.paciente_id = f.paciente_id
           and s3.estado in ('prevista', 'confirmada')
           and s3.inicio >= v.inicio - interval '3 days'
           and s3.inicio <= v.inicio + interval '3 days'
      ) as tem_sessao_por_perto,
      exists (
        select 1 from public.sessoes s4
         where s4.paciente_id = f.paciente_id
           and s4.estado in ('prevista', 'confirmada', 'realizada')
           and tstzrange(s4.inicio, s4.fim, '[)') && tstzrange(v.inicio, v.fim, '[)')
      ) as ocupado_na_hora,
      (select o.estado from public.ofertas o
        where o.sessao_id = p_sessao and o.paciente_id = f.paciente_id) as ja_ofertado
    from public.fila_encaixe f
    join public.pacientes p on p.id = f.paciente_id
    cross join vaga v
   where f.ativo
     and f.conta_id = v.conta_id
  )
  select
    c.paciente_id,
    c.nome,
    (c.motivo_calculado is null) as elegivel,
    coalesce(c.motivo_calculado, 'na fila') as motivo,
    row_number() over (
      order by
        (c.motivo_calculado is null) desc,
        c.prioridade desc,
        case when c.regra_prioridade = 'mais_tempo_sem_sessao'
             then coalesce(c.ultima_sessao, '-infinity'::timestamptz) end asc,
        c.entrou_em asc
    ) as ordem
  from (
    select cc.*,
      case
        when cc.estado_paciente = 'pausa'                           then 'em pausa'
        when cc.estado_paciente in ('alta','encerrado','arquivado') then 'não está em atendimento'
        when cc.msg_canal = 'nao_avisar'                            then 'pediu para não ser avisado'
        when cc.ja_ofertado = 'recusada'                            then 'já recusou esta vaga'
        when cc.ja_ofertado is not null                             then 'já recebeu esta oferta'
        when cc.ocupado_na_hora                                     then 'já tem sessão nesse horário'
        when not public.cabe_na_janela(cc.janelas, cc.inicio)       then 'fora da janela'
        when not cc.topa_antecipar and cc.tem_sessao_por_perto      then 'não quer antecipar'
        else null
      end as motivo_calculado
    from candidatos cc
  ) c
  order by ordem;
$$;

grant execute on function public.elegiveis_para_vaga(uuid) to authenticated;
