# O que falta construir — a fila, na ordem

*Consolidado em 02/09/2026, a partir do `claude/20-o-que-falta-construir.md` e
da auditoria de UX (`claude/30-auditoria-de-ux.md`). **Esta é a lista que se usa
para trabalhar.** Os roadmaps 12, 16 e 17 são história do raciocínio.*

Cada arquivo desta pasta **é o prompt de abertura da build**. Entrega,
pronto-quando e não-entra são o escopo fechado. Leia o `CLAUDE.md` da raiz antes
de abrir qualquer um.

---

## A ordem

| # | build | dias | por que aqui | arquivo |
|---|---|---|---|---|
| 1 | **B48** · O campo faz o que ela digitou | 3 | dois S1 aqui dentro, e é a metade do produto que ela toca todo dia | [B48](B48-o-campo-faz-o-que-ela-digitou.md) |
| 2 | **B43** · A mensagem diz onde está | 2 | o produto está no ar afirmando fato falso sobre paciente | [B43](B43-a-mensagem-diz-onde-esta.md) |
| 3 | **B44** · Um mês, um número | 2 | segunda fonte de verdade sobre dinheiro | [B44](B44-um-mes-um-numero.md) |
| 4 | **B39** · Evolução por ditado, e o registro que não se perde | 3 | prontuário gravado no paciente errado | [B39](B39-evolucao-por-ditado.md) |
| 5 | **B46** · A quarta varredura | 1 | antes da primeira pagante, porque é contrato | [B46](B46-a-quarta-varredura.md) |
| 6 | **B45** · A segunda-feira de manhã | 1,5 | a tela que ela abre todo dia | [B45](B45-a-segunda-feira-de-manha.md) |
| 7 | **P7** · A página transacional única | 2 | fecha a porta de fora | [P7](P7-a-pagina-transacional-unica.md) |
| 8 | **P8** · O assistente do Receita Saúde | 1 | a tela intermediária existe e é pior que não existir | [P8](P8-o-assistente-do-receita-saude.md) |
| 9 | **B31** · Plano terapêutico e encerramento guiado | 2,5 | | [B31](B31-plano-terapeutico-e-encerramento.md) |
| 10 | **B32** · Documentos da Res. 06/2019 e a gaveta | 3,5 | | [B32](B32-documentos-res-06-2019.md) |
| 11 | **B47** · O dia dela custa menos toques | 2,5 | a vassoura: 27 S3/S4 num número de dias só | [B47](B47-o-dia-dela-custa-menos-toques.md) |
| 12 | **B36** · Reajuste sem saia justa e modo férias | 3 | | [B36](B36-reajuste-e-modo-ferias.md) |
| 13 | **B34** · Pré-ficha administrativa | 2 | | [B34](B34-pre-ficha-administrativa.md) |
| 14 | **OP7** · Suporte com chamados | — | só quando o e-mail deixar de dar conta | [OP7](OP7-suporte-com-chamados.md) |

**Soma: 32,5 dias** (as 13 com estimativa). Eram 25,5 antes da auditoria; ela
acrescentou 14 e tirou 7 (**B38** e **B12b** saíram — ver
[`_arquivadas.md`](_arquivadas.md)).

**Os quatro primeiros são 10 dias e fecham os seis S1.** Não corte esses.

---

## Onde o produto está hoje

**103 migrações aplicadas · 45 suítes SQL adversariais · ~950 testes unitários ·
build de produção limpo.** Próxima migração livre: **`0066`**.

| trilha | entregue | falta |
|---|---|---|
| **B** produto | B0–B11, B13, B14, B16–B29, B33, B40, B41 | B31, B32, B34, B36, B39 |
| **P** integridade da receita | P1, P2, P3, P4, P5, P6 | P7, P8 |
| **OP** operação | OP1–OP6, OP8, OP9, OP10 | OP7 |
| **B4x** da auditoria de UX | — | B43, B44, B45, B46, B47, B48 |
| fora de trilha | Panorama · blog · documentos legais · ficha em abas | — |

**As três peças que não são build** — não dependem de teclado, dependem de uma
credencial cada:

| peça | o que falta | o que muda quando existir |
|---|---|---|
| Cliente HTTP do Asaas (B16) | credencial do provedor | o Pix da assinatura e a conciliação automática |
| Adaptador de e-mail com anexo (B25) | provedor de e-mail | a pasta do contador sai sozinha, e a régua da assinatura para de depender do Leandro |
| Cliente da Google Agenda (B26) | OAuth + Calendar API | o espelho da agenda sai da fila |

---

## O que bloqueia, e não é código

**A conversa com a psicóloga.** Não é build e é a coisa mais atrasada do
projeto. Bloqueia cinco decisões:

1. os modelos de evolução (livre, DAP, BIRP, SOAP) — um padrão por omissão molda
   o registro de todo mundo;
2. o "número 3" do aviso de anamnese aberta, que mora sozinho em
   `sessoes_ate_fechar_anamnese()` e a tela admite ser palpite;
3. a fronteira da B27 (anotar falta sem poder anotar a sessão);
4. o tamanho do **P8** — com que periodicidade ela executa o Receita Saúde;
5. **o formulário de cadastro** — a pergunta que a auditoria de UX acrescentou:
   *"me mostra como você anota hoje o dia, a hora e o valor de uma paciente
   nova"*. Decide se a política de falta se pergunta em número ou em palavra, e
   se o cadastro de 17 campos é o formulário certo.

Nenhuma build desta fila espera pela conversa, exceto o **tamanho** do P8.
