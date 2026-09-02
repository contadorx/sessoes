-- 0060c · A faixa não multiplica por quem não atende.
--
-- Defeito da 0060, encontrado escrevendo a verificação 6 da suíte — que é o
-- lugar onde os defeitos deste projeto costumam aparecer, e é o argumento para
-- a suíte existir.
--
-- `faixa_da_conta` contava **todos** os profissionais da conta, e
-- `public.profissionais` tem uma coluna `ativo` desde a 0002. Uma clínica que
-- desligou duas profissionais continuava com a faixa das quatro: o número
-- inflava a favor da cliente, e por isso ninguém reclamaria — o que é
-- exatamente o tipo de erro que fica anos no ar.
--
-- E ele erra dos dois lados, porque a faixa também é a base da conversa de
-- upgrade: `contas_acima_da_faixa()` deixaria de me mostrar uma conta que
-- **está** acima, porque o denominador dela estava contando gente que não
-- atende. Um número que erra a favor de quem lê é pior do que um que erra
-- contra, porque ninguém o corrige.
--
-- A frase da coluna já dizia "POR PROFISSIONAL QUE ATENDE". Era verdade no
-- comentário e mentira no `where`.

create or replace function public.faixa_da_conta(p_conta uuid)
returns table (
  tem_faixa     boolean,
  limite        integer,
  profissionais integer,
  limite_total  integer,
  usadas        integer,
  restantes     integer,
  acima         boolean,
  pct           integer,
  e_fair_use    boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim      integer;
  fair     boolean;
  n_prof   integer;
  n_sess   integer;
  total    integer;
  mes_ini  date := date_trunc('month', public.hoje_sp())::date;
  mes_fim  date := (date_trunc('month', public.hoje_sp()) + interval '1 month')::date;
  papel    text := coalesce(current_setting('role', true), 'none');
begin
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'a faixa é da conta de quem pergunta';
  end if;

  select pl.limite_sessoes_mes, pl.faixa_e_fair_use
    into lim, fair
    from public.planos pl
    join public.contas ct on ct.plano = pl.codigo
   where ct.id = p_conta;

  -- `and pr.ativo`, e é a correção inteira desta migração. O `greatest(..., 1)`
  -- fica: uma conta que desligou todo mundo tem a faixa de uma pessoa, e não
  -- uma faixa de zero — que faria `acima` ser verdade para quem não atendeu.
  select greatest(count(*), 1)::integer into n_prof
    from public.profissionais pr
   where pr.conta_id = p_conta
     and pr.ativo;

  select count(*)::integer into n_sess
    from public.sessoes se
   where se.conta_id = p_conta
     and (se.inicio at time zone 'America/Sao_Paulo')::date >= mes_ini
     and (se.inicio at time zone 'America/Sao_Paulo')::date <  mes_fim
     and se.estado <> 'cancelada_cedo';

  if lim is null then
    return query select false, null::integer, n_prof, null::integer,
                        n_sess, null::integer, false, 0, coalesce(fair, false);
    return;
  end if;

  total := lim * n_prof;

  return query select
    true,
    lim,
    n_prof,
    total,
    n_sess,
    greatest(total - n_sess, 0),
    n_sess > total,
    least(999, (100 * n_sess / greatest(total, 1)))::integer,
    fair;
end;
$$;

comment on function public.faixa_da_conta(uuid) is
  'Quanto da faixa de sessoes o mes corrente ja gastou. NAO barra nada — e a unidade de preco, medida e dita. `cancelada_cedo` fica de fora: sessao desmarcada no prazo nao foi vendida. Multiplica so por profissional ATIVO (0060c). As variaveis de mes levam prefixo desde a 0060b: `fim` sozinho colide com sessoes.fim.';

revoke execute on function public.faixa_da_conta(uuid) from public, anon;
grant  execute on function public.faixa_da_conta(uuid) to authenticated;
