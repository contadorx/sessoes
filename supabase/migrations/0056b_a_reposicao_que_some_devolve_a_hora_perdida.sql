/**
 * 0056b · a reposição que some devolve a hora perdida
 *
 * A suíte da 0056 achou isto na limpeza dela, o que é o lugar mais barato
 * possível — mas o defeito é de produção, e é sério.
 *
 * `reposta_por` foi declarada `on delete set null`, e o check
 * `sessoes_reposta_aponta` exige `(eixo_capacidade = 'reposta') = (reposta_por
 * is not null)`. As duas coisas se contradizem no instante em que a sessão que
 * **repôs** a hora deixa de existir: o `set null` tenta zerar o ponteiro, o
 * check recusa a linha, e o `delete` inteiro falha.
 *
 * ONDE ISSO DOERIA
 *
 * `sessoes.paciente_id` é `on delete cascade`. Então apagar um paciente que
 * algum dia desmarcou e remarcou faria a exclusão **estourar** — e a exclusão
 * de paciente não é um botão qualquer: é o direito de eliminação do titular
 * (LGPD, art. 18), com minuta própria no doc 18. Uma obrigação legal falhando
 * com "violates check constraint" é o pior lugar para descobrir uma
 * contradição de modelagem.
 *
 * A ESCOLHA, E ELA É DE DOUTRINA E NÃO DE CONSTRAINT
 *
 * A saída fácil seria afrouxar o check. Não: ele é a invariante 3 da 0056 —
 * `reposta` sem apontar para nada é linha que não conta história nenhuma.
 *
 * A saída certa é responder à pergunta que o `set null` faz: **o que aconteceu
 * com aquela hora, agora que a hora que a repôs não existe mais?** E a resposta
 * é a única honesta: ela voltou a ser hora perdida. A reposição era justamente
 * o fato de outra hora ter sido consumida com o mesmo dinheiro; sumindo a
 * outra hora, sobra a perda.
 *
 * O `valor_reconhecido` vai junto para zero, que já era o valor dela como
 * reposta — explicitar aqui é o que impede um caminho futuro de deixar receita
 * pendurada numa hora que ninguém prestou.
 *
 * `before` de propósito: o check roda depois dos gatilhos `before`, então
 * corrigir aqui é corrigir antes de ele olhar.
 */
create or replace function public.reposicao_que_some_vira_perda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.reposta_por is null
     and old.reposta_por is not null
     and new.eixo_capacidade = 'reposta' then
    new.eixo_capacidade   := 'perdida';
    new.valor_reconhecido := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists sessoes_reposicao_some on public.sessoes;
create trigger sessoes_reposicao_some
  before update of reposta_por on public.sessoes
  for each row execute function public.reposicao_que_some_vira_perda();

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.reposicao_que_some_vira_perda() from public, anon, authenticated;
