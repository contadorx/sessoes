import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

/**
 * A linha do mês fala uma língua só (B54, §5.4).
 *
 * O §5.4 da estratégia do canal pede a mesma linha, com as mesmas marcas, na
 * mesma ordem e com as mesmas palavras, na tela dela e na página do paciente.
 * **A maneira de garantir isso não é combinar — é não ter dois.**
 *
 * Este arquivo é a varredura que cobra as duas metades disso, e nenhuma das
 * duas é uma lista escrita à mão (lei 7):
 *
 *   1. **Ninguém desenha uma segunda linha do mês.** Quem lê `LinhaDoMes`
 *      dentro de `app/` ou `components/` ou é o componente `Meses`, ou o usa.
 *   2. **O tipo e a função do banco não podem divergir.** `linhas_do_mes` (0095)
 *      monta um `jsonb_build_object` com chaves fixas; `LinhaDoMes` as declara.
 *      Renomear uma coluna de um lado e esquecer o outro é exatamente o que
 *      matou a suíte 0053 em silêncio quando a 0067 renomeou três campos de
 *      `recibos_rfb`.
 */

const RAIZ = process.cwd();

function varrer(dir: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(dir)) {
    if (nome === "node_modules" || nome === ".next" || nome.startsWith(".")) continue;
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) varrer(caminho, achados);
    else if (/\.(ts|tsx)$/.test(nome) && !nome.endsWith(".test.ts")) achados.push(caminho);
  }
  return achados;
}

const ARQUIVOS = [
  ...varrer(join(RAIZ, "app")),
  ...varrer(join(RAIZ, "components")),
].map((caminho) => ({ caminho, texto: readFileSync(caminho, "utf8") }));

const O_COMPONENTE = join(RAIZ, "components", "app", "Meses.tsx");

describe("ninguém desenha uma segunda linha do mês", () => {
  it("só o componente monta as marcas", () => {
    // Carregar o tipo é legítimo em qualquer lugar — quem lê o banco precisa
    // dele. **Montar a marca** é que é privilégio de um arquivo só: é ali que
    // a palavra nasce, e duas nascenças divergem no dia em que uma for
    // corrigida.
    const montam = ARQUIVOS.filter(
      ({ caminho, texto }) => caminho !== O_COMPONENTE && /\bmarcasDoMes\s*\(/.test(texto),
    ).map(({ caminho }) => caminho.replace(RAIZ + "/", ""));

    expect(montam).toEqual([]);
  });

  it("nenhuma tela desenha a linha do mês por fora do componente", () => {
    const desviadas = ARQUIVOS.filter(
      ({ caminho, texto }) =>
        caminho.endsWith(".tsx") &&
        caminho !== O_COMPONENTE &&
        /\bLinhaDoMes\b/.test(texto) &&
        !/from "@\/components\/app\/Meses"/.test(texto),
    ).map(({ caminho }) => caminho.replace(RAIZ + "/", ""));

    expect(desviadas).toEqual([]);
  });

  it("o componente monta as marcas pela função, e não escreve rótulo próprio", () => {
    const texto = readFileSync(O_COMPONENTE, "utf8");
    expect(texto).toMatch(/marcasDoMes\(/);
    // `m.rotulo` e `m.texto` são a prova de que a palavra vem de fora. Um
    // rótulo escrito em JSX aqui reprova.
    expect(texto).toMatch(/\{m\.rotulo\}/);
    expect(texto).toMatch(/\{m\.texto\}/);
  });

  it("as duas telas passam por ele, e cada uma diz de que lado está", () => {
    const usam = ARQUIVOS.filter(({ caminho, texto }) =>
      caminho !== O_COMPONENTE && /from "@\/components\/app\/Meses"/.test(texto),
    );

    // As duas de hoje: a ficha dela e a página do paciente. Se aparecer uma
    // terceira, ela também tem que declarar o lado — o que este teste cobra
    // abaixo é a declaração, não o número.
    expect(usam.length).toBeGreaterThanOrEqual(2);

    for (const { caminho, texto } of usam) {
      expect(texto, `${caminho} desenha a linha do mês sem dizer de que lado está`)
        .toMatch(/comJanela/);
    }
  });
});

describe("o tipo e a função do banco não divergem", () => {
  // A migração **mais recente** que reescreve `linhas_do_mes`, achada varrendo
  // a pasta (lei 7). Cravar `0095` aqui faria este espelho conferir contra um
  // corpo que o banco já não roda — que é a lei 6 pelo avesso, e foi assim que
  // a 0053 ficou vermelha em silêncio.
  const DIR = join(RAIZ, "supabase", "migrations");
  const ONDE = readdirSync(DIR)
    .filter((f) => f.endsWith(".sql"))
    .filter((f) => /create or replace function public\.linhas_do_mes/.test(readFileSync(join(DIR, f), "utf8")))
    .sort()
    .at(-1);
  const SQL = readFileSync(join(DIR, ONDE ?? ""), "utf8");
  const TS = readFileSync(join(RAIZ, "lib", "meses.ts"), "utf8");

  it("as chaves de linhas_do_mes são exatamente os campos de LinhaDoMes", () => {
    // O `jsonb_build_object` da linha, dentro de `linhas_do_mes`. Recorta-se
    // pelo bloco, e não pelo arquivo, porque a migração tem outros objetos.
    const bloco = SQL.split("select coalesce(jsonb_agg(")[1]?.split("), '[]'::jsonb)")[0] ?? "";
    expect(bloco.length).toBeGreaterThan(0);
    const noBanco = [...bloco.matchAll(/'([a-z_]+)',\s/g)].map((m) => m[1]).sort();

    const corpo = TS.split("export type LinhaDoMes = {")[1]?.split("\n};")[0] ?? "";
    expect(corpo.length).toBeGreaterThan(0);
    const noTipo = [...corpo.matchAll(/^\s{2}([a-z_]+)[?]?:/gm)].map((m) => m[1]).sort();

    expect(noTipo).toEqual(noBanco);
  });

  it("a janela de 90 dias é lida do banco, e não recalculada na tela", () => {
    // `recibo_na_janela` existe justamente para a tela não reimplementar o
    // recorte de `documento_do_link`. Um `90` solto no **código** de
    // lib/meses.ts seria a segunda fonte de verdade sobre a mesma porta — os
    // comentários podem (e devem) explicar de onde vem o número.
    expect(SQL).toMatch(/recibo_na_janela/);
    expect(TS).toMatch(/recibo_na_janela/);

    const semComentario = TS.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    expect(semComentario).not.toMatch(/\b90\b/);
    expect(semComentario).toMatch(/recibo_na_janela/);
  });
});
