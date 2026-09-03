# B36 · Reajuste sem saia justa e modo férias

**3 dias · migração: a definir · décima segunda da fila**
**Códigos:** D14, D16.

---

## Por que esta build existe

São duas conversas difíceis que o produto pode preparar, e que hoje ela tem
sozinha:

**O reajuste.** O novo enquadre já existe desde a B4 — trocar o valor é uma
linha. O que falta é **o texto e o momento**: quando avisar, com que
antecedência, com que palavras, e o que acontece com a sessão que já estava
marcada pelo valor antigo.

**O modo férias.** Suspender sem cancelar. `excecoes_agenda` já existe (P1) e já
subtrai do vendável com cada motivo no seu balde; o que falta é o **caminho de
ida e volta** do ponto de vista dela e da paciente: o que a paciente recebe, o
que acontece com a mensalidade do mês, e como o horário volta.

---

## Entrega

1. **Reajuste como conversa preparada:** data de vigência, aviso com
   antecedência escolhida por ela, e o texto — no tom do doc `09`, sem pedir
   desculpa e sem justificar com inflação.
2. **A sessão já marcada pelo valor antigo mantém o valor antigo.** A política
   congelada na sessão já é o padrão do produto (P2/P4); o reajuste não pode
   reescrever o passado.
3. **Modo férias:** período, o que a paciente recebe, o que acontece com
   mensalidade e pacote no mês parcial, e o retorno automático.
4. **A capacidade declarada acompanha.** Um mês inteiro de férias **zera o
   vendável sem zerar a história** — é a verificação nº 21 do P1, e ela precisa
   continuar passando.

---

## Pronto quando

- [ ] reajustar hoje não altera nenhuma sessão anterior à mudança, nem nenhum
      valor já reconhecido;
- [ ] o período de férias sai do vendável e **não** aparece como hora não
      ocupada no livro-razão (é `excecao`, não perda);
- [ ] a mensalidade de um mês parcial sai certa, e a tela diz a conta;
- [ ] o texto do reajuste passa no check do público: se explica para uma
      psicóloga em uma frase.

---

## Não entra

- **Sugestão de valor.** Nem "abaixo do valor de referência", nem comparação com
  o mercado, nem percentual recomendado. O valor é dela.
- **Aviso automático de reajuste anual.** Isso é o produto decidindo calado por
  ela — o antipadrão "o default que decide por ela".
- **Preço promocional, desconto de retorno, ou qualquer coisa que dependa de
  preencher horário parado.** Fronteira do Código de Ética.

---

## Armadilha

**Tratar férias como uma sequência de cancelamentos.** Cancelamento é evento com
causa e entra no livro-razão; férias é capacidade não declarada. Confundir os
dois enche a tela dela de "hora não ocupada" no mês em que ela descansou — e a
regra que protege o descanso é do doc `01`.
