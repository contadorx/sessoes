-- 0047b · Os dois limites, e o que cada um bounda.
--
-- A 0047 fez duas coisas, e só uma delas estava certa.
--
-- **Certa:** criar o limite de pacientes ativos. Ele se explica em cinco
-- palavras e é o que vai na página de preços.
--
-- **Errada:** ter afrouxado o teto de mensagens para 500 no Grátis e 2000 nos
-- pagos, tratando-o como "rede de segurança muda". O raciocínio era que o teto
-- de mensagens não bounda o custo — e isso é verdade só pela metade.
--
-- ## O que eu errei no raciocínio
--
-- Eu escrevi que o teto de mensagens não limita o que existe para limitar,
-- porque lembrete de véspera é o grosso do volume e é essencial. Isso está
-- certo sobre o **custo do lembrete** e errado sobre a conclusão: o teto nunca
-- foi para limitar o lembrete. Ele limita **oferta de fila e cobrança**, que é
-- volume **discricionário** — não é proporcional a quantos pacientes ela tem,
-- é proporcional a quanto o sistema conversa por conta própria.
--
-- Uma conta com cinco pacientes pode mandar quinze mensagens não-essenciais
-- num mês normal, e duzentas num mês em que tudo desmarca e a fila roda três
-- vezes por vaga. **O limite de pacientes não alcança esse caso**, porque ele
-- limita o tamanho da conta, não a conversa dela.
--
-- ## Os dois, e por que não são "dois limites para a mesma coisa"
--
-- A 0046 alertou contra dois limites convivendo — foi o que custou cobrança em
-- dobro no Enquadria. A diferença aqui é que eles boundam eixos diferentes:
--
--     pacientes ativos  →  o tamanho da conta  →  vai na página de preços
--     mensagens/mês     →  a conversa da conta →  vive dentro do app
--
-- Um não substitui o outro, e nenhum dos dois é derivável do outro. O risco de
-- dois limites é um deles ser esquecido; aqui os dois têm teste, os dois têm
-- tela, e os dois falam quando agem.
--
-- ## Os números
--
--   · **Grátis: 60 mensagens não-essenciais/mês.** Com cinco pacientes, o uso
--     normal fica em torno de quinze. Sessenta é ~4× isso — só morde num mês
--     genuinamente atípico, que é exatamente quando ele deve morder.
--   · **Pagos: sem teto.** A 0047 tinha posto 2000 em todos, o que é rede de
--     segurança contra laço de código. Mas rede de segurança que aparece como
--     limite de plano confunde a conversa comercial, e o freio contra laço
--     pertence ao worker, não ao cardápio. Volta a `null`, e a verificação 6
--     da suíte 0046 — que afirma isso desde a OP2 — volta a passar.
--
-- Foi ela, aliás, que apontou a contradição: a 0047 mudou o mundo e não mudou
-- o teste, então o teste ficou vermelho dizendo a verdade.

update public.planos set limite_mensagens_mes = 60   where codigo = 'gratis';
update public.planos set limite_mensagens_mes = null where codigo <> 'gratis';

comment on column public.planos.limite_mensagens_mes is
  'Teto mensal de mensagens NAO-essenciais: oferta de fila e cobranca. NULL = sem teto. Bounda a CONVERSA da conta, que e volume discricionario — enquanto limite_pacientes_ativos bounda o TAMANHO dela. Um nao deriva do outro. Nunca alcanca template essencial: lembrete, desmarque e confirmacao de encaixe saem sempre, porque quem ficaria sem eles e o paciente, que nao escolheu plano nenhum.';

comment on column public.planos.limite_pacientes_ativos is
  'Teto de pacientes NAO arquivados — o limite que vai na pagina de precos, porque e o que se explica em cinco palavras. Arquivar quem encerrou devolve a vaga: a ficha continua guardada com o historico inteiro, porque obrigacao de guarda nao e consumo de plano.';
