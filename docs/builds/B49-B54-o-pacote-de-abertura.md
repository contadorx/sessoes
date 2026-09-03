<!--
  ===================================================================
  NOTA DE ARQUIVAMENTO — 03/09, ao entrar na pasta
  ===================================================================

  Este documento entra inteiro e sem edição no corpo. Ele cobre seis builds e
  se descreve como pacote: as colisões entre a B50 e o Anexo A, e o próprio
  Anexo A, só fazem sentido juntos. Quebrá-lo em seis arquivos, como a pasta
  faz para as builds antigas, perderia exatamente a parte que ele avisa para
  ler antes ("há dois bloqueios reais e quatro colisões com a B50").

  DUAS COISAS ENVELHECERAM ENTRE A ESCRITA E O ARQUIVAMENTO, no mesmo dia:

  1. **"Próxima migração livre: 0084"** e **"a última aplicada é a 0083"**
     valiam quando o doc foi escrito. Depois disso entraram, no mesmo dia:

         0084 · as duas policies de ofertas_fixas que viviam só no banco
         0085 · esquecer_contato revoga o link de verdade

     **Próxima migração livre: 0086.**

  2. Por consequência, **a B50 não é mais a migração 0084 — é a 0086.** O
     título dela dentro do doc não foi alterado, porque o corpo é o prompt de
     abertura e reescrever prompt de abertura é como se perde o que ele dizia.
     Quem abrir a B50 usa 0086.

  E UMA COLISÃO DE CONTEÚDO, que não é problema e vale saber:

  A B50 entrega 2 protege a oferta cuja mensagem ainda não saiu. A 0080, do
  mesmo dia, mexeu na família vizinha — seis funções que cancelavam mensagem
  olhando só `pendente` e não enxergavam `na_sua_mao`. São duas metades da
  mesma lição da 0061 e **não se sobrepõem**: a 0080 é sobre cancelar, a B50 é
  sobre expirar. A B50 continua valendo inteira.

  A B51 é o S2-6 da auditoria de entrega, e a B49 entrega 2 é o S2-16.
  ===================================================================
-->

# 35 · B49 a B54 — o pacote de abertura para o agente de código

*03/09/2026. As três primeiras (B49, B50, B51) nasceram da auditoria cega do GPT
(prompt no doc `33`, achados cruzados no doc `34`). As três últimas (B52, B53,
B54) são a estratégia de canal versão 5, reproduzida inteira no **Anexo A** —
ela já foi escrita para um agente de código, e não foi reescrita aqui. O que este
doc acrescenta a ela é a numeração, a ordem e as colisões.*

*O texto de cada build **é** o prompt de abertura dela: entrega, pronto quando e
não entra são o escopo fechado.*

> **Uma build por vez, na ordem.** Não abra a B50 antes de a B49 passar no
> critério de pronto dela. Se for rodar só uma, é a **B49**.
>
> **E leia a seção "O canal" antes de abrir qualquer coisa do Anexo A** — há
> dois bloqueios reais e quatro colisões com a B50.

---

## 0 · O que quem abrir precisa saber antes

**A regra de sempre deste projeto, e ela já custou caro três vezes:** ao mexer
numa função do banco, **leia o corpo dela do `pg_proc`, nunca da migração**. Duas
builds seguidas reescreveram função a partir do arquivo de migração e apagaram
comportamento que tinha sido acrescentado depois (`avancar_fila` perdeu a linha
que enfileira a mensagem duas vezes, pelo mesmo caminho).

**Cada build acrescenta a suíte adversarial dela e roda as suítes antigas que
ela toca.** Critério de pronto se verifica **rodando**, não lendo.

**Próxima migração livre: `0084`.** A última aplicada é a
`0083_a_copia_que_responde_ao_conselho_tambem_leva_o_plano`.

**Verificação com dados:** use a conta de demonstração. **Nunca a conta real** —
o banco de produção tem paciente de verdade dentro.

**O que eu já verifiquei no banco hoje, para ninguém refazer:**

- a B43 funcionou: existe **uma** linha `enviada/provedor=registro` em
  `public.mensagens`, e é a antiga, de 02/09 11h03. Nenhuma nova.
- `passar_para_a_sua_mao(mensagem, motivo)` existe e está correta: move
  `pendente`/`enviando` para `na_sua_mao` com o motivo, e recusa mexer no que já
  saiu.
- `expirar_ofertas` **já** pula oferta cuja mensagem esteja `na_sua_mao`, e
  `marcar_enviada_a_mao` reinicia `enviar_em` e `expira_em`. A decisão da OP9
  está implementada — **não mexa nessa parte.**
- há hoje 11 ofertas e 12 mensagens com `enviar_em`/`agendada_para` às 08:00
  (a janela de silêncio), `tentativas = 0`. Isso é normal, não é fila parada.

**As fronteiras valem inteiras.** Nenhuma destas três builds pode: criar tela
nova onde cabe frase · usar `window.confirm` ou diálogo nativo (o padrão da casa
é o estado `confirmando` no próprio componente) · introduzir meta, elogio, streak
ou cor que melhora quando o número sobe · instalar biblioteca de UI · mexer em
identidade visual.

---

# B49 · O comando faz o que ele diz · 2 dias · sem migração

**A família inteira desta build é uma só frase: o produto oferece uma ação e a
ação não acontece.** Não é bug isolado — são seis pontos com o mesmo formato, e é
o ponto cego que a auditoria de fluxo e a auditoria de banco não pegaram.

## Entrega

**1 · Os parâmetros de URL que ninguém lê.** `/agenda` lê apenas `semana`
(`app/(app)/agenda/page.tsx:45-54`), e o menu Novo (`lib/navegacao.ts:216-234`)
manda para quatro endereços com parâmetro:

| endereço | origem | efeito hoje |
|---|---|---|
| `/agenda?novo=sessao` | Novo → Sessão | tela idêntica; nenhuma criação abre |
| `/agenda?sessao={id}` | confirmação recusada → "ver sessão" (`components/app/Confirmacoes.tsx:87-95`) | tela idêntica; nada é selecionado |
| `/encaixes?novo=pedido` | Novo → Pedido de encaixe | parâmetro não lido |
| `/recebimentos?novo=entrada` | Novo → Recebimento | parâmetro não lido |

`/agenda?novo=sessao` abre a **menor composição possível** — paciente, data,
hora, duração —, mantendo o combinado como fonte das recorrências.
`/agenda?sessao={id}` resolve a semana correta, inicia `Semana`
(`components/app/Semana.tsx:52-69`) com a linha selecionada e rola até o painel.
Os outros dois: ou passam a abrir o editor que já existe na página, ou saem do
menu Novo. **Item de menu que não faz nada é pior que item de menu que não
existe.**

