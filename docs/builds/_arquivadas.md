# O que está morto, e não volta

*Registrado para ninguém reabrir por engano. A razão, em cada caso, não foi
prazo.*

---

## Saíram da fila em 02/09/2026, pela auditoria de UX

| build | era | por que saiu |
|---|---|---|
| **B38** · NFS-e nacional PJ | 5 dias | Serve a **zero contas** hoje. O próprio doc `20` já qualificava: *"cinco dias para uma funcionalidade que hoje serve a zero contas é a definição de construir cedo"*. Os campos IBS/CBS são exigíveis a partir de 01/10/2026, **sem rejeição até 31/12/2026**, e o Simples com destaque opcional só em 01/01/2027 — nada vence antes. Volta no dia em que existir cliente PJ. O motor herdado do FinanceiroX continua acompanhando as NTs. |
| **B12b** · link público de agendamento | 2 dias | **Vira uma rota do P7**, como o doc `20` já mandava reavaliar. Era o primeiro corte de prazo do `claude/12` e continua sendo paridade que ninguém troca de sistema para ter. |

---

## Mortas pelo doc 30 (o roadmap da integridade da receita)

| morta | era | por quê |
|---|---|---|
| **B30** · briefing de 30 s (D7) | a "ponte" da fase 3 | o valor está no livro-razão, não no resumo pré-sessão |
| **D12** · radar de furo | metade da B35 | vira uma das sete causas do P5, sem tela própria |
| **D8** · alerta de sumiço | a outra metade da B35 | **fronteira 3**: frequência clínica não é decisão de software. O que sobra e é legítimo — "a cadência combinada não aconteceu" — entra no P5 como fato, sem sugestão |
| **D10** · fila cruzada | fase 4 | complexidade sem demanda demonstrada |
| **D17** · encaminhamento remunerado | fase 4 | **veda ética**: remuneração por encaminhamento |
| **N1** QR · **N2** modelos por abordagem · **N5** check-in clínico | paridade | nenhum sustenta troca de sistema |
| **D18** · portal do paciente (B37) | 4 dias | vira o **P7**, uma página transacional só — e metade já existe em `/p/contrato` e `/p/remarcar` |

---

## Nunca chegou a nascer, para não ser proposta de novo

**Emitir o Receita Saúde no lugar dela.** Morreu em 02/09 como **fronteira 11**
do doc `11`, não como corte de prazo. O produto não guarda credencial gov.br —
nem senha, nem sessão, nem token, nem por intermediador que peça a conta dela por
dentro do nosso produto. O que ficou está no **P8**.

**O simulador de ROI.** Calculava R$ 800/mês de hora recuperada em aritmética de
padaria, e era o argumento mais forte que a landing tinha. Também era a hipótese
não demonstrada transformada em número na tela — e número é promessa mais forte
que qualquer frase. *O arquivo `components/site/Simulador.tsx` ainda existe no
repositório, compilando, e não é importado por nenhuma página. Apagar, ou pôr um
teste que reprove o import.*

**A B15** (piloto assistido) foi deixada para trás por decisão de 31/08: seguir
construindo em vez de parar no portão 1→2.

---

## E o que nunca entra, em nenhuma build

Gamificação, streak, badge, parabéns por meta · IA interpretando, transcrevendo
ou resumindo sessão · gravação de paciente · pergunta clínica em formulário que a
paciente preenche sozinha · sugestão de conduta clínica, alerta de frequência,
nudge sobre sumiço de paciente · impersonação ou leitura de prontuário pelo
suporte · número projetado como argumento de tela · preço promocional
last-minute, reativação de ex-paciente, remuneração por encaminhamento.

**Se um achado seu parecer pedir uma destas, o achado está mal formulado —
reformule.**
