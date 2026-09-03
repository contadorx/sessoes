# Sessões

**Sessões organiza tudo o que não é atender**: a agenda, os recebimentos, os
recibos e o fechamento do mês com o contador. E mostra quanto da capacidade
disponível virou receita — e por onde o resto foi.

E a metade da frase que define o produto contra o que seria fácil construir:
**sem decidir frequência clínica, sem reativar ex-paciente e sem definir preço
promocional.**

> **Antes de mexer em qualquer coisa, leia o [`CLAUDE.md`](CLAUDE.md).** Ele não
> descreve o código: descreve as decisões que o código não pode contrariar —
> quem é a usuária, as onze fronteiras, o que está morto e não volta, e o
> vocabulário. Quando ele e o código discordarem, é o código que está errado.

Quem usa é uma **psicóloga autônoma**, 40–80 sessões por mês, com o celular como
dispositivo principal. Ela abre o app entre uma sessão e outra, de pé, às vezes
com a próxima paciente na sala de espera. **375 px é a largura de projeto.**

## Rodar

```bash
npm install
cp .env.example .env.local   # e preencha com o projeto Supabase
npm run dev
```

| variável | o que é |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL do projeto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | chave publicável — é pública por natureza; quem protege é a RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | só o worker de mensageria e os crons |
| `CRON_SECRET` | as rotas de máquina devolvem 404 sem ele |
| `WHATSAPP_WEBHOOK_TOKEN`, `PAGAMENTOS_WEBHOOK_TOKEN` | os dois webhooks de entrada |

```bash
npm run verificar    # lint + tsc --noEmit + vitest — roda antes de qualquer commit
npm run test         # só os testes unitários
```

Hoje: **115 migrações · 54 suítes SQL adversariais · 1.616 testes unitários**,
com Next 16 (App Router), React 19, Tailwind 4 e Supabase.

As suítes SQL não rodam no `npm run verificar` — elas precisam de um banco. Cada
uma é um bloco `do $do$` que levanta exceção no primeiro furo e limpa o que
criou:

```bash
supabase db execute -f supabase/tests/0073_reajuste_com_data_e_o_mes_de_ferias.sql
```

## Estrutura

```
app/(site)/        páginas públicas — landing, termos, privacidade, segurança,
                   incidente, blog
app/(app)/         a área autenticada: agenda, encaixes, pacientes,
                   recebimentos, fechamento, perfil, comecar, buscar, negocio
app/p/             páginas transacionais por link mágico (contrato, remarcar,
                   a página do paciente e a pré-ficha)
app/api/           mensageria, diário, pagamentos, whatsapp (crons e webhooks)
components/app/    os componentes da área autenticada
components/site/   os componentes das páginas públicas
components/publico/ o que o paciente vê nas páginas por link
lib/               regra pura e testada — é aqui que a decisão mora
lib/db.ts          o helper db() — a lei nº 1
proxy.ts           a lista de rotas públicas; o Next 16 aposentou `middleware.ts`
supabase/          migrations e tests
testes/            as varreduras — o que se verifica por catálogo, não por lista
docs/builds/       uma build por arquivo; o arquivo É o prompt de abertura dela
```

**A navegação tem cinco destinos** — Agenda · Encaixes · Pacientes ·
Recebimentos · Fechamento — e `lib/navegacao.ts` é puro e testado. No celular o
teto é cinco cadeiras: não acrescente um sexto item de menu.

## As leis

Cinco vieram das cicatrizes do FinanceiroX; três, da auditoria de 02/09.

1. **`supabase-js` não lança erro.** Toda operação passa por `db()` de
   `lib/db.ts`, que loga com contexto e **lança**. O ESLint reprova o import
   direto de `@supabase/supabase-js` fora de `lib/supabase/`.
2. **RLS desde a primeira tabela.** Função `security definer` sempre com
   `search_path` fixado; políticas com `(select auth.uid())`; FK sempre indexada.
3. **Fuso é decisão.** Tudo que é "dia" se calcula em `America/Sao_Paulo`, no
   banco, por `hoje_sp()`. `toISOString()` num horário de 21h dá o dia seguinte.
4. **Dinheiro em `numeric`, nunca float.** Na aplicação, centavos inteiros
   (`lib/dinheiro.ts`). Sinal é contrato.
5. **Migração é arquivo versionado no repo.** Nada se aplica no Supabase que não
   esteja em `supabase/migrations/`.
6. **Ao reescrever uma função do banco, leia o BANCO e não a migração.** Este
   projeto foi mordido três vezes por isso. Use `pg_get_functiondef`: a migração
   mais recente pode não ser o que está rodando.
7. **Nunca verifique por lista escrita à mão.** Toda checagem por enumeração
   deixa passar o item novo — `exportar_conta` esqueceu 17 tabelas porque a lista
   era de quando havia doze. Varra o `information_schema`, o `pg_proc`, o
   catálogo.
8. **Adaptador ausente recusa, não finge.** Sem provedor configurado, o caminho é
   dizer que não saiu. A mensageria fingiu que enviou e virou S1.

## As varreduras

`testes/` não tem teste de unidade: tem as verificações que perguntam ao próprio
repositório em vez de a uma lista. Elas existem porque **os últimos defeitos
graves apareceram no espaço entre as camadas que cada verificação cobre**, e
nenhum foi encontrado lendo código.

| varredura | a pergunta |
|---|---|
| `nenhuma-acao-sem-porta` | toda ação de servidor tem caminho até uma tela? |
| `nenhuma-pergunta-clinica` | alguma tela do paciente virou anamnese? |
| `o-jargao-nao-vira-rotulo` | jargão do sistema apareceu como rótulo? |
| `o-contraste-se-calcula` | os tokens passam na WCAG, e o alvo chega a 44 px? |
| `o-produto-nao-emite` | alguma tela diz "emitido" sem dizer quem emitiu? |
| `o-que-esta-morto-nao-volta` | o que foi recusado por decisão voltou? |
| `varredura-de-campos` | algum campo faz coisa diferente do que ela digitou? |
| `a-tela-nao-oferece-o-que-a-rls-recusa` | a tela oferece escrita que o banco vai negar? |

Três delas já passaram verdes com o defeito reintroduzido, sempre pelo mesmo
motivo: **a varredura leu o comentário que explicava o defeito e o tomou pela
coisa.** Toda uma delas começa apagando comentário antes de ler. Num teste que
procura ausência, isso não é falso positivo — é falso negativo.

## Conta de demonstração

`demo@sessoes.com.br`, com 8 pacientes fictícios e 5 cobranças. **Nunca use a
conta real do Leandro** — ela tem pessoa de verdade dentro.

A conta demo tem zero `janelas_atendimento`, então os números do mês aparecem
como travessões. É o comportamento certo (nulo, não zero) e é também o motivo de
ela ser um mau cartão de visitas.

## Como se trabalha aqui

Uma build por vez, na ordem de [`docs/builds/README.md`](docs/builds/README.md).
**O arquivo de cada build é o prompt de abertura dela**: entrega, pronto-quando e
não-entra são o escopo fechado, e build que não passa no critério de pronto não
abre a seguinte.

Critério de pronto **se verifica rodando, não lendo**. Cada build acrescenta a
suíte adversarial dela e roda as antigas que ela toca — e o critério de regressão
é *que funções a migração reescreve*, não que assunto ela trata.

Os `[ ]` dos arquivos de build não são fonte de status: quem responde "isto foi
feito?" é o `git log`, onde cada build tem um commit com o código dela no assunto
e o corpo diz o que ficou de fora e por quê.
