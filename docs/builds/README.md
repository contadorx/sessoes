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

### E o pacote B49–B54, que entrou em 03/09

Vem da auditoria cega do GPT (docs `33` e `34`) e da estratégia de canal versão
5. Os seis moram **num arquivo só**, e é decisão: as colisões entre a B50 e o
Anexo A só fazem sentido lidas juntas —
[B49–B54](B49-B54-o-pacote-de-abertura.md).

| ordem | build | dias | por que aqui |
|---|---|---|---|
| 1 | ~~**B49** · o comando faz o que ele diz~~ | 2 | **entregue em 03/09** — um S1 de tarefa que não acontece e outro de dado que some em silêncio |
| 2 | ~~**B50** · a oferta só anda depois de sair~~ | 1,5 | **entregue em 03/09** (migrações `0088` e `0089`) — a fila podia queimar inteira sem ninguém ser convidado |
| 3 | ~~**B55** · a entrega do e-mail se confere~~ | 3 | **entregue em 03/09** (migração `0091`) — falta só ligar as contas dos provedores — [B55](B55-a-entrega-do-email-se-confere.md) |
| 4 | ~~**B52** · o canal entrega, e a oferta fura a fila~~ | a estimar | **entregue em 03/09** (migração `0092`) — classe, cascata e a fronteira 8 em código |
| 5 | ~~**B56** · o painel do canal~~ | a estimar | **entregue em 03/09** (migração `0093`) — o catálogo dos silêncios, em `/negocio` |
| 6 | ~~**B57** · o canal escolhe pelo custo~~ | a estimar | **entregue em 03/09** (migração `0094`) — a cascata virou `rota_do_canal`, configurável, com o custo à vista |
| 7 | **B53** · o PIX é dela, e o comprovante propõe | a estimar | depende da cláusula do doc `18`, não de código |
| 8 | ~~**B54** · a página vira o repositório~~ | a estimar | **a metade de teclado saiu em 03/09** (migrações `0095` e `0096`) — a linha do mês, o aviso que não leva o documento. A `0096` é o conserto que a suíte 0066 cobrou: a lista mostra que o recibo antigo existe e não entrega o id dele. A fechadura do §5.5 fica no backlog: ela é código por e-mail, e não há provedor |
| 9 | ~~**B51** · de quem é esta tela~~ | 1 | **entregue em 03/09** — e ela achou um S1 vivo: o livro-razão não abria para conta nenhuma |

**As três primeiras somam 4,5 dias; o anexo não traz estimativa e ninguém
inventou uma.** A **B49, a B50, a B51, a B52, a B55, a B56, a B57 e a metade de
teclado da B54 saíram em 03/09**. O que resta do pacote — a **B53** inteira e a
**fechadura do §5.5**, da B54 — não depende de teclado: a B53 espera a cláusula
do doc `18`, e a fechadura espera a conta do provedor de e-mail. É sobre isso
que entrou a
**B55**: dois documentos chegaram em 03/09 e agora moram em
[`docs/canal/`](../canal/) — a estratégia do canal, que o pacote citava sem
existir no repositório, e um repasse técnico de arquitetura de e-mail
transacional, de outro produto. **O que se leva de cada um, o que colide com o
que já existe e o que fica bloqueado por documento está em
[`docs/canal/README.md`](../canal/README.md)** — o repasse não é decisão de
produto até aquela página dizer o que é.

### A camada de comunicação — o estudo de 03/09

Os dois documentos do canal resolvem metades diferentes: um diz **por onde sai**,
o outro diz **como se sabe que chegou** — e só no e-mail. O que falta entre eles
está em [`docs/canal/CAMADA-DE-COMUNICACAO.md`](../canal/CAMADA-DE-COMUNICACAO.md),
com oito buracos nomeados. Os quatro que mais mudam a fila:

- **Confirmação de entrega só existe no e-mail.** A tese vale mais no WhatsApp,
  não menos: transporte não oficial responde `sent` com o número já banido.
- **`precos_canal` está no banco desde sempre e ninguém usa.** E-mail R$ 0,002 ·
  WhatsApp R$ 0,045 · SMS R$ 0,08. A cascata manda "e-mail + SMS" para urgente
  sem olhar que o SMS custa **40×**, e o teto do plano conta mensagens em vez de
  dinheiro.
