#!/usr/bin/env node
/**
 * Roda as suítes SQL adversariais contra um banco.
 *
 * ## Por que este arquivo existe
 *
 * `npm run verificar` é `lint && tsc && vitest`, e as suítes de
 * `supabase/tests/` nunca entraram nele — elas precisam de conexão, e o
 * `verificar` roda sem banco. O resultado foi que **56 suítes ficaram meses
 * sem rodar**, e quando finalmente rodaram, em 03/09, seis defeitos de produto
 * apareceram de uma vez. Todos os seis estavam acusados, por verificações que
 * o próprio projeto tinha escrito e ninguém executava.
 *
 * A evidência mais dura disso é a `0053`: ela morreu na `0067`, que renomeou
 * `recibos_rfb.emitido_em` para `marcado_por_ela_em`. Ficou vermelha e ninguém
 * soube.
 *
 * Este arquivo é o alvo separado. Ele não entra no `verificar` de propósito —
 * `verificar` tem de continuar rodando sem rede, na máquina de quem só quer
 * mexer numa tela — mas entra antes de commit de migração, e no CI.
 *
 * ## Como se usa
 *
 *     SUPABASE_DB_URL='postgresql://…' npm run verificar:sql
 *     SUPABASE_DB_URL='postgresql://…' npm run verificar:sql -- 0080 0081
 *
 * Sem argumento roda todas, em ordem de nome. Com argumentos, roda só as que
 * começam com cada prefixo — é o modo de quem está no meio de uma build.
 *
 * ## O que ele NÃO faz, e é decisão
 *
 * **Não roda contra produção sem que a pessoa diga que quer.** As suítes
 * escrevem: criam conta, paciente, sessão e apagam no fim. Rodar isso por
 * engano no banco que tem gente de verdade dentro é o erro que o `CLAUDE.md`
 * §11 nomeia — *"nunca use a conta real do Leandro"*. Por isso a URL vem de
 * variável de ambiente e nunca de arquivo commitado, e por isso existe o
 * aviso abaixo quando a URL não parece de teste.
 *
 * **Não lista as suítes à mão** (lei 7): lê a pasta. A suíte nova entra no
 * conjunto no instante em que o arquivo é salvo, sem ninguém acrescentar
 * nome nenhum aqui.
 *
 * ## E a razão mais forte para o banco ser separado
 *
 * Algumas suítes chamam **função de varredura** — a que o cron roda. Elas
 * escrevem no banco inteiro por construção: é o que o cron faz. Num banco com
 * conta de verdade dentro, rodá-las **expira oferta que não é do teste, marca
 * recibo alheio como vencido e puxa mensagem real para `enviando`**.
 *
 * Não é hipótese: rodando a 0026 em 03/09, `agendar_lembretes` enfileirou
 * cinco lembretes, um deles numa conta real. Aqueles eram legítimos — o cron
 * os criaria no dia seguinte de qualquer jeito —, mas expirar uma oferta viva
 * não tem essa defesa.
 *
 * **Quais são essas funções não está escrito aqui, e é de propósito.** A
 * primeira versão deste arquivo dizia "oito suítes" e nomeava sete funções.
 * As duas contas estavam erradas: `fechar_mes_do_contador(date)` estava na
 * lista e não pertence a ela (é `security definer` amarrada em
 * `conta_atual()`, toca só a conta de quem chamou), e faltavam oito funções
 * que ninguém tinha lembrado de escrever — `agendar_regua`,
 * `agendar_mensalidades`, `marcar_silenciosas`, `pedir_confirmacoes`,
 * `materializar_tudo`, `passar_a_regua_das_assinaturas`,
 * `destravar_mensagens` e `expurgar_mensagens`. Dezoito suítes, não oito.
 *
 * Foi a lei 7 cobrando o preço de sempre, e desta vez de mim: a lista à mão
 * deixou passar o item novo. Agora `varreduras()` pergunta ao `pg_proc`, com
 * o critério que define a classe em vez de enumerá-la — função volátil, que
 * não devolve gatilho, que escreve (direto ou por outra que escreve), que não
 * recebe argumento capaz de amarrá-la a uma conta, e que nunca chama
 * `conta_atual()`. Função nova que nasça com essa forma entra na conta
 * sozinha.
 *
 * A varredura de `testes/a-suite-nao-apaga-o-que-nao-criou.test.ts` não pega
 * esta classe, e não teria como: aqui a escrita está **dentro** da função de
 * cron, não no texto da suíte. O que protege é o banco ser separado.
 *
 * ## Como medir em vez de supor
 *
 * "Perigoso" não é o mesmo que "faz mal hoje". Num banco onde as varreduras já
 * rodaram e não há oferta viva, recibo em aberto nem fatura vencida, elas não
 * têm o que fazer — e recusá-las por precaução vira suíte que nunca roda, que
 * é como 56 delas ficaram meses paradas.
 *
 * Dá para medir sem arriscar, e o truque é o mesmo da verificação 23 da 0054:
 * um bloco `do` é uma transação, e um `raise` no fim dele desfaz tudo. Então:
 *
 *     do $$
 *     declare relatorio text := '';
 *     begin
 *       create temporary table _antes on commit drop as select …;  -- o retrato
 *       perform public.expirar_ofertas();                          -- e as demais
 *       …
 *       -- compara com o retrato e monta o relatório
 *       raise exception 'MEDIDA (desfeita): %', relatorio;         -- rollback
 *     end $$;
 *
 * Rodado em 03/09 com as quinze varreduras de uma vez, contra as contas reais e
 * contra a demo: **nada mudou em nenhuma das duas**. Foi com essa medida — e
 * não com otimismo — que a 0052 e a 0057 saíram do bloqueio.
 *
 * A medida vale para o estado do banco naquele instante, e é para ser refeita.
 */

