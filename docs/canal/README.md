# O canal — o que chegou de fora, e o que se aplica

*03/09/2026. Dois documentos entraram no repositório neste dia, e nenhum dos
dois é decisão de produto do Sessões até esta página dizer o que se leva.*

| documento | o que é | de onde vem |
|---|---|---|
| [`ESTRATEGIA-DO-CANAL-v5.md`](ESTRATEGIA-DO-CANAL-v5.md) | o **Anexo A** do pacote B49–B54: roteamento de saída, PIX próprio, validação do comprovante, a página como repositório | escrito para este produto, em 02/09 |
| [`ENTREGA-GARANTIDA-email-transacional.md`](ENTREGA-GARANTIDA-email-transacional.md) | arquitetura de e-mail transacional com confirmação de entrega | **outro produto** (Enquadria), extraído do código em produção |

**O Anexo A estava sendo citado e não existia aqui.** O pacote B49–B54 abre
dizendo que ele é o prompt de abertura da B52, da B53 e da B54, e aponta para
seções — §1 e §2, §3 e §4, §5 — que ninguém tinha como ler. Isso está corrigido.

---

## A tese que se leva inteira

> O provedor responde `success` quando a mensagem entra **na fila dele** — não
> quando o destino recebe.

É a frase que justifica os dois documentos existirem, e ela vale para o WhatsApp
tanto quanto para o e-mail. Este produto já aprendeu metade dela por outro
caminho: a **B43** existiu porque a tela afirmava envio que não houve, e a
**B50** acabou de separar `oferta_preparada` de `oferta_enviada` porque a trilha
dizia "enviada" onze vezes sem nenhuma mensagem ter saído.

O que o documento de fora acrescenta é o **grau seguinte**: mesmo depois de o
provedor aceitar, ainda não se sabe se chegou. E a resposta dele — confirmação
por webhook, janela, reenvio pelo caminho de queda, disjuntor — é a arquitetura
certa para isso.

---

## O que **não** se leva como está

### 1 · `emails_saida` seria a segunda fonte de verdade

O documento cria uma tabela própria com máquina de estados própria
(`aceito → entregue | falhou | perdido → reenviado`). **Este produto já tem essa
tabela**, e ela é `public.mensagens`: `chave_idem` garante que a mensagem existe
uma vez só, `reservar_mensagens` / `marcar_enviada` / `marcar_falha` /
`destravar_mensagens` são o ciclo de vida, e `na_sua_mao` é a camada manual que
o Anexo A depende.

Duas tabelas respondendo "esta mensagem saiu?" é **o antipadrão nº 1 do
`CLAUDE.md`**, e aqui ele seria sobre uma mensagem que chega numa paciente.

**A adaptação:** o registro continua em `mensagens`. O que falta lá é a
confirmação — uma coluna de "confirmada em", os estados que hoje não existem, e
o número de tentativas, que já existe.

| estado do documento | em `mensagens` |
|---|---|
| `aceito` | `enviada` — já existe, e passa a significar "o provedor aceitou" |
| `entregue` | `entregue` — já existe no `check`, e hoje ninguém escreve |
| `falhou` | `falhou` — já existe |
| `perdido` | **falta** |
| `reenviado` | **falta** |

### 2 · A janela de 20 minutos colide com a regra que a B50 acabou de escrever

`expirar_ofertas` só deixa a oferta expirar quando a mensagem **saiu** —
`enviada` ou `entregue`. Com a tese acima, `enviada` deixa de ser prova de
chegada: é prova de que o provedor aceitou.

Isso não invalida a B50, e é bom que apareça agora: a regra dela é sobre
*ninguém ter sido convidado*, e uma mensagem aceita pelo provedor **foi**
convidada. Mas o dia em que uma oferta sair por e-mail, a pergunta muda de
tamanho — e a decisão (esperar a confirmação, ou aceitar o `enviada`) é da B52,
que é onde o e-mail entra na cascata. A colisão 2 do pacote já dizia isso com
outras palavras.

### 3 · A trava contra a conclusão falsa já é o jeito da casa

A §6 do documento — *"sem nenhuma confirmação registrada, não se conclui perda
de ninguém"* — é a mesma forma da regra que a `0088` escreveu há poucas horas:
**oferta sem mensagem nenhuma segura**, porque ausência de sinal é falta de
instrumento, não evidência. Levar essa seção inteira é levar coerência, não
novidade.

### 4 · O corpo guardado é dado de paciente, e o provedor de queda é operador novo

Duas coisas que o documento resolve para o produto dele e **este produto tem de
resolver antes de aplicar**:

- **Guardar o HTML** do e-mail para poder reenviar *o documento* significa
  guardar, no banco, o conteúdo de um documento sobre uma paciente. O prazo tem
  de responder à retenção que a conta já declara (`contas.retencao_anos` e a
  `/privacidade`), não a uma constante nova de sete dias que ninguém conciliou.
