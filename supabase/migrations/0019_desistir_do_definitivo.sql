-- 0019 · Desistir do que não tem volta.
--
-- `marcar_falha` existe para o erro que passa: timeout, instabilidade, limite de
-- taxa. Ela devolve a mensagem para a fila e espera um pouco mais a cada vez.
--
-- Mas há erro que não passa. Número que não existe no WhatsApp, e-mail
-- malformado, template reprovado pela Meta: repetir cinco vezes não muda o
-- desfecho — só gasta dinheiro, atrasa a fila e ensina o provedor a desconfiar
-- do número. Para esse caso o worker precisa de uma porta diferente, e ela
-- precisa ser explícita: quem desiste declara que desistiu.
--
-- Sem isto, o worker faria a gambiarra de chamar `marcar_falha` várias vezes
-- para queimar o orçamento de tentativas — e código que finge cinco falhas para
-- registrar uma é código que mente na trilha.

create or replace function public.desistir_mensagem(p_mensagem uuid, p_erro text)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.mensagens
     set estado = 'falhou', erro = left(p_erro, 500)
   where id = p_mensagem
     and estado in ('pendente', 'enviando');
$$;

revoke execute on function public.desistir_mensagem(uuid, text) from public, anon, authenticated;
grant  execute on function public.desistir_mensagem(uuid, text) to service_role;

comment on function public.desistir_mensagem(uuid, text) is
  'Erro definitivo: encerra a mensagem sem novas tentativas. So o worker chama.';
