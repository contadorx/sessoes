-- 0040h · Gatilho não é rota, e FK sem índice é dívida.
--
-- Os dois apontamentos dos advisors depois da 0040. Nenhum dos dois é exótico —
-- os dois são leis do doc 05 que a 0040 esqueceu de cumprir.
--
-- **1. As três funções de gatilho estavam expostas em /rest/v1/rpc.**
--
-- `sessao_espelha`, `sessao_apagada_espelha` e `modo_reescreve_o_futuro` são
-- `security definer` por necessidade: escrevem em `espelhos_calendario`, que
-- não tem política de insert nem de update para o cliente. Só que `create
-- function` concede execute ao `PUBLIC` por padrão, e o PostgREST publica tudo
-- que é executável — então qualquer um podia chamá-las por RPC.
--
-- O estrago real é pequeno (chamada fora de gatilho estoura em `tg_op`, e a de
-- `modo_reescreve_o_futuro` estoura em `new`), mas o princípio não é: função de
-- gatilho não é endpoint, e a superfície que não precisa existir não deve
-- existir. É o mesmo `revoke` que faltou na 0018, pelo mesmo motivo — **são
-- duas concessões, a do PUBLIC e a dos papéis, e é preciso revogar as duas.**
--
-- **2. `espelhos_calendario.sessao_id` era FK sem índice de cobertura.**
--
-- O índice que existe é `(calendario_id, sessao_id)` parcial, e ele não serve
-- para buscar por `sessao_id` sozinho — a coluna não é a primeira. E buscar por
-- `sessao_id` sozinho é exatamente o que os dois gatilhos fazem a cada sessão
-- criada, movida, cancelada ou apagada, e o que a ação referencial faz a cada
-- `delete`. Numa base com um ano de agenda isso vira varredura de tabela na
-- rotina mais frequente do sistema.

revoke execute on function public.sessao_espelha() from public, anon, authenticated;
revoke execute on function public.sessao_apagada_espelha() from public, anon, authenticated;
revoke execute on function public.modo_reescreve_o_futuro() from public, anon, authenticated;

create index if not exists espelhos_da_sessao
  on public.espelhos_calendario (sessao_id) where sessao_id is not null;

comment on index public.espelhos_da_sessao is
  'Cobre a FK sessao_id. O unico parcial (calendario_id, sessao_id) nao serve: sessao_id nao e a primeira coluna, e a busca por ela sozinha e a mais frequente do sistema.';
