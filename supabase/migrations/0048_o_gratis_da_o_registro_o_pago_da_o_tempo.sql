-- 0048 · O Grátis dá o registro; o pago dá o tempo (OP3b).
--
-- A OP3 pôs limite de cinco pacientes ativos no plano Grátis. Sai — e o motivo
-- é de posicionamento, não de engenharia.
--
-- ## A regra do cardápio, agora escrita
--
--     **O plano Grátis dá tudo, menos o que economiza tempo.**
--
-- Agenda, pacientes, prontuário, anamnese, o livro-razão da sessão, o registro
-- fiscal: tudo isso é **o trabalho dela ficando guardado**, e cobrar por isso é
-- cobrar para ela poder existir organizada. Não dá para defender, e não é o que
-- este produto vende.
--
-- O que o plano pago vende é **a máquina trabalhando no lugar dela**: a fila
-- que oferece a vaga sozinha, a régua que cobra sem ela precisar mandar a
-- mensagem. Isso custa dinheiro nosso por unidade (cada mensagem tem preço), e
-- é exatamente onde o valor aparece — a psicóloga não paga por guardar dado,
-- paga por não ter que fazer a conversa.
--
-- Um limite de pacientes contradizia isso na primeira frase: ele limita o
-- registro, que é a parte que devia ser livre.
--
-- ## O que fica, e por que a máquina não é apagada
--
-- `limite_pacientes_ativos` continua na tabela, os dois gatilhos continuam
-- instalados, e **nenhum plano usa** — todos com `null`. Isso não é a mesma
-- coisa que "limite declarado e não aplicado", que a 0045 proibiu: lá havia
-- número na tela e nada que o cobrasse; aqui há mecanismo provado por suíte e
-- nenhum número configurado. Se um dia um plano precisar de teto de pacientes,
-- é um `update` — e ele funciona no mesmo instante.
--
-- E `pacientes_da_conta()` deixa de ser porteiro e vira **medida**: quantos
-- pacientes ativos uma conta tem é informação útil para o painel do negócio
-- (é o tamanho da conta) mesmo sem limite nenhum em cima.
--
-- ## O limite que sobra é um só
--
-- 60 mensagens de fila e cobrança por mês, no Grátis. E ele volta para a
-- página de preços, porque agora é o único — a OP3 o tinha tirado de lá
-- quando o de pacientes assumiu o papel.
--
-- Lembrete de véspera, aviso de desmarque e confirmação de encaixe continuam
-- fora de qualquer teto, em qualquer plano, porque quem ficaria sem eles é o
-- paciente — que não escolheu plano nenhum.

update public.planos set limite_pacientes_ativos = null;

comment on column public.planos.limite_pacientes_ativos is
  'Teto de pacientes NAO arquivados. NULL = sem teto, e HOJE NENHUM PLANO USA — o Gratis da tudo o que e registro (agenda, prontuario, livro-razao) e cobra so o que economiza tempo, que e a mensageria. A coluna e os dois gatilhos ficam porque estao provados por suite: se um plano precisar de teto de pacientes um dia, e um update e ele vale na hora.';

comment on function public.pacientes_da_conta(uuid) is
  'Quantos pacientes ativos a conta tem, e quantos cabem se houver limite. Desde a 0048 nenhum plano tem limite, entao ela e MEDIDA (o tamanho da conta, util para o painel do negocio) e nao porteiro. Ativo = arquivado_em is null. So responde para a propria conta, para o worker e para o operador.';
