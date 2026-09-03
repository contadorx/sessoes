import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * A pasta de migrações reconstrói o banco, na ordem em que ela se lê.
 *
 * A **lei 5** diz que nada se aplica no Supabase que não esteja em
 * `supabase/migrations/`. O corolário nunca esteve escrito, e é ele que
 * sustenta a lei: **a pasta, lida em ordem, tem de reconstruir o banco.** Se
 * não reconstrói, o restore não volta, o ambiente novo não sobe, e o segundo
 * par de mãos não entra no projeto.
 *
 * Ela deixou de reconstruir por um caractere. `0052_as_leituras_da_revisao_5`
 * recriava dez views que `0052a_drop_das_views_que_mudam_de_forma` derruba
 * antes — e em ordem lexicográfica `_` (0x5F) vem antes de `a` (0x61):
 *
 *     0052_a_regua_da_assinatura_e_o_churn_com_causa.sql
 *     0052_as_leituras_da_revisao_5.sql       ← morria aqui
 *     0052a_drop_das_views_que_mudam_de_forma.sql
 *
 *     ERROR: cannot change name of view column "n" to "n_total"
 *
 * No banco de produção a ordem sempre foi a certa — o `schema_migrations`
 * prova, pelos `version` —, e é isso que torna o defeito invisível: **nada em
 * produção acusa**. Só uma base nova acusa, e base nova é o que ninguém levanta
 * até precisar.
 *
 * ## O que este teste afere
 *
 * Não o caso do 0052. A regra geral, e ela é mais estreita do que parece à
 * primeira tentativa: **duas criações da mesma view, sem um `drop` entre
 * elas.** A segunda é que esbarra na forma da primeira.
 *
 * A primeira redação deste teste cobrava "quem derruba vem antes de quem
 * recria", e reprovava a `0044b` — que cria as views pela primeira vez, muito
 * antes de a `0052a` derrubá-las. `criar → derrubar → recriar` é uma sequência
 * perfeitamente sã, e uma regra que a proíbe é uma regra que ninguém vai
 * conseguir manter. O que não é são é `criar → recriar` com o `drop` chegando
 * atrasado, que era exatamente o desenho antigo:
 *
 *     0044b  cria v_leitura1_fila
 *     0052_as_leituras  RE-cria com outra forma   ← estoura
 *     0052a  derruba (tarde demais)
 *
 * Ele não precisa de banco, e é de propósito: as 56 suítes SQL não entram no
 * `npm run verificar` porque dependem de conexão, e foi por isso que 25 delas
 * passaram meses vermelhas sem ninguém ver. Esta lê texto, então roda junto
 * das outras 1.632 e falha no commit em que o nome errado entrar.
 */

const PASTA = join(import.meta.dirname, "..", "supabase", "migrations");

const ARQUIVOS = readdirSync(PASTA)
  .filter((f) => f.endsWith(".sql"))
  .sort();

const CONTEUDO = new Map(
  ARQUIVOS.map((f) => [f, readFileSync(join(PASTA, f), "utf8")] as const),
);

/** Sem comentário: `-- drop view if exists x` não derruba nada. */
function semComentarios(texto: string): string {
  return texto.replace(/(^|[^:])--[^\n]*/g, (l, antes) => antes);
}

function achar(fonte: string, padrao: RegExp): string[] {
  return [...semComentarios(fonte).matchAll(padrao)].map((m) => m[1].toLowerCase());
}

describe("a pasta de migrações reconstrói o banco na ordem em que se lê", () => {
  it("nenhuma view é recriada com outra forma sem um drop antes", () => {
    // Um evento por (view, arquivo), na ordem em que a pasta se lê.
    type Evento = { arquivo: string; tipo: "cria" | "derruba" };
    const linha = new Map<string, Evento[]>();

    const anotar = (v: string, arquivo: string, tipo: Evento["tipo"]) =>
      linha.set(v, [...(linha.get(v) ?? []), { arquivo, tipo }]);

    for (const f of ARQUIVOS) {
      const fonte = semComentarios(CONTEUDO.get(f)!);
      // Num mesmo arquivo o `drop` sempre precede o `create` que o acompanha,
      // que é a forma como a casa escreve. Anotar o drop primeiro reproduz isso.
      for (const v of achar(fonte, /drop\s+view\s+(?:if\s+exists\s+)?public\.([a-z_0-9]+)/gi)) {
        anotar(v, f, "derruba");
      }
      for (const v of achar(fonte, /create\s+or\s+replace\s+view\s+public\.([a-z_0-9]+)/gi)) {
        anotar(v, f, "cria");
      }
    }

    const fora: string[] = [];
    for (const [view, eventos] of linha) {
      // O `drop` e o `create` do mesmo arquivo são um par: só interessa o que
      // atravessa arquivos.
      const entreArquivos = eventos.filter(
        (e, i) => i === 0 || e.arquivo !== eventos[i - 1].arquivo || e.tipo !== "cria",
      );
      let criadaEm: string | null = null;
      for (const e of entreArquivos) {
        if (e.tipo === "derruba") {
          criadaEm = null;
          continue;
        }
        if (criadaEm !== null && criadaEm !== e.arquivo) {
          fora.push(
            `public.${view}: ${e.arquivo} recria o que ${criadaEm} já criou, e nenhum ` +
              `drop veio entre os dois — numa base nova o create or replace esbarra na forma antiga`,
          );
        }
        criadaEm = e.arquivo;
      }
    }

    expect(fora, `\n${fora.join("\n")}`).toEqual([]);
  });

  /**
   * O sufixo de letra existe para caber entre dois números, e só funciona se
   * o arquivo sem sufixo vier primeiro. `0052_a_regua…` e `0052_as_leituras…`
   * são dois arquivos "sem sufixo" no mesmo número — e é aí que o `_` derruba
   * a ordem, porque o segundo componente do nome passa a decidir.
   */
  it("cada número de migração tem no máximo um arquivo sem sufixo de letra", () => {
    const semSufixo = new Map<string, string[]>();
    for (const f of ARQUIVOS) {
      const m = /^(\d{4})([a-z]?)_/.exec(f);
      if (!m || m[2] !== "") continue;
      semSufixo.set(m[1], [...(semSufixo.get(m[1]) ?? []), f]);
    }

    const duplicados = [...semSufixo.entries()]
      .filter(([, fs]) => fs.length > 1)
      .map(([n, fs]) => `${n}: ${fs.join(" · ")}`);

    expect(
      duplicados,
      "Dois arquivos com o mesmo número e sem letra: a ordem entre eles passa a " +
        "ser decidida pelo texto do nome, e `_` vem antes de qualquer letra.\n" +
        duplicados.join("\n"),
    ).toEqual([]);
  });
});
