import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * A varredura da B48 — e a lei 7 do `CLAUDE.md` escrita como teste.
 *
 * Os dois S1 desta build não eram um campo cada: eram **um padrão cada**,
 * repetido em oito e em três lugares. Consertar os oito e os três não impede o
 * nono e o quarto — e foi assim que `exportar_conta` esqueceu dezessete
 * tabelas, porque a checagem era uma lista escrita à mão de quando havia doze.
 *
 * Por isso nada aqui é lista. O conjunto de caixas de seleção é **descoberto
 * varrendo os componentes**, e o conjunto de campos de dinheiro é descoberto
 * pelo nome do campo no próprio `form.get`. Um formulário novo entra na
 * varredura sozinho, no dia em que for escrito.
 */

const RAIZ = join(import.meta.dirname, "..");
const PASTAS = ["app", "components", "lib"];

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

/**
 * Apaga comentários antes de varrer, **preservando as linhas**.
 *
 * Sem isso a varredura acusa o próprio texto que explica o defeito: um
 * comentário citando `<input type="time">` vira um seletor de hora sem `step`,
 * e um que cita `form.get(x) !== "nao"` vira o defeito de volta. O primeiro
 * aconteceu de verdade, num comentário que descrevia o formato "09:00:00".
 */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (bloco) => bloco.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (linha, antes) => antes + " ".repeat(linha.length - antes.length));
}

const FONTES = PASTAS.flatMap((p) => arquivos(join(RAIZ, p))).map((caminho) => ({
  caminho: relative(RAIZ, caminho),
  texto: semComentarios(readFileSync(caminho, "utf8")),
}));

function linhaDe(texto: string, indice: number): number {
  return texto.slice(0, indice).split("\n").length;
}

/** Onde os dois parsers de dinheiro têm direito de morar. */
const CASA_DO_DINHEIRO = ["lib/formato.ts", "lib/dinheiro.ts"];

describe("nenhum campo de dinheiro tem parser próprio", () => {
  /**
   * As duas normalizações à mão que o produto tinha, escritas como elas
   * apareciam. Qualquer uma delas de volta é o S1 de volta.
   */
  const NORMALIZACAO_A_MAO = [
    { re: /\.replace\(\s*","\s*,\s*"\."\s*\)/g, o_que: '.replace(",", ".") — "1.200" vira R$ 1,20' },
    { re: /\.replace\(\s*\/\\\.\/g\s*,\s*""\s*\)/g, o_que: '.replace(/\\./g, "") — "1200.00" vira R$ 120.000,00' },
  ];

  it("ninguém normaliza dinheiro à mão fora de lib/formato.ts", () => {
    const achados: string[] = [];
    for (const { caminho, texto } of FONTES) {
      if (CASA_DO_DINHEIRO.includes(caminho)) continue;
      for (const { re, o_que } of NORMALIZACAO_A_MAO) {
        for (const m of texto.matchAll(re)) {
          achados.push(`${caminho}:${linhaDe(texto, m.index)} — ${o_que}`);
        }
      }
    }
    expect(achados, "use lerValor/lerCentavos de @/lib/formato").toEqual([]);
  });

  /**
   * O nome do campo é que diz que ele é dinheiro. Vale para o campo que
   * ninguém previu: se alguém criar `valor_do_pacote` amanhã, ele já entra.
   */
  const PALAVRA_DE_DINHEIRO = /(^|_)(valor|valores|mensalidade|preco|preço)(_|$)/i;

  // `mensalidade_dia` é o dia do vencimento, não dinheiro. O que desqualifica
  // é a **unidade** no fim do nome, não uma lista de campos.
  const UNIDADE_QUE_NAO_E_DINHEIRO = /_(dia|dias|mes|meses|ano|anos|hora|horas|min|minutos|percentual|pct|id|tipo|modelo|qtd|quantidade)$/i;

  const NOME_DE_DINHEIRO = (campo: string) =>
    PALAVRA_DE_DINHEIRO.test(campo) && !UNIDADE_QUE_NAO_E_DINHEIRO.test(campo);

  it("valor digitado não passa por Number() nem por paraCentavos()", () => {
    const achados: string[] = [];

    for (const { caminho, texto } of FONTES) {
      if (CASA_DO_DINHEIRO.includes(caminho)) continue;

      // Onde um campo de dinheiro vira variável.
      const variaveis = new Map<string, number>();
      for (const m of texto.matchAll(
        /(?:const|let)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*[^;\n]*form\.get\(\s*"([^"]+)"/g,
      )) {
        const [, variavel, campo] = m;
        if (NOME_DE_DINHEIRO(campo)) variaveis.set(variavel, linhaDe(texto, m.index));
      }

      for (const [variavel, linha] of variaveis) {
        for (const perigo of ["Number", "paraCentavos"]) {
          const re = new RegExp(`\\b${perigo}\\(\\s*${variavel}\\s*\\)`);
          if (re.test(texto)) {
            achados.push(
              `${caminho}:${linha} — "${variavel}" vem de um campo de dinheiro e cai em ${perigo}()`,
            );
          }
        }
      }

      // E a forma direta, sem passar por variável.
      for (const m of texto.matchAll(
        /\b(Number|paraCentavos)\(\s*(?:String\()?\s*form\.get\(\s*"([^"]+)"/g,
      )) {
        const [, perigo, campo] = m;
        if (NOME_DE_DINHEIRO(campo)) {
          achados.push(`${caminho}:${linhaDe(texto, m.index)} — ${perigo}(form.get("${campo}"))`);
        }
      }
    }

    expect(achados, "campo digitado se lê com lerValor/lerCentavos").toEqual([]);
  });
});