**2 · A busca manda sessão para a rota errada.** `app/(app)/buscar/page.tsx:185-195`
manda **toda** sessão para `/encaixes/{id}`, e
`app/(app)/encaixes/[sessao]/page.tsx:63-97` recusa sessão que não seja vaga.
Passa a usar o destino do item 1.

**3 · O combinado que se descarta em silêncio.** `app/(app)/pacientes/acoes.ts:27-37`
devolve `dados: null` quando hora **e** valor estão vazios — **antes** de ler dia,
duração, cobrança, política de falta e confirmação, que o formulário mostrou
(`components/app/FormPaciente.tsx:188-224` e `:298-434`). A paciente é criada e o
combinado inteiro some, sem aviso (`:128-159`).

Regra nova: se **qualquer** campo da seção divergir do vazio/padrão, exigir hora e
valor com erro **nos dois campos**. Só tratar como "sem combinado" quando a seção
inteira estiver intocada.

**4 · As ações que engolem o próprio erro.** Descartam o retorno de
`useActionState`: `components/app/PainelSessao.tsx:65-78` e `:102-133` (Confirmar,
Aconteceu, Não veio e os dois desmarques), `:254-258` (perdoar e marcar cobrança
paga), `app/(app)/agenda/acoes.ts:125-153`, e `components/app/Cascata.tsx:72-90`
(Aceitou / Não pôde). Se a ação falhar, **nada aparece** e o botão volta a ficar
clicável.

Guardar o resultado e renderizar erro **e** sucesso ao lado do controle, no padrão
`Recado` que recebimento e evolução já usam.

**5 · O cadastro que não mostra o que criou.** `app/(app)/pacientes/acoes.ts:138-165`
redireciona para a aba Combinado da ficha. Passa a mostrar uma **frase factual**
com a próxima sessão e o link que a abre na Agenda, pelo destino do item 1. Frase
factual, não comemoração.

## Pronto quando — verificado rodando

- [ ] os quatro itens do menu Novo percorridos: nenhum leva a uma tela onde nada
      abre
- [ ] `/agenda?sessao={id}` de uma sessão de outra semana abre aquela semana, com
      a linha selecionada e o painel no campo de visão
- [ ] um resultado de busca de sessão comum abre a sessão; nenhum cai na recusa
      de `/encaixes/[sessao]`
- [ ] cadastrar paciente com dia e política preenchidos e hora/valor vazios
      devolve erro **nos dois campos** e não cria paciente com combinado parcial
- [ ] cadastrar paciente com a seção do combinado **intocada** continua criando a
      paciente sem combinado, sem erro
- [ ] derrubar o RPC de cada uma das sete ações do item 4 mostra o erro **ao lado
      do controle**, e não em outro lugar da tela
- [ ] uma verificação varre `app/` e reprova página que receba `searchParams` sem
      lê-los

## Não entra

Tela de detalhe de sessão · calendário novo · segundo sistema de agenda · `toast`
global · tornar obrigatórios todos os campos da paciente (o cadastro de alguém em
triagem é legítimo) · redesenho de formulário.

## As armadilhas

**Criar uma tela nova de calendário** para fazer o `novo=sessao` funcionar, em vez
de fazer o comando existente cumprir o que diz. **Toast no topo** para o item 4:
em 375 px ele se separa da ação e o que ela faz é tocar de novo — e duplicar.
**Consertar só o `topa_antecipar` da vez**: o item 1 são quatro parâmetros e o
item 4 são sete ações; corrigir uma deixa a incoerência de pé e ninguém acha as
outras depois.

---

# B50 · A oferta só anda depois de sair · 1,5 dia · migração 0084

**Duas metades: uma frase que mente no tempo verbal, e um relógio que corre sobre
uma mensagem que ainda não saiu.**

## Entrega

**1 · A cascata anuncia envio que não houve.** `app/(app)/encaixes/acoes.ts:112-131`
cria a oferta, chama o despacho e **sempre** devolve "Oferta enviada. A fila anda
sozinha" (`components/app/Cascata.tsx:45-53` e `:250-255`), sem ler o resultado.
Com a janela de silêncio ativa, isso é falso em todo caso noturno: uma oferta
criada às 2h só tenta sair às 8h.

A ação passa a ler o estado real de `public.mensagens` e responder no tempo verbal
certo — *"oferta preparada; ela sai às 8h"* ou *"envie em Agenda → Na sua mão"* —,
e só rotula `oferta_enviada` quando a mensagem estiver `enviada` ou `entregue`.

**2 · `expirar_ofertas` protege a mensagem errada — migração 0084.** A função tem
hoje um `not exists` que pula oferta cuja mensagem esteja `na_sua_mao`. **Ela não
protege `pendente` nem `enviando`.** Se o worker atrasar ou o cron falhar, no
minuto do `expira_em` a oferta expira, `avancar_fila` chama a próxima — que
também não sai — e **a fila queima inteira sem uma única mensagem ter saído**,
com a tela mostrando "expirada" para gente que nunca foi convidada.

Regra nova, em `expirar_ofertas` **e** em `expirar_ofertas_fixas`: só expira
oferta cuja mensagem **saiu** (`enviada`/`entregue`) ou cuja saída ela recusou
(`nao_vou_mandar`). Mensagem `pendente` ou `enviando` segura a oferta, como a que
está na mão dela já segura.

**3 · As frases de canal contradizem umas às outras.** `components/app/FormPaciente.tsx:135-163`
promete remetente neutro sem condicionar ao canal; `app/(app)/encaixes/page.tsx:61-66`
diz "Você não pede nada a ninguém"; `app/(app)/recebimentos/page.tsx:49-62` diz que
o sistema lembra; e `components/app/NaSuaMao.tsx:92-117` admite que a mensagem sai
do WhatsApp dela. Todas passam a derivar do **mesmo** estado de plano e provedor,
no condicional — e no manual dizem quem envia e de qual número.

## Pronto quando — verificado rodando

- [ ] com o worker parado e uma oferta cuja mensagem esteja `pendente` e o
      `expira_em` vencido, `expirar_ofertas()` devolve **0** e a fila não avança
- [ ] a mesma oferta, com a mensagem `enviada`, expira normalmente
- [ ] nenhuma tela afirma envio sem que `mensagens.estado` esteja em `enviada` ou
      `entregue`
- [ ] a cascata acionada dentro da janela de silêncio responde com a hora prevista,
      e não no passado
- [ ] a suíte planta oferta com mensagem `pendente` vencida e **reprova** a
      expiração; e varre o JSX atrás de afirmação de envio no passado que não leia
      o estado

