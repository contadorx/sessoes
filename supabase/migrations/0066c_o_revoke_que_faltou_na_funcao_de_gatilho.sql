-- =====================================================================
-- 0066c · O revoke que faltou na função de gatilho
-- =====================================================================
--
-- Duas linhas, e elas fecham uma assimetria que a própria 0066 criou.
--
-- A 0066 revogou `public` das cinco funções que nomeou e concedeu `anon` a
-- três. **Esqueceu da sexta**: `link_do_paciente_monta()`, a função de gatilho
-- que ela mesma criou — e que é `security definer`, como todas as de gatilho
-- deste banco precisam ser.
--
-- **Não é explorável, e mesmo assim entra.** O Postgres recusa chamada direta
-- a função que devolve `trigger`, então não há caminho de `/rest/v1/rpc` que
-- alcance esta. A correção existe por outro motivo:
--
--   · **é a terceira vez desta família neste projeto.** A 0018 descobriu que
--     `revoke ... from anon, authenticated` não fecha nada enquanto `PUBLIC`
--     mantiver o execute que o `create function` concede por padrão; a 0040h
--     achou três gatilhos publicados em `/rest/v1/rpc` seis builds depois. As
--     duas custaram uma migração corretiva para consertar um `grant` que
--     ninguém tinha escrito de propósito;
--
--   · **uma exceção sem motivo escrito vira precedente.** No dia em que
--     alguém varrer o schema atrás de `security definer` aberta a `PUBLIC`, o
--     que essa pessoa vai encontrar é uma função da build de ontem — e vai
--     concluir, corretamente, que a regra não é uniforme. A defesa deste
--     produto contra furo de permissão é a uniformidade, não a auditoria caso
--     a caso.
--
-- **Achado por uma leitura externa da suíte**, e vale registrar como isso
-- aconteceu: a verificação 27 da 0066 precisava contar "quantas funções o
-- anônimo alcança", e descobriu no caminho que **contagem crua de grant não
-- serve** — o Supabase concede `EXECUTE` a `anon` por *default privileges*, e
-- hoje dezesseis funções de `public` carregam `anon` (`hoje_sp`, `reais`,
-- `rotulo_horario`, as de gatilho…). O recorte que significa alguma coisa é
-- *security definer + anon + resultado que não seja `trigger`*, e é ele que dá
-- exatamente sete. Ao escrever esse recorte é que a exceção apareceu.
--
-- =====================================================================

revoke all on function public.link_do_paciente_monta() from public, anon, authenticated;

comment on function public.link_do_paciente_monta() is
  'Gatilho before insert de links_do_paciente: o token, o conta_id e o prazo sao do SERVIDOR, sempre. Quem escolhe o endereco da prova forja a prova (0031). Sem execute para public/anon/authenticated — a 0066 esqueceu, a 0066c consertou, e a razao esta no cabecalho dela.';
