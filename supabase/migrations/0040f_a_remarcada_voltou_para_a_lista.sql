-- 0040f · A remarcada voltou para a lista.
--
-- Achado pela regressão da B21, e é o defeito mais instrutivo desta build.
--
-- A 0040 precisava de `origem = 'importada'` em `sessoes`. Para acrescentar um
-- valor a um `check` de coluna é preciso derrubar e recriar a restrição, e foi
-- o que ela fez — copiando a lista de valores **da 0006**, que é onde a coluna
-- nasceu:
--
--     check (origem in ('recorrencia', 'encaixe', 'avulsa', 'importada'))
--
-- Só que a lista já não era essa. A **0035** tinha feito exatamente a mesma
-- manobra para acrescentar `'remarcada'` (a B21), e a 0040 apagou esse valor
-- ao reescrever a restrição a partir da versão antiga. Resultado: a remarcação
-- guiada — uma feature inteira, com 24 verificações próprias — parou de
-- funcionar, e nada na 0040 tocava em remarcação.
--
-- Nenhum teste da B26 pegaria isto. Quem pegou foi rodar a suíte da B21 de
-- novo, que é o motivo pelo qual a regressão faz parte do ritual e não é
-- opcional.
--
-- **Regra que fica:** `drop constraint` + `add constraint` é um `create or
-- replace` disfarçado — reescreve o todo, não acrescenta ao que existe. A lista
-- se lê do **banco**, no momento da mudança, e nunca da migração que criou a
-- coluna.

alter table public.sessoes drop constraint if exists sessoes_origem_check;
alter table public.sessoes add constraint sessoes_origem_check
  check (origem in ('recorrencia', 'encaixe', 'avulsa', 'remarcada', 'importada'));

comment on constraint sessoes_origem_check on public.sessoes is
  'recorrencia (motor) · encaixe (fila) · avulsa (ela marcou) · remarcada (B21) · importada (B26, memoria de outro sistema). Acrescentar valor aqui exige reler a lista corrente do banco.';
