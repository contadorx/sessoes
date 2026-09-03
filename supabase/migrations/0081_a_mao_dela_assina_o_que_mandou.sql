-- =====================================================================
-- 0081 · A mão dela assina o que mandou
-- =====================================================================
--
-- Achado rodando a suíte `0022_cobrancas.sql` logo depois de a 0080 destravar
-- a verificação 5. A verificação 13 existe desde a B11 e diz uma frase só:
--
--     '13 FUROU: o app marcou mensagem como enviada'
--
-- Ela forja, rodando como `authenticated`:
--
--     update public.mensagens set estado = 'enviada', provedor = 'forjado'
--      where id = <uma mensagem na_sua_mao>;
--
-- E o banco deixou passar.
--
-- ## O que a 0061 quis, e o que ela escreveu
--
-- O comentário da própria política, na 0061, diz o que ela pretendia ser:
--
--     "ela é estreita de propósito: só sai de `na_sua_mao`, e nunca para
--      `enviando` ou `entregue`, que são estados de quem despacha."
--
-- A intenção está certa e a escrita ficou curta. A política é estreita **no
-- estado** e completamente muda sobre as duas colunas que dizem *quem*
-- despachou:
--
--     using      (conta_id = conta_atual() and estado = 'na_sua_mao')
--     with check (conta_id = conta_atual() and estado in ('enviada','cancelada'))
--
-- `enviada_a_mao` e `provedor` não aparecem. Então o mesmo `update` que
-- autoriza `marcar_enviada_a_mao()` a fazer a coisa honesta autoriza também a
-- desonesta: uma mensagem que diz ter saído por um provedor, sem a marca de
-- que a mão foi dela.
--
-- ## Por que isso não é detalhe de permissão
--
-- Trinta linhas acima, na mesma 0061, está `resumo_do_envio_manual`:
--
--     where ms.conta_id = p_conta
--       and ms.enviada_a_mao
--       and ms.enviada_em is not null
--
-- **A medida do canal manual conta `enviada_a_mao`.** Uma mensagem marcada
-- `enviada` sem essa coluna some da conta do que ela mandou à mão e passa a
-- parecer despacho do motor — **no plano Gratuito, onde motor não existe.**
-- É a "segunda fonte de verdade" do §9 sobre o que saiu, e é a cicatriz da lei
-- 8 escrita do outro lado: em vez de o adaptador fingir que enviou, é o banco
-- que aceita a ficha de um envio que ninguém fez.
--
-- Hoje nenhuma tela faz isso — `app/(app)/agenda/acoes.ts:512` chama a função
-- certa, e é a única escrita do repositório nesse caminho. O defeito não é uma
-- tela errada: é não haver nada impedindo a próxima. Uma invariante que
-- depende de todo mundo lembrar da função certa não é invariante.
--
-- ## O conserto
--
-- A política passa a exigir, para chegar em `enviada`, exatamente o que
-- `marcar_enviada_a_mao()` escreve e nada além: a marca da mão dela, e nenhum
-- provedor. `enviada_a_mao` é `not null default false`, então não há caso nulo
-- para arbitrar. `cancelada` continua livre — é `nao_vou_mandar()`, e uma
-- mensagem não enviada não precisa assinar nada.
--
-- O caminho de `service_role` não passa por política nenhuma: o worker é quem
-- despacha de verdade e continua escrevendo `provedor` como sempre escreveu.
-- =====================================================================

-- `mensagens` já tinha RLS e as outras três políticas seguem intactas: esta
-- migração reescreve uma só, e é a única que autoriza sair de `na_sua_mao`.
drop policy if exists "mensagens da conta: mandar à mão" on public.mensagens;

create policy "mensagens da conta: mandar à mão" on public.mensagens
  for update to authenticated
  using (
    conta_id = public.conta_atual()
    and estado = 'na_sua_mao'
  )
  with check (
    conta_id = public.conta_atual()
    and (
      -- Ela mandou: a marca da mão dela é obrigatória, e provedor nenhum pode
      -- ser nomeado — quem nomeia provedor é quem despachou, e não foi.
      (estado = 'enviada' and enviada_a_mao is true and provedor is null)
      -- Ela decidiu não mandar. Nada saiu, nada a assinar.
      or estado = 'cancelada'
    )
  );

comment on policy "mensagens da conta: mandar à mão" on public.mensagens is
  'Autoriza marcar_enviada_a_mao() e nao_vou_mandar(), que sao security invoker. Exige enviada_a_mao para chegar em enviada, e proibe nomear provedor: e a coluna que resumo_do_envio_manual conta, e sem ela um envio da mao dela vira despacho do motor num plano que nao tem motor.';
