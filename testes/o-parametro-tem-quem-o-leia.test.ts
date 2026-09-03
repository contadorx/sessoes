import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

/**
 * Todo parâmetro de endereço tem quem o leia — e toda página que declara
 * `searchParams` o usa.
 *
 * O DEFEITO, E POR QUE NENHUMA OUTRA VERIFICAÇÃO O PEGAVA
 *
 * O menu Novo mandava para quatro endereços com parâmetro —
 * `/agenda?novo=sessao`, `/encaixes?novo=pedido`, `/recebimentos?novo=entrada`
 * — e a faixa de confirmações oferecia *"ver sessão"* apontando para
 * `/agenda?sessao={id}`. A `/agenda` lia **só** `semana`; as outras duas não
 * liam nada. O que acontecia: ela tocava no item de menu, a página abria
 * **idêntica**, e não havia erro, aviso ou tela vazia — nada distinguia "o
 * comando não fez nada" de "eu não entendi o que ia acontecer".
 *
 * Isto passa por todas as outras redes do projeto. O `tsc` não reclama: um
 * parâmetro a mais numa URL é só texto. O lint não reclama. Os testes de `lib/`
 * não vêem endereço. A suíte SQL não vê tela. Nenhuma verificação de UI
 * existente compara **quem escreve o endereço** com **quem o lê** — e esse é
 * exatamente o vão onde o defeito morou desde que o menu Novo nasceu.
 *
 * A VARREDURA É DOS DOIS LADOS, E É DE PROPÓSITO
 *
 * 1 · **Link com parâmetro que ninguém lê.** Descobre as rotas lendo
 *     `app/**\/page.tsx` — a rota nova entra sozinha — e confere cada endereço
 *     escrito no produto contra o arquivo que o atende.
 * 2 · **Página que declara `searchParams` e não usa.** O contrário do primeiro,
 *     e o rastro que o primeiro deixaria se alguém "consertasse" apagando o
 *     link em vez de ler o parâmetro.
 *
 * O que ela não faz: inventar lista de parâmetros permitidos. Uma lista escrita
 * à mão aqui deixaria passar justamente o parâmetro novo, que é o único caso
 * que interessa (lei 7).
 */

const RAIZ = join(import.meta.dirname, "..");
const APP = join(RAIZ, "app");

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

/** Comentário fora antes de varrer — senão o exemplo escrito num comentário reprova. */
function semComentarios(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'`\\])\/\/[^\n]*/g, (_, antes) => antes);
}

/** `app/(app)/pacientes/[id]/page.tsx` → `/pacientes/:id`. Grupos de rota somem. */
function rotaDe(arquivo: string): string {
  const partes = relative(APP, arquivo).split(sep);
  partes.pop();
  const segmentos = partes
    .filter((p) => !/^\(.*\)$/.test(p))
    .map((p) => (/^\[.*\]$/.test(p) ? ":x" : p));
  return "/" + segmentos.join("/");
}

/** O endereço bate com a rota? `:x` casa com qualquer segmento. */
function casa(rota: string, caminho: string): boolean {
  const a = rota.split("/").filter(Boolean);
  const b = caminho.split("/").filter(Boolean);
  if (a.length !== b.length) return false;
  return a.every((seg, i) => seg === ":x" || seg === b[i]);
}

const TODOS = arquivos(join(RAIZ, "app")).concat(
  arquivos(join(RAIZ, "components")),
  arquivos(join(RAIZ, "lib")),
);

const PAGINAS = TODOS.filter((f) => /[/\\](page|route)\.tsx?$/.test(f));

describe("todo parâmetro de endereço tem quem o leia", () => {
  it("nenhum link do produto manda parâmetro que a página de destino não lê", () => {
    // `["'`]/caminho?a=1&b=2["'`]` — inclui interpolação, que vira segmento.
    const ENDERECO = /["'`](\/[A-Za-z0-9._\-/[\]${}]*\?[^"'`\s]+)["'`]/g;
    const orfaos: string[] = [];

    for (const arquivo of TODOS) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      for (const achado of fonte.matchAll(ENDERECO)) {
        const [caminhoBruto, consulta] = achado[1].split("?");
        // Interpolação vira um segmento coringa: `/pacientes/${id}` → `/pacientes/:x`.
        const caminho = caminhoBruto.replace(/\$\{[^}]*\}/g, ":x").replace(/\/$/, "") || "/";
        const nomes = consulta
          .split("&")
          .map((par) => par.split("=")[0])
          .filter((n) => n !== "" && !n.includes("${"));
        if (nomes.length === 0) continue;

        const destinos = PAGINAS.filter((p) => casa(rotaDe(p), caminho));
        if (destinos.length === 0) continue; // rota externa ou fora de `app/`

        const corpo = destinos.map((d) => readFileSync(d, "utf8")).join("\n");
        for (const nome of nomes) {
          const leu = new RegExp(`\\b${nome}\\b`).test(corpo);
          if (!leu) {
            orfaos.push(
              `${relative(RAIZ, arquivo)} manda "${nome}" para ${caminho}, e ${destinos
                .map((d) => relative(RAIZ, d))
                .join(", ")} não lê esse nome`,
            );
          }
        }
      }
    }

    expect(orfaos, orfaos.join("\n")).toEqual([]);
  });

  it("nenhuma página declara searchParams sem ler", () => {
    const mudas: string[] = [];

    for (const arquivo of PAGINAS) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      if (!/\bsearchParams\b/.test(fonte)) continue;

      // Ler é desestruturar (`const { x } = await searchParams`) ou guardar o
      // objeto (`const params = await searchParams`). Só declarar no tipo não é.
      const usa =
        /(await\s+searchParams)|(searchParams\s*\.\s*get)|(new URL\([^)]*searchParams)/.test(fonte);
      if (!usa) mudas.push(relative(RAIZ, arquivo));
    }

    expect(mudas, mudas.join("\n")).toEqual([]);
  });

  it("nenhuma ação de tela descarta o próprio resultado", () => {
    // `const [, despachar] = useActionState(...)`: a ação falha e a tela não
    // diz nada, então ela toca de novo — e em "Não veio" tocar de novo é
    // cobrar duas vezes.
    const surdas: string[] = [];
    for (const arquivo of TODOS) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      for (const achado of fonte.matchAll(
        /const\s*\[\s*,\s*[A-Za-z0-9_]+\s*\]\s*=\s*useActionState\(\s*([A-Za-z0-9_]+)/g,
      )) {
        surdas.push(`${relative(RAIZ, arquivo)}: ${achado[1]}`);
      }
    }
    expect(surdas, surdas.join("\n")).toEqual([]);
  });
});