## Não entra

Ligar o BSP (é o relógio da Meta; esta build existe para o produto não mentir
enquanto ele corre) · mexer na janela de silêncio · mexer em
`passar_para_a_sua_mao`, `marcar_enviada_a_mao` ou na proteção que já existe para
`na_sua_mao` — **as três estão corretas e verificadas hoje**.

## As armadilhas

**Marcar como enviada para manter a animação da cascata fluida.** **"Consertar"
pelo outro lado**, fazendo a mensagem sair na hora e furando a janela de silêncio
— a janela existe para não mandar mensagem a paciente de madrugada. E **trocar a
frase sem ler o estado**: frase vaga sobre fato não conferido continua sendo
afirmação sem lastro.

---

# B51 · De quem é esta tela · 1 dia · sem migração

**Três consultas que escolhem uma profissional arbitrária.** Hoje as quatro contas
do banco têm **uma** profissional cada, então o defeito existe e não está
machucando ninguém — **a prioridade sobe no dia em que entrar a primeira conta
Clínica**, e é por isso que esta build é a terceira e não a primeira.

## Entrega

- `app/(app)/perfil/page.tsx:62-67` — `.limit(1)` sem filtrar pela profissional da
  sessão e sem ordenar: numa clínica, o Perfil pode mostrar e **editar** CRP,
  documento e assinatura de uma pessoa arbitrária.
- `app/(app)/perfil/horarios/page.tsx:60-65` — o mesmo `.limit(1)` para a
  capacidade semanal: uma sócia ou secretária pode editar a semana da primeira
  profissional devolvida, sem saber qual.
- `app/(app)/fechamento/livro/page.tsx:100-130` e `:141-160` — o livro escolhe a
  profissional da sessão atual ou a primeira em ordem alfabética; quando há
  várias, escreve "de Nome" e **não oferece troca nem total da conta**.

Nos dois primeiros: a profissional é a da sessão, e ponto. No terceiro: seletor de
profissional na mesma rota, com rótulo explícito de que o recorte é individual e
não é o total da clínica.

## Pronto quando — verificado rodando

- [ ] numa conta com duas profissionais ativas, o Perfil e os horários abrem
      sempre os da profissional da sessão
- [ ] o livro diz de quem é e permite trocar, sem somar
- [ ] uma verificação varre `app/` e reprova consulta a `profissionais` com
      `.limit(1)` sem filtro e sem ordenação

## Não entra

**Somar profissionais por padrão.** Duplicidade de mensalidade, de despesa e de
responsabilidade fiscal não está resolvida, e um "total da clínica" errado é pior
que nenhum.

---

# O canal — B52, B53 e B54

**O Anexo A é o prompt de abertura destas três, e não foi reescrito.** O que
falta nele é só o recorte: ele foi escrito como uma estratégia, e uma estratégia
inteira não se abre de uma vez.

| build | o que é | seções do Anexo A | migração |
|---|---|---|---|
| **B52** · o canal entrega, e a oferta fura a fila | roteamento de saída, classe do template, circuit breaker, cascata de canais | §1 e §2 | 0085 |
| **B53** · o PIX é dela, e o comprovante propõe | cobrança por PIX próprio, entrada do comprovante, casamento, validação manual, descarte | §3 e §4 | a seguir |
| **B54** · a página vira o repositório | upload do lado do paciente, aviso de documento novo, a linha do mês, a fechadura do download | §5 | a seguir |

As fronteiras do piloto (§8 do anexo) valem para as três, e o "o que não trazer"
(§7) também.

## As quatro colisões com a B50 — resolva no papel antes do teclado

**1 · A janela de silêncio.** A B50 diz, no "não entra", para **não** mexer na
janela. O §2.3 do anexo precisa da exceção: `urgente` cuja vaga expira antes do
fim do silêncio não espera. **A exceção é da B52, não da B50** — e a ordem entre
as duas é essa de propósito: *a B50 conserta a mentira, a B52 remove a causa.*
Quando a exceção entrar, a frase da cascata muda junto e deixa de dizer "sai às
8h" para oferta urgente.

**2 · `expirar_ofertas` tem que cobrir o e-mail também.** A B50 passa a exigir
que a oferta só expire depois de a mensagem sair. O circuit breaker do §2.5 cria
um caminho novo — urgente indo por e-mail quando a instância cai. **Oferta cuja
mensagem foi para o e-mail e ainda não saiu não expira**, pela mesma razão. Isso
é linha da B52, e o teste da B50 tem que ser estendido, não reescrito.

**3 · A frase de canal deixa de ser estática.** A B50 manda todas as frases de
canal derivarem do mesmo estado de plano e provedor. Com o circuit breaker, esse
estado **muda sozinho** — então a fonte não é `planos.canal_saida` lido uma vez,
é o estado corrente da conta. A B52 herda o teste da B50 com essa correção.

**4 · O relógio da mão dela já está certo — não duplique.**
`marcar_enviada_a_mao` reinicia `enviar_em` e `expira_em`, e `expirar_ofertas` já
pula o que está `na_sua_mao`. **Verifiquei hoje no banco.** O worker do §2 não
pode reimplementar isso do lado dele: seria a segunda fonte de verdade sobre o
relógio da oferta.

## Os dois bloqueios — e um deles não é código

**1 · Não existe adaptador de e-mail.** O `claude/20` lista "adaptador de e-mail
com anexo — falta provedor de e-mail" entre as três peças que não dependem de
teclado. E o anexo usa e-mail em **três** lugares estruturais: fallback de
urgente (§2.2 e §2.5), canal único da classe `documento` (§2.3, passo 2) e
segundo fator do download (§5.5). **Confirme se o provedor já entrou antes de
abrir a B52.** Se não entrou, as opções honestas são: o provedor de e-mail vira
a primeira linha da B52; ou a B52 sai com a cascata degradada — urgente sem saída
cai em `na_sua_mao` na hora, em vez de e-mail — e a B54 sai sem o código de seis
dígitos, com o download atrás da data de nascimento e a fraqueza escrita na tela.
**O que não pode é a tela prometer e-mail que não sai.** É o quarto caso da
família "a promessa que o software não cumpre".

**2 · O OCR do §4.9 acrescenta um operador.** Mandar a imagem do comprovante para
um modelo multimodal põe um terceiro no inventário de operadores da política de
privacidade. O anexo já resolve o mérito (comprovante não é dado clínico) e já
manda escrever a fronteira — **mas a cláusula tem que existir no doc `18` antes
de a B53 abrir**, não depois. É o erro da `/privacidade` ao contrário: em vez de
prometer o que não existe, seria fazer o que não está declarado.

