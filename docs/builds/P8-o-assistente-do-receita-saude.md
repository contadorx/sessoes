# P8 · O assistente do Receita Saúde

**1 dia · migração: a definir (0066 já é da B44) · oitava da fila**
*O doc de origem é o `claude/25`. Subiu de prioridade pela auditoria de UX.*

---

## Por que esta build existe, e por que subiu

Nasceu de olhar a Hotina — que anuncia emitir o recibo "em um clique" — e
descobrir que **o preparo já estava construído**. O que faltava era o momento, e
o momento é pequeno.

A auditoria de UX mostrou que a tela intermediária **existe e é pior do que não
existir**:

```
components/app/ReceitaSaude.tsx:209   o comentário diz: "na ordem em que você vai digitar"
components/app/ReceitaSaude.tsx:211-233
   data (:215) · nome como link (:218) · CPF (:224) · valor (:231)
   — quatro <span> de leitura. Nenhum botão copia nada.

navigator.clipboard no repositório inteiro: três ocorrências —
   PainelSessao.tsx:134 (Pix) · Lastro.tsx:229 (link) · Remarcar.tsx:152
   nenhuma nesta tela.
```

O produto **ordenou os campos na sequência do app da Receita** e parou um toque
antes de tirar o trabalho. Hoje ela lê quatro dados na tela do Sessões e redigita
~25 caracteres por recibo no outro app, no mesmo telefone, sem área de
transferência. Em ~35 pagamentos/mês (o número que o próprio código usa,
`ReceitaSaude.tsx:287`): **~875 caracteres digitados à mão e ~70 toques**.

E se ela errar um dígito, nada aqui percebe — é "conciliador, não emissor" por
decisão. O recibo errado fica de pé na Receita, com dez dias para cancelar no
e-CAC.

---

## Entrega

1. **`contas.ritmo_recibo`** (`sessao` / `semanal` / `mensal` / `fevereiro`),
   default `mensal` até a pesquisa responder, **com a tela dizendo que é
   provisório**.
2. **O cartão de emissão** na conciliação do pagamento: seis campos copiáveis
   **um a um**, porque o app da Receita é campo a campo. Reusar o padrão já
   escrito em `components/app/PainelSessao.tsx:129-165`. Os dois que ela mais
   erra são **CPF e valor**.
3. **`recibos_rfb.marcado_por_ela_em`** e **`numero_informado`**.
4. **O lembrete do lote**, apontando para o CSV que a 0053b já gera.
5. **O pagador pessoa jurídica**, com motivo pré-escrito e relatório.
6. **A telemetria:** dias entre pagamento e baixa · pendências que chegam a
   janeiro · lote contra cartão.

---

## Pronto quando

- [ ] **copiar e colar produz o recibo sem digitar nada — verificado fazendo uma
      vez**, com CPF e valor;
- [ ] marcar como emitido baixa a pendência, e **nenhuma tela escreve "emitido"
      sem o "por você" junto**;
- [ ] mudar o ritmo hoje não reenvia nada do passado;
- [ ] conta PJ não recebe nada disso;
- [ ] a **suíte adversarial planta um valor com cara de credencial gov.br e
      reprova qualquer coluna que o aceite**.

---

## Não entra — e isto é a fronteira 11, não corte de prazo

Emitir · autenticar · navegar no e-CAC · guardar senha, sessão ou token ·
integrar com intermediador que peça a conta dela por dentro do nosso produto.

**Três razões, e a primeira sozinha decide:** a conta gov.br dela não é a chave
do recibo — é a chave do INSS, do e-CAC e da declaração; a automação sobre tela
de terceiro falha em silêncio e a multa de R$ 100 por recibo é do CPF dela; e
emitir é ato dela, e o produto não tem CPF nem CRP.

**Nenhuma razão comercial reabre isto.** Se a Hotina e os intermediadores
tornarem "o sistema emite por você" o padrão esperado (risco R15), a resposta é a
mesma do prontuário: **privacidade vira headline, não rodapé**.

---

## O que depende da conversa, e o que não depende

**Depende:** o *tamanho*. Se a periodicidade modal for mensal ou fevereiro e o
incômodo mediano for ≤ 4, o P8 encolhe para o alarme de novembro e o cartão não
se constrói. Ver o portão do bloco 7b do doc `08`.

**Não depende:** copiar e colar seis campos vale a pena em qualquer
periodicidade, porque **o custo por recibo não muda**. Se a conversa encolher o
P8, o cartão fica; o que sai é o ritmo e o alarme.

**E pode mudar de lugar:** se a "parte chata" do 7b.3 for **achar o CPF do
paciente**, a dor se resolve na **B34** (pré-ficha administrativa) e não aqui.

---

## Armadilha

**Esperar a conversa para construir o cartão.** A tela intermediária já existe,
já está na ordem certa, e cada mês que passa são ~875 caracteres redigitados.

---

## Arquivos que esta build toca

```
components/app/ReceitaSaude.tsx    ← o cartão
app/(app)/fechamento/receita-saude/page.tsx  e /acoes.ts
lib/receitasaude.ts
supabase/migrations/  (ritmo_recibo, marcado_por_ela_em, numero_informado)
```

**Bug de passagem que cabe aqui:**
`app/(app)/fechamento/receita-saude/csv/route.ts:62-63` — sem o CPF dela, a rota
devolve JSON 409 e, como é um `<a href>` simples, o navegador **troca a página**
pela string crua `{"erro":"…"}`.
