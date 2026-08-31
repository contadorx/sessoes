-- 0027 · O relógio é do cron.
--
-- O teste da 0026 pegou de novo, e é a terceira vez que este mesmo descuido
-- aparece no projeto: `revoke ... from public, anon` deixando `authenticated`
-- de fora. O Supabase concede execute a `authenticated` por default privileges,
-- então esquecer o papel na lista de revoke é deixar a porta aberta.
--
-- Aqui não vazava nada — `agendar_lembretes()` é `security invoker`, então uma
-- pessoa logada só enfileiraria lembretes dos próprios pacientes, que é algo que
-- ela já pode fazer pela tela. Mas rotina de relógio não é botão: se um dia
-- alguém precisar disso na interface, que apareça como uma ação com nome, e não
-- como uma função de cron acessível por acidente.
--
-- **Regra que fica, agora escrita:** todo `revoke` deste projeto lista os três —
-- `public, anon, authenticated` — e só então se concede de volta a quem precisa.

revoke execute on function public.agendar_lembretes() from public, anon, authenticated;
grant  execute on function public.agendar_lembretes() to service_role;
