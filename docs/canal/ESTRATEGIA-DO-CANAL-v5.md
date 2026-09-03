<!--
  ===================================================================
  NOTA DE ARQUIVAMENTO — 03/09/2026, ao entrar no repositório
  ===================================================================

  Este é o **Anexo A** que o pacote B49–B54 chama de "o prompt de abertura" da
  B52, da B53 e da B54 — e que até hoje **não estava no repositório**. O pacote
  o citava seção por seção (§1 e §2 para a B52, §3 e §4 para a B53, §5 para a
  B54) e quem abrisse qualquer uma das três não tinha o que ler.

  Entra inteiro e sem edição, como o pacote. O que envelheceu desde 02/09 está
  registrado em `docs/canal/README.md`, e não aqui: reescrever prompt de
  abertura é como se perde o que ele dizia.
  ===================================================================
-->

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
