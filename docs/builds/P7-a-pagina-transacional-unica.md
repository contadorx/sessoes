# P7 · A página transacional única

**2 dias · migração: a definir · sétima da fila**
*Substitui o D18 (portal do paciente), que morreu como conceito.*

---

## Por que esta build existe

O D18 propunha um **portal do paciente** — login, área logada, produto paralelo.
Ele morreu por isso: um segundo produto para manter, com uma segunda superfície
de dado clínico, para uma pessoa que entra três vezes por ano.

O que sobra e é legítimo é uma **página transacional**: o paciente chega por link
mágico, faz **uma** coisa, e vai embora. **Metade já existe** e está de pé desde a
B19 e a B21:

```
app/p/contrato/[token]/page.tsx    aceitar o contrato terapêutico
app/p/remarcar/[token]/page.tsx    escolher um novo horário
```

Ambas com `PREFIXOS_PUBLICOS` incluindo `/p/` (`proxy.ts:57`), token na tabela,
e `token` na lista do que **nunca vai para o papel** (terceira vez desta família:
`aceites.token` na 0031, `remarcacoes.token` na 0059c, e a lista da B33).

---

## Entrega

As três ações que faltam, no mesmo padrão de link mágico e na mesma rota `/p/`:

1. **Confirmar a sessão.** Hoje a confirmação chega por WhatsApp e a resposta
   entra pelo `responder_do_whatsapp` (B10 + P3). O link é o caminho para quem
   não respondeu por texto — e **zera o custo de mensagem**, porque toda resposta
   a mensagem do paciente cai na janela de 24h.
2. **Pagar.** O link de pagamento, no padrão que a B16 vai ligar. Enquanto o
   Asaas não existir, mostra a chave Pix e os dados, sem fingir conciliação (ver
   B46, item 3).
3. **Receber documento.** O recibo, a declaração de comparecimento, o PDF do mês
   para reembolso — o que a B32 emite chega aqui.

E uma decisão de arquitetura: **`B12b` (link público de agendamento) vira uma
rota desta página**, não uma build. O doc `20` já mandava reavaliar isso com o P7
de pé.

---

## Pronto quando

- [ ] as cinco ações (`contrato`, `remarcar`, `confirmar`, `pagar`, `documento`)
      vivem sob `/p/`, com o mesmo formato de token e a mesma expiração;
- [ ] nenhuma das cinco exige conta, senha ou cadastro;
- [ ] token não aparece em nenhuma exportação, nem na cópia impressa;
- [ ] abrir um link expirado diz o que aconteceu e o que fazer, sem expor nada;
- [ ] o paciente que abre o link e não conclui não deixa a vaga presa.

---

## Não entra

- **Login, sessão persistente, área logada.** Se aparecer a palavra "portal", o
  escopo escorregou.
- **Qualquer conteúdo clínico.** O paciente recebe o que é dele por
  `exportar_paciente` (B33), não por esta página.
- **Pergunta clínica em formulário.** Fronteira 6.
- **Trilha do paciente** (ele ver quem leu a ficha dele). É a pergunta certa e a
  resposta é da conversa com a psicóloga, não nossa. A B33 já a deixou de fora
  por isso.

---

## Armadilha

**Reaproveitar a página para "avisos" ou "novidades".** Uma página transacional
que ganha uma segunda função vira portal em três builds.
