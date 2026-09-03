# B45 · A segunda-feira de manhã

**1,5 dia · migração: nenhuma · sexta da fila**
*A tela que ela abre todo dia. É ordem, e ordem é de graça.*

---

## Por que esta build existe

Em 375 px, antes da grade da semana (`app/(app)/agenda/page.tsx:227`), vêm **oito
blocos**:

```
:109-137  título + navegação de semana
:142      faixa de prazos
:146      faixa "Terminar de configurar"
:159      dl de quatro números          ← sm:grid-cols-2 → UMA coluna no celular
:184      caixa "A decidir" (P4)
:194      caixa "Na sua mão" (OP9)      ← sempre presente no Gratuito
:202      cockpit com mais quatro números (P5)
:210      faixa de confirmações (P3)
:220      dois números da confirmação
```

**Dez números de dinheiro e ocupação antes do primeiro nome de paciente.** Ela
abre o app entre uma sessão e outra para ver quem vem às 15h, e rola dois
polegares de painéis primeiro. O produto compete com o caderno e perde essa
comparação por rolagem.

---

## Entrega

**1 · A ordem.** Sobem, porque exigem ação hoje: faixa de prazos · caixa "A
decidir" · caixa "Na sua mão". Depois delas vem **a grade da semana**. Descem
para baixo da grade: os quatro números da faixa, o cockpit, o Retorno, a faixa e
os números da confirmação.

**2 · Duas colunas no celular.** Os dois `dl` de números (`agenda/page.tsx:159` e
`components/app/Cockpit.tsx:79`) viram `grid-cols-2` já na base — hoje são uma
coluna abaixo de 640 px, e são oito cartões empilhados.

**3 · A meta de 60% sai da tela dela.**
`app/(app)/encaixes/page.tsx:70-80` mostra *"a meta é 60% — abaixo disso o
produto não se justifica"*, com `text-cheia` acima de 60% e `text-vaga` abaixo.
`lib/risco.ts:27-30` proíbe isso por escrito ("Não existe meta… nenhuma cor que
melhore com o número subindo"), e o P5 tem verificação — que olha o cockpit e não
olha esta tela. O número fica, sem juízo e sem cor; a meta some. **E a
verificação do P5 passa a varrer `app/(app)` inteiro.**

**4 · Nenhuma ação que fale com a paciente acontece em um toque.**
`components/app/PainelSessao.tsx:449-463` tem "Confirmar · Aconteceu · Não veio ·
Paciente desmarcou · Eu desmarquei" num `flex flex-wrap gap-2` — alvos de ~35 px
a 8 px de distância. Busca por `confirm(`, `window.confirm`, `<dialog>` em todo o
repositório: **zero**. "Não veio" leva a sessão para `falta`, que é cobrável
(`:357`) e dispara a proposta de multa.
Entra: **segunda etapa in-place** nos dois "desmarcou", no padrão que
`components/app/Privacidade.tsx:135-147` já usa (estado `confirmando` no próprio
componente), e **separação visual** entre "Aconteceu" e "Não veio".
Entra junto: nas duas confirmações que já existem, o escape ("deixa") é o
elemento de menor contraste da fileira — dar a ele o mesmo peso do destrutivo.

**5 · O erro do formulário aparece.** `components/app/campos.tsx:22-33` ganha
`role="alert"` e `scrollIntoView`. *(Se a B48 já rodou, isso já está feito — veja
antes de refazer.)*

---

## Pronto quando

- [ ] em 375 px, o **primeiro nome de paciente** aparece sem rolar mais de uma
      tela;
- [ ] nenhuma tela de `app/(app)` mostra meta, alvo ou cor que melhora subindo —
      e a verificação do P5 reprova quem acrescentar;
- [ ] nenhuma ação que cancele sessão ou dispare cobrança acontece em um toque;
- [ ] os dois `dl` de números mostram duas colunas no celular.

---

## Não entra

- **Abas, "ver mais", ou tela nova.** Aba é onde métrica morre, e o P5 tem razão
  escrita sobre isso: *"uma métrica que mora onde ninguém abre é uma métrica que
  não muda decisão nenhuma"*. O cockpit continua na primeira tela — só deixa de
  vir antes da agenda.
- **`window.confirm`.** O produto não usa nenhum diálogo nativo; o padrão da casa
  é o estado `confirmando` no próprio componente.
- **Esconder a caixa "Na sua mão".** No Gratuito ela é trabalho que só acontece
  se ela vir, e a oferta que ela não mandou **segura a vaga**.

---

## Armadilha

**Achar que o cockpit "desceu" significa que ele pode virar aba.** A decisão do
P5 é que ele fica na primeira tela; o que muda é a ordem dentro dela.

---

## Arquivos que esta build toca

```
app/(app)/agenda/page.tsx      ← a ordem
components/app/Cockpit.tsx     app/(app)/encaixes/page.tsx
components/app/PainelSessao.tsx  components/app/Privacidade.tsx
components/app/campos.tsx
supabase/tests/0059*  ← a verificação do P5, ampliada
```
