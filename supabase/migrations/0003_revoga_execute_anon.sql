-- 0003 · Tira do `anon` o execute nas funções de identidade.
--
-- O teste adversarial da B2 pegou isto: o `revoke ... from public` da 0002 não
-- basta, porque o Supabase concede execute a `anon` e `authenticated` por
-- default privileges do schema public — uma concessão explícita, que só some
-- com um revoke explícito.
--
-- Na prática `conta_atual()` devolveria null para o anônimo (não há auth.uid()),
-- então não havia vazamento. Mas função de identidade não é superfície do
-- visitante: fecha-se por postura, não porque hoje dá certo.

revoke execute on function public.conta_atual() from anon;
revoke execute on function public.papel_atual() from anon;