- **Não existe o catálogo dos silêncios.** Webhook mudo, cron parado, instância
  caída, teto batido, disjuntor aberto — cada um falha calado e com sintoma
  diferente. É o coração da **B56**.
- **Dedup cross-canal é nomeado e não é construído.** Sem a chave de entrega
  `(oferta_id, destinatário)`, a cascata manda a mesma oferta por dois canais.

### O que a B54 entregou, e o que ela deixou escrito que não entregou

**Entregue (migração `0095`):**

- **`linhas_do_mes`, e ela é uma só.** A tela dela (`meses_do_paciente`) e a
  página do paciente (`pagina_do_paciente`) chamam a **mesma** função. A
  verificação 1 da suíte `0095` compara as duas saídas e reprova se
  divergirem — é a lição da 0090, onde `retorno` e `financeiro_do_mes`
  discordavam em R$ 750,00 contra R$ 0,00 sobre o mesmo mês.
- **A competência, e não a cobrança.** Amarrar recibo a `cobranca_id` quebraria
  na primeira psicóloga que cobra por sessão e emite recibo por mês. A suíte
  planta um recibo de 01/07 a 30/09 e prova que ele aparece nos **três** meses.
- **`lib/meses.ts`: fato no banco, palavra no TypeScript.** Nenhum "pago", "em
  aberto" ou "disponível" existe em SQL, e nenhuma das duas telas escreve
  rótulo próprio — `marcasDoMes` monta as três marcas, na mesma ordem, para as
  duas. `testes/a-linha-do-mes-tem-uma-lingua-so.test.ts` reprova a segunda
  versão da frase e reprova a divergência entre as chaves do
  `jsonb_build_object` e os campos de `LinhaDoMes` (o defeito que matou a 0053
  em silêncio, em miniatura).
- **O aviso que não leva o documento** (§5.2): template `documento_disponivel`,
  classe `rotina`, e é ele que resolve a tensão da classe `documento` — o
  recibo nunca trafega, a mensagem carrega só o aviso e o papel fica na página.
  Ele **não carrega URL**: o banco não conhece o endereço deste produto, e link
  montado com endereço chutado é link quebrado no celular de uma paciente.
- **Avisar é botão, não efeito colateral.** `emitir_documento` continua não
  avisando ninguém — "o default que decide por ela" é antipadrão do §9, e há
  emissão que é só contabilidade dela, em lote, no fechamento. A verificação 7
  prova que emitir não põe mensagem na fila.

**Escrito e não entregue, com o motivo:**

- **A quarta marca, `Comprovante`.** Depende da tabela `comprovantes` (§4.8),
  que é da B53 — bloqueada pela cláusula do doc `18`. Ela **não aparece**: nem
  como "não enviado", nem cinza, nem desabilitada. Lugar em branco esperando
  feature é "a promessa que o software não cumpre".
- **A fechadura do download (§5.5).** É código de seis dígitos por e-mail, e
  não há adaptador de e-mail. A alternativa do anexo é cair para a data de
  nascimento — que sem limite de tentativa é fechadura de mentira, e com limite
  é uma decisão de quantas tentativas, que é dela. Por isso **nenhuma porta
  nova se abriu**: o documento continua com a janela de 90 dias da 0066, e
  `recibo_na_janela` faz a lista não oferecer o que a porta recusa. A
  verificação 4 confere as duas leituras uma contra a outra.

### O que a suíte 0066 achou contra a B54, no mesmo dia

**Rodar a suíte antiga que a migração toca não é zelo: é o critério de
regressão deste projeto**, e ele pagou na primeira vez em que foi aplicado
depois da 0095. A `0066` reprovou, e os dois achados viraram a `0096`.

- **O id do recibo fora da janela estava saindo na página do paciente.** A
  verificação 12 da 0066 diz, desde o P7, que *"recibo velho ele pede a ela,
  como sempre pediu"* — e `linhas_do_mes` devolvia o id de todo documento que
  cobre o mês, inclusive o de duzentos dias atrás. O id sozinho não abre nada
  (`documento_do_link` recusa, e a suíte prova isso nos dois sentidos), mas um
  id numa página de portador é metade de uma URL e a outra metade é pública: a
  defesa passaria a ser só a checagem de data dentro de uma função. **O §5.5 da
  estratégia previu exatamente isto** — o repositório permanente muda o perfil
  do link, e a fechadura que compensaria é código por e-mail, que não existe.
  Eu entreguei a metade que amplia a exposição e deixei fora a que a compensa; a
  `0096` desfaz a ampliação.
