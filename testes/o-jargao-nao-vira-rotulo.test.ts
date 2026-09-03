import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * O jargão do sistema não aparece na tela dela.
 *
 * O Manual da casa tem uma tabela para isto, e ela não é preciosismo de
 * redação: *eixo · livro-razão · cockpit · capacidade vendável · completude ·
 * lastro · régua · materializar* são palavras que descrevem **como o produto
 * foi construído**. Quem lê a tela está tentando saber o que aconteceu com o
 * dinheiro e com a agenda dela, e nenhuma dessas palavras responde isso.
 *
 * O teste do público, que é o mesmo do Manual: cada frase da interface se
 * explica para uma psicóloga em uma frase? "O livro-razão" não. "O que
 * aconteceu com cada hora" sim — e é a mesma tela.
 *
 * **Onde ele procura, e por que só ali.** Só em texto que vira pixel: nó de
 * JSX e literal de string com cara de frase. Comentário fica de fora de
 * propósito — o vocabulário interno é o vocabulário dos comentários, e trocar
 * "eixo" por perífrase no comentário deixaria o código pior para quem o
 * mantém. Identificador também fica de fora: `EixoAgenda`, `lastro.temContrato`
 * e `regua_ativa` são nomes de coisa, não frases.
 *
 * É a terceira varredura desta fila a começar pelo `semComentarios`, e pela
 * terceira razão idêntica: um teste que lê o parágrafo que explica o defeito
 * acha o defeito onde ele já foi consertado, e passa onde ele voltou.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
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

/**
 * O que a pessoa lê: nó de texto do JSX e literal com cara de frase.
 *
 * `className` sai antes de tudo — uma classe do Tailwind é uma string com
 * espaço, e sem tirá-la a varredura passaria a vida lendo utilitário de CSS.
 */
function fala(fonte: string): string[] {
  const limpo = semComentarios(fonte)
    .replace(/className=\{`[^`]*`\}/g, " ")
    .replace(/className=\{[^}]*\}/g, " ")
    .replace(/className="[^"]*"/g, " ")
    .replace(/^import[^\n]*$/gm, " ");

  // Nó de JSX: o que fica entre uma tag e outra. Pedaço que traz aspas, ponto
  // e vírgula ou seta é código que escapou entre um `>` de genérico e um `<` de
  // tag — não é frase, e ler como frase enche a varredura de ruído.
  const nosDeJsx = [...limpo.matchAll(/>([^<>{}]{3,})</g)]
    .map((m) => m[1])
    .filter((t) => !/["`;]|=>/.test(t));
  const literais = [...limpo.matchAll(/"([^"\n]{6,})"/g)]
    .map((m) => m[1])
    // Frase tem espaço, e não tem cara de caminho, seletor, lista de coluna,
    // rótulo de `db()` (`"[risco] falhou o cockpit"`) nem pedaço de código que
    // escapou entre duas aspas de linhas diferentes.
    .filter(
      (t) =>
        /\s/.test(t) &&
        !t.startsWith("[") &&
        !/[_/(){}<>=]|^[a-z]+,|\.\w+\b/.test(t),
    );

  return [...nosDeJsx, ...literais].map((t) => t.replace(/\s+/g, " ").trim());
}

/**
 * O backoffice fica de fora, e é decisão — não conveniência.
 *
 * `/negocio` e os componentes dele são a minha tela, não a dela: ali "a régua
 * correndo" e "quem saiu" são exatamente o vocabulário certo, porque quem lê
 * construiu o sistema. A regra do Manual é sobre a tela da profissional; aplicar
 * a mesma perífrase no painel do operador deixaria as duas piores.
 */
const SO_DELA = (caminho: string) =>
  !caminho.startsWith("app/(app)/negocio") && !/components\/app\/Negocio/.test(caminho);

/**
 * **A página pública entrou em 03/09, e ela era o buraco.**
 *
 * A varredura lia só a área logada, e o jargão estava no texto que vem antes
 * dela: a página de preços dizia *"Sem faixa de sessões"* em dois cartões e
 * *"Régua de atraso impessoal"* num terceiro, e a landing dizia *"quando você
 * interrompe a régua"*. As duas regras já estavam declaradas aqui embaixo,
 * com a perífrase pronta — só ninguém olhava para lá.
 *
 * O efeito é o pior possível para uma regra de vocabulário: o produto usava a
 * linguagem certa depois que ela assinava e a errada enquanto ela decidia se
 * assinava. Quem lê a landing ainda não tem contexto nenhum para adivinhar o
 * que "faixa" e "régua" querem dizer.
 *
 * `lib/planos.ts` entra na varredura por nome: ele não é tela, é a fonte dos
 * cartões que a landing renderiza — o texto sai daqui e vira pixel lá.
 */
const PUBLICO = ["app/(site)", "components/site"];

