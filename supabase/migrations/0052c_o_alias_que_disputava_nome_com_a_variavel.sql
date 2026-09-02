-- =====================================================================
-- 0052c · O alias de uma letra que disputava nome com a variável
-- =====================================================================
--
-- A `passar_a_regua_das_assinaturas` da 0052 declarava `f record` para os dois
-- laços, e uma das consultas dela usava `f` como **alias de tabela**:
--
--     update public.assinaturas a
--        set estado = 'em_atraso'
--      where a.estado in ('ativa', 'trial')
--        and exists (
--          select 1 from public.faturas f              -- ← o alias
--           where f.assinatura_id = a.id               -- ← e aqui
--             and f.estado = 'vencida'
--        );
--
-- Dentro de uma função plpgsql, `f.assinatura_id` é resolvido **primeiro contra
-- as variáveis declaradas** e só depois contra os aliases do SQL. O `f` da
-- consulta virou o `f record` da função, e o erro foi:
--
--     record "f" is not assigned yet
--
-- Desta vez o banco gritou, porque o record ainda não tinha sido atribuído. **A
-- versão perigosa deste mesmo defeito é a silenciosa**: se o laço já tivesse
-- rodado uma vez, `f` estaria preenchido, `f.assinatura_id` teria um valor
-- perfeitamente válido — o da iteração anterior — e o `exists` compararia a
-- fatura errada sem reclamar de nada. A régua marcaria em atraso a assinatura
-- errada, ou nenhuma, e o sintoma apareceria como "a cobrança não roda direito".
--
-- É a mesma família das armadilhas de record da B20, da B24 e da B25, com a
-- peça trocada: lá o problema era ler campo de record não atribuído porque o
-- plpgsql não curto-circuita; aqui é o **nome** do record capturar um alias de
-- SQL que nunca quis falar com ele.
--
-- **Regra que ficou:** dentro de plpgsql, variável e alias vivem no mesmo
-- espaço de nomes, e a variável ganha. Toda variável declarada numa função que
-- contém SQL leva prefixo (`v_`), e nenhum alias de tabela tem uma letra só.
-- Custa seis caracteres e fecha uma classe inteira de defeito que, na forma
-- silenciosa, é indistinguível de uma regra de negócio errada.
--
-- Foi a verificação 5 da suíte 0052 que pegou, na primeira execução.
-- =====================================================================

create or replace function public.passar_a_regua_das_assinaturas()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vencidas   integer := 0;
  v_atraso     integer := 0;
  v_avisos     integer := 0;
  v_suspensas  integer := 0;
  v_fatura     record;
  v_conta      record;
  v_degrau     record;
  v_hoje       date := public.hoje_sp();
begin
  -- 1 · a fatura pendente cujo vencimento passou vira vencida.
  update public.faturas set estado = 'vencida'
   where estado = 'pendente' and vencimento < v_hoje;
  get diagnostics v_vencidas = row_count;

  -- 2 · a assinatura viva com fatura vencida entra em atraso.
  --
  -- O alias virou `fat`. Nenhum alias de uma letra dentro de plpgsql.
  update public.assinaturas a
     set estado = 'em_atraso'
   where a.estado in ('ativa', 'trial')
     and exists (
       select 1 from public.faturas fat
        where fat.assinatura_id = a.id and fat.estado = 'vencida'
     );
  get diagnostics v_atraso = row_count;

  -- 3 · os avisos, um por degrau por fatura.
  for v_fatura in
    select fat.id as fatura, fat.conta_id, fat.vencimento, fat.competencia,
           (v_hoje - fat.vencimento) as dias
      from public.faturas fat
      join public.contas ct on ct.id = fat.conta_id
      join public.assinaturas ass on ass.id = fat.assinatura_id
     where fat.estado = 'vencida'
       and not ct.is_teste
       and ass.origem <> 'cortesia'
  loop
    for v_degrau in
      select * from public.regua_da_assinatura() where dias <= v_fatura.dias
    loop
      insert into public.avisos_assinatura (conta_id, fatura_id, degrau, assunto, corpo)
      values (v_fatura.conta_id, v_fatura.fatura, v_degrau.degrau,
              v_degrau.assunto, v_degrau.corpo)
      on conflict (fatura_id, degrau) do nothing;

      if found then v_avisos := v_avisos + 1; end if;
    end loop;
  end loop;

  -- 4 · a suspensão, e ela é o plano Grátis de volta.
  for v_conta in
    select distinct ass.id as assinatura, ass.conta_id
      from public.assinaturas ass
      join public.contas ct on ct.id = ass.conta_id
      join public.faturas fat on fat.assinatura_id = ass.id
     where ass.estado = 'em_atraso'
       and fat.estado = 'vencida'
       and not ct.is_teste
       and ass.origem <> 'cortesia'
       and (v_hoje - fat.vencimento) >= public.dias_para_suspender()
  loop
    update public.assinaturas set estado = 'suspensa' where id = v_conta.assinatura;
    -- A decisão inteira cabe nesta linha: a conta volta ao piso, e o piso foi
    -- desenhado para ser habitável.
    update public.contas set plano = 'gratis' where id = v_conta.conta_id;
    v_suspensas := v_suspensas + 1;
  end loop;

  return jsonb_build_object(
    'dia', v_hoje,
    'faturas_vencidas', v_vencidas,
    'assinaturas_em_atraso', v_atraso,
    'avisos_criados', v_avisos,
    'contas_suspensas', v_suspensas
  );
end;
$$;

revoke execute on function public.passar_a_regua_das_assinaturas() from public, anon, authenticated;
grant execute on function public.passar_a_regua_das_assinaturas() to service_role;
