-- =====================================================================
-- 0049b · As funções novas seguem a convenção da casa
-- =====================================================================
--
-- Os advisors reprovaram três coisas logo depois da 0049, e as três são a
-- mesma omissão: `create function` concede EXECUTE a **PUBLIC** por padrão, e
-- eu não desfiz.
--
--   1. `le_clinico()` e `ve_financeiro()` ficaram alcançáveis pelo `anon`,
--      via /rest/v1/rpc. Não vazam nada — sem sessão as duas devolvem `false`,
--      e a verificação 5 da suíte 0049 prova isso —, mas `papel_atual()`, que
--      é a irmã mais velha delas, nunca teve `anon`. Divergência de convenção
--      é o começo de um buraco: daqui a seis meses alguém copia a errada.
--
--   2. `permissao_nao_se_autoconcede()` é **função de gatilho** e estava
--      publicada em /rest/v1/rpc. Chamada de lá ela só sabe dizer "trigger
--      functions can only be called as triggers", então o risco prático é
--      zero — mas `operador_nao_se_promove()` e `anamnese_fechada_nao_muda()`
--      já são `{postgres, service_role}` e a verificação 24 da suíte 0043
--      existe justamente para exigir isso. Uma superfície pública que não
--      serve a ninguém é superfície a menos para pensar.
--
-- Nada aqui muda comportamento. É o acabamento que a 0049 devia ter trazido.
-- =====================================================================

begin;

-- A leitura do próprio acesso é pergunta de quem já entrou. Mesma concessão de
-- `papel_atual()` e `conta_atual()`.
revoke all on function public.le_clinico()    from public, anon;
revoke all on function public.ve_financeiro() from public, anon;
grant execute on function public.le_clinico()    to authenticated, service_role;
grant execute on function public.ve_financeiro() to authenticated, service_role;

-- Gatilho não é rota.
revoke all on function public.permissao_nao_se_autoconcede() from public, anon, authenticated;
grant execute on function public.permissao_nao_se_autoconcede() to service_role;

commit;
