-- =====================================================================
-- 0052d · A lista de "estados vivos" estava em três lugares, e um ficou para trás
-- =====================================================================
--
-- A 0052 acrescentou o estado `suspensa`. E a resposta à pergunta *"esta conta
-- tem assinatura viva?"* estava escrita à mão em três funções diferentes:
--
--     abrir_assinatura   →  estado in ('trial', 'ativa', 'em_atraso')
--     mudar_plano        →  estado in ('trial', 'ativa', 'em_atraso')
--     painel_do_negocio  →  estado in ('trial', 'ativa', 'em_atraso')
--
-- A 0052 corrigiu a segunda, porque estava mexendo nela. As outras duas não —
-- e a primeira é a que guarda a invariante *"uma assinatura viva por conta"*,
-- que existe desde a OP1.
--
-- O buraco, exatamente: uma conta suspensa por falta de pagamento não tem, para
-- `abrir_assinatura`, nenhuma assinatura viva. Abrir outra passa. A conta fica
-- com duas — uma suspensa devendo, outra ativa — e a partir daí `valor_da_conta`
-- e o MRR passam a somar sobre uma base que não deveria existir. Quem faria
-- isso? Eu, tentando resolver na mão um caso que a régua já tinha suspendido.
--
-- **Regra que ficou, e é a terceira vez que este projeto a aprende:** quando
-- uma pergunta de domínio aparece escrita em mais de um lugar, ela diverge no
-- dia em que alguém acrescenta um valor. A resposta não é lembrar dos três
-- lugares — é a lista virar função, do mesmo jeito que `causas_de_churn()`
-- virou nesta mesma migração, e que `contas_para_fechar` virou na B25.
--
-- E `painel_do_negocio` fica de fora da correção **de propósito**: uma conta
-- suspensa não é receita, e somá-la ao MRR seria contar dinheiro que não
-- entrou. Lá a lista continua sendo a das que pagam. São duas perguntas
-- diferentes que pareciam a mesma, e é por isso que a função nova se chama
-- `assinatura_viva_da_conta` e não `estados_vivos`.
-- =====================================================================

/**
 * A assinatura viva de uma conta — a resposta à pergunta "já tem uma?".
 *
 * `suspensa` conta como viva: ela existe, tem dívida pendurada e volta ao ar no
 * dia em que a fatura for paga. Só `cancelada` está morta.
 */
create or replace function public.assinatura_viva_da_conta(p_conta uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.id
    from public.assinaturas a
   where a.conta_id = p_conta
     and a.estado in ('trial', 'ativa', 'em_atraso', 'suspensa')
   limit 1;
$$;

create or replace function public.abrir_assinatura(
  p_conta uuid,
  p_plano text,
  p_ciclo text default 'mensal',
  p_origem text default 'painel',
  p_valor_centavos integer default null,
  p_trial boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare o_plano record; nova uuid; valor integer;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select codigo, preco_centavos, ativo into o_plano
    from public.planos where codigo = p_plano;

  if o_plano.codigo is null then
    raise exception 'plano % não existe no cardápio', p_plano; end if;
  if not o_plano.ativo then
    raise exception 'plano % está fora do cardápio', p_plano; end if;

  valor := coalesce(p_valor_centavos, o_plano.preco_centavos);
  if valor < 0 then raise exception 'valor negativo'; end if;

  -- A pergunta virou função. Antes esta lista estava escrita aqui à mão, e a
  -- 0052 acrescentou `suspensa` sem que ela soubesse.
  if public.assinatura_viva_da_conta(p_conta) is not null then
    raise exception 'esta conta já tem assinatura viva — cancele a atual antes de abrir outra';
  end if;

  insert into public.assinaturas
    (conta_id, plano_codigo, estado, valor_centavos, ciclo, origem, proximo_vencimento)
  values (p_conta, p_plano,
    case when p_trial then 'trial' else 'ativa' end,
    valor, p_ciclo, p_origem,
    case when p_ciclo = 'anual' then public.hoje_sp() + interval '1 year'
         else public.hoje_sp() + interval '1 month' end)
  returning id into nova;

  update public.contas set plano = p_plano where id = p_conta;
  return nova;
end;
$$;

/** E `mudar_plano` passa a perguntar pela mesma porta. */
create or replace function public.mudar_plano(p_conta uuid, p_plano text, p_motivo text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare atual uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  atual := public.assinatura_viva_da_conta(p_conta);

  if atual is not null then
    perform public.cancelar_assinatura(
      atual,
      coalesce(nullif(btrim(p_motivo), ''), 'mudança de plano'),
      'mudanca_de_plano');
  end if;

  return public.abrir_assinatura(p_conta, p_plano);
end;
$$;

revoke execute on function public.assinatura_viva_da_conta(uuid) from public, anon;
grant execute on function public.assinatura_viva_da_conta(uuid) to authenticated;
