-- 0023 · A única edição que o app pode fazer numa mensagem.
--
-- O teste da B11 pegou uma contradição entre duas regras minhas, e as duas
-- estavam certas:
--
--   · a 0017 diz que o app **não** mexe em estado de envio — quem escreve isso
--     é o worker, e sem essa regra qualquer cliente marcaria mensagem como
--     entregue ou reescreveria a trilha;
--   · a B11 diz que perdoar uma cobrança **tem** de segurar o aviso que ainda
--     não saiu — perdoar e mandar a conta mesmo assim é o pior desfecho do
--     build inteiro.
--
-- Sem política de update, o `perdoar_cobranca` atualizava zero linhas e não
-- reclamava: o perdão parecia funcionar na tela e a mensagem saía uma hora
-- depois. Falha silenciosa, que é a pior categoria.
--
-- A saída não é abrir a tabela nem contornar com `security definer`. É desenhar
-- a **única transição** que faz sentido do lado de fora e permitir só ela:
-- pendente → cancelada. Nada mais. Não dá para marcar como enviada, não dá para
-- ressuscitar cancelada, não dá para tocar no que já saiu.
--
-- E ela vale para além do perdão: "não manda isso" é um direito de quem tem a
-- conta, e é bom que o caminho seja este, e não um jeitinho.

drop policy if exists "mensagens da conta: segurar" on public.mensagens;
create policy "mensagens da conta: segurar" on public.mensagens
  for update to authenticated
  using  (conta_id = public.conta_atual() and estado = 'pendente')
  with check (conta_id = public.conta_atual() and estado = 'cancelada');
