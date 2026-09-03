# B46 · A quarta varredura

**1 dia · migração: nenhuma · quinta da fila**
*Antes da primeira pagante, porque é contrato.*

---

## Por que esta build existe

"A promessa que o software não cumpre" é um antipadrão nomeado deste projeto, e
**já aconteceu três vezes**: a `/privacidade` descreveu duas exclusões
inexistentes (achado da B41); a `/termos` prometeu 60 mensagens depois de o
limite ter mudado (achado da OP8); a página de planos descrevia oito recursos
inexistentes (achado da OP10). A auditoria de UX previu o quarto caso e o achou —
mais três da mesma família.

**A lição da B40 vale aqui:** a correção que importa não é a lista. É a
**varredura**.

---

## As quatro afirmações falsas

### 1 · "com aprovação em etapas" — o nono recurso inexistente

```
lib/planos.ts:157   "Permissões por pessoa: quem vê o quê, com aprovação em etapas"
migração 0064:329   'permissões por pessoa: quem vê o quê'      ← sem a segunda metade
app/(site)/page.tsx:695   {PLANOS.map(...)}   ← lê o TypeScript, não public.planos.recursos
```

A 0064 criou `por_vir` e a restrição `planos_promessa_nao_e_recurso` para isso não
voltar. Voltou, no cartão de R$ 129, e passou porque **a trava mora na coluna do
banco e a landing renderiza a constante do TypeScript**. Não há implementação de
aprovação em etapas em `app/`, `lib/` ou `supabase/`. E `lib/planos.test.ts:153`
reimplementa a checagem contra a constante, mas nunca compara as duas listas
entre si — elas já divergiram em três pontos.

### 2 · `/termos`: cobrança por faixa de sessões

`app/(site)/termos/page.tsx:121-127` — *"Cada plano tem uma faixa de sessões por
mês, e é essa a unidade cobrada… avisamos você, e sugerimos o plano seguinte"*.
**Três dos quatro planos não têm faixa:** `lib/planos.ts:85` (`gratis: faixa
null`, decisão da 0064), e `pro`/`clinica` são `fairUse: true`, o que faz
`lib/faixa.ts:146` responder *"Seu plano não tem faixa de sessões"*. E o aviso
prometido nunca dispara em plano fair-use (`lib/faixa.ts:106-107`).

### 3 · A conciliação do Pix

`app/(site)/page.tsx:383-389` — *"…para você revisar só as divergências **em vez
de conferir o extrato inteiro no fim do dia**"*. Mas
`lib/pagamentos/adaptadores.ts:106-115` sempre devolve `pixDireto` (o ramo do
Asaas lança), e `pixDireto` grava `provedorCobrancaId: null` — o comentário
`:91-92` diz que é justamente por isso que *"esta cobrança nunca entra na fila de
conciliação diária"*. `cobrancas_a_conciliar` filtra
`provedor_cobranca_id is not null`: zero linhas, sempre. O caminho real é ela
apertar "já recebi".

### 4 · "o sistema recusa apagar o que está no prazo de guarda"

`app/(site)/page.tsx:605-608` e `app/(site)/privacidade/page.tsx:180-182` — *"o
sistema recusa apagar"*, *"nem a seu pedido"*. O cabeçalho da 0062 diz o
contrário, com todas as letras: *"não decide nada pela guarda. A função não
recusa a exclusão porque o prazo de cinco anos está correndo… o que ele faz é
**dizer**, na frase que devolve, até quando ela continua responsável."*
`eliminar_conta` tem três recusas (dona, nome digitado, exportação em 24h) e
nenhuma olha `retencao_anos`. A decisão da 0062 é defensável; a tela é que não foi
atualizada junto.

*(A quinta afirmação da família — "pela API oficial da Meta" — é conserto de
comportamento e está na **B43**. Se a B43 já rodou, a frase daqui passa a ser
verdadeira quando o BSP existir; até lá, a landing precisa dizer o que é.)*

---

## Entrega

1. **As quatro frases corrigidas**, com a palavra da página (ver o vocabulário no
   `CLAUDE.md`).
2. **A varredura:** um teste que compara `PLANOS` de `lib/planos.ts` com
   `public.planos.recursos` **linha a linha**, nos dois sentidos, e reprova a
   diferença. Hoje a trava do banco protege a coluna que ninguém renderiza.
3. **Uma segunda varredura, mais ampla:** toda afirmação factual de tela pública
   (número, prazo, garantia, "o sistema faz X") tem uma função nomeada ao lado,
   no teste. Comece pelas que a auditoria conferiu e **batem** — elas viram o
   corpo da suíte, não só as que falharam.

---

## Pronto quando

- [ ] acrescentar uma linha de `recursos` só em um dos dois lugares **reprova a
      suíte**;
- [ ] as quatro frases descrevem o comportamento real, verificado abrindo a
      função correspondente;
- [ ] a suíte lista, por página pública, cada afirmação e a função que a
      sustenta.

---

## Não entra

- **Reescrever a landing.** São quatro frases e uma varredura.
- **Apagar as linhas de `recursos` que descrevem o que não existe.** A 0064 já
  resolveu isso do jeito certo: entra em `por_vir`, sob o rótulo *"Ainda não
  existe, e não está no preço"*. Apagar deixaria a página honesta e muda.

---

## Armadilha

**Corrigir as quatro frases e não escrever a varredura.** A quinta aparece na
semana que vem, pelo mesmo caminho, e a coluna do banco continuará protegida
enquanto a tela continua livre.

---

## Arquivos que esta build toca

```
lib/planos.ts       lib/planos.test.ts
app/(site)/page.tsx         app/(site)/termos/page.tsx
app/(site)/privacidade/page.tsx
supabase/tests/  (ou um teste vitest que leia o banco)
```

**Bônus para o diário, não para a tela:** o cabeçalho da 0061 (`:47`) ainda
raciocina o custo do Gratuito com "8 sessões de faixa", número que a 0064 apagou.
