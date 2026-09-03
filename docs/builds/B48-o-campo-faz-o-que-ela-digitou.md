# B48 · O campo faz o que ela digitou

**3 dias · migração: nenhuma · primeira da fila**
*Abre por dois S1. Nasceu da segunda passada da auditoria de UX, a que olhou
campo em vez de fluxo.*

---

## Por que esta build existe

O produto tem **153 campos de entrada em 91 formulários**, e o artesanato deles
nunca recebeu a atenção que o resto recebeu. O inventário, medido:

| | quantos |
|---|---|
| máscara de entrada (CPF, telefone, dinheiro) | **0** — nenhum `pattern=`, nenhuma biblioteca, os 36 `onChange` do produto são todos `setEstado(e.target.value)` puros |
| campos com `inputMode` | **10 de 153** |
| `type="time"` com `step` | **0 de 9** — a roda abre minuto de 1 em 1 |
| erro ao lado do campo que o causou | **0** — zero `aria-invalid` no repositório inteiro |
| ajuda contextual nas telas dela | **0** — as 3 ocorrências de `<details>`/`title=` estão no editor de blog |
| botão primário `w-full` | **1 de ~30** (só `Entrar.tsx:252`) |
| alvo de toque ≥ 44 px | **0** — os primários vão de ~31 px a ~40 px |

E dois desses buracos são S1: **o campo aceita um número mil vezes menor do que
ela digitou**, e **a caixa que tira alguém da fila não desliga nada**.

---

## Os dois S1

### S1-A · `1.200` vira R$ 1,20, calado

O produto tem **duas normalizações de dinheiro incompatíveis**, e as duas erram
em silêncio, em direções opostas:

```
app/(app)/pacientes/acoes.ts:25   valor da sessão   .replace(",", ".") + Number()
app/(app)/pacientes/acoes.ts:45   mensalidade       .replace(",", ".") + Number()
app/(app)/agenda/acoes.ts:162     valor do encaixe  .replace(",", ".") + Number()
   → Number("1.200") === 1.2 → passa em Number.isFinite && >= 0 → grava R$ 1,20

app/(app)/pacientes/acoes.ts:316                    .replace(/\./g,"").replace(",",".")
app/(app)/recebimentos/movimentacoes/acoes.ts:110   .replace(/\./g,"").replace(",",".")
   → "1200.00" → "120000" → grava R$ 120.000,00
```

**Reproduzir A:** cadastrar paciente com Valor da sessão = `1.200`. Nenhum erro.
O combinado nasce em R$ 1,20 e o número atravessa cobrança, Pix, recibo e
carnê-leão.
**Reproduzir B:** vender pacote com Valor total = `1200.00`. Nenhum erro. Grava
cem vezes mais.

**O parser certo já existe e está de quarentena:** `lib/importacao.ts:95`
(`lerValor`) fareja a vírgula decimal e acerta `200`, `200,00`, `R$ 200,00`,
`1.200,50` e `1200.50`. Só a colagem do importador o usa.

`lib/dinheiro.ts:14` (`paraCentavos`) **recusa separador de milhar por decisão**
— ele existe para o que vem do banco, que nunca tem. Não relaxe essa regex:
`lerValor` é a camada de entrada, `paraCentavos` é a de fronteira.

### S1-B · "topa antecipar" e "na fila" não desligam

```
components/app/EditorFila.tsx:76-81    <input type="checkbox" name="topa_antecipar" value="sim">
components/app/EditorFila.tsx:147-152  <input type="checkbox" name="ativo"          value="sim">

app/(app)/encaixes/acoes.ts:47   topa_antecipar: form.get("topa_antecipar") !== "nao"
app/(app)/encaixes/acoes.ts:78   topa_antecipar: form.get("topa_antecipar") !== "nao"
app/(app)/encaixes/acoes.ts:80   ativo:          form.get("ativo")          !== "nao"
```

Checkbox desmarcado **não envia nada**. `form.get()` devolve `null`,
`null !== "nao"` é `true`, e o banco recebe `true`. Os únicos
`<input type="hidden">` do arquivo são `:132` e `:172`, ambos `name="id"` — **não
existe nenhum campo que envie `"nao"`**. As duas caixas são write-only-true.

**Reproduzir:** abrir `/encaixes`, desmarcar "na fila" de alguém, salvar,
recarregar. A pessoa continua ativa, o selo "pausada" nunca aparece, e a próxima
vaga é oferecida a ela.

**Por que é S1 e não S2:** é a única coisa do produto que fala com a paciente sem
a psicóloga no meio. Ela configurou para não oferecer, o sistema ofereceu, e quem
descobre é a paciente. O opt-out de um toque é fronteira ética escrita (R10).

---

## Entrega

