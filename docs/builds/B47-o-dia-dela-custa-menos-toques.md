# B47 · O dia dela custa menos toques

**2,5 dias · migração: nenhuma · décima primeira da fila**
*A build-vassoura. Existe para os pequenos não desaparecerem nem virarem onze
builds. Um número de dias só.*

---

## Como usar este arquivo

A lista abaixo são os **S3 e S4** da auditoria de UX. Nenhum abre build sozinho.
Faça de cima para baixo, marque o que fez, e **não deixe nenhum item virar uma
build nova** — se algum se revelar S1/S2 ao abrir, pare e escreva o achado.

---

## Celular e toque

- [x] **"toquei na sessão e não aconteceu nada"** — `Semana.tsx:162-182` e
      `:207-215`: no celular o painel abre **depois da lista dos sete dias**, sem
      `scrollIntoView`, sem âncora e sem estado visual de selecionado. Numa
      semana de 25 sessões o painel abre mil pixels abaixo. *(Se a B39 já rodou,
      isso já está feito.)*
- [x] **alvos de toque de 17 a 37 px.** Nenhum chega aos 44 px. Os piores:
      `Navegacao.tsx:240-255` (a barra do celular, 37 px) ·
      `PainelSessao.tsx:53-61` (Aconteceu / Não veio, ~34,8 px) ·
      `Decisoes.tsx:86-92` (Cobrar / Não cobrar) · `Registro.tsx:34` e `:120-126`
      ("Guardar" da evolução e "editar", ~31 e ~17 px) · `Anamnese.tsx:38` ·
      `Cockpit.tsx:70-75` · `Confirmacoes.tsx:90-96`.
      Conserto: `py-3` nas fileiras de decisão · `min-h-[44px]` na barra ·
      uma classe compartilhada com `-m-2 p-2` nos linkzinhos (aumenta o alvo sem
      mexer no layout).
- [x] **rótulo de campo em 10,5 px, maiúsculas, na cor mais apagada.**
      `app/globals.css:79-85` (`.rotulo`), usado por `campos.tsx:15`. Um
      formulário de 15 campos rotulado assim, lido de pé, é o pior caso do
      produto. Conserto: 12 px, sem uppercase, em `tinta2`.
- [x] **o iPhone dá zoom em todo campo** *(não verificado em aparelho)* — 195 de
      253 campos abaixo de 16 px. Conserto:
      `@media (max-width:640px){input,textarea,select{font-size:16px}}` no
      `globals.css`. **Não** use `maximum-scale=1`: resolve o zoom e quebra a
      acessibilidade de quem precisa ampliar.
- [x] **o teclado sobe e a barra fixa senta em cima do "Guardar"** —
      `Navegacao.tsx:240` é `fixed bottom-0` e não tem handler de
      `focusin`/`focusout`; `Registro.tsx:152` é o botão coberto. Conserto:
      esconder a barra com `:focus-within` num campo.
- [x] **as setas de semana e o "Hoje" se comprimem em 375 px** —
      `agenda/page.tsx:116` reserva `min-w-[13rem]` fixos para o rótulo,
      deixando ~127 px para os três controles. Conserto: `sm:min-w-[13rem]` e
      `py-2` nos três.
- [x] **PWA não abre nada offline** *(não verificado em aparelho)* —
      `public/sw.js:52-60` nunca cacheia navegação (decisão de LGPD, correta) e
      `:26-29` não pré-carrega nada; instalada como PWA, ela recebe a tela de
      erro do navegador **sem barra de endereço para sair**. Conserto: uma rota
      `/offline` **sem dado nenhum**, pré-cacheada no `install` e servida só para
      `request.mode === "navigate"`. **Não cacheie a agenda** — é prontuário no
      aparelho.

## Onboarding e estados vazios

- [x] **"faltam três passos" numa página de cinco.** `agenda/page.tsx:151` diz
      três; `comecar/page.tsx:79` diz cinco.
- [x] **a faixa de configuração nunca some.** `agenda/page.tsx:104-105`:
      `comecando` exige `vagas_abertas > 0`, que depende de **uma paciente
      desmarcar de verdade**. Numa conta bem configurada sem cancelamentos, a
      faixa fica para sempre — e alarme que toca sempre vira paisagem.
- [x] **e a mesma condição ignora `janelas`.** Quem pula o passo 1 e faz os
      outros três **perde a única porta para `/comecar`** — ele não está em
      `destinos()` nem em `SECOES` (`lib/navegacao.ts:115-118`, `:453-473`). É a
      única rota órfã do produto.
- [x] **o passo 3 se marca sozinho.** `comecar/page.tsx:72`:
      `temHorario = enquadres > 0`, que o passo 2 já satisfaz. Ela nunca confere
      valor nem política, e o passo diz que conferiu.
- [x] **o passo 5 não é um passo.** `:74`: `jaRodou = vagas_abertas > 0`. Não há
      ação nessa tela. Conserto: ele deixa de ser caixa a marcar e vira a frase
      que fecha a página.