- **`p_so_na_janela` nasce ligado**, e é decisão: `pagina_do_paciente` não
  precisou ser reescrita, e quem quiser o id **pede** — há um lugar só que pede,
  com o motivo escrito ao lado. O defeito de hoje nasceu de um `default` que
  abria.
- **O mês fantasma.** Um recibo trimestral cria três competências e as cobranças
  podem estar lançadas em uma só: as outras duas vinham com `combinado: 0,
  quantos: 0`, e a tela escrevia *"R$ 0,00 · nenhum horário"* ao lado de um
  recibo de R$ 800. Agora escreve travessão — a tela não se contradiz sobre o
  mesmo mês.
- **E o efeito colateral do conserto, achado ao consertar:** com o id nulo,
  `marcaDoRecibo` lia "não emitido" sobre um recibo emitido. A existência passou
  a ser `recibo_em`, não o id — senão a página mandaria a pessoa cobrar dela um
  papel que ela já fez.

A verificação 12 da 0066 ficou com a redação corrigida em vez de removida: a
frase *"não há extrato nesta página"* deixou de ser verdadeira quando a B54
entrou, e o que continua valendo — **nenhum id de registro numa página de
portador** — está escrito ali com o motivo. É a mesma coisa que a 0022 fez
quando o P4 tirou a cobrança automática.

### O que a B51 achou que não estava no documento dela

- **O livro-razão não abria para conta nenhuma, e ninguém sabia.** A consulta
  pedia `profissionais.nome`, e **essa coluna não existe** — o nome mora em
  `usuarios.nome`, pela FK. Entrou na B44 (`a946c95`), junto com a correção que
  fez a tela usar a profissional da sessão, e derrubava "o que aconteceu com
  cada hora" desde então: `db()` lança quando o PostgREST recusa a coluna.
- **Uma quarta e uma quinta consulta arbitrárias**, além das três listadas:
  `/perfil/contrato` punha o CRP de outra pessoa na prévia do contrato, e o
  `.eq("ativo", true).limit(1)` dos horários é filtro que não escolhe ninguém —
  por isso a varredura exige `eq("id", …)` ou `order()`, e não "algum filtro".
- **O defeito do Perfil era pior do que "mostra a pessoa errada".** O formulário
  nasce preenchido com o que a consulta trouxe e a ação grava em
  `sessao.profissionalId`: abrir e salvar **copiava o CRP da colega para cima do
  próprio**.

### O que a B49 achou que não estava no documento dela

Três coisas, todas da mesma família — o produto oferece e não cumpre —, e as
três só apareceram porque a entrega obrigou a passar por elas:

- **A sessão marcada à mão inflava dinheiro recuperado.** `criarEncaixe` cravava
  `origem = 'encaixe'` em toda sessão marcada fora da recorrência, e a lista de
  quem aparece no formulário é `pacientesParaEncaixe()` — todo paciente ativo,
  sem vaga nenhuma envolvida. A `financeiro_do_mes` (0037:465-472) soma "o que
  voltou" por `origem = 'encaixe'` **sem casar com vaga**, e `fraseDoRecuperado`
  escreve na tela *"N horas que a fila preencheu"*. Quem preenche vaga é a fila,
  e é `responder_oferta` que registra isso — lido do `pg_get_functiondef`. A
  marcação à mão passou a gravar `'avulsa'`.
- **Duas ações a mais engoliam o próprio erro**, além das sete listadas:
  `sairDaFila` e `removerAusencia`. Nenhuma lista as teria achado; a varredura
  achou, e agora reprova a próxima (lei 7).
- **`/recebimentos?novo=entrada` não tinha o que abrir.** Não existe recebimento
  avulso neste produto: dinheiro entra contra uma sessão realizada, que é o que
  permite emitir recibo (0037). O item de menu passou a apontar para a seção
  onde essas horas estão listadas, em `/recebimentos/movimentacoes`.

**E uma S2 ficou de pé aqui e saiu em 03/09, na migração `0090` — com o par que
eu tinha nomeado errado.** A primeira redação dizia "`reposta_por` (0056) contra
`origem = 'encaixe'` (0037)", e `reposta_por` é outra coisa: é a **remarcação**,
a mesma paciente consumindo outra hora com o mesmo dinheiro — duas horas de
capacidade, uma receita. Está no comentário da coluna, lido do banco.