/**
 * O conjunto de caixas de seleção do produto, descoberto varrendo os
 * componentes — nunca escrito à mão aqui.
 */
const CAIXAS = (() => {
  const nomes = new Map<string, string>();
  for (const { caminho, texto } of FONTES) {
    for (const m of texto.matchAll(/<input\b[^>]*?>/g)) {
      const tag = m[0];
      if (!/type="checkbox"/.test(tag)) continue;
      const nome = /name="([^"]+)"/.exec(tag)?.[1];
      if (nome) nomes.set(nome, `${caminho}:${linhaDe(texto, m.index)}`);
    }
  }
  return nomes;
})();

describe("caixa desmarcada desliga de verdade", () => {
  it("a varredura acha as caixas do produto", () => {
    // Se este número cair para zero, a varredura parou de varrer e os testes
    // abaixo passariam vazios — que é o modo silencioso de um teste morrer.
    expect(CAIXAS.size).toBeGreaterThanOrEqual(8);
    expect([...CAIXAS.keys()]).toContain("ativo");
    expect([...CAIXAS.keys()]).toContain("topa_antecipar");
  });

  /**
   * `dias` é a única que não é liga-desliga: são sete caixas com o mesmo
   * `name`, lidas com `getAll`. Comparar valor ali é o certo.
   */
  const MULTIPLA = new Set(["dias"]);

  it("nenhuma caixa é lida por comparação — todas passam por caixaMarcada", () => {
    const achados: string[] = [];

    for (const { caminho, texto } of FONTES) {
      for (const [nome, onde] of CAIXAS) {
        if (MULTIPLA.has(nome)) continue;
        const re = new RegExp(`form\\.get\\(\\s*"${nome}"\\s*\\)`, "g");
        for (const m of texto.matchAll(re)) {
          achados.push(
            `${caminho}:${linhaDe(texto, m.index)} — lê a caixa "${nome}" (${onde}) ` +
              `com form.get; use caixaMarcada(form, "${nome}")`,
          );
        }
      }
    }

    expect(achados).toEqual([]);
  });

  /**
   * O defeito exato, escrito para nunca mais passar: `form.get(x) !== "nao"`
   * devolve `true` para a caixa desmarcada, e não existia em lugar nenhum do
   * produto um campo escondido mandando `"nao"`.
   */
  it('ninguém decide um booleano com form.get(...) !== "…"', () => {
    const achados: string[] = [];
    const CONFIRMACAO_POR_PALAVRA = /form\.get\(\s*"(confirma|site)"/;

    for (const { caminho, texto } of FONTES) {
      for (const m of texto.matchAll(/form\.get\([^)]*\)[^;\n]*?!==\s*"/g)) {
        if (CONFIRMACAO_POR_PALAVRA.test(m[0])) continue; // digitar "fechar", e o honeypot
        achados.push(`${caminho}:${linhaDe(texto, m.index)} — ${m[0].trim()}`);
      }
    }

    expect(achados).toEqual([]);
  });
});

/**
 * Todo `<input>` do produto, com o que a tag declara. Descoberto varrendo — a
 * tela nova entra sozinha, e é o oposto da lista escrita à mão que deixou
 * `exportar_conta` esquecer dezessete tabelas.
 */
const ENTRADAS = (() => {
  const achadas: { caminho: string; linha: number; tag: string; tipo: string; nome: string | null }[] = [];
  for (const { caminho, texto } of FONTES) {
    for (const m of texto.matchAll(/<input\b[^>]*?>/g)) {
      const tag = m[0];
      achadas.push({
        caminho,
        linha: linhaDe(texto, m.index),
        tag,
        tipo: /type="([^"]+)"/.exec(tag)?.[1] ?? "text",
        nome: /name="([^"]+)"/.exec(tag)?.[1] ?? null,
      });
    }
  }
  return achadas;
})();