import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const AQUI = dirname(fileURLToPath(import.meta.url));
const TESTES = join(AQUI, "tests");

const URL_DO_BANCO = process.env.SUPABASE_DB_URL ?? process.env.DATABASE_URL;

if (!URL_DO_BANCO) {
  console.error(
    "\nFalta a URL do banco.\n\n" +
      "    SUPABASE_DB_URL='postgresql://…' npm run verificar:sql\n\n" +
      "Ela não mora em arquivo do repositório de propósito: estas suítes\n" +
      "escrevem no banco, e um arquivo commitado é como se roda no banco\n" +
      "errado sem perceber.\n",
  );
  process.exit(2);
}

const prefixos = process.argv.slice(2).filter((a) => !a.startsWith("-"));

// Lê a pasta. Nunca uma lista escrita à mão — é a lei 7, e é a razão pela qual
// a suíte nova nunca fica de fora por esquecimento.
const suites = readdirSync(TESTES)
  .filter((f) => f.endsWith(".sql"))
  .sort()
  .filter((f) => prefixos.length === 0 || prefixos.some((p) => f.startsWith(p)));

if (suites.length === 0) {
  console.error(`Nenhuma suíte casou com: ${prefixos.join(" ")}`);
  process.exit(2);
}

const PARECE_DE_TESTE = /localhost|127\.0\.0\.1|test|staging/i.test(URL_DO_BANCO);

if (!PARECE_DE_TESTE) {
  console.log(
    "\n⚠  A URL não parece de banco de teste. Estas suítes ESCREVEM: criam\n" +
      "   conta, paciente e sessão, e apagam no fim. Se este banco tem gente\n" +
      "   de verdade dentro, pare aqui.\n",
  );
}

/**
 * As funções de varredura — as que o cron roda —, perguntadas ao catálogo.
 *
 * O critério é a forma, não o nome: volátil, não devolve gatilho, escreve
 * (direto ou por outra que escreve), não recebe argumento que a amarre a uma
 * conta, e nunca chama `conta_atual()`. É o que separa `expirar_ofertas()`, que
 * varre o banco todo, de `fechar_mes_do_contador(date)`, que é `security
 * definer` amarrada na conta de quem chamou e só toca essa.
 *
 * O fecho transitivo importa: `agendar_lembretes()` não tem um `insert` no
 * corpo — ela chama quem tem. Sem o fecho, a função mais perigosa da lista
 * seria a que ficaria de fora.
 */
const CONSULTA_DAS_VARREDURAS = `
with recursive f as (
  select p.oid, p.proname, p.prosrc,
         p.prorettype::regtype::text as retorna,
         pg_get_function_identity_arguments(p.oid) as args,
         (p.prosrc ~* 'conta_atual') as amarra
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v'
),
escritoras as (
  select oid, proname from f
   where prosrc ~* '(insert\\s+into|update\\s+public\\.|update\\s+[a-z_]+\\s+set|delete\\s+from)'
  union
  select f.oid, f.proname
    from f join escritoras e on f.oid <> e.oid
         and f.prosrc ~ ('\\m' || e.proname || '\\s*\\(')
)
select distinct f.proname
  from f join escritoras e on e.oid = f.oid
 where f.retorna <> 'trigger'
   and not f.amarra
   and (f.args = '' or f.args ~ '^p_[a-z_]+ integer$')
 order by 1`;

