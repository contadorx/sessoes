# B43 · A mensagem diz onde está

**2 dias · migração: nenhuma · segunda da fila**
*Abre por dois S1. O produto está no ar afirmando fato falso sobre paciente.*

---

## Por que esta build existe

O produto **diz que mandou mensagens que nunca saíram** e **diz que a paciente
não respondeu a uma pergunta que nunca fez**. Os dois são o mesmo tipo de
defeito: a tela afirma um fato que ela não tem como conferir, sobre alguém que
ela atende.

---

## S1-A · "O sistema disse que avisei ela. Ela jura que não recebeu nada."

```
lib/mensageria/adaptadores.ts:82-85
  export function adaptadorPara(canal: Canal): Adaptador {
    void canal;
    return registro;          // ← sempre, para qualquer canal
  }

lib/mensageria/adaptadores.ts:47-61
  registro.enviar() → console.info(...) → { ok: true, provedor: "registro", ... }

lib/mensageria/worker.ts:88-102
  if (r.ok) → supabase.rpc("marcar_enviada", ...)
```

**Prova no banco de produção**, colhida em 02/09:

```
template            estado    provedor    provedor_msg_id           enviada_em
lembrete_de_sessao  enviada   registro    registro:1788346982148    2026-09-02 11:03:02
```

O próprio comentário do arquivo admite: *"a mensagem percorre a fila inteira, é
reservada, marcada como enviada e aparece na trilha — só não sai do prédio"*.
Vale para lembrete de véspera, aviso de desmarque, encaixe confirmado e pedido de
confirmação — as quatro "essenciais" que a OP9 deixou automáticas **inclusive no
Gratuito**.

**O padrão certo está no mesmo repositório:**
`lib/calendario/adaptadores.ts:86-88` declara `disponivel: false` e **recusa**,
com a razão escrita — *"marcar um espelho como espelhada sem ter id do outro lado
quebra a atualização seguinte"*. A mensageria escolheu fingir.

**E as telas públicas afirmam o contrário:** `app/(site)/page.tsx:819-821` diz
"pela API oficial da Meta"; `app/(site)/termos/page.tsx:134-135` diz "tudo é
automático"; `app/(site)/privacidade/page.tsx:111-113` declara um subprocessador
que não existe. *(Essas frases são conserto da B46 — aqui você conserta o
comportamento.)*

---

## S1-B · "Aqui diz que ela não respondeu. Eu não lembro de ter perguntado nada."

```
supabase/migrations/0057_a_confirmacao_ativa.sql:166-174
  enfileirar_mensagem(..., 'confirmacao_de_sessao', ...)

banco: public.templates → codigo='confirmacao_de_sessao', essencial=true

lib/mensageria/templates.ts:31-39
  export const FAMILIAS = [
    "oferta_de_vaga", "encaixe_confirmado", "lembrete_de_sessao",
    "aviso_de_desmarque", "aviso_de_cobranca", "lembrete_de_pagamento",
    "oferta_de_vaga_fixa",
  ] as const;            // ← sete. `confirmacao_de_sessao` não está aqui.

lib/mensageria/templates.ts:335-338
  if (!ehFamilia(template)) throw new Error(`Template desconhecido: ${template}`)
```

O `catch` do worker (`worker.ts:125-138`) chama `marcar_falha` até desistir na
quinta tentativa. Enquanto isso a 0057 já carimbou `eixo_confirmacao='pendente'`,
e `marcar_silenciosas()` o converte em `silenciosa` perto da hora. A faixa da
agenda passa a dizer "não respondeu".

**É a frase do cabeçalho da própria 0057**, palavra por palavra: *"a hora aparece
como 'não respondeu' sem nunca ter sido perguntada — e a psicóloga decide sobre
um silêncio que o sistema inventou."*

---

## S2 · "Toquei em 'Já mandei' e não aconteceu nada"

```
app/(app)/agenda/acoes.ts:489-495  mandeiPeloWhatsapp — sem try/catch
app/(app)/agenda/acoes.ts:504-510  naoVouMandar       — sem try/catch
lib/db.ts:45                       db() lança
components/app/NaSuaMao.tsx:141-146  await ...; setFeito("mandei")  — sem catch
```

Se o RPC falhar, `setFeito` não roda, nada aparece e o botão volta a ficar
clicável. **A oferta continua parada** — no canal manual o relógio da oferta só
começa quando ela registra o envio (decisão da OP9), então a vaga fica presa sem
sintoma. O plano Gratuito inteiro depende desse botão.

Efeito colateral do mesmo caminho: cada "Já mandei" faz
`revalidatePath("/agenda")` (`:492-493`), refazendo as ~15 consultas da agenda.
Oito envios num dia = oito recargas completas.

