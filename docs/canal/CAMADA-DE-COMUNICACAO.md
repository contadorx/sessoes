# A camada de comunicação — o estudo

*03/09/2026. Escrito depois de os dois documentos entrarem no repositório, e
para responder a pergunta que eles não respondem juntos: **como o produto sabe
que a mensagem chegou, e o que ele faz quando não chegou.***

Os dois documentos são bons e resolvem metades diferentes. A
[estratégia do canal](ESTRATEGIA-DO-CANAL-v5.md) resolve **por onde sai**; a
[entrega garantida](ENTREGA-GARANTIDA-email-transacional.md) resolve **como se
sabe que chegou** — mas só no e-mail, e com uma tabela própria. Nenhum dos dois
resolve **o que se vê quando o conjunto está degradado**, que é o que uma camada
de comunicação precisa ter para não virar duas integrações lado a lado.

---

## A tese: três eixos, e o banco só tem um

Toda mensagem deste produto responde a três perguntas independentes:

| pergunta | onde ela mora hoje | governa |
|---|---|---|
| **quem se machuca se não for?** | `templates.essencial` | teto de plano — o essencial nunca é barrado |
| **quanto valor ela perde com atraso?** | *não existe* | roteamento, cascata, ordem da fila |
| **como eu sei que ela chegou?** | *não existe* | reenvio, disjuntor, e o que a tela pode afirmar |

A estratégia acrescenta o segundo (`templates.classe`). O repasse de e-mail
acrescenta o terceiro, para um canal só. **A camada de comunicação é o terceiro
eixo aplicado aos três canais, sobre o outbox que já existe.**

E o eixo três muda o que o produto pode dizer. A B43 e a B50 já brigaram com
isso duas vezes: a tela afirmava envio que não houve. Sem confirmação, "enviada"
significa *o provedor aceitou* — e é tudo o que se pode escrever.

---

## O que se leva, o que se descarta

**Uma tabela, não duas.** `public.mensagens` já é o registro de saída:
`chave_idem` (existe uma vez só), `reservar_mensagens` / `marcar_enviada` /
`marcar_falha` / `destravar_mensagens` (ciclo de vida), `na_sua_mao` (a camada
manual), `tentativas`, `provedor_msg_id`. O `emails_saida` do repasse seria a
segunda fonte de verdade sobre "a mensagem saiu?" — antipadrão nº 1, sobre
mensagem que chega numa paciente.

**Um disjuntor por (conta × canal), não um global e um por instância.** O
repasse tem um disjuntor global de e-mail; a estratégia tem health check por
instância de WhatsApp. São a mesma peça com escopos diferentes, e a regra que
vale para as duas é a do repasse, porque é a mais dura: **abre por taxa de
perda, fecha só por evidência — nunca por tempo.** O que o tempo autoriza é
*sondar*.

**A cascata termina na mão dela, e isso é decisão de produto.** Ordem:
instância A → instância B → e-mail → **painel manual**. O painel é o último
degrau porque depende de humano acordado; e é o último degrau *que existe*
porque a conta de WhatsApp é dela — um segundo transporte automático seria o
produto assumindo um risco que quem paga é ela.

---

## Os oito buracos, e o que fazer com cada um

Isto é o "ampliar". Cada linha é uma coisa que **nenhum dos dois documentos
cobre** e que a camada precisa para funcionar como camada.

### 1 · Confirmação de entrega só existe no e-mail

A tese do repasse — *`success` é "entrou na fila dele", não "chegou"* — vale
**mais** no WhatsApp, não menos: um transporte não oficial responde `sent` com o
número já banido. `mensagens` precisa de `confirmada_em` e dos estados
`perdida` / `reenviada`, e o webhook de cada canal alimenta os mesmos campos.

### 2 · Ninguém usa o custo, e ele está no banco desde sempre

`precos_canal` guarda, em milésimos de centavo: **e-mail 200 · WhatsApp 4.500 ·
SMS 8.000**. O e-mail é **22× mais barato** que o WhatsApp e **40× mais barato**
que o SMS, e a tabela de roteamento da estratégia escolhe canal sem olhar para
ela. Duas consequências:

- a cascata deve preferir e-mail antes de SMS **sempre que a classe tolerar** —
  hoje ela manda "e-mail + SMS" para urgente, o que custa 40× por uma
  redundância que raramente muda o desfecho;
- o teto de plano é contado em **mensagens**, não em dinheiro. Uma conta que
  estoura o teto por lembrete de e-mail está sendo barrada por R$ 0,002.

### 3 · Dedup cross-canal é nomeado e não é construído

A estratégia diz que a chave de entrega é `(oferta_id, destinatário)`, e o
outbox tem `chave_idem` por mensagem. Sem a chave de entrega, a cascata manda a
mesma oferta por WhatsApp **e** por e-mail, e a paciente recebe duas — que é o
jeito mais rápido de a psicóloga desligar o canal.

### 4 · Não existe o catálogo dos silêncios

Um sistema de mensagens falha **calado**, e cada silêncio tem um sintoma
diferente. Isto é o coração do monitor:

