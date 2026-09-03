# B34 · Pré-ficha administrativa

**2 dias · migração: a definir · décima terceira da fila**
**Código:** PR4.

---

## Entrega

Link para a paciente preencher **dados administrativos** antes da primeira
sessão. Reusa a página pública da B19/B21 — e, com o **P7** de pé, é uma rota da
página transacional única, não uma superfície nova.

O que ela preenche: nome completo, data de nascimento, documento, contato,
responsável (quando menor), como prefere ser avisada, e **CPF**.

---

## Pronto quando

- [ ] a paciente preenche sem conta, sem senha e sem cadastro;
- [ ] o que ela preenche cai no cadastro sem retrabalho de digitação;
- [ ] **nenhuma pergunta clínica aparece no formulário**, verificado por teste
      que varre o conjunto de campos;
- [ ] menor de idade exige responsável, e o cadastro de responsáveis da B13
      recebe o dado.

---

## Não entra — e é a fronteira 6

**Pergunta clínica nenhuma.** Anamnese é da sala. Cinco dos oito concorrentes
atravessam essa linha, e é uma das razões pelas quais este produto existe.

Não entra também: consentimento clínico, escala, triagem, questionário de
sintoma, "o que te traz aqui".

---

## Pode subir de prioridade

Se a conversa com a psicóloga mostrar que **a "parte chata" do Receita Saúde é
achar o CPF do paciente** (bloco 7b.3 do doc `08`), a dor se resolve **aqui** e
não no P8 — e esta build sobe. O CPF do paciente é o campo que trava a linha na
importação do Carnê-Leão: sem ele a linha não entra, e o gerador diz quantas
ficaram de fora.

---

## Armadilha

**Aproveitar o formulário para "já ir adiantando" a anamnese.** É exatamente o
caminho pelo qual cinco concorrentes atravessaram a fronteira 6, e ele começa com
um campo só.
