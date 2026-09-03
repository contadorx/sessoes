import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { basename, join, relative } from "node:path";

/**
 * O que está morto não volta.
 *
 * O `CLAUDE.md` tem uma seção inteira só para isso — **"§4 · O que está morto e
 * não volta"** —, e a razão dela é específica: as coisas dessa lista não foram
 * cortadas por prazo. Foram recusadas por decisão, quase todas de ética ou de
 * honestidade, e **cada uma delas tinha um bom argumento a favor** no dia em
 * que foi recusada. É por isso que voltam.
 *
 * Até aqui a lista era prosa. Prosa não reprova build.
 *
 * O caso que abriu este arquivo: `components/site/Simulador.tsx` — o simulador
 * de ROI, morto porque *"calculava R$ 800/mês de hora recuperada em aritmética
 * de padaria"* e transformava hipótese não demonstrada em número na tela.
 * Estava lá, compilando, sem ser importado por ninguém, com o preço de um plano
 * que não existe mais escrito dentro (`SOLO = 69`). O `_arquivadas.md` chegou a
 * escrever a tarefa — *"apagar, ou pôr um teste que reprove o import"* — e ela
 * ficou aberta. Este arquivo é as duas metades.
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

const TODAS = ["app", "components", "lib"]
  .flatMap((d) => arquivos(join(RAIZ, d)))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    bruto: readFileSync(caminho, "utf8"),
    texto: semComentarios(readFileSync(caminho, "utf8")),
  }));

/**
 * Componente que ninguém renderiza é o esconderijo do que foi morto.
 *
 * Ele não aparece em tela, não quebra teste, não polui a navegação — e continua
 * ali, compilando, esperando alguém achar que "já está pronto, é só importar".
 * Foi assim que o simulador de ROI sobreviveu à própria morte por dias.
 *
 * A varredura é sobre `components/`, onde a resposta é sempre a mesma: um
 * componente existe para ser desenhado. É a irmã de
 * `nenhuma-acao-sem-porta.test.ts`, que faz a mesma pergunta do lado das ações
 * de servidor.
 */
describe("nenhum componente fica no repositório sem ninguém desenhar", () => {
  const COMPONENTES = TODAS.filter((f) => f.caminho.startsWith("components/"));

  it("a varredura está achando os componentes", () => {
    expect(COMPONENTES.length).toBeGreaterThan(50);
  });

  it.each(COMPONENTES.map((c) => [c.caminho] as const))("%s é usado", (caminho) => {
    const nome = basename(caminho).replace(/\.tsx?$/, "");
    const usos = TODAS.filter(
      (f) => f.caminho !== caminho && new RegExp(`\\b${nome}\\b`).test(f.texto),
    );

    expect(
      usos.map((u) => u.caminho),
      `${caminho} não é importado nem citado por ninguém. Componente órfão é ` +
        `onde o que foi recusado espera: compila, não aparece, e um dia alguém ` +
        `acha que "já está pronto". Se ele morreu, apague; se não morreu, ` +
        `desenhe em algum lugar.`,
    ).not.toEqual([]);
  });
});

/**
 * O vocabulário do que foi recusado, na tela dela.
 *
 * Cada linha aqui é uma decisão do `CLAUDE.md` §4 ou §6, e nenhuma é de gosto:
 *
 * · **gamificação, streak, badge, elogio** — o produto não parabeniza. Ocupação
 *   alta não é conquista: comemorar isso é empurrar alguém a eliminar o próprio
 *   tempo de registro e de descanso, e a tela de uma psicóloga não faz isso.
 * · **número projetado como argumento** — o simulador de ROI morreu por isso.
 *   Número na tela é promessa mais forte que qualquer frase, e projeção é
 *   hipótese não demonstrada com cara de fato.
 * · **reativar ex-paciente, preço promocional, desconto de retorno** — é o
 *   Código de Ética, e a fronteira mais afiada do produto: frequência clínica
 *   não é decisão de software.
 *
 * A varredura lê **texto de tela** — nó de JSX e rótulo —, nunca comentário: é
 * no comentário que estas palavras precisam aparecer, para explicar por que
 * estão proibidas.
 */