const TELAS = ["app/(app)", "components/app", ...PUBLICO]
  .flatMap((d) => arquivos(join(RAIZ, d)))
  .concat([join(RAIZ, "lib/planos.ts")])
  .filter((c) => SO_DELA(relative(RAIZ, c)))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    frases: fala(readFileSync(caminho, "utf8")),
  }));

/**
 * As palavras, e a consequência que se escreve no lugar de cada uma.
 *
 * A coluna da direita não é decoração: ela é o conserto, e existe para o
 * próximo achado não terminar em "tirei a palavra e a frase ficou sem sentido".
 */
const JARGAO: { termo: RegExp; palavra: string; escreva: string }[] = [
  { termo: /livro[- ]raz[ãa]o/i, palavra: "livro-razão", escreva: "o que aconteceu com cada hora" },
  { termo: /\beixos?\b/i, palavra: "eixo", escreva: "o que a agenda diz, se o dinheiro entrou…" },
  { termo: /materializ\w*/i, palavra: "materializar", escreva: "montada até 27/10" },
  { termo: /\blastro\b/i, palavra: "lastro", escreva: "o que dá base à cobrança" },
  { termo: /\br[ée]gua\b/i, palavra: "régua", escreva: "ver quem está devendo" },
  { termo: /capacidade vend[áa]vel/i, palavra: "capacidade vendável", escreva: "as horas que você declarou" },
  { termo: /\bcompletude\b/i, palavra: "completude", escreva: "dá para confiar neste mês?" },
  { termo: /faixa de sess[õo]es/i, palavra: "faixa (cota de plano)", escreva: "as sessões que o seu plano inclui" },
  { termo: /cockpit/i, palavra: "cockpit", escreva: "os quatro números do mês" },
];

/**
 * A promessa que a 0058 desfez.
 *
 * O software parou de cobrar sozinho quando o P4 trocou o silêncio-que-cobra
 * pelo silêncio-que-não-cobra: hoje nada é cobrado antes de ela decidir, na
 * caixa "A decidir". Três telas continuavam dizendo o contrário — e essa é a
 * "promessa que o software não cumpre", ao contrário: aqui o software fazia
 * **menos** do que a tela dizia, o que é pior, porque ela pode estar esperando
 * uma cobrança que nunca vai sair.
 */
const PROMESSAS_MORTAS = [
  { termo: /cobran[çc]a autom[áa]tica/i, o_que: '"cobrança automática" — a 0058 tirou a cobrança do software' },
  { termo: /a pol[íi]tica cobrou/i, o_que: '"a política cobrou" — quem cobrou foi ela, na caixa "A decidir"' },
];

describe("o jargão do sistema não vira rótulo de tela", () => {
  it("a varredura está lendo texto de tela", () => {
    expect(TELAS.length).toBeGreaterThan(40);
    const todas = TELAS.flatMap((t) => t.frases);
    expect(todas.length).toBeGreaterThan(300);
    // Um controle: uma frase que existe mesmo tem de ser encontrada.
    expect(todas.some((f) => /Quanto da sua capacidade virou receita/.test(f))).toBe(true);
  });

  it.each(JARGAO.map((j) => [j.palavra, j] as const))(
    '"%s" não aparece em texto de tela',
    (_p, regra) => {
      const achados = TELAS.flatMap((t) =>
        t.frases.filter((f) => regra.termo.test(f)).map((f) => `${t.caminho}: "${f}"`),
      );
      expect(
        achados,
        `"${regra.palavra}" é vocabulário do sistema, não da profissional. ` +
          `Escreva a consequência: "${regra.escreva}".\n` + achados.join("\n"),
      ).toEqual([]);
    },
  );

  it.each(PROMESSAS_MORTAS.map((p) => [p.o_que, p] as const))(
    "nenhuma tela ainda diz %s",
    (_o, regra) => {
      const achados = TELAS.flatMap((t) =>
        t.frases.filter((f) => regra.termo.test(f)).map((f) => `${t.caminho}: "${f}"`),
      );
      expect(achados, achados.join("\n")).toEqual([]);
    },
  );

  /**
   * O número de passos do começo não é constante literal em tela nenhuma.
   *
   * A agenda dizia "três passos" e a página se chamava "cinco passos", e as
   * duas contavam de cabeça. Quem conta agora é `lib/comecar.ts`; escrever o
   * número à mão é reabrir a divergência.
   */
  it("nenhuma tela escreve de quantos passos é o começo", () => {
    const achados = TELAS.flatMap((t) =>
      t.frases
        .filter((f) => /\b(dois|três|quatro|cinco|seis)\s+passos\b/i.test(f))
        .map((f) => `${t.caminho}: "${f}"`),
    );
    expect(
      achados,
      "o número de passos sai de `faltando()` em lib/comecar.ts — escrever à mão " +
        "é como a agenda passou a dizer três numa página que se chamava cinco.\n" +
        achados.join("\n"),
    ).toEqual([]);
  });
});
