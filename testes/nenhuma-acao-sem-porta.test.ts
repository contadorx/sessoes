import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * Toda ação de servidor tem uma porta na tela.
 *
 * `cancelarDocumento` existia desde a B17, correta e testada pelo banco. A tela
 * do documento até **sabia desenhar o resultado**: dois blocos renderizam
 * "Cancelado em … — motivo", e a cópia impressa sai com o carimbo. O que não
 * existia era o botão. Nenhum arquivo `.tsx` importava a ação.
 *
 * O que isso significava: um recibo emitido com o valor errado — que leva o
 * **nome e o CRP dela**, e que já foi entregue a alguém — não tinha como ser
 * cancelado pela interface. Um irreversível ao contrário: o irreversível era
 * não poder desfazer.
 *
 * **Por que isso não aparece em nenhuma outra verificação.** O lint não reclama
 * de export não usado entre arquivos. O `tsc` não reclama. A suíte SQL testa a
 * função do banco, que está certa. Os testes de unidade testam `lib/`, e a ação
 * não mora lá. É um defeito que só existe no espaço **entre** as camadas que
 * cada verificação cobre — e é por isso que ele durou builds inteiras.
 *
 * A varredura descobre as ações lendo os arquivos `acoes.ts`, não uma lista: a
 * ação nova entra sozinha no dia em que for escrita.
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

/**
 * Comentário fora antes de varrer — **a terceira vez nesta fila**.
 *
 * A varredura de campos da B48 acusou o parágrafo que explicava o defeito. A
 * varredura de permissão da B31 passou com o defeito reintroduzido, porque o
 * comentário citava `SemAcessoClinico`. E esta aqui passou com o botão de
 * cancelar removido, porque o comentário que eu tinha acabado de escrever na
 * página dizia "a ação `cancelarDocumento` existia e estava correta".
 *
 * Três vezes o mesmo erro, e ele tem uma forma só: **a varredura confundiu a
 * descrição da coisa com a coisa.** Num teste que procura ausência, isso não é
 * um falso positivo — é um falso *negativo*, e ele acontece exatamente no
 * arquivo mais bem comentado, que costuma ser o que acabou de ser consertado.
 */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (l, antes) => antes + " ".repeat(l.length - antes.length));
}

const FONTES = ["app", "components", "lib"]
  .flatMap((d) => arquivos(join(RAIZ, d)))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    texto: semComentarios(readFileSync(caminho, "utf8")),
  }));

/** As ações exportadas, descobertas nos arquivos que as guardam. */
const ACOES = FONTES.filter((f) => /acoes\.ts$/.test(f.caminho)).flatMap((f) =>
  [...f.texto.matchAll(/export async function ([A-Za-z0-9_]+)/g)].map((m) => ({
    arquivo: f.caminho,
    nome: m[1],
  })),
);

describe("nenhuma ação de servidor fica sem porta", () => {
  it("a varredura acha as ações do produto", () => {
    expect(ACOES.length).toBeGreaterThan(50);
    expect(ACOES.map((a) => a.nome)).toContain("cancelarDocumento");
  });

  /**
   * Ter um importador não basta: a porta precisa estar numa parede que alguém
   * alcance.
   *
   * A primeira versão desta varredura passava com o botão removido, porque o
   * componente `CancelarDocumento.tsx` continuava importando a ação — e um
   * componente que ninguém renderiza é exatamente a mesma funcionalidade
   * inalcançável, uma casa mais longe. A cadeia é seguida até chegar numa
   * página (`app/**` que não seja `acoes.ts`), que é o que o navegador abre.
   */
  const PAGINAS = new Set(
    FONTES.filter((f) => f.caminho.startsWith("app/") && !/acoes\.ts$/.test(f.caminho)).map(
      (f) => f.caminho,
    ),
  );

  const nomeDoComponente = (caminho: string) =>
    caminho.split("/").pop()!.replace(/\.tsx?$/, "");

  function alcancavel(nome: string, deArquivo: string, visto = new Set<string>()): boolean {
    if (visto.has(nome + "@" + deArquivo)) return false;
    visto.add(nome + "@" + deArquivo);

    const quemUsa = FONTES.filter(
      (f) => f.caminho !== deArquivo && new RegExp(`\\b${nome}\\b`).test(f.texto),
    );

    for (const f of quemUsa) {
      // Chegou numa página: o navegador abre isso.
      if (PAGINAS.has(f.caminho)) return true;
      // Componente: ele próprio precisa ser renderizado em algum lugar.
      if (alcancavel(nomeDoComponente(f.caminho), f.caminho, visto)) return true;
    }
    return false;
  }

  it.each(ACOES.map((a) => [a.nome, a] as const))(
    "%s chega até uma tela que o navegador abre",
    (_nome, acao) => {
      expect(
        alcancavel(acao.nome, acao.arquivo),
        `${acao.arquivo} exporta "${acao.nome}", e não há caminho dela até uma página.\n` +
          `Ação sem porta é funcionalidade que existe e não acontece — foi assim ` +
          `que cancelar um documento emitido ficou impossível pela interface, ` +
          `com a ação pronta e a tela já sabendo desenhar o resultado.`,
      ).toBe(true);
    },
  );
});