O par que discordava de verdade é **`retorno` (agenda) contra
`financeiro_do_mes` (movimentações)**, e a diferença era o estado da sessão: a
primeira contava toda encaixe não cancelada, inclusive a que ainda vai
acontecer; a segunda, só `realizada`. Na conta de demonstração isso era
**R$ 750,00 contra R$ 0,00**, com a agenda escrevendo o número em serifa de
26 px embaixo de *"que não teria entrado sem a fila e sem a política"* — sobre
quatro sessões que ainda não tinham acontecido. A `0090` separou
`valor_preenchido` (aconteceu) de `valor_agendado` (marcado), a falta ficou fora
das duas somas, e a suíte `0090` prova que as duas telas passam a concordar.

> **A B50 saiu nas migrações `0088` e `0089`** — nem a `0084` do título dela,
> nem a `0086` da nota de arquivamento: as duas foram ocupadas antes, no mesmo
> 03/09. O corpo do documento não foi corrigido de propósito — ele é o prompt de
> abertura, e reescrever prompt de abertura é como se perde o que ele dizia.
>
> Ela virou **duas** migrações porque são dois defeitos: a `0088` é o relógio
> (só expira o que saiu), e a `0089` é o rótulo (a trilha dizia "oferta enviada"
> onze vezes e a mensagem não havia saído nenhuma).

### O que a B50 achou que não estava no documento dela

- **A trilha dizia "Oferta enviada" onze vezes, e nas onze a mensagem nunca
  saiu.** `avancar_fila` gravava o evento no instante em que **criava** a
  oferta. A `0089` separou `oferta_preparada` de `oferta_enviada`, pôs quem
  grava o segundo no único lugar onde o envio é observado
  (`registrar_oferta_enviada`, chamada por `marcar_enviada` e por
  `marcar_enviada_a_mao`), e reetiquetou as onze linhas antigas por derivação —
  o mesmo teste que as contou.
- **`nao_vou_mandar` grava `cancelada`.** O documento pedia a regra em nome de
  um estado que não existe no `check` de `mensagens.estado`; escrita com esse
  nome, ela não casaria com nada. Lido do `pg_get_functiondef` (lei 6).
- **`barrada_no_teto` e `falhou` também seguram a oferta**, além de `pendente` e
  `enviando`. O documento nomeia só os dois — e `barrada_no_teto` é o caminho
  normal de uma conta que bateu a cota do mês, ou seja, o gatilho mais provável
  do defeito em produção. `passar_para_a_sua_mao` não aceita esses dois estados,
  então a oferta segurada não tem caminho para a mão dela: fica **viva**, e ela
  resolve pelo "Aceitou / Não pôde", que é melhor do que expirar em silêncio.
- **Duas telas da página pública afirmavam envio automático** — a demonstração
  da cascata (*"oferta enviada…"*) e a `Discricao` (*"Remetente neutro"*). É a
  **quinta e a sexta** ocorrência do antipadrão "a promessa que o software não
  cumpre", e as duas estavam no texto que ela lê **antes de assinar**, que é
  onde o §5 avisa que a regra foi violada por último.
- **A tela do contador coleta e-mail e "dia do envio" para um envio que não
  acontece** (B25 — falta o adaptador de e-mail com anexo). O rótulo passou a
  dizer "dia em que a pasta fica pronta", que é o que o cron faz de verdade.
- **A fila da vaga fixa tinha o mesmo defeito da cascata**, e não estava na
  lista: `oferecerVaga` dizia *"Oferecida… a fila anda sozinha"* sem ler nada.

### Onde este pacote encosta na auditoria de entrega

Duas das seis já estavam achadas do outro lado, e é bom sinal que os dois
caminhos tenham chegado nas mesmas linhas: a **B51** é o **S2-6** (as três telas
do perfil que sorteiam a profissional) e a **B49 entrega 2** é o **S2-16** (a
busca que manda toda sessão para `/encaixes/{id}`, que recusa quatro dos seis
estados).

**Soma: 29 dias** (as 13 com estimativa) — é a soma da coluna, conferida linha
a linha. Estava escrito 32,5, que vinha da aritmética da frase seguinte
(25,5 + 14 − 7) e nunca bateu com a tabela; quando os dois discordam, quem manda
é a tabela. Eram 25,5 antes da auditoria, que acrescentou builds e tirou duas
(**B38** e **B12b** — ver [`_arquivadas.md`](_arquivadas.md)).