describe("o campo abre o teclado e a roda certos", () => {
  it("a varredura acha as entradas do produto", () => {
    expect(ENTRADAS.length).toBeGreaterThanOrEqual(60);
  });

  /**
   * A roda do seletor de hora abria minuto a minuto: para marcar 14:30 ela
   * passava por trinta paradas. Nenhuma sessão do produto começa em minuto
   * quebrado.
   */
  it("todo seletor de hora anda de quinze em quinze minutos", () => {
    const sem = ENTRADAS.filter((e) => e.tipo === "time" && !/step=\{900\}/.test(e.tag));
    expect(sem.map((e) => `${e.caminho}:${e.linha}`)).toEqual([]);
  });

  /**
   * Rolar a página com o cursor em cima de um `type="number"` **muda o valor**.
   * Num campo chamado "Aí a sessão é cobrada" isso altera a política de falta
   * sem um clique — e a rolagem some, então ela nunca vê o que mudou.
   */
  it("rolar a página não altera um campo numérico", () => {
    const sem = ENTRADAS.filter((e) => e.tipo === "number" && !/onWheel=/.test(e.tag));
    expect(sem.map((e) => `${e.caminho}:${e.linha}`)).toEqual([]);
  });

  /**
   * O teclado de letras num campo de CPF custa dois toques por campo, e ela
   * está de pé, com dez minutos, às vezes com o app da Receita na outra mão.
   */
  it("nenhum campo de dígito abre teclado de letras", () => {
    const NOME_DE_DIGITO = /(cpf|cnpj|documento|telefone|celular|numero|crp|valor|mensalidade|preco)/i;
    const TIPO_JA_NUMERICO = new Set([
      "hidden", "checkbox", "radio", "time", "date", "email", "number", "file", "submit",
    ]);

    const sem = ENTRADAS.filter(
      (e) =>
        !TIPO_JA_NUMERICO.has(e.tipo) &&
        e.nome !== null &&
        NOME_DE_DIGITO.test(e.nome) &&
        !/inputMode=/.test(e.tag),
    );
    expect(sem.map((e) => `${e.caminho}:${e.linha} name=${e.nome}`)).toEqual([]);
  });
});
