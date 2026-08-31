-- 0004 · Tira `ao_criar_auth_user()` da API pública.
--
-- Apontado pelos advisors: por default privileges do schema public, a função
-- do gatilho ficou exposta em /rest/v1/rpc/ao_criar_auth_user para anon e
-- authenticated. Chamá-la direto falharia (o Postgres recusa executar função
-- de gatilho fora de um gatilho), mas função de gatilho não tem por que
-- aparecer na superfície da API. Fecha-se.
--
-- `conta_atual()` e `papel_atual()` continuam executáveis por `authenticated`
-- **de propósito**: as políticas de RLS as chamam, e a expressão da política
-- roda com o privilégio de quem consulta. Revogar quebraria a RLS inteira.
-- Os avisos correspondentes dos advisors são esperados e ficam.

revoke execute on function public.ao_criar_auth_user() from public;
revoke execute on function public.ao_criar_auth_user() from anon;
revoke execute on function public.ao_criar_auth_user() from authenticated;