**Restam 3,5 dias:** só a **B32**, e só os itens 1 e 2 dela — o item 3 saiu em
`478ab45`. A OP7 não tem estimativa e não entra na conta: ela só abre quando o
e-mail deixar de dar conta.

**Os quatro primeiros são 10 dias e fecham os seis S1.** Não corte esses.

---

## Onde o produto está hoje

**137 migrações no repositório · 67 suítes SQL adversariais, e as sessenta
rodaram · 1.822 testes unitários em 74 arquivos · build de produção limpo.**
Próxima migração livre: **`0097`**.

> **As suítes SQL ganharam um alvo que as roda**, em 03/09:
> `SUPABASE_DB_URL='…' npm run verificar:sql`. Elas não entram no `verificar`
> porque precisam de conexão — e foi exatamente por isso que ficaram meses sem
> rodar. Quando rodaram, seis defeitos de produto apareceram de uma vez, todos
> já acusados por verificações que este projeto tinha escrito. **Roda antes de
> commit que toca em migração.**

> **O banco registra 133 migrações e o repositório guarda 128, e a diferença
> foi conferida em 03/09** — varrendo `schema_migrations` contra a pasta, não
> por lista. Nove entradas são passos que o banco recebeu separados durante as
> builds B20–B25 e que o repositório guarda consolidados no arquivo da build
> (`0033b`, `0036b/c/d`, `0037b`, `0038b`, `0039b/c`); três arquivos — `0049`,
> `0049b` e `0050` — foram aplicados sem entrar no registro do Supabase. Todos
> os objetos que eles criam estão vivos no banco **e** descritos no repositório:
> nenhum objeto ficou sem arquivo, que é o que a lei 5 protege.

| trilha | entregue | falta |
|---|---|---|
| **B** produto | B0–B11, B13, B14, B16–B29, B31, B33, B34, B36, B39–B41 | B32 (itens 1 e 2, os dois bloqueados por insumo) |
| **P** integridade da receita | P1–P8 | — |
| **OP** operação | OP1–OP6, OP8, OP9, OP10 | OP7 |
| **B4x** da auditoria de UX | B43–B48 | — |
| **B49–B57** o pacote do canal | B49–B52, B55, B56, B57 · B54 na metade de teclado | B53 (cláusula do doc 18) · a fechadura do §5.5 (conta de e-mail) |
| fora de trilha | Panorama · blog · documentos legais · ficha em abas · a prova do restore | — |

> **Os `[ ]` dos arquivos de build não são fonte de status.** Eles quase nunca
> foram mantidos: das builds entregues, só a B34, a B36 e a B47 estão marcadas,
> e as outras continuam com todos os itens em branco. Quem responde "isto foi
> feito?" é o `git log` — cada build tem um commit com o código dela no
> assunto, e o corpo dele diz o que ficou de fora e por quê.

**As dez suítes das migrações aplicadas nesta sessão rodaram em 03/09, e as
dez passaram** — as primeiras deste projeto a serem executadas de verdade:
`0067` · `0068` · `0069` · `0070` · `0071` · `0072` · `0073` · `0074` · `0077` ·
`0079`. Nenhum defeito do produto apareceu; **doze defeitos nas próprias suítes**
apareceram, todos da mesma família: elas pediam ao banco coisas que o banco
recusa com razão (insert cru onde só função escreve, estado que o gatilho
sobrescreve, data cravada como "passado", teardown na ordem errada). O caminho
de escrita é o servidor Supabase que roda como `postgres`; o outro é
somente-leitura e não troca de papel.

**E as outras 46 rodaram no mesmo 03/09: as sessenta estão verdes.** Cinco
defeitos de produto e um número grande de defeitos das próprias suítes
apareceram nessa segunda metade, todos do mesmo jeito — rodando, não lendo.

- **A `0087`** é o único defeito de produto que virou migração aqui. A `0064`
  fechava a promessa contra o recurso com `recursos && por_vir`, e `&&` é
  interseção **literal** de array: depois que a `0070` recapitalizou as duas
  listas, passou a ser possível vender *"Tudo do Gratuito"* e prometer *"tudo
  do Gratuito"* no mesmo cartão de preço. A verificação 17 da `0064` acusou; o
  conserto foi normalizar dentro do `check`, com `lista_normalizada()`, e não
  trocar a grafia da sonda — trocar a sonda deixaria a suíte verde e apagaria o
  achado, que é o antipadrão nº 4.
