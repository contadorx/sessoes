/**
 * 0056e · o link do paciente também abre a vaga
 *
 * **Este defeito é de produção, não é do P2, e é o mais sério que uma regressão
 * já encontrou neste projeto.** A suíte 0035 o denunciou na verificação 15,
 * enquanto eu conferia se o livro-razão tinha quebrado alguma coisa.
 *
 * O SINTOMA
 *
 * Quando o paciente remarca **pelo link** — o caminho que o produto anuncia, e
 * o único que não exige a psicóloga na frente da tela —, a hora que vagou
 * **não era oferecida para a fila**. Nenhum erro, nenhum aviso: a remarcação
 * respondia `ok`, a agenda trocava, e o buraco ficava lá.
 *
 * Remarcando presencialmente (com ela logada) funcionava. Ou seja: a peça que
 * diferencia o produto — *"um buraco fechado, um buraco oferecido"* — estava
 * desligada exatamente no fluxo em que ela mais vale.
 *
 * A CADEIA
 *
 * `escolher_remarcacao` chama `abrir_vaga` dentro de um
 * `begin ... exception when others then null`, e o comentário de lá explica por
 * quê: *"a fila não pode derrubar a remarcação"*. Está certo — a troca de hora
 * é o que o paciente pediu, e ela tem de acontecer mesmo que a fila falhe.
 *
 * Só que esse `null` engoliu um erro real: `abrir_vaga` → `avancar_fila` →
 * `teto_da_conta`, que desde a 0046b recusa responder quando quem pergunta não
 * é a conta dona do teto:
 *
 *     if papel not in ('service_role','none')
 *        and p_conta is distinct from public.conta_atual()
 *        and not public.e_operador() then
 *       raise exception 'o teto é da conta de quem pergunta';
 *
 * No caminho do link não existe sessão nenhuma: `conta_atual()` é **nulo**, o
 * papel é `anon`, e a comparação falha contra qualquer conta. A guarda da 0046b
 * foi escrita para impedir que **alguém logado** sondasse o plano de outra
 * conta — e ela nunca considerou o caso de não haver ninguém logado.
 *
 * A CORREÇÃO, E POR QUE ELA NÃO ABRE BURACO
 *
 * A exceção é estreita: **sem sessão nenhuma, a pergunta passa.** Não é
 * afrouxar a guarda para usuário logado — para ele tudo continua igual, e a
 * verificação da 0046b continua valendo.
 *
 * E o anônimo não ganha nada com isso, porque `teto_da_conta` **não é executável
 * por `anon`** (a 0046c a revoga, e este arquivo revoga de novo). O único jeito
 * de chegar até ela sem sessão é por dentro de uma função `security definer` —
 * e essas, no caminho do link, já validaram um token que prova de qual sessão
 * se trata antes de tocar em qualquer coisa.
 *
 * O QUE ESTE ARQUIVO **NÃO** FAZ
 *
 * Não tira o `exception when others then null` da `escolher_remarcacao`. Ele
 * continua certo pelo motivo que o comentário original dá. O que ele deixa de
 * esconder é este erro — porque a causa foi corrigida, não silenciada de novo.
 *
 * A lição fica escrita: **`exception when others then null` é uma decisão de
 * produto, e toda decisão dessas precisa de um teste que prove que o caminho
 * feliz acontece.** A verificação 15 da 0035 é esse teste, e ela existia — o
 * que faltava era rodá-la depois da build do teto.
 *
 * Corpo copiado da definição viva (`pg_get_functiondef`), com esta única
 * mudança.
 */
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
  -- A mudança da 0056e: `conta_atual() is null` significa "não há sessão
  -- nenhuma", e aí a comparação não protege ninguém — só quebra o caminho do
  -- link. Para quem está logado, a guarda da 0046b continua inteira.
  if papel not in ('service_role', 'none')
     and public.conta_atual() is not null
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
     and m.enviada_em is not null
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date >= ini;

  return query select
    true,
    lim,
    n,
    greatest(lim - n, 0),
    n >= lim,
    least(100, (100 * n / greatest(lim, 1)))::integer;
end;
$$;

-- O anônimo continua sem poder perguntar direto. É isso que faz a exceção
-- acima ser estreita: sem sessão só se chega aqui por dentro de uma função
-- `security definer` que já validou um token.
revoke execute on function public.teto_da_conta(uuid) from public, anon;
grant execute on function public.teto_da_conta(uuid) to authenticated;