## Três instruções de casa para quem for construir o anexo

- **`comprovantes` (§4.8) sai com `conta_id`, RLS e trilha**, como toda tabela
  desta base. O schema do anexo não os escreve porque está resumindo — não os
  omita.
- **`templates.classe` é lista em dois lugares.** No dia em que a coluna existir
  no banco, o lado TypeScript precisa da varredura que compara os dois — este
  projeto já foi mordido quatro vezes pela mesma família (`exportar_conta` sem
  dezessete tabelas, `FAMILIAS` sem `confirmacao_de_sessao`, `PLANOS` contra
  `planos.recursos`). Varredura, não lista.
- **O descarte (§4.11) e a fechadura (§5.5) viram cláusula no doc `18`** na mesma
  passada em que virarem código. Prazo declarado na tela é o padrão da casa.

---

# A ordem, e a conta

| ordem | build | dias | por que aqui |
|---|---|---|---|
| 1 | **B49** · o comando faz o que ele diz | 2 | um S1 de tarefa que não acontece e outro de dado que some em silêncio |
| 2 | **B50** · a oferta só anda depois de sair | 1,5 | a fila é a feature-âncora, e pode queimar inteira sem ninguém ser convidado |
| 3 | **B52** · o canal entrega, e a oferta fura a fila | a estimar | remove a causa que a B50 só conserta na frase; depende do e-mail |
| 4 | **B53** · o PIX é dela, e o comprovante propõe | a estimar | depende da cláusula do doc `18`, não de código |
| 5 | **B54** · a página vira o repositório | a estimar | fecha o ciclo, e dá lugar ao kit de reembolso do doc `23` |
| 6 | **B51** · de quem é esta tela | 1 | existe e não machuca ninguém hoje; sobe com a primeira conta Clínica |

**As três primeiras somam 4,5 dias; o anexo não traz estimativa e eu não vou
inventar uma.** O `claude/20` está dezesseis migrações desatualizado e precisa
ser reescrito antes de qualquer soma com o resto da fila.

---
---

# ANEXO A · A estratégia do canal, íntegra

*Reproduzida sem corte. É o prompt de abertura da B52, da B53 e da B54.*


# Estratégia do canal WhatsApp do Sessões — para o agente de código

Versão 5, 02/09/2026. Escrita a partir de dois kits já em produção do Leandro
(`evolution-worker`, do sureya-app; `contatia-whatsapp-kit`, do Contatia), mais quatro
camadas: **roteamento de saída**, **cobrança por PIX próprio sem gateway**,
**validação manual do comprovante com descarte** e **a página do paciente como repositório
de documentos**. Complementa `claude/25b-piloto-de-canal-evolution.md`.

---

## 0. A regra que governa tudo o resto

**Os kits são camada de TRANSPORTE. O Sessões já tem a camada de DECISÃO.**

| peça que já existe no banco | o que ela já decide |
|---|---|
| `public.mensagens` (outbox, `chave_idem`) | a mensagem existe uma vez só |
| `reservar_mensagens` / `marcar_enviada` / `marcar_falha` / `destravar_mensagens` | ciclo de vida do envio |
| `enfileirar_mensagem(...)` | única porta de entrada da outbox |
| `templates.essencial` | o que nunca é barrado por teto |
| `planos.canal_saida` (`manual` \| `plataforma`) | se a conta envia sozinha ou pela mão dela |
| `mensagens_na_sua_mao()` / `marcar_enviada_a_mao()` / `nao_vou_mandar()` | a camada manual |
| `limites_tecnicos` · `proximo_envio(conta, agora)` | freio técnico e janela de silêncio |
| `mensagens_recebidas` (único por provedor + id) | idempotência de entrada |
| `cobrancas` (com `confirmado_por`) · `marcar_cobranca_paga()` · `perdoar_cobranca()` | dinheiro |
| `propostas_de_cobranca` · `decidir_cobranca()` | **a doutrina: dinheiro nasce de decisão, não de gatilho** |
| `contas.pix_chave` / `pix_nome` / `pix_cidade` · `txid_da_cobranca()` | PIX próprio, sem gateway |
| `links_do_paciente` · `pagina_do_paciente(token)` | a página transacional do paciente |
| `historico_de_cobranca()` · `financeiro_do_mes()` · `livro_razao()` | relatório |

> **Proibição nº 1:** não criar `fila_envios` (do worker) ao lado de `public.mensagens`.
> Duas filas são duas verdades — a paciente recebe a mesma oferta duas vezes.

> **Proibição nº 2:** nada marca cobrança como paga a partir de um comprovante. Ver 3.2.

> **Proibição nº 3:** nenhuma mensagem automática comunica recusa de comprovante. Ver 4.4.

---

## 1. O que vem de cada kit

**Do `contatia-whatsapp-kit`, literalmente:** `brVariants()` com
`INICIO_CELULAR = /^[6-9]/`, `telefone.ts` (fixo × celular), `waModo.ts`
(assistido \| híbrido \| evolution \| meta), as 3 travas do `fromMe` (contato conhecido,
`wa_message_id`, janela de 10 min), `respostaAutomatica.ts` (classifica por texto **e**
tempo), `daily_cap`, `sendPresence("composing")`, `logout` **+** `delete`,
`integration: "WHATSAPP-BAILEYS"`, QR gerado localmente, `setWebhook` tentando v2 (header)
e caindo para v1 (query), `whatsapp_accounts` multi-instância, token na URL do webhook.

