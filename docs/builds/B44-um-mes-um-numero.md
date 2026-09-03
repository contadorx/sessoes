# B44 · Um mês, um número

**2 dias · migração `0066` · terceira da fila**
*Abre por S1: segunda fonte de verdade sobre dinheiro é S1 automático neste
produto.*

---

## Por que esta build existe

Quatro funções respondem "quanto entrou neste mês" e **duas delas discordam sem
que nenhuma tela diga por quê**. Se ela vir dois números que não batem, o produto
perdeu a discussão inteira — e é a discussão que ele existe para ganhar.

As quatro, lado a lado (corpos lidos do `pg_proc`, não das migrações):

| | `retorno` | `financeiro_do_mes` | `livro_razao` | `cockpit_do_mes` |
|---|---|---|---|---|
| escopo | RLS (conta) | `conta_atual()` | `p_profissional` | `p_profissional` |
| base | competência | competência **e** caixa | competência | herda do livro |
| multa cobrada | sim, **sem filtro de tipo** | sim | sim | sim, excluída da soma |
| sessão realizada não paga | não | sim | sim | sim |
| mensalidade / pacote | **sim** | sim | sim | sim |
| despesa | não | sim | não | não |
| **sessão importada** | não | **não** (`s.origem <> 'importada'`) | **sim** | **sim** |

---

## S1-A · O livro-razão conta o histórico importado; o Financeiro não

```
supabase/migrations/0040b:44     financeiro_do_mes → and s.origem <> 'importada'
supabase/migrations/0056:580-585 livro_razao       → sem filtro de origem
supabase/migrations/0056:299-306 recalcular_eixos  → valor_reconhecido := s.valor
                                                     em toda sessão realizada
supabase/migrations/0040:956     a importação insere exatamente isso
```

A razão do filtro está escrita na própria 0040b: *"uma planilha com dois anos
despejaria dezenas de milhares de reais em meses fechados"*. A decisão é certa —
só não foi aplicada na segunda função.

**Reproduzir:** rodar o passo 2 do onboarding com dois meses de histórico, abrir
`/fechamento/livro?mes=…` e `/recebimentos/movimentacoes?mes=…` no mesmo mês. O
primeiro mostra receita reconhecida; o segundo mostra R$ 0,00. Nenhuma das duas
telas explica.

O mesmo contamina os quatro números do Cockpit, que herda do livro.

---

## S1-B · "Retorno" apresenta o faturamento do mês como ganho da fila

```
banco: função retorno, CTE `dinheiro`
  coalesce(sum(c.valor) filter (where c.estado = 'paga'), 0) as recebido
  ...
  from public.cobrancas c
  where c.competencia between ...          -- ← nenhum filtro de c.tipo

banco: check cobrancas_tipo_check
  tipo in ('falta', 'sessao', 'mensalidade', 'pacote')

components/app/Retorno.tsx:34    total = somar(preenchido, recebido)
components/app/Retorno.tsx:52-56 <p className="font-serif text-[26px] ...">
                                 "que não teria entrado sem a fila e sem a política."
```

A CTE soma os quatro tipos. Numa conta de mensalistas, o número em serifa de 26
px na agenda é **o faturamento do mês apresentado como ganho da fila**. E o
componente renderiza mesmo com zero cancelamentos: `Retorno.tsx:36` só some
quando o total **também** é zero.

O cabeçalho da própria 0025 descreve outra coisa: *"recebido — a cobrança de
cancelamento tardio que ela marcou como paga"*.

**Por que dói mais do que um número errado:** é a única frase do produto que faz
afirmação contrafactual sobre o dinheiro dela — parente próximo do simulador de
ROI que o doc `09` matou de propósito.

---

## Os S2 da mesma família

**"hora vazia" desconta uma multa que ninguém decidiu.**
`app/(app)/agenda/dados.ts:86-91` faz `perdido += valor - multa` para
`cancelada_tarde`, e a nota da tela (`agenda/page.tsx:173`) diz "o que a política
não recupera". Desde a 0058 a política não recupera nada sozinha: nasce uma
`proposta_de_cobranca`, que a própria migração marca como *"NÃO é dinheiro"*. A
mesma multa aparece logo abaixo, indecisa, na `CaixaDeDecisoes`. Dois números da
mesma semana, na mesma tela, um assumindo o que o outro está perguntando.

**"Recebi" grava datas diferentes em duas telas.**
`components/app/Financeiro.tsx:200-204` manda `quando = s.dia` (o dia da
**sessão**); `components/app/PainelSessao.tsx:108-111` não manda nada e
`registrar_recebimento` cai em `hoje_sp()`. Não há campo de data em nenhuma das
duas, e a nota manda "corrigir na cobrança" — que não existe. Na virada do mês
isso põe dinheiro no mês errado, e o mês errado vai para o contador.