| silêncio | como se detecta | o que ele faz se ninguém olhar |
|---|---|---|
| webhook mudo | nenhuma confirmação na janela, com saídas > 0 | tudo vira "perdida", a base é reenviada, o disjuntor abre e desliga o canal que estava bom |
| cron parado | data da última varredura > 3 ciclos | nada é reenviado e nada denuncia |
| instância caída | `statusConexao` em erro/desconectado | as mensagens ficam paradas com cara de fila normal |
| teto do plano batido | `barrada_no_teto` | a fila queima em silêncio (era o S1 que a `0088` fechou) |
| disjuntor aberto | estado do disjuntor | tudo sai pelo canal de queda, com o custo dele |
| provedor ausente | `adaptadorPara(canal).disponivel` | a mensagem vai para a mão dela — e isso é o desenho, não a falha |

**A trava contra a conclusão falsa vale para os três canais:** sem nenhuma
confirmação na janela, não se conclui perda de ninguém. Ausência total de sinal
é falta de instrumento, não evidência — a mesma forma da regra que a `0088`
escreveu para a oferta sem mensagem.

### 5 · O monitor não tem casa, e agora tem

`/negocio` — decidido em 03/09. Uma tela, e ela responde três perguntas na
ordem: **o que está cego · o que está degradado · o que está parado.** Por conta
e por canal, com o motivo escrito e a data da última varredura à vista.

Nada de gráfico bonito: cada linha precisa dizer o que fazer.

### 6 · O que ela vê quando a camada degrada

A regra: **degradação que precisa da mão dela é visível; o resto é nosso.**

| acontece | ela vê |
|---|---|
| instância caiu, rotina foi para a mão dela | a caixa "Na sua mão", que já existe |
| disjuntor abriu e o e-mail assumiu | **nada** — chegou, e por qual cano é problema nosso |
| teto do plano batido | a faixa do plano, que já existe |
| webhook mudo | **nada** — mas o produto para de afirmar entrega |

O último item é o que amarra tudo: as frases da tela derivam do estado desde a
B50, e a camada só acrescenta um estado a mais para elas derivarem.

### 7 · A entrada é meio caminho, e não tem monitor nenhum

`app/api/whatsapp/route.ts` existe, com token, idempotência e
`responder_do_whatsapp`. O que não existe é a leitura: quantas respostas
chegaram, quantas o banco **não entendeu** (`resposta_nao_entendida` já é tipo
de evento), quantas viraram aceite. Uma taxa alta de não-entendidas é a fila
funcionando e o produto parecendo quebrado.

### 8 · Retenção, e o operador novo

O corpo guardado para reenvio é documento de paciente parado no banco: o prazo
responde a `contas.retencao_anos` e à `/privacidade`, não a uma constante nova.
E cada provedor que passa a ver conteúdo — o de queda do e-mail, o transporte do
WhatsApp — **é operador no inventário da política de privacidade**. A cláusula
existe antes, não depois. É o mesmo portão da B53.

---

## O que isso vira, em builds

A ordem é a de dependência, e cada uma é entregável sozinha.

| build | o que fecha | depende de |
|---|---|---|
| **B55** · a entrega do e-mail se confere | eixo 3 no e-mail: confirmação, reenvio, disjuntor, a trava do instrumento | contas nos provedores |
| **B52** · o canal entrega, e a oferta fura a fila | eixo 2: `templates.classe`, roteamento, cascata, a oferta furando a fila | B55 (o e-mail é degrau da cascata) |
| **B56** · o painel do canal *(novo)* | os buracos 4, 5 e 7: o catálogo dos silêncios, a tela em `/negocio`, a leitura da entrada | B52 e B55 |
| **B57** · o canal escolhe pelo custo *(novo)* | o buraco 2: `precos_canal` entra no roteamento e no teto | B52 |

Os buracos **1, 3, 6 e 8** não viram build própria: são linhas dentro da B55 e
da B52, e estão anotadas ali.

---

## As três coisas que eu não decidiria sozinho

**A primeira virou configuração em 03/09 (B57): ela não espera mais por mim.**
`rota_do_canal` guarda a cascata por classe, em ordem, com o motivo de cada
degrau escrito — e o painel do operador mostra, na mesma tela, o que a rota
custa por mensagem no pior caso. Tirar o SMS da urgente é apagar uma linha.

1. ~~**SMS na cascata de urgente.**~~ Continua sendo decisão de risco contra
   dinheiro — e agora é uma linha do banco, não um commit. O degrau está lá,
   com o motivo escrito: *"custa 40x o e-mail: está aqui até alguém decidir que
   não vale"*.
2. **Quantas instâncias de WhatsApp por conta.** A estratégia pressupõe duas
   (`urgente` e `rotina`). Duas instâncias é o dobro de números para manter
   aquecidos, e o benefício só aparece com volume.
3. **O que fazer quando o disjuntor abre no meio da janela de silêncio.** Urgente
   fura a janela; rotina espera. Quem decide o que é urgente é a tabela de
   roteamento, e ela é uma decisão de produto, não de infraestrutura.
