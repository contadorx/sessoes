-- 0018 · O `revoke` que faltava.
--
-- O teste da B9 pegou isto: `revoke execute ... from anon, authenticated` não
-- fecha nada sozinho. `create function` concede execute a **PUBLIC**, e PUBLIC
-- inclui todo mundo — tirar de `anon` deixando PUBLIC intacto é revogar uma
-- porta e esquecer a outra.
--
-- É o espelho da 0003. Lá o `revoke from public` não bastava porque o Supabase
-- concede a `anon` explicitamente; aqui o `revoke from anon` não basta porque o
-- Postgres concede a PUBLIC implicitamente. As duas concessões existem, e
-- fechar de verdade é revogar as duas.
--
-- Na prática nada vazava: todas estas funções são `security invoker`, então a
-- RLS já devolvia zero linhas para o anônimo. Mas "hoje dá certo" nunca foi
-- argumento neste projeto — o motor da fila e o worker de mensagens não são
-- superfície de visitante, e agora isso está escrito no banco, não na sorte.

-- ------------------------------------------------------------ o worker (B9)

revoke execute on function public.reservar_mensagens(int) from public, anon, authenticated;
revoke execute on function public.marcar_enviada(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.marcar_falha(uuid, text) from public, anon, authenticated;
revoke execute on function public.destravar_mensagens(int) from public, anon, authenticated;
revoke execute on function public.mensagem_confere_retrato() from public, anon, authenticated;

grant execute on function public.reservar_mensagens(int) to service_role;
grant execute on function public.marcar_enviada(uuid, text, text) to service_role;
grant execute on function public.marcar_falha(uuid, text) to service_role;
grant execute on function public.destravar_mensagens(int) to service_role;

-- Enfileirar é da pessoa logada — o gatilho da 0017 já cuida do resto.
revoke execute on function public.enfileirar_mensagem(uuid, text, text, jsonb, timestamptz) from public, anon;
grant  execute on function public.enfileirar_mensagem(uuid, text, text, jsonb, timestamptz) to authenticated, service_role;

-- ------------------------------------------------------- o motor da fila (B7)
--
-- Mesma falha, mesma correção. `abrir_vaga` e `responder_oferta` mudam estado;
-- `elegiveis_para_vaga` e `taxa_de_preenchimento` leem. Nenhuma delas tem o que
-- conversar com quem não entrou.

revoke execute on function public.abrir_vaga(uuid) from public, anon;
revoke execute on function public.avancar_fila(uuid) from public, anon;
revoke execute on function public.responder_oferta(uuid, text) from public, anon;
revoke execute on function public.elegiveis_para_vaga(uuid) from public, anon;
revoke execute on function public.taxa_de_preenchimento(date, date) from public, anon;
revoke execute on function public.cabe_na_janela(jsonb, timestamptz) from public, anon;

grant execute on function public.abrir_vaga(uuid) to authenticated;
grant execute on function public.avancar_fila(uuid) to authenticated;
grant execute on function public.responder_oferta(uuid, text) to authenticated;
grant execute on function public.elegiveis_para_vaga(uuid) to authenticated;
grant execute on function public.taxa_de_preenchimento(date, date) to authenticated;
grant execute on function public.cabe_na_janela(jsonb, timestamptz) to authenticated;

-- A varredura de expiração fica com o cron **e** com a tela: ela é `security
-- invoker`, então a RLS já a prende à própria conta de quem chama — o botão da
-- fila existe para não depender do relógio numa demonstração.
revoke execute on function public.expirar_ofertas() from public, anon;
grant  execute on function public.expirar_ofertas() to authenticated, service_role;

-- `hoje_sp()` e `janela_semanas()` continuam abertas de propósito: são
-- constantes usadas em `default` de coluna, e o default roda com o privilégio
-- de quem insere — inclusive o anônimo que deixa o e-mail na landing.