const MORTOS = [
  {
    o_que: "gamificação e elogio",
    termos: /\bparabéns\b|\bconquist|\bmedalha|\bbadge\b|\bstreak\b|\btroféu|você bateu a meta|mandou bem|isso a[íi]!/i,
    porque:
      "o produto não parabeniza. Ocupação alta não é conquista — comemorar é empurrar alguém a eliminar o próprio descanso.",
  },
  {
    o_que: "número projetado como argumento",
    termos: /você (pode|poderia) (ganhar|recuperar|faturar)|deixa de ganhar|economia estimada|proje[çc][ãa]o de receita|quanto você ganharia/i,
    porque:
      "é o simulador de ROI voltando por outra porta. Projeção é hipótese não demonstrada com cara de fato, e número é promessa mais forte que frase.",
  },
  {
    o_que: "reativação e preço promocional",
    termos: /reativar (o |a )?(ex-)?paciente|preço promocional|desconto de retorno|volte com desconto|traga (de volta|um amigo)/i,
    porque:
      "frequência clínica não é decisão de software, e dinheiro não compra posição na fila. É o Código de Ética, não preferência.",
  },
] as const;

/** O que vira pixel: nó de JSX e os atributos que a pessoa lê. */
function fala(texto: string): string[] {
  const limpo = texto
    .replace(/className=\{`[^`]*`\}/g, " ")
    .replace(/className=\{[^}]*\}/g, " ")
    .replace(/className="[^"]*"/g, " ");

  return [
    ...[...limpo.matchAll(/>([^<>{}]{4,})</g)].map((m) => m[1]),
    ...[...limpo.matchAll(/(?:rotulo|dica|placeholder|title|aria-label|mensagem)="([^"]{4,})"/g)].map(
      (m) => m[1],
    ),
    ...[...limpo.matchAll(/"([^"\n]{8,})"/g)]
      .map((m) => m[1])
      .filter((t) => /\s/.test(t) && !/[_/(){}<>=]/.test(t)),
  ].map((t) => t.replace(/\s+/g, " ").trim());
}

describe("o vocabulário do que foi recusado não aparece em tela", () => {
  const TELAS = TODAS.filter(
    (f) => f.caminho.startsWith("app/") || f.caminho.startsWith("components/"),
  );

  it.each(MORTOS.map((m) => [m.o_que, m] as const))("%s", (_o, regra) => {
    const achados = TELAS.flatMap((f) =>
      fala(f.texto)
        .filter((t) => regra.termos.test(t))
        .map((t) => `${f.caminho}: "${t}"`),
    );
    expect(achados, `${regra.porque}\n${achados.join("\n")}`).toEqual([]);
  });
});

/**
 * E o simulador em particular, pelo nome.
 *
 * Não é redundante com a varredura de órfãos: ele pode voltar **importado**, e
 * aí deixa de ser órfão e passa a ser pior. O `_arquivadas.md` guarda o motivo
 * inteiro; aqui fica o nome.
 */
describe("o simulador de ROI não volta", () => {
  it("o arquivo não existe", () => {
    expect(existsSync(join(RAIZ, "components/site/Simulador.tsx"))).toBe(false);
  });

  it("ninguém o importa", () => {
    const achados = TODAS.filter((f) => /\bSimulador\b/.test(f.texto)).map((f) => f.caminho);
    expect(
      achados,
      "o simulador de ROI calculava hora recuperada em aritmética de padaria e " +
        "era o argumento mais forte da landing — o que é exatamente o problema. " +
        "Ver docs/builds/_arquivadas.md.",
    ).toEqual([]);
  });
});
