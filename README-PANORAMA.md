# Panorama — o que entra no projeto Sessões

**Atualizado em 02/09/2026 · instrumento na revisão 5 · migrations 0052a e 0052 aplicadas**

Este pacote tem duas metades: **o banco**, em parte já aplicado remotamente, e
**as páginas**, que você coloca no projeto.

> ## ⚠ Leia isto primeiro
>
> **O formulário que está no ar em `sessoes.com.br/panorama/` é anterior à
> revisão 2.** Descobrimos isso lendo a primeira resposta real: ela tem os
> campos `q67`/`q68`, removidos na revisão 2, e não tem `q37`, `q38`, `q512`,
> `q513`, `q69`, que a revisão 2 acrescentou.
>
> **Enquanto a revisão 5 não for publicada, cada resposta que chegar mede o
> instrumento errado** — sem capacidade, sem hora reposta, sem antecipação, sem
> conjunção, sem a saída de "não se aplica". Publicar a pasta
> `public/panorama/` deste zip é a ação número um.

---

## 1 · O banco

### Já aplicadas no projeto `sessoes` (`shzqiymgmgosuhdjotyq`, sa-east-1)

| versão | nome | o que faz |
|---|---|---|
| `20260901094424` | `0044_o_panorama_estrutura` | 3 tabelas, RLS, policies de insert com CHECK |
| `20260901094459` | `0044b_as_leituras_do_panorama` | 12 views, todas fechadas para `anon` |
| `20260901094607` | `0044c_o_teto_do_jsonb…` | sobe o teto de texto para não perder resposta longa |

Copie os arquivos para `supabase/migrations/` no seu repo. Eles **não** rodam de
novo — o banco remoto já registrou essas versões; servem para o repositório
contar a mesma história que o banco.

### Aplicadas em 02/09, junto com a revisão 5

| versão | nome | o que faz |
|---|---|---|
*(as 0049, 0050 e 0051 foram descartadas antes de aplicar: liam campos que a
revisão 5 aposentou. Estão substituídas pela 0052.)*

| versão | nome | o que faz |
|---|---|---|
| `20260902175900` | `0052a_drop_das_views_que_mudam_de_forma` | `create or replace view` não renomeia coluna; duas views mudaram de forma |
| `20260902180000` | `0052_as_leituras_da_revisao_5` | 19 views, todas fechadas para `anon` |

```bash
supabase migration list --linked   # as cinco devem aparecer nas duas colunas
```

**Verificado no banco depois de aplicar: 19 views criadas, e ZERO views legíveis
por `anon` ou `authenticated`.**

### O que essas tabelas são

```
pesquisa_abertas     bloco 1, gravado no envio do bloco — antes de qualquer lista
pesquisa_respostas   o questionário inteiro, em jsonb
pesquisa_contatos    e-mail de quem quer o relatório · SEM ligação com as respostas
```

**A `pesquisa_contatos` não pode ganhar FK, coluna `sessao`, nem nada que ligue
ela às respostas.** É essa separação que sustenta "participantes não
identificados" da Res. CNS 510/2016 — e é promessa escrita na tela final do
questionário e na página do estudo.

> **Verificado em produção, com carimbo de tempo.** Na resposta-piloto, a linha
> da `pesquisa_abertas` foi gravada às 23:28:49 e a resposta completa às
> 23:38:12, mesma `sessao`. As quatro abertas estavam no banco **9,4 minutos
> antes** de qualquer lista aparecer na tela. A decisão de desenho deixou de ser
> promessa e virou log.

### A trava que quase faltou

No Supabase, o `ALTER DEFAULT PRIVILEGES` do schema `public` concede tudo ao
papel `anon`, e view em Postgres nasce com `security_invoker = off` — roda com
os direitos do dono e **ignora a RLS das tabelas de baixo**.

Sem o bloco final da `0044b`, qualquer pessoa com a chave anon — que é pública e
está no formulário — faria `GET /rest/v1/v_residual_textos` e leria todos os
textos abertos das respondentes. Todas as views estão com
`security_invoker = on` **e** com `revoke` para `anon` e `authenticated`.

