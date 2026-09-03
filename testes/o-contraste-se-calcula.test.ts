import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * O contraste dos tokens, calculado — não olhado.
 *
 * A borda de campo do produto (`--color-linha2`, `#C0C7BC`) dava **1,73:1**
 * sobre o branco. O mínimo da WCAG para contorno de componente é 3:1, e a borda
 * do campo não é enfeite: é a única coisa que diz onde o campo começa e onde
 * ele acaba. Numa tela lida de pé, com reflexo, ela sumia.
 *
 * Ninguém percebe isso lendo o hex. Já aconteceu antes nesta base — o `tinta3`
 * ficou em 2,78:1 por meses, elegante e ilegível, e só saiu de lá quando
 * alguém calculou. Então o cálculo passa a rodar junto com os testes.
 *
 * **Por que não é uma lista de pares.** A lista de pares esquece o token novo
 * (lei 7). Aqui cada token do `@theme` precisa ter um **papel** declarado, e o
 * papel é que decide o mínimo. Token novo sem papel reprova a suíte — que é
 * exatamente a hora de decidir se ele carrega significado sozinho ou não.
 */

const CSS = readFileSync(join(import.meta.dirname, "..", "app", "globals.css"), "utf8");

/** Os tokens de cor, lidos do `@theme` — não transcritos. */
const TOKENS = new Map(
  [...CSS.matchAll(/--color-([a-z0-9-]+):\s*(#[0-9A-Fa-f]{6})\s*;/g)].map((m) => [
    m[1],
    m[2],
  ]),
);

function luminancia(hex: string): number {
  const canais = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const [r, g, b] = canais.map((c) =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4,
  );
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contraste(a: string, b: string): number {
  const [x, y] = [luminancia(a), luminancia(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

/** Os fundos em que qualquer coisa do produto pode cair. */
const FUNDOS = ["papel", "folha", "folha2"];

/**
 * O papel de cada token, e o mínimo que ele obriga.
 *
 * - **`texto`** — 4,5:1 contra os três fundos. É o mínimo AA para texto normal,
 *   e todo token desta lista aparece como texto em alguma tela.
 * - **`contorno`** — 3:1, o mínimo para limite de componente. Só o `linha2`
 *   está aqui, e é ele que desenha campo e botão de contorno.
 * - **`fundo`** e **`sobre-fundo`** — o par tingido (vaga sobre vaga-bg). Aqui
 *   o texto é conferido contra o **próprio** fundo dele.
 * - **`decorativo`** — a borda que acompanha um preenchimento. O `--color-linha`
 *   separa cartões que já se distinguem pelo fundo, e o `vaga-linha` contorna
 *   uma caixa que já é rosa por dentro: em nenhum dos dois o contorno é a única
 *   informação, que é a condição da regra 1.4.11. Exigir 3:1 deles deixaria o
 *   produto com cara de arame — e regra que se cumpre estragando a tela é regra
 *   que alguém desliga na semana seguinte.
 */
const PAPEL: Record<string, string> = {
  tinta: "texto",
  tinta2: "texto",
  tinta3: "texto",
  linha2: "contorno",
  linha: "decorativo",
  papel: "fundo",
  folha: "fundo",
  folha2: "fundo",
  vaga: "sobre-fundo",
  "vaga-bg": "fundo",
  "vaga-linha": "decorativo",
  cheia: "sobre-fundo",
  "cheia-bg": "fundo",
  "cheia-linha": "decorativo",
  aviso: "sobre-fundo",
  "aviso-bg": "fundo",
  "aviso-linha": "decorativo",
};

describe("o contraste dos tokens se calcula", () => {
  it("a leitura do @theme achou os tokens", () => {
    expect(TOKENS.size).toBeGreaterThan(12);
    expect(TOKENS.get("linha2")).toMatch(/^#/);
  });

  /** O guarda contra a lista escrita à mão: token novo tem que ganhar papel. */
  it("todo token de cor tem um papel declarado", () => {
    const semPapel = [...TOKENS.keys()].filter((t) => !(t in PAPEL));
    expect(
      semPapel,
      `token de cor sem papel: ${semPapel.join(", ")}. Antes de usá-lo, decida ` +
        `se ele carrega significado sozinho (texto, contorno) ou acompanha um ` +
        `preenchimento (decorativo) — é o papel que diz qual é o mínimo dele.`,
    ).toEqual([]);
  });

  const comPapel = (p: string) => [...TOKENS.entries()].filter(([t]) => PAPEL[t] === p);

  it.each(comPapel("texto"))("%s se lê nos três fundos (4,5:1)", (nome, cor) => {
    for (const f of FUNDOS) {
      const r = contraste(cor, TOKENS.get(f)!);
      expect(r, `${nome} (${cor}) sobre ${f}: ${r.toFixed(2)}:1`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it.each(comPapel("contorno"))("%s desenha um limite visível (3:1)", (nome, cor) => {
    for (const f of FUNDOS) {
      const r = contraste(cor, TOKENS.get(f)!);
      expect(
        r,
        `${nome} (${cor}) sobre ${f}: ${r.toFixed(2)}:1 — a borda do campo é a ` +
          `única coisa que diz onde ele começa.`,
      ).toBeGreaterThanOrEqual(3);
    }
  });

  it.each(comPapel("sobre-fundo"))("%s se lê sobre o fundo tingido dele", (nome, cor) => {
    const r = contraste(cor, TOKENS.get(`${nome}-bg`)!);
    expect(r, `${nome} sobre ${nome}-bg: ${r.toFixed(2)}:1`).toBeGreaterThanOrEqual(4.5);
    for (const f of FUNDOS) {
      const s = contraste(cor, TOKENS.get(f)!);
      expect(s, `${nome} sobre ${f}: ${s.toFixed(2)}:1`).toBeGreaterThanOrEqual(4.5);
    }
  });
});

/**
 * O que mais só se descobre medindo: foco e alvo de dedo.
 *
 * Estes três não são opinião de design. Cada um tem um número atrás — 44 px de
 * alvo, 16 px de campo, um contorno de foco que exista —, e cada um só apareceu
 * porque alguém foi conferir com régua, não com olho.
 */
describe("o dedo e o foco", () => {
  it("todo botão chega aos 44 px no celular, sem lista de botões", () => {
    expect(CSS).toMatch(/@media \(max-width: 640px\), \(pointer: coarse\)/);
    const regra = CSS.slice(CSS.indexOf("(pointer: coarse)"));
    expect(regra).toMatch(/min-height:\s*44px/);
    expect(
      regra.slice(0, regra.indexOf("}")),
      "a regra do alvo tem de valer para `button`, senão vira lista de exceções",
    ).toMatch(/\bbutton\b/);
  });

  it("nenhum campo abaixo de 16 px no celular — e sem maximum-scale", () => {
    expect(CSS).toMatch(/@media \(max-width: 640px\)[\s\S]*?textarea[\s\S]*?font-size:\s*16px/);
    expect(
      readFileSync(join(import.meta.dirname, "..", "app", "layout.tsx"), "utf8"),
      "`maximum-scale=1` resolve o zoom do iPhone tirando o zoom de quem precisa " +
        "ampliar para enxergar — a troca que este produto não faz.",
    ).not.toMatch(/maximumScale|maximum-scale/);
  });

  /**
   * `focus:outline-none` sem substituto apaga o único sinal de onde o teclado
   * está. Havia **um** no repositório inteiro, e a especificidade dele vencia o
   * `:focus-visible` global — o que é pior do que não ter foco nenhum, porque
   * some só naquele elemento e ninguém percebe.
   */
  it("nenhum focus:outline-none fica sem substituto", () => {
    const arquivos = (dir: string, res: string[] = []): string[] => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const caminho = join(dir, e.name);
        if (e.isDirectory()) arquivos(caminho, res);
        else if (/\.tsx$/.test(e.name)) res.push(caminho);
      }
      return res;
    };

    const RAIZ = join(import.meta.dirname, "..");
    const sem = ["app", "components"]
      .flatMap((d) => arquivos(join(RAIZ, d)))
      .flatMap((caminho) =>
        readFileSync(caminho, "utf8")
          .split("\n")
          .map((linha, i) => ({ caminho: relative(RAIZ, caminho), linha, n: i + 1 }))
          .filter(
            (l) =>
              /focus:outline-none/.test(l.linha) &&
              !/focus:(border|ring|bg)|focus-visible/.test(l.linha),
          ),
      )
      .map((l) => `${l.caminho}:${l.n}`);

    expect(
      sem,
      "quem tira o contorno de foco tem de pôr outro no lugar — borda, anel ou fundo.",
    ).toEqual([]);
  });
});