function varreduras() {
  const r = spawnSync(
    "psql",
    [URL_DO_BANCO, "--quiet", "--no-psqlrc", "--tuples-only", "--no-align",
     "--set=ON_ERROR_STOP=1", "--command", CONSULTA_DAS_VARREDURAS],
    { encoding: "utf8" },
  );
  if (r.status !== 0) {
    console.error("Não deu para perguntar ao catálogo quais são as varreduras:");
    console.error(`${r.stdout ?? ""}${r.stderr ?? ""}`);
    process.exit(2);
  }
  return (r.stdout ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
}

const NOMES = varreduras();
const CHAMA_VARREDURA = new RegExp(`\\b(${NOMES.join("|")})\\s*\\(`);

const comCron = process.argv.includes("--com-cron");

/**
 * Tira os comentários antes de procurar a chamada.
 *
 * Sem isto o guarda acusa a suíte que só **fala** de uma varredura. Aconteceu
 * com a 0066: ela tem um comentário explicando que `pedir_confirmacoes()`
 * passou a exigir template essencial, não chama a função em lugar nenhum, e
 * mesmo assim entrava na lista das bloqueadas — bloqueada por uma frase.
 *
 * O teste irmão, `a-suite-nao-apaga-o-que-nao-criou`, já fazia isso desde o
 * primeiro dia; este esqueceu. O `[^:]` na frente do `--` é o que salva
 * `https://` de ser lido como começo de comentário.
 */
function semComentarios(sql) {
  return sql.replace(/(^|[^:])--[^\n]*/g, (_, antes) => antes);
}

const perigosas = suites.filter((f) =>
  CHAMA_VARREDURA.test(semComentarios(readFileSync(join(TESTES, f), "utf8"))),
);

if (perigosas.length > 0 && !PARECE_DE_TESTE && !comCron) {
  console.log(
    `\n⏭  ${perigosas.length} suíte(s) chamam função de varredura e ficam de fora:\n` +
      perigosas.map((f) => `     ${f}`).join("\n") +
      "\n\n   Elas escrevem no banco inteiro, não só nas linhas que criaram.\n" +
      "   Rode-as num banco isolado, ou force com --com-cron se este banco\n" +
      "   não tem ninguém de verdade dentro.\n",
  );
}

const aRodar =
  perigosas.length > 0 && !PARECE_DE_TESTE && !comCron
    ? suites.filter((f) => !perigosas.includes(f))
    : suites;

console.log(`\nRodando ${aRodar.length} suíte(s).\n`);

const falhas = [];
let verdes = 0;

for (const arquivo of aRodar) {
  const r = spawnSync(
    "psql",
    [
      URL_DO_BANCO,
      "--quiet",
      "--no-psqlrc",
      // `ON_ERROR_STOP` é o que transforma "psql imprimiu um erro e seguiu"
      // em "o processo falhou". Sem isso a suíte vermelha sai com código 0.
      "--set=ON_ERROR_STOP=1",
      "--file",
      join(TESTES, arquivo),
    ],
    { encoding: "utf8" },
  );

  const saida = `${r.stdout ?? ""}${r.stderr ?? ""}`.trim();

  if (r.status === 0) {
    verdes += 1;
    const ok = saida.split("\n").find((l) => l.includes("OK") || l.includes("ok"));
    console.log(`  ✓ ${arquivo}${ok ? `  ${ok.replace(/^NOTICE:\s*/, "").trim()}` : ""}`);
  } else {
    falhas.push({ arquivo, saida });
    console.log(`  ✗ ${arquivo}`);
  }
}

console.log(`\n${verdes} verde(s) · ${falhas.length} vermelha(s)\n`);

for (const { arquivo, saida } of falhas) {
  console.log(`─── ${arquivo} ${"─".repeat(Math.max(0, 60 - arquivo.length))}`);
  console.log(saida);
  console.log("");
}

process.exit(falhas.length === 0 ? 0 : 1);
