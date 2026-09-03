-- 0078 · A última "faixa" que queria dizer cota, e a "régua" que estava junto.
--
-- O `CLAUDE.md` §5 lista as palavras do sistema que **não podem ser rótulo de
-- tela**, e duas delas estavam no lugar mais caro possível: a página de preços.
--
--     Consultório           'Régua de atraso impessoal'
--     Consultório Completo  'Sem faixa de sessões'
--     Clínica               'Sem faixa de sessões, por profissional que atende'
--
-- Não é preciosismo de vocabulário. **"Faixa" queria dizer duas coisas ao mesmo
-- tempo para a mesma pessoa na mesma semana** — cota do plano, aqui, e bloco de
-- horário, no `Horarios.tsx` e na tela de começar. O `lib/faixa.ts` já tinha
-- tirado a palavra das frases dele em 02/09 e escrito por quê; a página de
-- preços ficou.
--
-- E "régua" é pior, porque não significa nada para quem chega: é o nome interno
-- da sequência de lembretes de atraso. Quem lê o cartão precisa saber o que
-- acontece, não como o sistema chama o mecanismo.
--
-- ## Por que sobreviveram
--
-- `testes/o-jargao-nao-vira-rotulo.test.ts` **já declarava as duas regras**,
-- inclusive com a perífrase pronta para cada uma. Ele só não olhava para cá: a
-- varredura lia `app/(app)` e `components/app` — a área logada — e a página de
-- preços é pública. O jargão estava exatamente no primeiro texto que uma
-- psicóloga lê do produto, no único lugar que a varredura não alcançava.
--
-- A varredura foi alargada junto com esta migração, para `app/(site)`,
-- `components/site` e `lib/planos.ts`. Foram esses três achados e mais nenhum.
--
-- ## O que as frases novas dizem, e por que são verdade
--
-- **"Sessões sem limite"** é literal nos dois planos de cima. A faixa de 200 é
-- `fair_use`: existe para eu enxergar a clínica disfarçada de autônoma, e nunca
-- aparece para ela. `lib/faixa.ts` abre dizendo *"a faixa é a unidade de preço,
-- ela não é uma cerca"*, e com `e_fair_use` ligado `nivelDaFaixa` devolve
-- `'nenhum'` e `fraseDaFaixa` devolve `''` **em qualquer uso**, inclusive muito
-- acima de 200. Nada bloqueia, nada cobra a mais, nada avisa. A frase nova
-- descreve o comportamento; a antiga descrevia a implementação.
--
-- O Gratuito já dizia "Sessões sem limite" desde a 0070, com `faixa = null`. As
-- duas frases iguais dizem a mesma coisa do ponto de vista dela — que é o único
-- ponto de vista que o cartão tem — e a diferença entre `null` e `200 fair-use`
-- é minha, não dela.
--
-- **"Lembrete de atraso impessoal, para você não puxar o assunto"** é a mesma
-- frase que a landing já usava três parágrafos abaixo (*"é para você não
-- precisar puxar o assunto"*), e é o que o recurso faz.
--
-- A restrição `planos_promessa_nao_e_recurso` da 0064 continua valendo, e esta
-- migração não a toca: as três linhas trocadas são recursos que existem, e
-- continuam sendo recursos que existem.

update public.planos set
  recursos = array[
    'Tudo do Gratuito',
    'A fila e a cobrança saem sozinhas, na hora em que a vaga abre',
    '60 sessões por mês',
    'Modo Receita Saúde e pasta do contador',
    'Lembrete de atraso impessoal, para você não puxar o assunto',
    'Receita por hora disponível e o que aconteceu com cada horário'
  ]
where codigo = 'solo';

update public.planos set
  recursos = array[
    'Tudo do Consultório',
    'Sessões sem limite',
    'Permissões por pessoa: quem vê o quê'
  ]
where codigo = 'pro';

update public.planos set
  recursos = array[
    'Tudo do Consultório Completo',
    'Vários profissionais, com sigilo entre eles por construção',
    'Sessões sem limite, com quantos profissionais você tiver'
  ]
where codigo = 'clinica';