**Nenhum dos oito números do topo da agenda abre.**
`agenda/page.tsx:159-177` e `Retorno.tsx:63-76` não têm nenhum `Link`. O padrão
certo existe em `components/app/Contador.tsx:250-262`, que nomeia as telas de
origem.

**O dinheiro da agenda é arredondado para real inteiro, e só ali.**
`agenda/page.tsx:36-37` usa `maximumFractionDigits: 0`; todo o resto usa
`formatar` em centavos. E `dados.ts:88` faz a conta da multa em reais com
`Math.round`, enquanto `multa_da_politica` arredonda em centavos.

**O livro-razão é de "um profissional ativo qualquer".**
`app/(app)/fechamento/livro/page.tsx:87-92` faz
`.eq("ativo",true).limit(1)` — sem ordenação e sem rótulo dizendo de quem é o
mês. O Cockpit usa `sessao.profissionalId`. Numa clínica, o link "o mês inteiro"
leva de um mês para outro mês, com o mesmo título.

---

## Entrega

1. **`and s.origem <> 'importada'`** nas consultas de `livro_razao` — a mesma
   cláusula, com o mesmo motivo, na segunda função.
2. **`and c.tipo = 'falta'`** na CTE `dinheiro` do `retorno`.
3. **"hora vazia" soma o valor cheio** enquanto a proposta estiver `pendente`.
4. **"Recebi" grava uma data só** — a de hoje, que é o regime de caixa que o
   resto usa — e o painel ganha um campo de data opcional para o Pix que caiu
   dias depois.
5. **Os números do topo da agenda abrem** na lista que os forma, no padrão do
   `Contador.tsx`.
6. **`formatar` na agenda**, e a conta da multa em centavos.
7. **O livro-razão diz de quem é o mês**, e escolhe o profissional com ordenação
   estável (ou o da sessão, como o Cockpit).
8. **A suíte que impede a próxima divergência:** compara as quatro funções no
   mesmo período, para a mesma conta, e reprova divergência que a tela não
   explique.

---

## Pronto quando

- [ ] uma conta com histórico importado mostra **o mesmo mês igual** em
      `/fechamento/livro` e em `/recebimentos/movimentacoes`;
- [ ] uma conta só de mensalistas, sem cancelamento, mostra **R$ 0** em
      "Retorno" — e a caixa some;
- [ ] a soma de "hora vazia" da semana não desconta multa em estado `pendente`;
- [ ] marcar "Recebi" nas duas telas, no mesmo dia, grava a mesma data;
- [ ] tocar em "previsto" na agenda leva às sessões que o formam;
- [ ] a suíte nova compara as quatro funções e reprova divergência.

---

## Não entra

- **Unificar as quatro funções numa.** Elas respondem perguntas diferentes, e a
  divergência é legítima **quando dita**. O que não é legítimo é divergirem em
  silêncio.
- **Tirar o filtro do `financeiro_do_mes` para os dois baterem.** Aí mentem
  juntos, e o mês fechado que ela mandou ao contador ano passado ganha receita
  nova.
- **Trocar a frase do "Retorno" em vez do número.** Frase vaga sobre número
  errado deixa de ser conferível e continua errada.
- **Mexer no `mês em duas colunas` de `/recebimentos`.** A `financeiro_do_mes`
  responde isso desde a B23; duplicá-la na agenda seria criar a segunda fonte que
  esta build existe para não ter.

---

## Armadilhas

- **Reescrever `livro_razao` a partir da migração 0056.** Leia o banco (lei 6).
  Ela foi tocada por 0056b–e e pelo P5.
- **Achar que `retorno` só é lida pela caixa da agenda.** Confira quem mais a
  chama antes de mudar a assinatura.
- **Mandar sempre o dia da sessão no "Recebi".** Aí o recebimento vira
  competência e passa a discordar do `financeiro_do_mes`, que é caixa — três
  definições em vez de duas.

---

## Arquivos que esta build toca

```
supabase/migrations/0066_*.sql   ← livro_razao e retorno
app/(app)/agenda/dados.ts        app/(app)/agenda/page.tsx
app/(app)/fechamento/livro/page.tsx
components/app/Retorno.tsx       components/app/Financeiro.tsx
components/app/PainelSessao.tsx
app/(app)/recebimentos/movimentacoes/acoes.ts
supabase/tests/0066_*.sql (nova) 
```

**Suítes a rodar depois:** `0025_retorno_e_o_comeco.sql` ·
`0037_financeiro.sql` · `0040*` · `0056*` (livro-razão) · `0058*` (propostas) ·
`0059*` (cockpit). O critério é que funções a migração reescreve.
