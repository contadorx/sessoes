import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * Na superfície do Receita Saúde, ninguém escreve "emitido" sozinho.
 *
 * **O produto não emite.** Não existe API pública do Receita Saúde, não existe
 * função que emita, e há teste de estrutura desde a 0038 que reprova qualquer
 * função com esse nome. Quem abre o app da Receita Federal, digita e confirma é
 * ela — e o Sessões registra que ela fez.
 *
 * A distância entre as duas frases é a distância entre um produto honesto e um
 * que faz alguém levar multa por confiar nele: se a tela diz "emitido" e o
 * recibo não foi emitido, ela descobre em fevereiro, com R$ 100 por recibo no
 * CPF dela.
 *
 * O banco já foi corrigido uma vez por isso — a 0067 renomeou
 * `recibos_rfb.emitido_em` → `marcado_por_ela_em`, `numero_rfb` →
 * `numero_informado` e o estado `'emitido'` → `'marcado_por_ela'`. Esta
 * varredura é a mesma regra do lado da tela, onde não há `check` para segurar.
 *
 * **O escopo é a superfície do Receita Saúde, e não o produto inteiro** — e a
 * fronteira é real, não conveniência: `documentos.emitido_em` fala do recibo da
 * B17, que **este produto emitiu de verdade**, com número queimado por ele e
 * gatilho de imutabilidade em cima. Ali a palavra é verdadeira, e apagá-la por
 * simetria apagaria justamente a diferença que a 0067 existe para escrever.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  if (!existsSync(dir)) return res;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) arquivos(caminho, res);
    else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) res.push(caminho);
  }
  return res;
}

function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (l, antes) => antes + " ".repeat(l.length - antes.length));
}

const SUPERFICIE = [
  join(RAIZ, "app/(app)/fechamento/receita-saude"),
  join(RAIZ, "components/app/ReceitaSaude.tsx"),
  join(RAIZ, "lib/receitasaude.ts"),
]
  .flatMap((p) => (p.endsWith(".ts") || p.endsWith(".tsx") ? [p] : arquivos(p)))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    texto: semComentarios(readFileSync(caminho, "utf8")),
  }));

/** As frases que a pessoa lê: nó de JSX e literal com cara de frase. */
function fala(texto: string): string[] {
  const limpo = texto
    .replace(/className=\{`[^`]*`\}/g, " ")
    .replace(/className=\{[^}]*\}/g, " ")
    .replace(/className="[^"]*"/g, " ");

  return [
    ...[...limpo.matchAll(/>([^<>{}]{4,})</g)].map((m) => m[1]),
    ...[...limpo.matchAll(/"([^"\n]{4,})"/g)]
      .map((m) => m[1])
      // Fora: chave de contexto do `db()`, nome de coluna, seletor.
      .filter((t) => /\s/.test(t) && !/[_/(){}<>=]/.test(t)),
  ].map((t) => t.replace(/\s+/g, " ").trim());
}

describe("o produto não emite, e a tela não diz que emitiu", () => {
  it("a varredura está lendo a superfície do Receita Saúde", () => {
    expect(SUPERFICIE.length).toBeGreaterThan(2);
    const todas = SUPERFICIE.flatMap((f) => fala(f.texto));
    expect(todas.length).toBeGreaterThan(30);
    // Controle: a frase que tem de existir, existe.
    expect(todas.some((f) => /Emiti na Receita/.test(f))).toBe(true);
  });

  /**
   * "Emitido" sozinho afirma que alguma coisa emitiu. Com "você" ou "Emiti" na
   * mesma frase, o sujeito é ela — que é o que aconteceu.
   *
   * "A emitir" fica de fora porque não afirma nada: é o nome de uma lista de
   * trabalho que ainda não foi feito, e é justamente o oposto da afirmação que
   * esta regra proíbe.
   */
  it("nenhuma frase diz 'emitido' sem dizer quem emitiu", () => {
    const achados = SUPERFICIE.flatMap((f) =>
      fala(f.texto)
        .filter((t) => /\bemitid[oa]s?\b/i.test(t))
        // Sem `\b` em volta de palavra acentuada: em JavaScript, `ê` não é
        // caractere de palavra, então `\bvocê\b` nunca casa — e a primeira
        // versão desta linha acusou "você marcou como emitido" por causa disso.
        // Um teste que não sabe ler a própria exceção acusa o texto certo e
        // ensina a trocá-lo pelo errado.
        // `Emiti` precisa de fronteira à direita: sem ela, "emiti" casa dentro
        // de "emitidos" e a exceção engole a regra que ela deveria abrir. A
        // mutação mostrou exatamente isso — o contador voltou a dizer
        // "emitidos N" e o teste continuou verde.
        .filter((t) => !/você|\bEmiti\b|marque|sua /i.test(t))
        .map((t) => `${f.caminho}: "${t}"`),
    );

    expect(
      achados,
      "frase que diz 'emitido' sem dizer que quem emitiu foi ela. O produto não " +
        "emite: não há API do Receita Saúde, e a 0067 renomeou o banco inteiro " +
        "por causa disto. Se a tela afirmar o que não aconteceu, ela descobre em " +
        "fevereiro, com R$ 100 por recibo no CPF dela.\n" + achados.join("\n"),
    ).toEqual([]);
  });

  /** E o verbo na primeira pessoa do produto não aparece: ele não emite. */
  it("nenhum botão convida a 'emitir' como se o sistema fizesse", () => {
    const achados = SUPERFICIE.flatMap((f) =>
      fala(f.texto)
        .filter((t) => /^(emitir|emitir recibo|emitir agora)$/i.test(t.trim()))
        .map((t) => `${f.caminho}: "${t}"`),
    );
    expect(achados, achados.join("\n")).toEqual([]);
  });
});
