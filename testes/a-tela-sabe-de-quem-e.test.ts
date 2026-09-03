import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * Nenhuma tela escolhe uma profissional arbitrária.
 *
 * O DEFEITO, E POR QUE ELE É PIOR DO QUE PARECE
 *
 * Quatro consultas a `profissionais` eram `.limit(1)` **sem ordenação**. O
 * Postgres não promete ordem nenhuma nesse caso: a consulta devolve uma linha
 * qualquer, e pode devolver outra na chamada seguinte. Numa conta com uma
 * profissional só — que é o caso de todas as contas do banco hoje — isso nunca
 * aparece. Numa clínica, aparece assim:
 *
 *  · **`/perfil`** mostrava CRP, documento e assinatura de alguém, e o
 *    formulário nasce preenchido com o que a consulta trouxe. `salvarAssinatura`
 *    grava em `sessao.profissionalId` — então abrir o Perfil e apertar Salvar
 *    **copiava o CRP da colega para cima do próprio**. Depois disso ela assina
 *    documento com registro alheio, e nada na tela disse isso.
 *  · **`/perfil/horarios`** deixava editar a semana declarada de outra pessoa.
 *    Esta tinha `.eq("ativo", true)` — filtro que não escolhe ninguém em
 *    particular, e é por isso que a regra abaixo pede filtro **por `id`**.
 *  · **`/perfil/contrato`** punha o CRP de outra pessoa na prévia do contrato.
 *  · **`/fechamento/livro`** escolhia por ordem alfabética e não oferecia troca.
 *
 * A REGRA, E POR QUE ELA É ESTA
 *
 * Uma consulta a `profissionais` com `.limit(1)` precisa de **`.eq("id", …)`**
 * — uma linha específica, escolhida por quem está olhando — ou de `.order(…)`,
 * que ao menos torna a escolha estável e explicável. Qualquer outro filtro não
 * basta: `ativo = true` continua devolvendo "uma das ativas, qualquer uma".
 *
 * O que ela não faz: lista de arquivos permitidos. A tela nova de amanhã que
 * consultar `profissionais` nasce dentro desta varredura.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      arquivos(caminho, res);
    } else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) {
      res.push(caminho);
    }
  }
  return res;
}

function semComentarios(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'`\\])\/\/[^\n]*/g, (_, antes) => antes);
}

/**
 * O trecho da cadeia, delimitado por parênteses e não por número de linhas.
 *
 * Uma janela de N caracteres vazaria para a consulta vizinha e acharia um
 * `.eq(` que não é desta cadeia — um falso negativo, que numa varredura é pior
 * que um falso positivo: passa calado.
 */
function cadeiaDe(fonte: string, inicio: number): string {
  let profundidade = 0;
  for (let i = inicio; i < fonte.length; i += 1) {
    const c = fonte[i];
    if (c === "(") profundidade += 1;
    else if (c === ")") {
      profundidade -= 1;
      if (profundidade < 0) return fonte.slice(inicio, i);
    }
  }
  return fonte.slice(inicio);
}

describe("nenhuma tela escolhe uma profissional arbitrária", () => {
  const fontes = arquivos(join(RAIZ, "app")).concat(
    arquivos(join(RAIZ, "lib")),
    arquivos(join(RAIZ, "components")),
  );

  it("consulta a profissionais com limit(1) escolhe por id ou ordena", () => {
    const arbitrarias: string[] = [];

    for (const arquivo of fontes) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      const alvo = /from\(\s*["'`]profissionais["'`]\s*\)/g;

      for (const achado of fonte.matchAll(alvo)) {
        const cadeia = cadeiaDe(fonte, achado.index);
        if (!/\.limit\(\s*1\s*\)/.test(cadeia)) continue;

        const porId = /\.eq\(\s*["'`]id["'`]/.test(cadeia);
        const ordenada = /\.order\(/.test(cadeia);
        if (porId || ordenada) continue;

        const linha = fonte.slice(0, achado.index).split("\n").length;
        arbitrarias.push(
          `${relative(RAIZ, arquivo)}:${linha} consulta profissionais com limit(1) sem eq("id") e sem order()`,
        );
      }
    }

    expect(arbitrarias, arbitrarias.join("\n")).toEqual([]);
  });

  /*
    A outra metade: escrever na profissional é sempre na da sessão. O `update`
    do Perfil já estava certo — `.eq("id", sessao.profissionalId)` —, e é essa
    linha que fazia o defeito de leitura virar corrupção de dado. Se alguém
    afrouxar o filtro da escrita, é aqui que aparece.
  */
  it("escrita em profissionais é sempre por id", () => {
    const soltas: string[] = [];

    for (const arquivo of fontes) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));

      for (const achado of fonte.matchAll(/from\(\s*["'`]profissionais["'`]\s*\)/g)) {
        const cadeia = cadeiaDe(fonte, achado.index);
        if (!/\.(update|delete)\(/.test(cadeia)) continue;
        if (/\.eq\(\s*["'`]id["'`]/.test(cadeia)) continue;

        const linha = fonte.slice(0, achado.index).split("\n").length;
        soltas.push(`${relative(RAIZ, arquivo)}:${linha} escreve em profissionais sem eq("id")`);
      }
    }

    expect(soltas, soltas.join("\n")).toEqual([]);
  });
});
