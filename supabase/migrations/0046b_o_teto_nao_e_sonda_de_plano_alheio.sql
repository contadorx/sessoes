-- 0046b · O teto não é sonda de plano alheio.
--
-- A 0046 escreveu `teto_da_conta(p_conta uuid)` como `security definer`, sem
-- conferir nada por dentro, e concedeu EXECUTE a `authenticated` para a tela
-- dela poder mostrar o próprio consumo.
--
-- O resultado é uma sonda: qualquer pessoa logada, com um `conta_id` na mão,
-- faria `POST /rest/v1/rpc/teto_da_conta` e leria **quantas mensagens a
-- psicóloga da porta ao lado mandou este mês** — que é volume de atendimento,
-- ou seja, informação de negócio dela. `security definer` existe justamente
-- para passar por cima da RLS, e passar por cima da RLS sem conferir nada no
-- lugar dela é remover a tranca e não pôr outra.
--
-- É exatamente a lição da B7, quando `vaga_esta_livre` e `proximo_envio` eram
-- `definer` e respondiam sobre a agenda de qualquer conta para quem estivesse
-- logado. Lá a resposta foi virar `security invoker`. Aqui não dá: a função
-- precisa ler `planos` cruzando com `contas`, e é chamada também pelo worker,
-- que não tem sessão nenhuma. Então a conferência é à mão, e são três
-- chamadores legítimos:
--
--   · **ela**, pela tela, sobre a própria conta — `conta_atual()`;
--   · **o worker**, sem sessão, como `service_role` — é ele quem barra;
--   · **eu**, pelo painel do negócio — `e_operador()`.
--
-- Qualquer outro recebe exceção, e não zero: devolver zero silenciosamente
-- transformaria uma tentativa de bisbilhotar num número plausível na tela de
-- quem tentou.
--
-- Achado antes de rodar a suíte, relendo a 0046 à procura de exatamente este
-- padrão — `definer` + parâmetro de id + grant para `authenticated` é a
-- assinatura do defeito, e vale procurá-la em toda migração que criar função.

create or replace function public.teto_da_conta(p_conta uuid)
returns table (
  tem_teto boolean,
  limite integer,
  usadas integer,
  restantes integer,
  estourou boolean,
  pct integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim integer;
  n integer;
  ini date := date_trunc('month', public.hoje_sp())::date;
  papel text := coalesce(current_setting('role', true), 'none');
begin
  -- A tranca que a 0046 esqueceu.
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'o teto é da conta de quem pergunta';
  end if;

  select p.limite_mensagens_mes into lim
    from public.planos p join public.contas c on c.plano = p.codigo
   where c.id = p_conta;

  if lim is null then
    return query select false, null::integer, 0, null::integer, false, 0;
    return;
  end if;

  select count(*)::integer into n
    from public.mensagens m
    join public.templates t on t.codigo = m.template
   where m.conta_id = p_conta
     and not t.essencial
     and m.estado in ('enviando', 'enviada', 'entregue', 'barrada_no_teto')
     and (m.atualizado_em at time zone 'America/Sao_Paulo')::date >= ini;

  return query select
    true,
    lim,
    n,
    greatest(lim - n, 0),
    n >= lim,
    least(100, (100 * n / greatest(lim, 1)))::integer;
end;
$$;

revoke execute on function public.teto_da_conta(uuid) from public, anon;
grant execute on function public.teto_da_conta(uuid) to authenticated;

comment on function public.teto_da_conta(uuid) is
  'O teto do plano da conta e quanto ja foi gasto. Conta so mensagem NAO-essencial. So responde para a propria conta, para o worker (service_role) e para o operador — definer com parametro de id e sem conferencia e sonda de conta alheia (licao da B7).';