> **Se você criar qualquer view nova sobre essas tabelas, repita as duas
> linhas.** Uma view nova nasce aberta. A `0050` repete.

Verificado: `anon` insere, `anon` não lê nem tabela nem view, `anon` tem insert
de lixo barrado pelo CHECK.

---

## 2 · As páginas

```
public/panorama/
  index.html      a página do estudo
  pesquisa.html   o questionário · REVISÃO 5
  contato.html    as duas portas do fim (relatório · conversa)
  protocolo.pdf   o protocolo, 6 páginas
instrumento-panorama.pdf   o questionário na íntegra, para o OSF (não vai para o site)
```

**Copie a pasta `public/panorama/` inteira para o `public/` do projeto.**
Funciona sem configuração em Next.js, Vite, Astro, Remix e SvelteKit.

As chaves do Supabase já estão preenchidas, com a chave *publishable* — usada de
propósito no lugar da anon legada porque **é desativável sozinha**: se um dia
precisar ser trocada por causa da pesquisa, a chave do produto não vai junto.

```js
SUPABASE_URL:      "https://shzqiymgmgosuhdjotyq.supabase.co"
SUPABASE_ANON_KEY: "sb_publishable_7XvMflZ0v5m1gHNuaDUzHA_aiSLTD4b"
```

### URLs limpas, opcional

`/panorama` sozinho dá 404 do jeito que está. Para limpar, `next.config.js`:

```js
async rewrites() {
  return [
    { source: '/panorama',          destination: '/panorama/index.html' },
    { source: '/panorama/pesquisa', destination: '/panorama/pesquisa.html' },
    { source: '/panorama/contato',  destination: '/panorama/contato.html' },
  ];
}
```

Se fizer, troque também o `href` do botão em `index.html` e os dois `LINK_` do
topo de `pesquisa.html`.

---

## 3 · O instrumento hoje

> **52 itens numerados · 15 condicionais · 36 obrigatórios · zero escalas de
> intensidade.**
> O caminho mais curto real — recebe só no CPF, não teve falta, não usa IA,
> nada administrado por terceiro — tem **37 itens**.

O `instrumento-panorama.pdf` é **gerado do próprio HTML** por
`build_instrumento.py`, e não redigido à parte. Se você mexer no formulário,
rode o script de novo — um anexo escrito à mão diverge do formulário na
primeira correção, e aí o pré-registro passa a mentir.

### O que mudou, e por quê

**Revisão 2** — a tese virou *integridade da receita e visibilidade da
capacidade*, no lugar de motor de ocupação. Saíram os dois itens de bem-estar
(a comparabilidade internacional que os justificava não se sustentou), a
recusa por falta de horário e o número de profissionais no espaço. Entraram
capacidade semanal, hora reposta, antecipação já praticada, a conjunção (H7) e
a dúvida de regularização.

**Revisão 3** — veio da primeira resposta real. Três coisas:

1. **Q4.3 e Q4.4 ganharam saída de "não se aplica".** A respondente digitou 0
   porque o campo exigia número, quando a verdade era que a pergunta não
   descrevia a prática dela. Como a **H1 é exatamente a mediana da Q4.3**, sem
   essa saída a hipótese seria confirmada por artefato do próprio instrumento.
2. **Item novo Q4.9 — o destino de quem procura e não consegue horário**, com
   `encaminho para uma colega` na frente. O bloco 4 media a lista de espera e
   não media a alternativa a ela, que é o mecanismo real da categoria.
3. **Um `TypeError` removido** — handler órfão do `q28-wrap`, que disparava a
   cada clique na Q2.3 e na Q2.7 desde a revisão 2. Invisível, e por isso
   sobreviveu.

