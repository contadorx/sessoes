-- 0060b · A variável que disputava nome com a coluna.
--
-- A 0060 aplicou com `{"success": true}` e deixou **três funções quebradas em
-- runtime**: `faixa_da_conta`, `contas_acima_da_faixa` (que a chama por lateral)
-- e `registrar_avaliacao`. Todas com o mesmo erro:
--
--     column reference "fim" is ambiguous
--     DETAIL: It could refer to either a PL/pgSQL variable or a table column.
--
-- **`public.sessoes` tem uma coluna chamada `fim`** — desde a 0006, e é o fim do
-- horário da sessão. As duas funções declaravam `fim date` para marcar o fim do
-- mês e depois consultavam `public.sessoes`, e o plpgsql resolve contra a
-- variável.
--
-- ## É a quarta vez, e a lição precisa mudar de forma
--
-- A 0052c registrou o alias de uma letra disputando nome com a variável; a
-- suíte 0024 repetiu com `t`; a 0056 teve a sua. Todas foram anotadas como
-- **"não use alias de uma letra"** — e essa formulação é o motivo de o defeito
-- ter voltado hoje: aqui não há alias nenhum. Os aliases desta função são
-- `pl`, `ct`, `pr`, `se`, todos de duas letras, todos escolhidos justamente por
-- causa da lição anterior. O que colidiu foi a **variável**.
--
-- A lição certa é mais larga e é esta:
--
--   > **Em plpgsql, variável declarada e coluna de qualquer tabela do `from`
--   > dividem o mesmo espaço de nomes, e a variável ganha.** Não é sobre
--   > aliases. É sobre toda palavra curta e genérica — `fim`, `inicio`,
--   > `nota`, `valor`, `estado`, `plano` —, que são exatamente os nomes que
--   > uma variável de conveniência recebe **e** os nomes que uma coluna de
--   > domínio recebe.
--
-- A regra operacional que fica: **variável local de função que consulta tabela
-- leva prefixo** — `mes_ini`, `mes_fim`, `v_nota`. É feio e é barato, e o que
-- ele compra é que o nome não pode colidir com uma coluna que alguém vai criar
-- daqui a três migrações.
--
-- ## E a lição da 0059c se confirma pela terceira vez
--
-- Nada disto apareceu na aplicação. `create or replace function` em plpgsql não
-- analisa o corpo: as três funções entraram inteiras, com `success: true`, e só
-- quebraram quando alguém as chamou. **Migração de função não está aplicada
-- enquanto alguém não a chamar** — e quem chamou, hoje, foi o passo 2 do
-- roteiro de aplicação, que existe por causa da 0059b.
--
-- Nada além dos nomes das duas variáveis muda nesta migração.

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

  select greatest(count(*), 1)::integer into n_prof
    from public.profissionais pr
   where pr.conta_id = p_conta;

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
  'Quanto da faixa de sessoes o mes corrente ja gastou. NAO barra nada — e a unidade de preco, medida e dita. `cancelada_cedo` fica de fora: sessao desmarcada no prazo nao foi vendida. As variaveis de mes levam prefixo desde a 0060b: `fim` sozinho colide com sessoes.fim.';

create or replace function public.registrar_avaliacao(
  p_nota    smallint,
  p_texto   text default null,
  p_momento text default 'perfil'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c        uuid := public.conta_atual();
  v_plano  text;
  v_sess   integer;
  v_dias   integer;
  novo     uuid;
  mes_ini  date := date_trunc('month', public.hoje_sp())::date;
  mes_fim  date := (date_trunc('month', public.hoje_sp()) + interval '1 month')::date;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_nota is null or p_nota < 0 or p_nota > 10 then
    raise exception 'a nota vai de 0 a 10';
  end if;

  select ct.plano, greatest(0, (public.hoje_sp() - ct.criado_em::date))
    into v_plano, v_dias
    from public.contas ct where ct.id = c;

  select count(*)::integer into v_sess
    from public.sessoes se
   where se.conta_id = c
     and (se.inicio at time zone 'America/Sao_Paulo')::date >= mes_ini
     and (se.inicio at time zone 'America/Sao_Paulo')::date <  mes_fim
     and se.estado <> 'cancelada_cedo';

  insert into public.avaliacoes (conta_id, nota, texto, momento, plano, sessoes_no_mes, dias_de_uso)
  values (c, p_nota, nullif(btrim(coalesce(p_texto, '')), ''), p_momento, v_plano, v_sess, v_dias)
  returning id into novo;

  return novo;
end;
$$;

revoke execute on function public.faixa_da_conta(uuid) from public, anon;
grant  execute on function public.faixa_da_conta(uuid) to authenticated;
revoke execute on function public.registrar_avaliacao(smallint, text, text) from public, anon;
grant  execute on function public.registrar_avaliacao(smallint, text, text) to authenticated;
