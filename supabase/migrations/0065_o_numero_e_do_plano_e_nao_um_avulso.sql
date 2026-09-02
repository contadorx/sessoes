-- =====================================================================
-- 0065 · O número próprio é o plano, e não um avulso
-- =====================================================================
--
-- Duas linhas de dado, e uma decisão comercial atrás delas.
--
-- A decisão 1 do `claude/25` dizia: **número próprio da psicóloga = add-on de
-- R$ 19/mês, incluso no plano superior.** A OP9 construiu o degrau de baixo
-- dessa escada — no Gratuito a mensagem sai do WhatsApp dela, na mão — e
-- deixou a pergunta observável, que era o ponto: *de quem tem que ser o número
-- que fala com a sua paciente?*
--
-- **O Leandro decidiu em 02/09: o número próprio é o Consultório Completo
-- inteiro. Não há add-on.**
--
--
-- ---------------------------------------------------------------------
-- POR QUE ISTO É UMA MIGRAÇÃO, E NÃO UMA ANOTAÇÃO NUM DOCUMENTO
-- ---------------------------------------------------------------------
--
-- A 0064 pôs `número próprio` em `planos.por_vir` do **Consultório**, porque
-- naquele desenho ele era um avulso que o plano de entrada podia comprar. Sem
-- o add-on, essa linha vira uma promessa feita no cartão errado: a pessoa lê
-- no Consultório que o número próprio está vindo, assina o Consultório, e
-- descobre depois que ele nunca vem nesse plano.
--
-- É a mesma família de defeito que a 0064 inteira existe para fechar — a
-- diferença é que aqui a linha nem sequer é falsa sobre o software, é falsa
-- sobre **o plano**. E `por_vir` foi criada exatamente para não virar um
-- segundo lugar onde se promete sem conferir.
--
-- **O add-on também não vira coluna, e o motivo não mudou:** o número próprio
-- depende de BSP com Embedded Signup e de Coexistence, que não existem. A
-- 0064 já tinha recusado criar `preco_addon_centavos` por isso. A decisão do
-- Leandro não constrói o recurso; ela só resolve **em qual plano** ele vai
-- morar quando existir — e o efeito disso hoje é subtrativo.
--
--
-- ---------------------------------------------------------------------
-- O QUE A DECISÃO CUSTA, DITO AQUI PORQUE É COMERCIAL
-- ---------------------------------------------------------------------
--
-- O add-on era a única receita incremental que o Consultório tinha desenhada:
-- R$ 69 + R$ 19 = R$ 88, com margem de canal de 90% na tabela do `claude/25`.
-- Sem ele, o Consultório é R$ 69 e ponto, e quem quiser o próprio número tem
-- de subir para R$ 129.
--
-- **A contrapartida é que o Consultório Completo ganha o diferencial concreto
-- que a 0064 mostrou que ele não tinha.** Ele estava com três linhas de
-- `recursos` — tudo do Consultório, sem faixa, permissões — e nenhuma delas é
-- o motivo de alguém pagar R$ 60 a mais. O número próprio é: *"as mensagens
-- chegam do número que seus pacientes já conhecem"* é uma frase que a
-- psicóloga entende sem explicação, e é o quadrante que o `claude/24` mostrou
-- vazio no mercado inteiro — ninguém junta automático **e** do número dela.
--
-- Isto não conserta o problema comercial de hoje, e não deve parecer que
-- conserta: enquanto o BSP não existir, o Completo continua com três linhas. O
-- que a decisão faz é dizer **qual** linha vai ser a quarta.
--
--
-- ---------------------------------------------------------------------
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
-- ---------------------------------------------------------------------
--
--   · não cria valor de canal `proprio` — a 0061 recusou e a recusa continua
--     de pé, com verificação própria na suíte 0061;
--   · não mexe em preço nenhum. O Consultório continua R$ 69 e o Completo
--     R$ 129 — a decisão move um recurso de lugar, não a tabela;
--   · não toca no Gratuito nem na Clínica. A Clínica já dizia "número próprio
--     da clínica" em `por_vir`, e continua: lá o número é da clínica e não de
--     uma profissional, que é outra coisa e vai precisar de outra build.
--
-- =====================================================================


-- O Consultório para de prometer o que não vai receber. `por_vir` fica vazio,
-- e isso é o retrato certo: o Consultório é um plano completo dentro do que
-- ele se propõe, e não um degrau esperando peça.
update public.planos
   set por_vir = '{}'::text[]
 where codigo = 'solo';

-- E o Completo diz de quem é o número, em vez de dizer "incluso" — que só
-- significa alguma coisa para quem já leu a linha do plano de baixo, e essa
-- linha acabou de deixar de existir.
update public.planos
   set por_vir = array[
     'NFS-e para quem atende como PJ',
     'número próprio: as mensagens chegam do número que suas pacientes já conhecem',
     'página do paciente: confirmar, pagar e receber documento',
     'reajuste assistido e modo férias'
   ]
 where codigo = 'pro';
