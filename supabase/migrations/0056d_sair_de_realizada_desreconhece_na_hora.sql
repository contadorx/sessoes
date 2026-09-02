/**
 * 0056d · sair de "realizada" desreconhece na hora
 *
 * A regressão inteira apontou para o mesmo lugar, e o defeito é meu: quatro
 * suítes verdes (0009, 0022, 0033 e 0041) passaram a falhar com
 *
 *   new row for relation "sessoes" violates check constraint
 *   "sessoes_reconhecido_so_prestada"
 *
 * sempre no mesmo movimento — uma sessão **saindo** de `realizada` para `falta`
 * ou para `prevista`.
 *
 * O QUE ESTAVA ERRADO
 *
 * A invariante 2 da 0056 está certa: receita reconhecida só existe para hora
 * prestada. O que estava errado era **onde ela era cobrada**.
 *
 * `valor_reconhecido` é derivado, e quem o deriva é `recalcular_eixos`, chamada
 * por um gatilho `after`. Só que uma `check constraint` é avaliada **antes**
 * disso: no instante do `update`, a linha já tem `estado = 'falta'` e ainda tem
 * `valor_reconhecido = 200`. O banco olha, vê a contradição e recusa — antes de
 * o gatilho ter chance de desfazê-la.
 *
 * Ou seja: eu escrevi uma regra sobre uma coluna derivada e a cobrei num
 * momento em que a derivação ainda não tinha acontecido. A linha estava
 * momentaneamente inconsistente **por construção**, e a constraint fazia o
 * trabalho dela.
 *
 * A CORREÇÃO, E POR QUE NÃO É AFROUXAR O CHECK
 *
 * A saída fácil seria remover a constraint e confiar no gatilho. Não: ela é o
 * que protege contra escrita direta pelo PostgREST — a verificação 5 da suíte
 * 0056 prova isso, tentando reconhecer receita de uma sessão futura por `update`
 * e sendo recusada.
 *
 * A correção é tornar a linha **válida no instante em que o check olha**: um
 * gatilho `before` que zera o reconhecido no mesmo movimento em que o estado
 * deixa de ser `realizada`. Não é remendo para o check passar — é a invariante
 * acontecendo **de forma síncrona**, que é mais forte do que acontecer logo
 * depois. Desfez a realização, a receita some no mesmo instante.
 *
 * O `after` continua existindo e continua recalculando tudo: este gatilho
 * resolve só a meia-linha que o check enxergava, e o resto do livro-razão
 * (capacidade, financeiro, fiscal) segue vindo de `recalcular_eixos`.
 *
 * A LIÇÃO, PARA A PRÓXIMA
 *
 * **Coluna derivada por gatilho `after` não se cobra em `check constraint`
 * junto com a coluna que a deriva.** Ou a derivação sobe para um `before`, ou a
 * regra vira gatilho de validação — mas as duas no mesmo `update` só convivem
 * se quem escreve o valor rodar antes de quem o confere.
 */
create or replace function public.sair_de_realizada_desreconhece()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.estado is distinct from 'realizada'
     and coalesce(new.valor_reconhecido, 0) <> 0 then
    new.valor_reconhecido := case
      -- Ainda não resolveu: volta a ser "não sei", e não zero.
      when public.eixo_agenda(new.estado) = 'reservada' then null
      else 0
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists sessoes_desreconhecem on public.sessoes;
create trigger sessoes_desreconhecem
  before update of estado on public.sessoes
  for each row execute function public.sair_de_realizada_desreconhece();

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.sair_de_realizada_desreconhece() from public, anon, authenticated;