**Do `evolution-worker`, o padrão:** backoff 2/4/8/16/32/60 com teto de 5 tentativas;
**lock por escrita condicional** antes de enviar (impede que duas execuções do cron mandem
a mesma mensagem — incidente real e documentado); os **5** estados de conexão
(`conectado` · `conectando` · `desconectado` · `inexistente` · `erro` — "não consegui
perguntar" nunca é exibido como "desconectado"); `baixarMidiaBase64` com os dois caminhos
(inline com `base64: true` e `getBase64FromMediaMessage`); link de mídia assinado **na hora
do envio**, nunca guardado assinado.

**A fronteira, e nenhuma rota a contorna:**

```ts
export interface CanalMensagem {
  enviarTexto(destino: string, texto: string): Promise<ResultadoEnvio>;
}
export type ResultadoEnvio =
  | { estado: "enviada"; provedorMsgId: string }
  | { estado: "sem_whatsapp" }
  | { estado: "falhou"; erro: string };
```

O motivo está no incidente que o worker documenta: 58 saídas no dia, a última do dia
anterior, mensagens de cliente chegando o dia inteiro — porque uma rota chamou a função
crua e a exceção morreu na tela.

**O bug do 9º dígito é o mais caro do conjunto:** a regra ingênua transforma o fixo
`(11) 2451-1469` em `(11) 9 2451-1469`, **um celular real de outra pessoa, que tem
WhatsApp**. Nada falha, e a mensagem sobre a consulta de uma paciente vai para um estranho.
Num produto de psicologia isso não é bug de integração, é quebra de sigilo.

---

## 2. Camada de roteamento de saída

### 2.1 O eixo que falta

`templates.essencial` responde *"quem se machuca se não for"* e governa **teto de plano**.
Roteamento precisa de outra pergunta: *"quanto valor a mensagem perde com atraso"*.

```sql
alter table public.templates
  add column classe text not null default 'rotina'
    check (classe in ('urgente','rotina','documento')),
  add column tolera_atraso_min integer;
```

- **urgente** — perde valor em minutos. Fura fila, tem cascata automática.
- **rotina** — tolera horas ou dias. Pode cair na mão dela.
- **documento** — recibo, informe, declaração. **Nunca sai pelo canal não oficial.**

**Cuidado para não ler errado:** `documento` é o *arquivo*, não o *valor*. Uma cobrança que
diz "seu pagamento combinado: R$ 200" **pode** ir pelo WhatsApp — valor não é dado de
saúde, e a mensagem discreta não nomeia terapia. O que não vai é o recibo, que nomeia o
serviço e existe para reembolso e Receita Saúde. **Valor pode; documento não.**

### 2.2 Tabela de roteamento

| template | essencial | classe | tolera | instância | fallback |
|---|---|---|---|---|---|
| `oferta_de_vaga` | não | **urgente** | 10 min | urgente | e-mail + SMS |
| `oferta_de_vaga_fixa` | não | urgente | 30 min | urgente | e-mail |
| `encaixe_confirmado` | sim | **urgente** | 5 min | urgente | e-mail + SMS |
| `aviso_de_desmarque` | sim | **urgente** | 15 min | urgente | e-mail + SMS |
| `lembrete_de_sessao` | sim | urgente | 60 min | urgente | e-mail |
| `confirmacao_de_sessao` | sim | rotina | 240 min | rotina | e-mail → mão dela |
| `aviso_de_cobranca` | não | rotina | 1 dia | rotina | mão dela |
| `lembrete_de_pagamento` | não | rotina | 1 dia | rotina | mão dela |
| `aviso_de_reajuste` | não | rotina | 2 dias | rotina | mão dela |
| `aviso_de_pausa` | não | rotina | 1 dia | rotina | mão dela |
| `comprovante_recebido` *(novo)* | **sim** | urgente | 10 min | rotina | e-mail |
| recibo, informe, declaração | — | **documento** | — | **nunca WhatsApp** | e-mail é o canal |

### 2.3 A regra de saída, na ordem

```
para cada mensagem reservada:
  1. canal_saida da conta == 'manual'?  → mensagens_na_sua_mao(), fim
  2. classe == 'documento'?             → canal e-mail, fim
  3. dentro da janela de silêncio?      → reagenda por proximo_envio(conta)
     · exceto 'urgente' cuja vaga expira antes do fim do silêncio
  4. estourou limites_tecnicos?         → adia
  5. estourou daily_cap da instância?   → tenta a irmã; se as duas, adia
  6. escolhe instância pela classe; se a de destino está fora, usa a irmã
  7. sendPresence("composing") 2-5s proporcional ao texto (falha em silêncio)
  8. envia
  9. dorme intervalo SORTEADO entre 45 e 180s antes do próximo envio da mesma instância
```

**O passo 9 é o que mais protege o número.** O que denuncia máquina não é a velocidade, é a
regularidade. Nunca valor fixo.

### 2.4 A oferta de vaga fura a fila

```sql
order by
  case classe when 'urgente' then 0 when 'rotina' then 1 else 2 end,
  agendado_para asc
```

Uma oferta expira em `contas.oferta_timeout_min` (40 min). FIFO com 200 lembretes na frente
mata a métrica norte sem nenhum erro aparecer.

### 2.5 Circuit breaker e cascata

```
health check por minuto (statusConexao, 5 estados)
  2 leituras seguidas em erro/desconectado
    → conta passa a canal_saida='manual'
    → urgentes NÃO esperam: e-mail imediato (+ SMS se tolera_atraso_min <= 60)
    → rotinas vão para mensagens_na_sua_mao()
  2 leituras seguidas em conectado → volta a 'plataforma'
```

Ordem: **instância A → instância B → e-mail automático (+SMS se urgente) → painel manual.**
O painel manual é o último degrau, nunca o segundo: depende de humano acordado.

**Dedup cross-canal:** a chave de entrega é `(oferta_id, destinatário)`, não
`(mensagem_id, canal)`.

---

## 3. Cobrar por PIX próprio, sem gateway

### 3.1 Este é o caminho principal, não a exceção

Enquanto não houver gateway ativo, a cobrança sai com a **chave PIX dela**
(`contas.pix_chave`, `pix_nome`, `pix_cidade` — os três campos do BR Code já existem no
schema) e o dinheiro cai direto na conta dela. O Sessões nunca toca no dinheiro.

Quando o gateway (Asaas) estiver ativo para a conta, **este caminho inteiro desliga**: a
verdade passa a vir de `conciliar_pagamento(...)` e `eventos_pagamento`, e comprovante
vira anexo, não prova. **Comprovante e gateway nunca são duas fontes da mesma verdade.**

Regra de código: se a cobrança tem `provedor_cobranca_id`, o comprovante **não propõe baixa**.

### 3.2 A doutrina: comprovante propõe, ela decide

Um print de PIX é **prova fraca** — existe indústria de gerador de comprovante falso.
Deixar uma imagem mudar `cobrancas.estado` para `'paga'` é aceitar prova falsificável para
mexer em dinheiro.

O banco já tem a regra certa, escrita no comentário de `propostas_de_cobranca`:
*"a multa nasce de `decidir_cobranca()`, nunca do gatilho"*. **O comprovante segue a mesma
doutrina.** A coluna `cobrancas.confirmado_por` existe exatamente para guardar quem decidiu.

### 3.3 A mensagem de cobrança carrega valor e link, não o QR

```
"Seu pagamento combinado: R$ 200,00. Para pagar e enviar o comprovante: <link>"
```

O link é o `links_do_paciente` que já existe — cuja defesa, como diz o comentário do próprio
código, **não é o token, é a janela**. A página (`pagina_do_paciente`) mostra:

- o valor e a competência;
- o **copia-e-cola PIX** montado com `txid_da_cobranca()`;
- o botão **"já paguei"**;
- o botão **"anexar comprovante"**.

Sobre o `txid` no BR Code estático: ele viaja no campo de referência e **alguns bancos o
exibem no extrato dela, outros não**. Onde aparecer, ele transforma "qual dos doze
pagamentos de R$ 200 é este?" num problema resolvido. Onde não aparecer, o casamento cai
para valor + data. Não prometer na tela o que depende do banco dela.

### 3.4 O comprovante vem pela PÁGINA, e o WhatsApp é o fallback

Esta é a decisão de arquitetura que mais economiza trabalho: **o caminho primário do
comprovante é o upload na página do paciente**, não a mídia no WhatsApp.

Pela página, o comprovante chega **já amarrado à `cobranca_id`** — não existe problema de
casamento, não depende do canal não oficial, não gasta OCR para saber a que se refere, e
funciona igual no plano Gratuito.

Pelo WhatsApp é o fallback de quem não abre o link e só manda o print. Aí sim entra o
casamento da seção 4.2.

---

## 4. A camada de validação manual

### 4.1 Dois eixos independentes, e é isso que a tela precisa mostrar

O erro seria tratar "pagou" e "mandou comprovante" como a mesma coisa. São quatro casos
reais, e três deles pedem ação diferente:

| | mandou comprovante | não mandou |
|---|---|---|
| **pagou** (ela vê no extrato) | conferir e baixar — 1 toque | ela baixa pelo extrato; normal |
| **não pagou** | **conferir com atenção** — comprovante falso, agendado, ou não caiu | régua de cobrança age |

O eixo do dinheiro é `cobrancas.estado`. O eixo da evidência é `comprovantes.estado`.
A tela **junta os dois** — e o valor está nas divergências, não nos casos limpos.

### 4.2 O fluxo de entrada, quando vem pelo WhatsApp

```
webhook MESSAGES_UPSERT
  → grava o evento em mensagens_recebidas ANTES dos filtros
  → dedupe por (provedor, provedor_msg_id)
  → telefone conhecido (paciente OU responsável)?  ── não → guarda em caixa separada, para
  → tem mídia image/* ou application/pdf?          ── não → segue o fluxo normal de resposta
  → baixa o binário (base64 inline; senão getBase64FromMediaMessage)
  → guarda o arquivo no storage da conta
  → extrai: valor, data/hora, E2E ID, instituição, nome do pagador
  → e2e_id já usado?                               ── sim → estado 'reenvio', avisa, não propõe
  → casa com cobrança aberta do paciente
       1 casamento  → proposta, confiança alta
       N casamentos → proposta com opções
       0            → estado 'orfao' (4.5)
  → enfileira `comprovante_recebido` para a paciente
  → aparece na fila de conferência dela
```

### 4.3 O casamento

Por, nesta ordem: **valor exato** contra cobranças abertas do paciente → **janela de data**
(7 dias antes, 1 dia depois) → **paciente do telefone remetente**.

**Nunca casar pelo nome do pagador.** Em terapia quem paga é com frequência a mãe, o marido,
a empresa. Casar por nome produz erro silencioso no lugar mais caro. O nome é **exibido**,
para ela julgar — nunca usado como chave.

**Sempre exibir os campos lidos.** A tela nunca diz "pago"; diz *"li isto — confirma?"*.
É o mesmo S1 da auditoria de UX (*"marca como enviada sem enviar"*) aplicado ao dinheiro.

### 4.4 A recusa é silenciosa

Quando ela recusa um comprovante, a cobrança continua aberta e **nenhuma mensagem
automática sai**. Acusar automaticamente uma paciente de comprovante falso é o pior
resultado possível deste produto — e é irreversível.

A recusa abre uma conversa **dela**, não do sistema. A tela oferece o rascunho; quem manda
é ela, e ela edita antes.

### 4.5 Comprovante órfão é caso comum, não erro

Paga adiantado, ou paga antes de a cobrança do mês nascer. Fica numa caixa e **casa sozinho
quando a cobrança aparecer**, com o mesmo teste de valor e janela.

### 4.6 O reporte

Uma tela, três filas — e ela resolve tudo sem sair dali:

1. **Esperando você conferir** — comprovante chegou, cobrança aberta. Um toque: confere
   (→ `marcar_cobranca_paga()`, e o trigger `ao_pagar_gera_recibo_rfb` dispara sozinho) ou
   recusa (silenciosa).
2. **Pagas sem comprovante** — ela baixou pelo extrato. Normal; fica rastreável para o
   Receita Saúde.
3. **Abertas sem nada** — nem pagamento nem comprovante. É onde a régua de inadimplência age.

Por paciente, `historico_de_cobranca()` já existe e passa a mostrar as duas trilhas lado a
lado: o que foi cobrado e o que foi comprovado.

### 4.7 O `e2e_id` e o que ele prova

```sql
create unique index comprovantes_e2e_uniq
  on public.comprovantes (conta_id, e2e_id) where e2e_id is not null;
```

Isso mata a fraude que realmente acontece, que não é falsificar: é **reenviar o comprovante
do mês passado**.

Honestidade que vai na tela: **conferir o E2E de verdade exige o extrato do banco dela, e o
Sessões não tem isso.** O E2E aqui previne reuso, não prova autenticidade. Quem quer prova
automática ativa o gateway — e essa é uma boa frase de venda do gateway.

### 4.8 Schema

```sql
create table public.comprovantes (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null,
  paciente_id   uuid,
  cobranca_id   uuid,                     -- já preenchido quando vem pela página
  mensagem_id   uuid,                     -- de mensagens_recebidas, quando vem pelo WhatsApp
  origem        text not null check (origem in ('pagina','whatsapp','manual')),
  arquivo       text,                     -- caminho no storage; NULO depois do descarte
  arquivo_hash  text,                     -- sha256, sobrevive ao descarte
  descartado_em timestamptz,
  mime          text not null,
  bytes         integer not null,
  e2e_id        text,
  valor         numeric(12,2),
  pago_em       timestamptz,
  instituicao   text,
  pagador_nome  text,                     -- exibido, NUNCA usado para casar
  extraido      jsonb not null default '{}'::jsonb,
  confianca     text not null default 'baixa' check (confianca in ('alta','media','baixa')),
  estado        text not null default 'pendente'
                  check (estado in ('pendente','conciliado','recusado','reenvio','orfao')),
  decidido_por  text,
  decidido_em   timestamptz,
  criado_em     timestamptz not null default now()
);
```

**Retenção:** ver 4.12 — o arquivo **não** fica cinco anos. Os campos ficam.

### 4.9 OCR: onde roda e o que sai daqui

Comprovante varia muito por banco. Regex sobre OCR local é frágil entre layouts; **modelo
multimodal devolvendo JSON é bem mais robusto** e é o caminho recomendado — com três
condições:

- manda-se **só a imagem**, nunca com nome de paciente, sessão ou contexto clínico no prompt;
- o provedor do modelo entra no **inventário de operadores** da política de privacidade —
  o doc 18 promete que conteúdo **clínico** não vai a terceiros, e comprovante não é
  clínico, mas a fronteira precisa estar escrita;
- guarda-se o JSON extraído; não se guarda o prompt.

### 4.10 Armadilhas

- **Comprovante de plano de saúde**, não de PIX. Vai chegar. É órfão, não erro.
- **Print de PIX agendado** parece comprovante e não é dinheiro ainda. Se o texto trouxer
  "agendado", marcar e não propor.
- **Áudio dizendo "paguei"** não é comprovante.
- **A mesma imagem reenviada 3 vezes** porque ela não respondeu — dedupe por
  `wa_message_id` e por `e2e_id`.
- **Grupo mandando comprovante** — filtro `@g.us` continua valendo.
- **Telefone desconhecido** — pode ser o marido pagando do celular dele, caso frequente.
  Guarda em caixa separada, não propõe.

### 4.11 O descarte do comprovante — o insumo some, o resultado fica

**O comprovante é insumo de uma decisão, não registro da decisão.** É a mesma doutrina do
áudio de ditado, já decidida em 02/09: depois que a transcrição está confirmada, o áudio
some. Aqui: depois que ela confere, o arquivo some — e o que ficou é o que importa.

**O que sobrevive ao descarte, para sempre:** `valor`, `pago_em`, `e2e_id`, `instituicao`,
`pagador_nome`, `confianca`, `decidido_por`, `decidido_em` e o **`arquivo_hash` (sha256)`**.
O registro do dinheiro é a `cobranca`, com `confirmado_por` — que já existe e é imutável
pela trilha.

O hash não é enfeite: se um dia alguém apresentar um comprovante e perguntar "é este que
você conferiu?", o hash responde sem que a gente tenha guardado o arquivo.

**Por que descartar é melhor do que guardar:**

1. **É dado bancário de terceiro.** Quem paga é com frequência a mãe, o marido, a empresa —
   gente que não é cliente dela e nunca consentiu com nada. Guardar cinco anos o extrato
   bancário dessas pessoas é acumular responsabilidade sem finalidade. Minimização, art. 6º,
   III da LGPD.
2. **A obrigação fiscal é sobre o recibo que ELA emite**, e sobre o registro da receita —
   não sobre a prova de pagamento do pagador. O `documentos` e o `recibos_rfb` já guardam o
   que a Receita quer.
3. **O paciente nunca depende da nossa cópia:** o comprovante dele está no banco dele.
4. **Zera a cota.** Eram ~144 MB/ano por psicóloga; passam a ser alguns kilobytes de campos.

**A política, por estado** (a cláusula publicável está no `18`, item 9):

| estado | quanto tempo o arquivo fica | por quê |
|---|---|---|
| `conciliado` | **60 dias após a conferência**, depois some | janela para ela perceber que conferiu errado, e para fechar o mês com folga |
| `recusado` | **12 meses** | é a única prova de que algo estranho aconteceu; some depois |
| `reenvio` | **7 dias** | é duplicata de algo já decidido |
| `pendente` / `orfao` | até decidir; se passar de **90 dias** sem casar, avisa e descarta | órfão eterno é dado parado sem dono |

O expurgo roda no mesmo cron que já limpa a outbox (`expurgar_mensagens`), com uma função
irmã `expurgar_comprovantes(dias)`.

**Isso precisa aparecer na tela, com o número** — é o padrão do doc 18, que resolve a
tensão entre "apagamos" e "temos backup" declarando as duas coisas com prazo:

> *"Comprovante conferido em 03/09. O arquivo é descartado em 02/11; o valor, a data e o
> identificador da transação ficam no seu histórico."*

E vira cláusula no `18`, no mesmo lugar onde entra o descarte do áudio.

### 4.12 A fronteira do `25b`: receber não é enviar

A regra *"o canal não oficial só carrega horário e link"* é sobre **o que nós enviamos**.
A paciente mandando um comprovante por conta própria é entrada: não muda risco de ban e não
é conteúdo que nós publicamos.

O que continua proibido é **responder com documento**. No WhatsApp vai só
`comprovante_recebido` — *"recebi seu comprovante, já confirmo com você"* —, sem valor, sem
recibo, sem nome de procedimento. **O recibo sai por e-mail**, decisão de 30/08.

---

## 5. A página do paciente como repositório de documentos

### 5.1 Metade já existe

`documentos` já é *"recibo, declaração e informe, numerado por conta, imutável, com retrato
congelado"*, e **`documento_do_link(p_token, p_documento)` já serve documento pela página**.
`links_do_paciente` já é um link vivo por paciente, que revoga o anterior quando se gera outro.

O que falta são duas coisas: **o upload do lado do paciente** e **o aviso de que há
documento novo**.

### 5.2 Isso resolve a tensão da classe `documento`

O recibo nunca precisa trafegar por canal nenhum. **A mensagem carrega só o aviso e o link;
o documento mora na página.**

```
"Seu recibo de agosto já está disponível: <link>"
```

Novo template `documento_disponivel` — classe `rotina`, essencial **não** (ela consegue
mandar por fora), tolera 1 dia. E como ele não carrega valor nem nome de procedimento,
pode sair pelo WhatsApp sem tocar na fronteira do `25b`.

O e-mail deixa de ser obrigatório e passa a ser **sob demanda**: a página tem "baixar PDF",
e quem precisa mandar ao plano de saúde baixa e encaminha. Menos e-mail, menos custo, e o
paciente com a coisa na mão.

### 5.3 O que a página passa a ter

| aba | conteúdo | quem escreve |
|---|---|---|
| **Próxima sessão** | data, hora, modalidade, e o aceite de vaga quando houver | sistema |
| **Pagar** | valor em aberto, copia-e-cola PIX com `txid`, "já paguei", "anexar comprovante" | paciente |
| **Meus meses** | uma linha por competência, com os quatro estados (5.4) | sistema |

### 5.4 A espinha: uma linha por mês, quatro estados, três lugares

O que amarra cobrança, comprovante, pagamento e recibo **não é a cobrança** — é a
**competência**. `cobrancas.competencia` já existe, e `emitir_documento(paciente, tipo, de,
ate)` já emite por período: um recibo mensal cobre N sessões. Amarrar por `cobranca_id`
quebraria na primeira psicóloga que cobra por sessão e emite recibo por mês.

**A linha do mês, com quatro marcas:**

| marca | de onde vem | estados |
|---|---|---|
| **Combinado** | `cobrancas` da competência | valor total, vencimento |
| **Comprovante** | `comprovantes` | não enviado · recebido · conferido · recusado |
| **Pago** | `cobrancas.estado` + `confirmado_por` | em aberto · pago em DD/MM · perdoado |
| **Recibo** | `documentos` da competência | não emitido · disponível |

E a mesma linha, com as mesmas quatro marcas, na mesma ordem e com as mesmas palavras,
aparece nos **três lugares**: a aba "Meus meses" do paciente, a tela dela, e o e-mail. É
isso que faz a informação ser uniforme — não um relatório novo, e sim **um vocabulário só**.

**Nunca duas verdades:** se a conta tem gateway ativo, a marca **Pago** vem do webhook e a
marca **Comprovante** não aparece. As duas juntas seriam duas fontes para o mesmo fato.

### 5.5 O risco do repositório, e o controle que eu recomendo

O comentário do próprio código diz que a defesa do link *"não é o token, é a JANELA"*. Isso
valia quando a página servia **uma vaga**. Um repositório permanente muda o perfil: o link
passa a dar acesso ao histórico financeiro do paciente — e o recibo nomeia o serviço, o que
revela que a pessoa faz terapia. Isso é dado de saúde por inferência, e a porta merece
fechadura.

**Primeiro, a simplificação que resolve metade sem atrito nenhum:** a lista não escreve o
serviço. Mostra *"Recibo · agosto · R$ 800 · baixar"*. A palavra "psicológico" só existe
**dentro do PDF**. Assim a aba abre livre, e a fechadura fica só no download.

**Segundo, a fechadura — código de 6 dígitos por e-mail**, válido 10 minutos, liberando os
downloads por 15. É o padrão que todo mundo já viu em banco, e a força vem de ser **outro
canal**: o link chegou no WhatsApp, o código vai no e-mail.

**Sem e-mail cadastrado, cai para data de nascimento** — com a fraqueza assumida por
escrito, porque quem está com o celular na mão costuma ser da família e sabe a data.

**Duas coisas descartadas, e o porquê:**

- **Os quatro últimos dígitos do telefone** — foi sugestão minha na versão anterior e está
  errada. O link chegou naquele telefone; quem tem o link tem o número. Segurança zero.
- **CPF** — não é dado sensível pela LGPD (sensível é saúde, origem, religião, biometria e
  afins), mas é **péssimo segredo**: está em toda parte e vaza há anos. E cria um efeito
  ruim próprio — passar a conferir CPF numa página de paciente de psicologia estabelece uma
  associação CPF ↔ terapia que hoje não existe. Mais risco do que proteção.

`revogar_link_do_paciente()` já existe para cortar o acesso quando ela precisar.

### 5.6 Um efeito colateral bom

Com o repositório de pé, o **kit de reembolso** (doc `23`) ganha o lugar natural dele: a
página é onde a paciente encontra tudo o que o plano dela pede, junto, sem precisar pedir
por WhatsApp. Vale amarrar as duas builds.

---

## 6. O que NÃO trazer

- `fila_envios` do worker — a fila é `public.mensagens`
- `whatsapp_messages` do contatia — já existe `mensagens_recebidas`
- scoring, cadência (`enrollments`/`tasks`), triagem, agente IA
- o probe SMTP da pasta `worker/` do Contatia
- qualquer caminho que marque cobrança como paga sem decisão dela
- qualquer mensagem automática que comunique recusa de comprovante

---

## 7. Checklist de aceitação

**Saída**
- [ ] nenhuma rota chama a função crua da Evolution
- [ ] a resposta distingue **enviada** de **em fila** de **falhou** de **sem WhatsApp**
- [ ] duas execuções simultâneas do cron não mandam a mesma mensagem
- [ ] intervalo entre envios é **sorteado**, nunca fixo
- [ ] oferta de vaga sai na frente de 200 lembretes enfileirados
- [ ] template de classe `documento` **não** sai por WhatsApp em nenhuma hipótese
- [ ] envio com e sem o 9º dígito funciona; **fixo** devolve "não tem WhatsApp"
- [ ] instância fora do ar → conta vira `manual`, urgente por e-mail, rotina para a tela
- [ ] a paciente não recebe a mesma oferta por dois canais

**Cobrança e comprovante**
- [ ] a mensagem de cobrança leva valor + link; o copia-e-cola PIX está na página
- [ ] upload pela página cria comprovante **já com `cobranca_id`**, sem casamento
- [ ] o mesmo `e2e_id` **não** dá baixa duas vezes
- [ ] comprovante **nunca** muda `cobrancas.estado` sem decisão dela
- [ ] cobrança com `provedor_cobranca_id` não aceita proposta por comprovante
- [ ] comprovante sem cobrança vira órfão e casa sozinho depois
- [ ] a tela mostra os campos lidos e pergunta "confirma?", nunca afirma "pago"
- [ ] recusa **não** dispara mensagem automática
- [ ] as três filas do reporte batem com `financeiro_do_mes()`
- [ ] o arquivo do comprovante some no prazo do estado dele; valor, data, `e2e_id` e hash ficam
- [ ] a tela diz a data em que o arquivo será descartado, antes de acontecer

**Página do paciente**
- [ ] upload de comprovante pela página cria a linha com `origem='pagina'`
- [ ] a lista de documentos NÃO escreve o serviço; "psicológico" só aparece dentro do PDF
- [ ] o download exige código de 6 dígitos por e-mail (fallback: data de nascimento), válido 10 min e liberando 15
- [ ] a linha do mês mostra as quatro marcas com as mesmas palavras na página, na tela dela e no e-mail
- [ ] com gateway ativo, a marca Comprovante some da tela
- [ ] `documento_disponivel` leva só o aviso e o link — nunca o arquivo
- [ ] `revogar_link_do_paciente()` corta o acesso ao repositório inteiro

**Entrada**
- [ ] evento gravado **antes** dos filtros, com o destino de cada um
- [ ] mesma mensagem entregue duas vezes grava **uma** linha
- [ ] grupo e `status@broadcast` não geram linha, mas geram registro

---

## 8. Fronteiras do piloto (do `25b`)

1. **O canal não oficial só carrega horário, valor e link, na saída.** Documento por e-mail.
2. **O add-on "seu número" não existe no piloto.**
3. **Encerra no que vier primeiro:** aviso/bloqueio/queda de qualidade · 20 contas pagantes ·
   60 dias após o lançamento.
4. **O caminho oficial começa em paralelo, agora** — WABA, verificação, template e
   aquecimento levam de duas a quatro semanas.