**1 · Dinheiro (S1-A).** `lerValor` vira o **único** parser de dinheiro digitado.
Trocar as cinco normalizações locais. Mover `lerValor` de `lib/importacao.ts`
para `lib/dinheiro.ts` (ou um `lib/formato.ts`), mantendo o import antigo
funcionando.

**2 · Checkbox (S1-B).** `=== "sim"` nas três leituras. E **varrer todo
`form.get(...) !== "` do repositório** — a lei 7 do `CLAUDE.md` vale aqui: o
conserto não é o campo, é a varredura.

**3 · `lib/formato.ts` novo.** `mascaraCpf` e `mascaraTelefone` aplicadas no
`onChange` de:
- `components/app/Conta.tsx:316` — `documento` (CPF/CNPJ dela), que hoje tem
  placeholder `000.000.000-00` prometendo uma máscara que não existe;
- `components/app/FormPaciente.tsx:69` (telefone) e `:81` (CPF do paciente).

Para lá sobem também os dois `cpfBr` duplicados:
`components/app/ReceitaSaude.tsx:86` e
`app/(app)/fechamento/documentos/[id]/page.tsx:26-35`.

**4 · Teclado.** `inputMode="numeric"` em `Conta.tsx:316` (CPF/CNPJ),
`Conta.tsx:304` (CRP) e `ReceitaSaude.tsx:239` (número do recibo — ela está com o
app da Receita na outra mão).

**5 · Horário.** `step={900}` nos nove `type="time"`:
`FormPaciente.tsx:176` · `Encaixe.tsx:93` · `Vagas.tsx:163` ·
`Horarios.tsx:106` e `:115` · `EditorFila.tsx:68` e `:71` ·
`RegrasDaFila.tsx:78` e `:86`.

**6 · Política em palavra, não em número.** Copiar para
`components/app/FormPaciente.tsx:221-238` os dois `<select>` que **já existem**
em `components/app/Importar.tsx:181-199`: horas (12 / 24 / 48) e percentual
(`nada` / `50%` / `a sessão inteira`), **com uma opção "outro" que revela o campo
numérico** — alguém cobra 30%. E `onWheel={(e)=>e.currentTarget.blur()}` nos nove
`type="number"` (`FormPaciente.tsx:180,:222,:232` · `Encaixe.tsx:98` ·
`Vagas.tsx:172` · `EditorFila.tsx:138` · `RegrasDaFila.tsx:68` ·
`Contador.tsx:99` · `Pacote.tsx:128`), porque hoje rolar a página com o cursor
sobre "Senão, cobra (%)" altera a política de falta sem clique.

**7 · `autoComplete="off"`** em `FormPaciente.tsx:57,:69,:78,:81`. Sem o
atributo, o navegador cai na heurística por `name=` e oferece o nome, o telefone,
o e-mail e o **CPF dela** dentro da ficha de outra pessoa — e no caminho do
Receita Saúde isso vira recibo com o CPF errado. Reforce com
`autoComplete="new-password"` no campo de CPF, que é o truque que o Chrome
respeita.

**8 · CPF dela com dígito verificador.** `lib/paciente.ts:64` (`cpfValido`) já
implementa o DV completo e é chamado só em `validarPaciente`. Chamar também em
`app/(app)/perfil/acoes.ts:147` (hoje só confere comprimento) e em
`lib/receitasaude.ts:275` (`cpfValidoParaArquivo`, idem). Um dígito trocado hoje
vai para a **coluna 15 de toda linha** do CSV do Carnê-Leão
(`lib/receitasaude.ts:311`) e o arquivo inteiro é recusado no *Analisar Arquivo*
do e-CAC — ela descobre em fevereiro, no prazo, com 35 recibos pendentes.

**9 · Erro no campo.** `components/app/campos.tsx` — o `Campo` já aceita `dica`
(`:10`, `:17`). Aceitar também `erro` (renderizado sob o campo, com
`aria-invalid` no controle) e `ajuda` (um `<details><summary>?</summary>`). Isso
resolve os ~53 formulários de uma vez, e é a peça que falta para o "explica
demais / explica de menos" da B47. O bloco `Erros` (`:22-33`) ganha
`role="alert"` e `scrollIntoView`.

**10 · Dica nos três campos que decidem no escuro.**
- `FormPaciente.tsx:213-216` — "valor social" não tem explicação em lugar nenhum
  do produto. Escreva a consequência (o que muda no preço, no recibo, na fila).
- `FormPaciente.tsx:59-67` — "Situação" filtra em silêncio:
  `app/(app)/encaixes/dados.ts:214` tira `alta`/`encerrado`/`arquivado` de quem
  pode entrar na fila, e `app/(app)/agenda/dados.ts:118` tira `pausa` da lista de
  encaixe. O padrão é `interessado`.