- [x] **o passo 2 só aceita colagem.** `comecar/page.tsx:130-140` renderiza
      exclusivamente o `<Importar />`, sem link para `/pacientes/novo`. Quem tem
      seis pacientes na cabeça não tem saída. Conserto: uma linha — *"Sem lista à
      mão? Cadastre uma pessoa por vez."*
- [x] **conta nova vê o cockpit com três travessões.** Confirmado no banco: a
      conta `demo` tem 8 pacientes e **zero** `janelas_atendimento`, e
      `cockpit_do_mes` devolve `sem_janela: true` com três nulos. A frase de
      `fraseDoCockpit` está certa e chega **depois** dos travessões
      (`lib/risco.ts:142-156`). Conserto: subir a frase, esconder os quatro
      números enquanto não há janela.
- [x] **`/fechamento` promete ficar quieta e não fica** — `page.tsx:71-74` diz
      *"quando não há nada vencendo, esta tela fica quieta"* e `:76-102` renderiza
      sempre os quatro cartões. **`/encaixes`** mostra `0 / 0 / 0 / —` numa conta
      nova sem dizer que zero é o esperado. Conserto: copiar o estado vazio de
      `/pacientes` (`page.tsx:26-40`), que é o melhor do produto.

## Palavra

- [x] **jargão do sistema como rótulo de tela** — "livro-razão"
      (`fechamento/livro/page.tsx:21,121`, `fechamento/page.tsx:38`) · "eixo"
      (`livro/page.tsx:135,251`, `fechamento/page.tsx:40`) · "materializada"
      (`Ausencias.tsx:145`, **na agenda**) · "lastro"
      (`pacientes/[id]/page.tsx:132`, `perfil/page.tsx:271`) · "régua"
      (`lib/livro.ts:155` — o rótulo é "ver a régua" e o destino se chama "A
      receber") · "capacidade" (`Cockpit.tsx:68`).
- [x] **"faixa" quer dizer duas coisas** — cota de plano (`Faixa.tsx:78,110`) e
      janela de horário (`comecar/page.tsx:101`).
- [x] **o Perfil nunca escreve o nome do plano.** `perfil/page.tsx:135` mostra só
      a barra; `nomeDoPlano` (`lib/planos.ts:206`) existe e **não é chamada em
      tela nenhuma**.
- [x] **"cobrança automática" e "a política cobrou"**, depois de a 0058 ter
      tirado a cobrança do software — `pacientes/[id]/page.tsx:132` ·
      `perfil/page.tsx:271` · `lib/financeiro.ts:178` (impressa sob "O sistema
      trouxe de volta:"). Quem cobrou foi ela, na caixa "A decidir".
- [x] **"o sistema oferece sozinho"** no Gratuito, onde quem oferece é o polegar
      dela — `FilaEntrada.tsx:53,59` · `comecar/page.tsx:82-83,197-199`. A frase
      condicional já existe na página de planos.
- [x] **"Boa, Renata." como h1**, sem "tarde"/"noite" — lê-se como elogio, que a
      regra recusa. `agenda/page.tsx:111`; o arquivo já usa "Sua semana" como
      alternativa.
- [x] **~200 palavras de texto de projeto no meio de tarefas.** Doze ocorrências
      de "é de propósito / é decisão / nem por você / o Manual pede". Cortar as
      quatro piores: `fechamento/livro/page.tsx:259-265` (52 palavras sobre um
      número que a tela **não mostra**) · `livro/page.tsx:250-255` (52 palavras
      sobre arquitetura) · `perfil/horarios/page.tsx:153-156` (33 palavras de
      roadmap **antes** do formulário do passo 1) · `Registro.tsx:163-165`
      ("Guarda de cinco anos", dentro da fileira de botões da evolução — a frase
      pior colocada do produto). **Elas pertencem ao diário.**
      *(A peça que resolve o "explica demais / explica de menos" é o `ajuda` em
      `<details>` no `Campo`, e é da B48 — faça os cortes depois dela.)*

## Estado, foco e contraste

- [x] **na grade do desktop o estado da sessão é só cor** — `Semana.tsx:15-22`
      e `:118-137`; a lista do celular (`:179-181`) já mostra o rótulo em texto e
      está certa. Conserto: `title` + `sr-only` com `ROTULO_ESTADO`.
- [x] **o prontuário não diz ao leitor de tela o que está pronto** —
      `Registro.tsx:253-266`: o `●`/`○` é `aria-hidden` e a única diferença que
      sobra é a cor.
- [x] **a sub-navegação são links de 19,5 px colados a 4 px** quando quebram de
      linha — `Navegacao.tsx:66-79`. Conserto: `py-2` e `gap-y-2`.
- [x] **o menu do perfil não fecha com Escape** — `Navegacao.tsx:275-282`
      registra só `mousedown`; o `BotaoNovo` ao lado (`:139-153`) registra os
      dois. Nenhum devolve o foco ao botão ao fechar.
- [x] **o único `focus:outline-none` sem substituto do repositório** —
      `Anamnese.tsx:209-218`, no título de seção. A especificidade dele vence o
      `:focus-visible` global de `globals.css:68-72`.
- [x] **o foco da busca global se marca com uma borda de contraste 1,18:1** —
      `Navegacao.tsx:227`. Conserto: `focus-visible:border-vaga`.
- [x] **bordas de campo com contraste 1,73:1 sobre branco** (o mínimo WCAG para
      contorno de componente é 3:1) — token `--color-linha2` (`#C0C7BC`), usado
      em sete componentes. Conserto: escurecer o token (algo em torno de
      `#9AA39C`) — muda todos os campos de uma vez.

## Irreversíveis e desfechos

- [x] **"não recebi ainda" desfaz sem avisar**, e a frase de sucesso nunca chega
      à tela — `PainelSessao.tsx:207-221`; a ação devolve dois desfechos
      materialmente distintos (`recebimentos/movimentacoes/acoes.ts:76-81`) e o
      componente só renderiza o erro.
- [x] **nas duas confirmações que existem, o escape é o elemento de menor
      contraste** — `Privacidade.tsx:135-147` e `:176-193`: "Sim, apagar" é
      `tom="grave"` e "deixa" é um botão sem borda em `text-tinta3`.
- [x] **a trava das 24h se explica, menos quando a leitura da exportação falha** —
      `Encerrar.tsx:194-200` só renderiza sob `exportacao.estado === "ok"`; no
      estado `indisponivel` (`perfil/encerrar/dados.ts:44-47`) sobra um campo
      cinza sem explicação. E a lista do que some (`:182-187`) não menciona
      assinatura nem fatura, que `eliminar_conta` também apaga.

## Dinheiro e origem *(se a B44 já rodou, pule)*

- [x] os oito números do topo da agenda não abrem — `agenda/page.tsx:159-177`,
      `Retorno.tsx:63-76`; o padrão existe em `Contador.tsx:250-262`.
- [x] o dinheiro da agenda é arredondado para real inteiro, e só ali —
      `agenda/page.tsx:36-37` vs `lib/dinheiro.ts:51-57`.
- [x] o campo "cobrar quanto" nasce em formato americano
      (`Decisoes.tsx:174` → `deCentavos` → `"200.00"`) e `paraCentavos` está
      **fora** do `try` em `agenda/acoes.ts:405` (o `try` começa em `:414`), então
      um valor com milhar derruba a server action com falha genérica.

---

## Pronto quando

- [x] todos os itens marcados, ou com a razão escrita de por que não;
- [x] `npm run verificar` limpo;
- [x] nenhum item virou build nova.

---

## O que foi feito de outro jeito, e por quê

Três itens não terminaram como o arquivo previa. Nenhum virou build nova.

- **`--color-linha2` foi para `#7F8982`, não para `#9AA39C`.** O tom sugerido dá
  2,60:1 sobre o branco — ainda abaixo dos 3:1 que o item pede. O valor aplicado
  é o mais claro que passa nos **três** fundos ao mesmo tempo (papel 3,10 ·
  folha 3,62 · folha2 3,32), e `testes/o-contraste-se-calcula.test.ts` recalcula
  isso a cada rodada em vez de deixar o número no comentário.

- **"capacidade" ficou.** O item pede tirar a palavra do `Cockpit.tsx:68`, mas o
  `CLAUDE.md` §5 manda escrever exatamente *"quanto da capacidade virou
  receita"* no lugar de "otimizar ocupação" — é a frase aprovada, não o jargão.
  O que a §5 proíbe é **"capacidade vendável"**, e essa não existe em tela
  nenhuma (a varredura confere).

- **"Sem faixa de sessões" continua no texto dos planos.** É o único lugar em
  que "faixa" com sentido de cota sobrou, e ele mora no **banco**: a 0070 mantém
  `lib/planos.ts` e as linhas de `planos` idênticas, e a suíte espelho reprova a
  divergência. Trocar a palavra exige migração, e migração é o que esta build
  recusa por escrito. Vai na próxima que tocar em planos. As frases da conta
  (`lib/faixa.ts`, `Faixa.tsx`) já saíram: "as sessões que o seu plano inclui".

**As três varreduras que ficam de pé:**
`testes/o-contraste-se-calcula.test.ts` — recalcula o contraste de **todo** token
do `@theme`, e reprova o token novo que aparecer sem papel declarado; confere os
44 px, os 16 px e o `focus:outline-none` sem substituto ·
`testes/o-jargao-nao-vira-rotulo.test.ts` — lê só o texto que vira pixel (nó de
JSX e literal com cara de frase, sem comentário e sem `className`) e procura as
nove palavras do Manual, as duas promessas que a 0058 desfez, e qualquer tela
que volte a escrever de quantos passos é o começo · `lib/comecar.test.ts` — o
que falta configurar, contado num lugar só.

---

## Não entra

Nada que exija migração, e nada que mude comportamento de dinheiro, fila ou
prontuário. Se um item pedir isso, ele não era S3.
