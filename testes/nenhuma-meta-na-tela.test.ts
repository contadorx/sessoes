import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * A regra 3 do P5, estendida à área autenticada inteira.
 *
 * `lib/risco.ts` já a escrevia: *"não existe meta, e nada elogia. Nenhum alvo,
 * nenhuma barra de progresso rumo a 100%, e passar de 100% é fato — nunca
 * parabéns. Um produto para psicólogas que comemora ocupação alta é um produto
 * empurrando alguém a eliminar o próprio tempo de registro e de descanso."*
 *
 * A verificação existia — a suíte `0059_receita_em_risco.sql`, verificações 11,
 * 12 e 15. Ela olha a **resposta do cockpit** e as **colunas do banco**, e por
 * isso não tinha como ver o que estava em `/encaixes`:
 *
 *     nota="a meta é 60% — abaixo disso o produto não se justifica"
 *     cor={Number(metrica.taxa) >= 60 ? "text-cheia" : "text-vaga"}
 *
 * Verde acima de 60, vermelho abaixo — a cor que melhora quando o número sobe,
 * literalmente. E a frase era sobre **o meu negócio**, pintada de vermelho na
 * tela de quem está tentando preencher um horário.
 *
 * O banco estava protegido; a tela, não. Este arquivo é a metade que faltava, e
 * varre `app/` e `components/` inteiros — não uma lista de telas, que é a
 * checagem que esquece a tela nova.
 */

const RAIZ = join(import.meta.dirname, "..");
/*
  O escopo é a área dela.

  `app/(site)` fica de fora: lá "Meta" é a empresa dona do WhatsApp, e `meta` é
  etiqueta de SEO. A regra do P5 é sobre as telas em que ela vê números do
  próprio consultório — é ali que uma meta vira empurrão.
*/
const PASTAS = ["app/(app)", "components/app"];

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

/** Comentário fora, preservando as linhas — senão a varredura acusa o texto que a explica. */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (l, antes) => antes + " ".repeat(l.length - antes.length));
}

const FONTES = PASTAS.flatMap((p) => arquivos(join(RAIZ, p))).map((caminho) => ({
  caminho: relative(RAIZ, caminho),
  texto: semComentarios(readFileSync(caminho, "utf8")),
}));

const linhaDe = (t: string, i: number) => t.slice(0, i).split("\n").length;

describe("nenhuma tela põe meta, alvo ou elogio em cima de um número dela", () => {
  it("a varredura está varrendo", () => {
    expect(FONTES.length).toBeGreaterThan(50);
  });

  /**
   * A cor que melhora com o número subindo, que é a forma mais discreta da
   * meta: nenhuma palavra na tela, e mesmo assim um número certo e um errado.
   */
  it("nenhuma cor é escolhida comparando um número com um limite", () => {
    const achados: string[] = [];
    /*
      O limite tem que ser **diferente de zero**, e a distinção é a build
      inteira em uma linha: `> 0 ? "text-vaga"` é "existe ou não existe" — um
      fato, e a cor diz que há algo para olhar. `>= 60 ? "text-cheia"` é um
      número certo e um errado, que é uma meta sem a palavra.
    */
    const re = /[<>]=?\s*(\d+(?:\.\d+)?)\s*\)?\s*\?[\s\S]{0,80}?"text-(cheia|vaga|aviso)"/g;

    for (const { caminho, texto } of FONTES) {
      for (const m of texto.matchAll(re)) {
        if (Number(m[1]) === 0) continue;
        achados.push(`${caminho}:${linhaDe(texto, m.index)} — ${m[0].replace(/\s+/g, " ")}`);
      }
    }
    expect(achados, "cor que melhora quando o número sobe é uma meta sem a palavra").toEqual([]);
  });

  it("nenhuma tela escreve meta, alvo ou objetivo sobre um número", () => {
    const achados: string[] = [];
    /*
      Só as formas em que a palavra **é** uma meta — "a meta é 60%", "sua meta
      do mês", "objetivo de 80%". A palavra solta não conta: `alvo` é nome de
      variável em meio repositório (`const alvo = useRef`), e proibir
      identificador seria proibir programação, não promessa.
    */
    const re = /\b(?:(?:a|sua|uma|nossa)\s+(?:meta|alvo)|(?:meta|alvo|objetivo)\s+(?:de|do|da|é|mensal|do mês))\b/gi;

    for (const { caminho, texto } of FONTES) {
      for (const m of texto.matchAll(re)) {
        achados.push(`${caminho}:${linhaDe(texto, m.index)} — "${m[0]}"`);
      }
    }
    expect(achados).toEqual([]);
  });

  it("nenhuma tela elogia", () => {
    const achados: string[] = [];
    const re = /\b(parab[ée]ns|excelente|[óo]timo|mandou bem|arrasou|meta atingida)\b/gi;

    for (const { caminho, texto } of FONTES) {
      for (const m of texto.matchAll(re)) {
        achados.push(`${caminho}:${linhaDe(texto, m.index)} — "${m[0]}"`);
      }
    }
    expect(achados, "nenhuma palavra de elogio: o número já é dela").toEqual([]);
  });

  /**
   * Barra de progresso é a meta desenhada. O cockpit mostra ocupação, e uma
   * barra rumo a 100% diz que 100% é onde se quer chegar — que é o mesmo que
   * pedir a ela que elimine o tempo de registro e de descanso.
   */
  it("nenhuma barra de progresso rumo a cem por cento", () => {
    const achados: string[] = [];
    for (const { caminho, texto } of FONTES) {
      for (const m of texto.matchAll(/<progress\b|role="progressbar"/g)) {
        achados.push(`${caminho}:${linhaDe(texto, m.index)}`);
      }
    }
    expect(achados).toEqual([]);
  });
});