- `components/app/Registro.tsx:80` — as duas frases que explicam prontuário e
  gaveta só aparecem uma de cada vez; clicar no outro rádio já é escolher.
  Mostrar as duas, uma sob cada rádio.

**11 · O botão no alcance.** `w-full sm:w-auto` + `py-3` nos primários dos
formulários longos, e rodapé sticky com a ação em `FormPaciente` e `Horarios` —
os dois têm ~2,5 telas de rolagem até o botão em 375 px, e o `Horarios` guarda
todo o estado em `useState` (`:60`), então sair antes do fim perde tudo. **O
sticky senta acima da barra de navegação do celular** (`Navegacao.tsx:240` é
`fixed bottom-0`; o layout já reserva `pb-14`).

**12 · Telefone marcado como obrigatório** em `FormPaciente.tsx:68-75` enquanto o
canal não for "não avisar" — hoje `lib/paciente.ts:136` o exige de fato (o canal
nasce `whatsapp`) e o campo não tem `required` nem marca visual.

---

## Pronto quando

Verificado rodando, não lendo:

- [ ] digitar `1.200` em **qualquer** campo de valor do produto grava
      R$ 1.200,00 — e digitar `1200.00` também;
- [ ] uma suíte varre o repositório e **reprova campo de dinheiro que não use
      `lerValor`**;
- [ ] desmarcar "na fila" e salvar tira a pessoa da fila, verificado com a oferta
      seguinte; e uma suíte reprova `form.get(...) !== "` em leitura de checkbox;
- [ ] nenhum campo de dígito abre teclado de letras no celular;
- [ ] o seletor de hora abre em passos de 15 minutos;
- [ ] a política de falta se escolhe em palavras, com saída para o número livre;
- [ ] errar um campo mostra o erro **naquele campo**, com `aria-invalid`, e a
      tela rola até ele;
- [ ] um CPF de 11 dígitos com DV inválido é recusado no Perfil e no gerador do
      CSV;
- [ ] em 375 px, o botão de "Cadastrar" e o de "Guardar a semana" estão
      alcançáveis sem rolar até o fim do formulário.

---

## Não entra

- **Biblioteca de máscara.** São duas funções de quinze linhas, e o produto não
  tem dependência de UI nenhuma hoje — vale manter assim.
- **Redesenho de formulário.** Nada de multi-step, wizard ou reordenar campos.
  Esta build é infra de campo; a ordem das telas é a B45 e a B47.
- **Tirar o número livre da política.** O `<select>` precisa de "outro".
- **Relaxar a regex de `paraCentavos`.** Ela recusa milhar de propósito.

---

## Armadilhas

- **Consertar um campo de dinheiro e não os cinco.** São dois parsers
  incompatíveis e um terceiro certo em quarentena; corrigir um deixa a
  incoerência de pé e ninguém acha os outros quatro depois.
- **Consertar `topa_antecipar` e esquecer `ativo`.** Mesmo padrão, mesma tela, e
  é o que pausa alguém.
- **Tornar a textarea/campo controlado para resolver máscara.** Máscara no
  `onChange` com cursor preservado é suficiente; controlar tudo custa re-render
  numa tela que já faz quinze consultas.
- **Confiar só em `autoComplete="off"`.** O Chrome ignora `off` em alguns campos.
- **Validar o CPF só na tela.** O CSV é gerado por função no banco (0053) — a
  checagem tem que existir dos dois lados, como já acontece com o CPF do
  paciente.
- **Escrever a dica explicando a implementação.** A dica diz a consequência para
  a paciente, não o que a coluna guarda.

---

## Arquivos que esta build toca

```
lib/dinheiro.ts | lib/formato.ts (novo) | lib/importacao.ts | lib/paciente.ts
lib/receitasaude.ts
components/app/campos.tsx  ← a peça que resolve os ~53 formulários
components/app/FormPaciente.tsx  components/app/EditorFila.tsx
components/app/Conta.tsx  components/app/ReceitaSaude.tsx
components/app/Encaixe.tsx  components/app/Vagas.tsx  components/app/Pacote.tsx
components/app/Horarios.tsx  components/app/RegrasDaFila.tsx
components/app/Contador.tsx  components/app/Financeiro.tsx
components/app/Decisoes.tsx  components/app/Registro.tsx
app/(app)/pacientes/acoes.ts  app/(app)/agenda/acoes.ts
app/(app)/encaixes/acoes.ts   app/(app)/perfil/acoes.ts
app/(app)/recebimentos/movimentacoes/acoes.ts
app/(app)/fechamento/documentos/[id]/page.tsx
```

**Suítes a rodar depois:** todas as de vitest (`npm run verificar`), mais as SQL
que tocam fila e cobrança — `0012_fila_e_ofertas.sql`, `0022_cobrancas.sql`,
`0036_vaga_fixa.sql` — porque o conserto do checkbox muda o que entra em
`fila_encaixe`.
