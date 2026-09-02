/**
 * 0053b · o alarme não pode tocar para quem não tem a obrigação
 *
 * A 0053 fez o gatilho parar de gerar pendência de Receita Saúde para conta PJ
 * e dispensou as que já existiam. Faltou o outro lado da mesma moeda: o campo
 * `ligado` de `receita_saude_do_ano` continuava respondendo só pelo
 * interruptor `contas.receita_saude`, sem perguntar o regime.
 *
 * Isso importa porque `ligado` não é decoração de tela — é o que o alarme de
 * fevereiro do menu lê para decidir se aparece. Uma conta PJ que tivesse ligado
 * o modo antes de virar PJ continuaria com o modo "ligado" para todo efeito, e
 * o dia em que o painel voltasse a somar qualquer coisa ali, ela veria um
 * aviso de prazo de uma obrigação que não tem.
 *
 * A regra é a mesma da 0053 e mora agora num lugar só: **o Receita Saúde está
 * ligado quando o interruptor está ligado E a conta é PF.** Uma conta PJ
 * responde `ligado: false` mesmo com o interruptor de pé — e o interruptor não
 * é apagado, porque voltar a PF é decisão dela e não deve custar remarcar
 * ajuste.
 *
 * O `regime` passa a vir junto na resposta, para a tela não precisar de uma
 * segunda consulta só para saber qual caminho desenhar.
 *
 * Corpo copiado da definição viva (`pg_get_functiondef`), com estas duas
 * mudanças e nada mais. `create or replace` é `drop` + `create` disfarçado, e o
 * jeito de não perder o que estava lá é partir do que estava lá.
 */
create or replace function public.receita_saude_do_ano(p_ano integer)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  cont record;
  prazo date;
  pend_n int := 0;   pend_v numeric := 0;
  emit_n int := 0;   emit_v numeric := 0;
  disp_n int := 0;   disp_v numeric := 0;
  venc_n int := 0;   venc_v numeric := 0;
  div_n  int := 0;
  sem_cpf int := 0;
  falta_n int := 0;  falta_v numeric := 0;
  por_mes jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_ano < 2000 or p_ano > 2100 then raise exception 'ano fora de faixa'; end if;

  select * into cont from public.contas where id = c;
  prazo := public.prazo_do_ano(p_ano);

  select
    count(*) filter (where estado = 'pendente'),
    coalesce(sum(valor) filter (where estado = 'pendente'), 0),
    count(*) filter (where estado = 'emitido'),
    coalesce(sum(valor) filter (where estado = 'emitido'), 0),
    count(*) filter (where estado = 'dispensado'),
    coalesce(sum(valor) filter (where estado = 'dispensado'), 0),
    count(*) filter (where estado = 'vencido'),
    coalesce(sum(valor) filter (where estado = 'vencido'), 0),
    count(*) filter (where divergente_em is not null and estado = 'emitido')
    into pend_n, pend_v, emit_n, emit_v, disp_n, disp_v, venc_n, venc_v, div_n
    from public.recibos_rfb
   where conta_id = c and extract(year from competencia)::int = p_ano;

  select count(*) into sem_cpf
    from public.recibos_rfb r
    join public.pacientes p on p.id = r.paciente_id
   where r.conta_id = c
     and extract(year from r.competencia)::int = p_ano
     and r.estado = 'pendente'
     and (p.cpf is null or length(p.cpf) <> 11);

  -- O que ficou de fora, e por quê. Some da obrigação, não da tela.
  select count(*), coalesce(sum(valor), 0)
    into falta_n, falta_v
    from public.cobrancas
   where conta_id = c and tipo = 'falta' and estado = 'paga' and paga_em is not null
     and extract(year from (paga_em at time zone 'America/Sao_Paulo')::date)::int = p_ano;

  select coalesce(jsonb_agg(x order by x->>'mes'), '[]'::jsonb)
    into por_mes
    from (
      select jsonb_build_object(
               'mes', to_char(competencia, 'YYYY-MM'),
               'pendentes', count(*) filter (where estado = 'pendente'),
               'emitidos', count(*) filter (where estado = 'emitido'),
               'vencidos', count(*) filter (where estado = 'vencido'),
               'valor', sum(valor)
             ) as x
        from public.recibos_rfb
       where conta_id = c and extract(year from competencia)::int = p_ano
         and estado <> 'cancelado'
       group by competencia
    ) g;

  return jsonb_build_object(
    'ano', p_ano,
    -- A mudança: PJ não tem esta obrigação, e portanto não tem este alarme.
    'ligado', coalesce(cont.receita_saude, false)
              and coalesce(cont.regime, 'pf') = 'pf',
    'regime', coalesce(cont.regime, 'pf'),
    'prazo', prazo,
    'dias_ate_o_prazo', (prazo - public.hoje_sp()),
    'pendentes',  jsonb_build_object('n', pend_n, 'valor', pend_v),
    'emitidos',   jsonb_build_object('n', emit_n, 'valor', emit_v),
    'dispensados', jsonb_build_object('n', disp_n, 'valor', disp_v),
    'vencidos',   jsonb_build_object('n', venc_n, 'valor', venc_v),
    'divergentes', div_n,
    'sem_cpf', sem_cpf,
    -- Piso, nunca estimativa. R$ 100 é o mínimo por recibo em atraso.
    'piso_multa', (pend_n + venc_n) * 100,
    'faltas_de_fora', jsonb_build_object('n', falta_n, 'valor', falta_v),
    'por_mes', por_mes
  );
end;
$$;