> **O campo do item novo é `q49`, não `q48`.** O `q48` antigo ("recusou alguém
> por falta de horário", aposentado na revisão 2) já existe em linha gravada, e
> reaproveitar a chave misturaria dois significados na mesma coluna do jsonb.

**Revisão 4** — o ritmo do Receita Saúde. Dois itens condicionais, mostrados só
a quem declara emitir na Q5.10:

- **Q5.14 · com que frequência emite** — a cada atendimento · fim do dia ·
  semanal · mensal · quando lembro · uma vez por ano · quem faz é o contador.
- **Q5.15 · quantos recibos de uma vez** — um por um na hora · 1 · 2 a 5 ·
  6 a 20 · mais de 20.

Eles existem para decidir **um valor de código**: o default de
`contas.ritmo_recibo`, hoje `mensal` por suposição. A obrigação é per-sessão
desde 2025 e a Receita liberou emissão em lote em novembro/2025 — não há dado
público sobre qual dos dois ritmos a categoria pratica, e a primeira
respondente do piloto emite **um por sessão, oito vezes por semana**.

A ordem é deliberada e vem do doc 25: **comportamento primeiro (Q5.10),
frequência depois (Q5.14), tamanho do lote (Q5.15), esforço por último
(Q5.11)**. Perguntar esforço antes contamina a resposta de frequência.

> **O que ficou de fora do questionário, e por quê.** O doc 25 propõe também
> perguntar se ela entregaria a credencial gov.br a um sistema que emite por
> ela, e testar o conceito do cartão do minuto. **Nenhuma das duas entra aqui.**
> A primeira cita prática de concorrente e a segunda testa produto — as duas
> quebrariam a declaração de conflito de interesse do protocolo, que diz que
> *nenhum item faz referência a produto, marca ou solução comercial*. E a
> pergunta de nota 0–10 do doc 25 é escala de intensidade, que o instrumento
> declara não ter. **As três vão para o roteiro de entrevista**, onde valem
> mais e não custam a integridade do levantamento.

### O tempo declarado

Estava **9 minutos** em todas as peças. A primeira resposta real levou
**17,9 minutos** — dos quais **8,5 nos blocos 0 e 1**, ou seja, quase metade nas
quatro perguntas abertas.

A página do estudo chegou a dizer *"9 minutos. Medimos: a maioria leva entre 8 e
11"*. **Nunca medimos.** Numa pesquisa sobre medir direito, essa era a pior
linha do pacote. Foi removida.

Todas as peças agora dizem **cerca de 15 minutos, e que metade é nas perguntas
abertas, onde a pessoa escreve o quanto quiser**. É provisório e está declarado
como provisório: com 8 a 10 respostas de piloto, `v_duracao_real` dá a mediana e
o número definitivo entra em tudo.

**Não vale encurtar cortando o bloco 6:** ele economiza cerca de um minuto. O
comprimento está no bloco aberto, que é o coração científico e não se corta.

---

## 4 · Antes de divulgar: dois testes

### a) Grava mesmo? — *já verificado em 01/09*

O `POST` na `pesquisa_abertas` devolveu 201 e a linha de teste foi apagada. A
autorização também foi verificada no nível do SQL (`set role anon`), que é o
caminho que o PostgREST usa.

### b) O modo debug

Abra `/panorama/pesquisa.html?debug=1` e responda o bloco aberto. Se algo não
gravar, **aparece uma faixa marrom no rodapé com o erro HTTP**.

Existe porque o envio é best-effort de propósito — a respondente nunca é punida
por erro nosso —, então sem isso uma chave errada perderia respostas **em
silêncio**, por semanas.

---

## 5 · O pré-registro está feito

> **DOI: `10.17605/OSF.IO/4A8FR`** — registrado em 2 de setembro de 2026,
> público, sem embargo, licença CC-By 4.0.
> `https://doi.org/10.17605/OSF.IO/4A8FR`

Template **OSF Preregistration**, com o protocolo, o instrumento na íntegra e
este README anexados e arquivados junto ao registro. O OSF criou
automaticamente um projeto-companheiro (`osf.io/gepdv`) para hospedar os
arquivos; ele é subproduto e vira somente-leitura em fevereiro de 2027 — o
registro, não.

**Os colchetes acabaram.** DOI e datas já estão preenchidos na página do
estudo, no `protocolo.pdf` e nos e-mails:

| | |
|---|---|
| encerramento da coleta | **31 de janeiro de 2027** |
| relatório previsto | **março de 2027** |
| prorrogação | única, até 60 dias, só se houver menos de 120 completos |

**Como citar:**

```
Oliveira, L. (2026). Panorama da Prática Psicológica: condições administrativas
e financeiras do exercício da clínica privada no Brasil. OSF.
https://doi.org/10.17605/OSF.IO/4A8FR
```

---

## 6 · Os links por canal

O formulário lê `?c=` e grava em `canal_url`, mais confiável que o autodeclarado
da Q0.1. **Use um código diferente por canal** — sem isso você tem uma média de
canais desconhecidos e não consegue detectar o próprio viés de recrutamento.

```
/panorama/pesquisa.html?c=piloto           as primeiras 8 a 10 · APAGAR depois
/panorama/pesquisa.html?c=ig-comparacao    post 1 · não nomeia dor nenhuma
/panorama/pesquisa.html?c=ig-convite       post 2 · nomeia quatro
/panorama/pesquisa.html?c=ig-story
/panorama/pesquisa.html?c=crp06            um por CRP
/panorama/pesquisa.html?c=rfb-pj           base da Receita, só o estrato PJ
/panorama/pesquisa.html?c=contador         encaminhado por contador
/panorama/pesquisa.html?c=ind-<nome>       indicação pessoal · um por quem indica
/panorama/pesquisa.html?c=lista-sessoes    sua lista de espera · o estrato mais enviesado
```

Os dois primeiros do Instagram existem para medir o priming: se `ig-convite`
produzir muito mais menção às quatro dores nomeadas do que `ig-comparacao`, você
mediu a contaminação — e isso entra no relatório como achado, não some.

Limpeza do piloto, quando terminar:

```sql
delete from public.pesquisa_respostas where canal_url = 'piloto';
delete from public.pesquisa_abertas   where canal_url = 'piloto';
```

---

## 7 · Como ler, e em que ordem

Pelo SQL Editor do Supabase, ou pela `service_role`. **A ordem importa e está
pré-registrada no protocolo.**

```sql
-- 1º · SEMPRE. A nota que a lista de 16 itens tirou.
select * from v_residual;
--   até 10%  → a lista cobriu bem
--   10 a 20% → falta um domínio: leia os textos e nomeie no relatório
--   > 20%    → a lista está errada; o ranking sai como PROVISÓRIO

-- 2º · O material aberto, codificado ANTES de olhar o ranking fechado
select * from v_residual_textos;
select * from v_nao_se_aplica_textos;                       -- 0050
select dia, irritante, gambiarra, preocupacao from pesquisa_abertas order by criado_em;

-- 3º · só agora o fechado
select * from v_ranking_ponderado;
select * from v_nao_e_problema;
select * from v_itens_novos;

-- as decisões de produto
select * from v_leitura1_fila;    -- 0050 · agora separa "não se aplica" de zero
select * from v_destino_demanda;  -- 0050 · para onde vai quem não conseguiu horário
select * from v_conjuncao;        -- 0049 · a H7, a que sozinha decide a fila
select * from v_ocupacao;         -- 0049 · sessões ÷ capacidade declarada
select * from v_hora_reposta;     -- 0049 · duas horas de capacidade, uma receita
select * from v_antecipacao;      -- 0049
select * from v_regularizacao;    -- 0049
select * from v_leitura3_cobranca;
select * from v_leitura4_agenda;
select * from v_leitura5_canal;   -- o ranking muda por canal? aí o viés é seu

-- operação
select * from v_funil;
select * from v_duracao_real;     -- 0049 · o número que corrige o tempo declarado
select * from v_rendimento_canal;
select * from v_qualidade;
```

A ordem 1→2→3 não é preferência: está no plano de análise, fixada antes da
coleta. Olhar o ranking primeiro faz as categorias fechadas guiarem a leitura
das abertas, e aí o instrumento perde a única parte capaz de produzir achado
fora das hipóteses.

### Duas checagens de coerência

- **Soma do bloco 3** — Q3.3 a+b+c deve fechar com Q3.2. Já é critério de
  exclusão declarado.
- **Janela de memória** — Q5.5 (faltas em 3 meses) contra Q3.3b (desmarcação em
  cima da hora na semana passada). Na resposta-piloto vieram 0 e 1, o que não
  pode ser verdade junto. **Não é descuido: é a diferença entre lembrar de um
  trimestre e lembrar da semana passada** — que é a razão de o instrumento
  ancorar em "semana passada". Reportar como medida de viés de memória, nunca
  como motivo de exclusão.

---

## 8 · O estado do pré-registro

| etapa | estado |
|---|---|
| conta no OSF + Project + upload dos arquivos | **reversível — pode fazer agora** |
| a *registration* com DOI | **espera a mediana do piloto** |

A registration do OSF é **imutável**: nunca pode ser editada nem apagada.
Pré-registrar um instrumento que ainda vai mudar é o pior dos mundos.

Os campos do template OSF Preregistration já estão escritos, prontos para colar,
no doc **33**. Faltam três valores, e os três dependem do piloto ou de você:
tempo mediano real, data de encerramento e período de coleta.

Anexar ao registro: `protocolo.pdf`, `instrumento-panorama.pdf` e este README.
**Não** anexar documentos de produto, roadmap, copy ou concorrência — dentro de
um registro de pesquisa eles contaminam a leitura do conflito de interesse que a
folha declara com cuidado.

---

## 9 · O que o piloto já ensinou sobre o produto

Uma resposta só, do estrato mais enviesado que existe ("colega me mandou"). Não
é achado sobre a categoria. Mas mudou prioridade de build, e está inteiro no doc
**35**. O essencial:

- **8 sessões na semana, 5 horários vagos que ela quer preencher, e zero pessoas
  que a procuraram sem horário.** Os vagos valem uns R$ 4.000–5.000/mês e
  **nenhuma feature de fila os recupera** — não há demanda represada. A
  inadimplência, de R$ 1.000, é quatro vezes menor e é a que o produto alcança.
- Ela escolheu **cobrar · fiscal · reajuste** como as três mais custosas — e
  marcou **prontuário** e **mensagens fora do horário** como *não é problema*.
- **Emite o recibo do Receita Saúde ao fim de cada sessão, uma por uma.** A
  Receita Federal liberou emissão em lote em novembro/2025: CSV na escrituração
  do Carnê-Leão pelo e-CAC, até 1.000 linhas, **sem API**. A feature é gerar o
  CSV no layout exato, não "emitir por você".
- Contrato terapêutico *"sem procedimento"*, política de falta *"de boca"*, mais
  de R$ 1.000 em aberto, e "lidar com inadimplentes" como o mais irritante da
  semana. **O combinado escrito é a mesma coisa que a resposta para "fazer
  gestão sem ser insensível"**: o que fere não é cobrar, é cobrar uma regra que
  a pessoa nunca soube que existia.

---

## 10 · Pendências que não são de código

- **Publicar a revisão 3** e aplicar `0049` e `0050`. *(a número um)*
- **Rastrear o relatório original da APS** antes de repetir o número da
  Austrália em peça pública. Os 53% dos EUA estão verificados (APA *Practitioner
  Pulse* 2024, N=853); o australiano veio de cobertura sem N — já foi retirado
  das hipóteses, mas ainda aparece em material de divulgação.
- **Pré-registrar no OSF** antes da primeira resposta de campo.
- **Escrever a avaliação de legítimo interesse** antes de qualquer envio para a
  base PJ da Receita.
- **A `pesquisa_contatos` guarda e-mail.** Entra no seu inventário de dados
  pessoais e na política de retenção — não é anônima como as respostas.
- **Falar com a respondente do piloto.** Deixou WhatsApp e topou entrevista 24
  segundos depois de terminar, e acompanha a sazonalidade da própria procura há
  cinco anos, à mão. Uma hora com ela vale mais que as próximas dez respostas.
