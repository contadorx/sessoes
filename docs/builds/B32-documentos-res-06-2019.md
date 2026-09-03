# B32 · Documentos da Res. 06/2019 e a gaveta

**3,5 dias (era 3; +0,5 pelo S2 da auditoria) · migração: a definir · décima da fila**
**Códigos:** PR10, PR11.

---

## Entrega

**1 · Os cinco documentos** da Res. CFP 06/2019 — declaração, atestado
psicológico, relatório psicológico, relatório multiprofissional, parecer — cada
um com **estrutura própria** e numeração, reusando o motor da B17.

**A fonte é o Manual Orientativo de nov/2025, não a resolução sozinha.** Ele traz
os quadros comparativos, a linguagem, a validade, a guarda e o descarte de cada
um; a resolução sozinha não basta.

A **declaração de comparecimento** sai com texto discreto por padrão: não nomeia
psicoterapia a menos que ela queira.

**2 · A gaveta.** Anexos com `acesso_exclusivo` — o **Registro Documental** da
Res. 001/2009: testes psicológicos, protocolos, material que não se entrega.
Acesso só dela (+ o Sistema Conselhos, e a justiça quando requisitada).

Isto **não é a mesma pilha** do Prontuário Psicológico, e a diferença é
invariante de banco, não escolha de tela: um teste psicológico anexado **não vai**
na cópia que o paciente leva; o resto vai.

**3 · O S2 da auditoria: `cancelar_documento` não tem tela.**

```
app/(app)/fechamento/documentos/acoes.ts:78-108   cancelarDocumento — existe e está correto
grep "cancelarDocumento" em *.tsx                  — zero importações
app/(app)/fechamento/documentos/[id]/page.tsx:61-67 e :202-206
                                                   — a tela JÁ SABE desenhar o cancelado
```

A ação existe, a tela sabe renderizar o resultado, e não há botão que o produza.
Um recibo emitido com o valor errado — que leva o nome e o CRP dela — **não se
cancela pela interface**. É um irreversível ao contrário: o irreversível é não
poder desfazer.

**A palavra importa:** a `/privacidade` foi corrigida na B41 justamente para
dizer que documento **se cancela**, com data e motivo, e não se exclui. O botão
usa a palavra da página.

---

## Pronto quando

- [ ] **cada tipo recusa ser emitido sem a estrutura que a resolução exige** —
      verificado tentando emitir cada um dos cinco incompleto;
- [ ] **anexo exclusivo não aparece na exportação do paciente** — verificado
      rodando `exportar_paciente` numa ficha que tenha um;
- [ ] **todo documento emitido se cancela pela tela, com motivo**, e o
      cancelamento aparece na cópia impressa;
- [ ] toda cópia sai marcada "cópia de documento sigiloso";
- [ ] a numeração não se repete nem pula, e documento publicado não muda.

---

## Não entra

- **Modelo por abordagem** (N2, morto).
- **Assinatura digital / ICP-Brasil.** Não é exigência da 06/2019 para estes
  documentos, e é uma build inteira.
- **Excluir documento.** Ele se cancela.

---

## Armadilha

**Tratar a gaveta como uma flag na mesma tabela e confiar na tela para filtrar.**
A separação entre Prontuário e Registro Documental precisa ser invariante de
banco — é a lição de `exportar_paciente`, e a exportação é justamente onde o
vazamento aconteceria.

---

## Arquivos que esta build toca

```
app/(app)/fechamento/documentos/  (page, [id]/page, acoes)
components/app/EmitirDocumento.tsx   components/app/Acervo.tsx
components/app/Imprimir.tsx
supabase/migrations/  (estrutura por tipo, acesso_exclusivo)
```

**Nota de arquitetura, já decidida:** o motor de PDF deste produto **é o
navegador**, e o `Imprimir.tsx` explica por quê — biblioteca de PDF em serverless
significa posicionar texto à mão, e o conteúdo aqui é de tamanho variável. Não
reabra isso.
