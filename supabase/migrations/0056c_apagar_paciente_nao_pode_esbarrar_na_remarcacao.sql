/**
 * 0056c · apagar paciente não pode esbarrar na remarcação
 *
 * **Este defeito é de produção e não é da 0056 — ele existe desde a B21.** A
 * suíte do livro-razão o encontrou por acidente, tentando apagar a sessão que
 * repôs outra, e vale registrar em voz alta o que estava acontecendo.
 *
 * `remarcacoes.nova_sessao_id` é `on delete set null`, e o gatilho
 * `remarcacao_congela` recusa qualquer edição de uma remarcação já fechada —
 * `nova_sessao_id` inclusive. As duas regras juntas dizem: **a sessão que
 * nasceu de uma remarcação nunca pode ser apagada.** Qualquer `delete` nela
 * falha com "remarcação já fechada não se edita".
 *
 * ONDE ISSO DOÍA
 *
 * `sessoes.paciente_id` é `on delete cascade`. Então apagar um paciente que
 * algum dia remarcou fazia a exclusão **estourar** — e a exclusão de paciente é
 * o direito de eliminação do titular (LGPD art. 18), com minuta própria no doc
 * 18 e tela desde a B13. Uma obrigação legal quebrando por contradição entre
 * uma FK e um gatilho é o pior lugar possível para uma surpresa.
 *
 * Pior: numa cascata, se o Postgres apagasse antes a linha de `remarcacoes`
 * (pela FK `sessao_id`, que é `cascade`), o `delete` passaria. A ordem entre as
 * duas ações não é garantida — ou seja, o defeito é **intermitente**, do tipo
 * que some quando se vai investigar.
 *
 * A CORREÇÃO, E O QUE ELA PRESERVA
 *
 * Não é afrouxar o congelamento: ele existe para que ninguém reescreva o que
 * foi combinado com o paciente depois de fechado, e continua valendo para
 * `opcoes`, `token`, `escolhida_em`, `escolhido_inicio` e `origem`.
 *
 * A exceção é estreita e tem nome: **zerar `nova_sessao_id` porque a sessão
 * deixou de existir não é editar uma remarcação, é registrar que a hora nova
 * sumiu.** É o mesmo fato que a 0056b escreve do outro lado, quando devolve a
 * hora antiga para "perdida".
 *
 * E a exceção só vale para `not null → null`. Trocar uma sessão por outra
 * continua recusado — que é o caso que o congelamento existe para impedir.
 *
 * Corpo copiado da definição viva (`pg_get_functiondef`), com esta única
 * mudança. `create or replace` é `drop` + `create` disfarçado, e o jeito de não
 * perder o que estava lá é partir do que estava lá.
 */
create or replace function public.remarcacao_congela()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if row(new.conta_id, new.paciente_id, new.sessao_id)
     is distinct from row(old.conta_id, old.paciente_id, old.sessao_id)
  then
    raise exception 'remarcação não muda de dono nem de sessão';
  end if;

  if old.escolhida_em is not null then
    -- A exceção da 0056c: a sessão nova foi apagada e a FK está zerando o
    -- ponteiro. Deixar passar é o que permite apagar um paciente que remarcou.
    if new.nova_sessao_id is null
       and old.nova_sessao_id is not null
       and row(new.opcoes, new.token, new.escolhida_em, new.escolhido_inicio, new.origem)
           is not distinct from
           row(old.opcoes, old.token, old.escolhida_em, old.escolhido_inicio, old.origem)
    then
      return new;
    end if;

    if row(new.opcoes, new.token, new.escolhida_em, new.escolhido_inicio,
           new.origem, new.nova_sessao_id)
       is distinct from
       row(old.opcoes, old.token, old.escolhida_em, old.escolhido_inicio,
           old.origem, old.nova_sessao_id)
    then
      raise exception 'remarcação já fechada não se edita';
    end if;
    return new;
  end if;

  if new.escolhida_em is not null then
    new.escolhida_em := now();
    if (select auth.uid()) is not null then
      new.origem := 'presencial';
    else
      new.origem := 'link';
    end if;
  end if;

  return new;
end;
$$;