- **O provedor de queda vê o conteúdo.** Pôr um segundo provedor na frente de
  documento de paciente acrescenta **um operador** ao inventário da política de
  privacidade. É o mesmo portão da B53 com o OCR do comprovante: *a cláusula tem
  de existir no doc `18` antes de a build abrir, não depois.*

### 5 · O adaptador que recusa já está construído, e é onde isto se pluga

`lib/mensageria/adaptadores.ts` devolve `semProvedor` para **todo** canal, com
`disponivel: false` e motivo escrito — é a lei 8. Toda a área logada e a página
pública já derivam as frases desse estado (B50). Quando o e-mail entrar, ele
entra **ali**, e as telas ficam verdadeiras juntas sem ninguém reescrever frase
nenhuma.

---

## Onde a configuração mora — decisão de 03/09

**O ambiente de configuração do WhatsApp e da mensageria fica em `/negocio`.**

`/negocio` é o painel do operador: `app/(app)/negocio/page.tsx:29` devolve
**404** — e não "acesso negado" — para quem não for operador. É o lugar certo
para o que é **infraestrutura da plataforma e não da conta dela**: credencial do
provedor próprio e do de queda, estado da instância, segredo do webhook,
disjuntor.

E é o lugar errado para o que é **por conta**, que continua onde está:

| o que | onde | por quê |
|---|---|---|
| credencial do provedor, disjuntor, estado da instância | `/negocio` | é uma configuração para a plataforma inteira, e ela não é operadora |
| `planos.canal_saida` (manual × plataforma) | vem do plano | é consequência do que ela assinou, não uma chave que ela vira |
| a mensagem esperando o dedo dela | Agenda → **Na sua mão** | é tarefa, não configuração |
| o que a tela pode afirmar sobre envio | derivado, nunca digitado | `envioAutomaticoLigado()`, desde a B50 |

**A consequência que não pode se perder:** as telas dela nunca leem a
configuração — leem o **estado que resulta** dela. É isso que faz a área logada
e a página pública ficarem verdadeiras juntas no dia em que o provedor entrar,
sem ninguém reescrever frase nenhuma.

---

## A fronteira 8 — decidida em 03/09

**O `CLAUDE.md` proíbe, na fronteira 8, "Evolution / API não-oficial de
WhatsApp".** A estratégia do canal é construída sobre exatamente isso: os dois
kits de origem são o `evolution-worker` e o `contatia-whatsapp-kit`, e o §1 traz
`integration: "WHATSAPP-BAILEYS"`, QR gerado localmente, `logout` + `delete` e
instância multi-conta. O `waModo` do kit tem quatro modos — assistido, híbrido,
**evolution**, **meta** —, e o critério de aceitação do §7 diz "nenhuma rota
chama a função crua da Evolution", que é regra de encapsulamento, não de
abstinência.

**Decisão de 03/09: vale o documento, e a fronteira 8 do `CLAUDE.md` foi
reescrita** para dizer isso e para guardar o que a decisão **não** afrouxa —
está tudo lá, na lei, não aqui.

Em resumo: template de classe `documento` nunca sai por canal não oficial; toda
saída passa pela interface `CanalMensagem`, e nenhuma rota chama a função crua
do transporte; a regra do 9º dígito é trava de sigilo, porque a versão ingênua
manda a mensagem sobre a consulta de uma paciente para um estranho. E o risco
ficou escrito: número banido é a agenda dela parada, e a conta é dela.

**A B52 está aberta.** O que a mantém atrás da B55 na fila é só a dependência
técnica: o e-mail é um degrau da cascata.

---

## O que ainda falta, e não é código

| o que | por quê |
|---|---|
| conta no provedor próprio (VPS + Postal) e no de queda | a arquitetura chegou; as credenciais não |
| SPF, DKIM, DMARC e PTR do domínio de envio | passo 1 da ordem de implantação do documento, e sem ele o resto não adianta |
| a cláusula do doc `18` sobre o operador de e-mail | ver o item 4 acima |


**A ordem de implantação do documento não é sugestão.** Ligar o cron antes do
webhook produz o cenário que ele descreve na §6: tudo vira "perdido", a base
inteira é reenviada a cada 15 minutos, o disjuntor abre, e o remédio mata o
paciente — sem uma linha de erro em lugar nenhum.

---

## O estudo da camada inteira

Os dois documentos resolvem metades diferentes — por onde sai, e como se sabe
que chegou (só no e-mail). O que falta entre eles, e os oito buracos que a
camada precisa fechar para não virar duas integrações lado a lado, está em
**[`CAMADA-DE-COMUNICACAO.md`](CAMADA-DE-COMUNICACAO.md)**.

## A build que aplica isto

**[B55 · A entrega do e-mail se confere](../builds/B55-a-entrega-do-email-se-confere.md)**,
e ela vem antes da B52 e da B54 na fila — as duas dependem de e-mail que chega.