- **A `0053` estava vermelha em silêncio desde a `0067`**, que renomeou três
  coisas de `recibos_rfb` de uma vez (`emitido` → `marcado_por_ela`,
  `numero_rfb` → `numero_informado`, `emitido_em` → `marcado_por_ela_em`). Ler
  a migração mais recente não bastou: foi o `pg_get_functiondef` que mostrou as
  três (lei 6).
- **Nove suítes não recolhiam a conta que criavam** — e a prova disso não é uma
  lista, é `testes/a-suite-recolhe-a-conta-que-criou.test.ts`, que varre a
  pasta e compara, por posição, quantas contas cada arquivo cria contra quantas
  ele apaga depois da última criação.
- **O `rodar-suites.mjs` bloqueava as suítes que chamam varredura de cron por
  uma lista escrita à mão** — e a lista estava errada nas duas direções (tinha
  uma função que não pertencia e faltavam oito). Virou uma CTE recursiva sobre
  o `pg_proc`: fecho transitivo das funções que escrevem, filtrado por volátil,
  não-gatilho, sem argumento que amarre conta e que nunca chama `conta_atual()`
  (lei 7).
- **A `0066` acusou a oitava e a nona função abertas para o anônimo**, que são
  as duas da pré-ficha (`ficha_do_paciente` e `salvar_ficha`, da `0074`). Elas
  são legítimas — a lista de campos da `salvar_ficha` é fechada no banco e
  recusa a chamada inteira se vier chave fora dela, e a leitura devolve só o
  primeiro nome —, então a lista declarada virou nove **com o motivo escrito**.
  E ganhou a metade que uma lista escrita à mão não tem: a **27b** varre o
  corpo de toda função `security definer` que o `anon` executa procurando
  `evolucoes`, `anamneses`, `registros` e `nota`. A função que alguém criar
  amanhã já nasce dentro dessa varredura, e a que alguém acrescentar à lista
  por pressa continua tendo que passar por ela.

**As duas dívidas que não eram build saíram daqui em 03/09.**

- **A `0067b`** foi recuperada do banco byte a byte e o md5 fechou
  (`9242187d0f9b4c16a4a8bfc763ff01bc`, 30.733 caracteres). A lei 5 voltou a
  valer: não há mais nada aplicado no Supabase que não esteja em
  `supabase/migrations/`.
- **"Sem faixa de sessões"** saiu na **0078**, junto com *"Régua de atraso
  impessoal"* e *"quando você interrompe a régua"* — as três eram jargão do §5
  na **página pública**, que é o primeiro texto que uma psicóloga lê. Elas
  sobreviveram porque `o-jargao-nao-vira-rotulo.test.ts` já declarava as duas
  regras e só varria a área logada. A varredura foi alargada para `app/(site)`,
  `components/site` e `lib/planos.ts`, e não achou mais nada.

**As três peças que não são build** — não dependem de teclado, dependem de uma
credencial cada:

| peça | o que falta | o que muda quando existir |
|---|---|---|
| Cliente HTTP do Asaas (B16) | credencial do provedor | o Pix da assinatura e a conciliação automática |
| Adaptador de e-mail com anexo (B25) | **a conta do provedor** — a arquitetura chegou em 03/09, ver [`docs/canal/`](../canal/) | a pasta do contador sai sozinha, a régua da assinatura para de depender do Leandro, e a fechadura do download (§5.5, o que falta da B54) deixa de depender da data de nascimento |
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
4. o tamanho do **P8** — com que periodicidade ela executa o Receita Saúde.
   *A metade que não depende da conversa passou a ser medida em 03/09: a 0079
   levou a mediana de dias entre o pagamento e a baixa para o painel do
   negócio, fora as contas de teste. Hoje ela diz o que tem de dizer — **quatro
   contas no escopo, uma com recibo, nenhuma marcou ainda** —, e o número que
   decide se o cartão serviu só existe quando alguém usar.*;
5. **o formulário de cadastro** — a pergunta que a auditoria de UX acrescentou:
   *"me mostra como você anota hoje o dia, a hora e o valor de uma paciente
   nova"*. Decide se a política de falta se pergunta em número ou em palavra, e
   se o cadastro de 17 campos é o formulário certo.

Nenhuma build desta fila espera pela conversa, exceto o **tamanho** do P8.