E quando `renderizar` falha (`NaSuaMao.tsx:91-95`), a tela diz "nada foi enviado"
**e mesmo assim** mostra "Abrir no WhatsApp", porque `linkDoWhatsapp`
(`lib/canal.ts:47-52`) só olha o destino: o toque abre a conversa com mensagem
vazia.

---

## Entrega

1. **`adaptadorPara` passa a recusar.** Sem provedor configurado, devolver um
   adaptador que responde `{ ok: false, definitivo: false, erro: "sem provedor
   configurado" }` — ou, melhor, um `disponivel: false` no padrão do calendário.
   A mensagem **não** é marcada como enviada.
2. **Mensagem sem canal de saída cai em `na_sua_mao`, em qualquer plano.** A
   caixa já existe (OP9, `components/app/NaSuaMao.tsx`), o estado já existe
   (`mensagens.na_sua_mao`), e `marcar_enviada_a_mao` já existe. O que muda é
   quem cai lá: hoje é o gatilho `mensagens_z_o_canal_do_plano` lendo
   `planos.canal_saida`; passa a ser também "não há provedor".
3. **A tela diz a verdade.** Onde hoje aparece "enviada", aparece "esperando você
   mandar" enquanto não houver provedor. Uma frase, não uma tela.
4. **`confirmacao_de_sessao` entra em `FAMILIAS`**, com o texto do template e a
   entrada em `PROIBIDAS_NO_DISCRETO` (`templates.ts:86-98`).
5. **A varredura que impede o quinto caso.** Uma verificação que compara
   `public.templates` com `FAMILIAS` e **reprova a diferença nos dois sentidos**.
   Lei 7 do `CLAUDE.md`: o invariante foi protegido contra teto de plano e contra
   canal, e ficou desprotegido contra sete strings num arquivo TypeScript.
6. **`try/catch` em `mandeiPeloWhatsapp` e `naoVouMandar`**, com o erro
   renderizado **no próprio item** da caixa "Na sua mão".
7. **`linkDoWhatsapp` só aparece quando há texto renderizado.**
8. **Revalidação mais estreita** no "Já mandei" — revalidar a caixa, não a agenda
   inteira.

---

## Pronto quando

- [ ] nenhuma linha de `public.mensagens` fica `enviada` sem que um provedor real
      tenha aceitado — verificado rodando `/api/mensageria` sem credencial e
      olhando a tabela;
- [ ] uma verificação compara `public.templates` com `FAMILIAS` e reprova a
      diferença; acrescentar um template só no banco reprova a suíte;
- [ ] um pedido de confirmação enfileirado hoje chega até o destino (ou até
      `na_sua_mao`), e **nunca** vira `falhou` por template desconhecido;
- [ ] derrubar o RPC do "Já mandei" mostra o erro no item e não deixa a fila
      parada;
- [ ] quando o texto não renderiza, não há botão de WhatsApp.

---

## Não entra

- **Ligar o BSP.** Isso é o relógio da Meta e leva semanas (ver
  `claude/28-fechar-as-pendencias.md`). Esta build existe para o produto **não
  mentir enquanto ele corre**, e não depende de terceiro.
- **Trocar o texto das telas públicas.** É a B46.
- **Segunda tentativa de confirmação ou botão de "liberar por silêncio".** O P3
  cortou os dois por resposta de campo; nada aqui os traz de volta.

---

## Armadilhas

- **Ligar o BSP primeiro e deixar o adaptador como está "porque logo sai".** O
  produto está no ar hoje. Consertar a mentira é meio dia.
- **Consertar só a lista de `FAMILIAS`.** Sem a varredura, o quinto caso aparece
  na semana que vem, pelo mesmo caminho.
- **Pôr um toast global no erro do "Já mandei".** Ela está com o polegar no item;
  o erro precisa estar no item, senão ela toca de novo e duplica.
- **Fazer o adaptador ausente lançar.** O comentário atual está certo nisso:
  estourar deixaria a fila parada em silêncio, que é pior. Ele deve **recusar com
  motivo**, e o motivo tem que chegar à tela.

---

## Arquivos que esta build toca

```
lib/mensageria/adaptadores.ts   ← o coração da build
lib/mensageria/templates.ts     ← FAMILIAS + o texto do template novo
lib/mensageria/worker.ts
lib/canal.ts
components/app/NaSuaMao.tsx
app/(app)/agenda/acoes.ts
supabase/tests/  ← a verificação templates × FAMILIAS
```

**Suítes a rodar depois:** `0017_outbox.sql` · `0021_respostas.sql` ·
`0046_*` e `0060_*` (as que exigem a **presença** de `enfileirar_mensagem` no
corpo de `avancar_fila`) · `0057_confirmacao_ativa.sql` · `0061_*`. O critério é
**que funções a mudança toca**, não que assunto ela trata.
