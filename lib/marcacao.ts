import { slugDe, urlDeLinkSegura, urlDeFiguraSegura } from "@/lib/blog";

/**
 * A marcação restrita do blog — e por que ela não é "markdown".
 *
 * A 0051 fechou com uma previsão: *"essa tentação chega num dia em que eu vou
 * querer negrito"*. Chegou. A resposta não foi afrouxar a recusa; foi construir
 * o caminho que dá negrito **sem** abrir a porta.
 *
 * A DIFERENÇA QUE IMPORTA, E É DE TIPO
 *
 * Uma biblioteca de markdown devolve **string de HTML**, e quem recebe string
 * de HTML precisa jogá-la na página com `dangerouslySetInnerHTML`. A partir daí
 * a segurança da página inteira passa a depender de o sanitizador estar certo,
 * estar atualizado e ter sido chamado em todos os caminhos.
 *
 * Este arquivo devolve uma **árvore tipada**. Olhe os tipos `Bloco` e `Trecho`:
 * não existe nenhum caso capaz de carregar HTML. Não há `{ t: "html" }`, e o
 * compilador recusa quem tentar acrescentar um sem mexer aqui. A tela percorre
 * a árvore e monta elementos React — texto vira texto, e não há passo em que
 * uma string possa ser interpretada como marcação de página.
 *
 * Isso é diferente de escapar depois. Escapar é uma defesa que alguém pode
 * esquecer de aplicar num caminho novo; **não existir o nó** é uma defesa que
 * não depende de ninguém lembrar de nada. O teste de estrutura que reprova
 * `dangerouslySetInnerHTML` no repositório inteiro continua de pé.
 *
 * O QUE A MARCAÇÃO TEM, E POR QUE PAROU AÍ
 *
 *   ## subtítulo · ### sub-subtítulo
 *   - item de lista        1. item numerado
 *   > citação
 *   **negrito**            *itálico*
 *   [rótulo](endereço)     ![alternativa](endereço da figura)
 *   ---                    (separador)
 *
 * Não há tabela, nem HTML embutido, nem `iframe`, nem vídeo, nem código com
 * destaque de sintaxe. Cada um deles é útil e cada um deles é uma porta; a
 * régua é "isto serve para escrever sobre consultório de psicologia?" — e as
 * seis coisas acima servem.
 *
 * O ASTERISCO SIMPLES NÃO ABRE LISTA
 *
 * Em markdown, `* item` é lista e `*palavra*` é itálico, e a diferença é um
 * espaço. Num texto em português cheio de asteriscos usados como asterisco, isso
 * vira defeito silencioso. Aqui lista é só `- `, e o asterisco é sempre ênfase.
 *
 * ENDEREÇO QUE NÃO PASSA VIRA TEXTO, NÃO SOME
 *
 * Um link com `javascript:` não vira link e **também não desaparece**: vira o
 * texto literal que a pessoa escreveu. Sumir esconderia o engano; virar texto
 * mostra que algo ali não funcionou como ela esperava.
 */

// ============================================================ os tipos

export type Trecho =
  | { t: "texto"; v: string }
  | { t: "negrito"; v: string }
  | { t: "italico"; v: string }
  | { t: "link"; v: string; href: string; externo: boolean };

export type Bloco =
  | { b: "paragrafo"; trechos: Trecho[] }
  | { b: "subtitulo"; nivel: 2 | 3; texto: string; ancora: string }
  | { b: "lista"; ordenada: boolean; itens: Trecho[][] }
  | { b: "citacao"; trechos: Trecho[] }
  | { b: "figura"; url: string; alt: string }
  | { b: "separador" };

// ============================================================ o inline

const LINK = /\[([^\]\n]+)\]\(([^)\s]+)\)/;
const NEGRITO = /\*\*([^*\n]+)\*\*/;
const ITALICO = /\*([^*\n]+)\*/;

/** Endereço de fora do próprio site — a tela põe `rel="noopener"` nesses. */
export function eExterno(href: string): boolean {
  return /^https?:\/\//i.test(href.trim());
}

/**
 * Uma linha de texto vira trechos.
 *
 * A ordem das tentativas é link → negrito → itálico, e ela não é estética: o
 * rótulo de um link pode conter asterisco, e resolver ênfase primeiro
 * despedaçaria o `[...]` antes de alguém olhar para ele.
 */
export function trechos(linha: string): Trecho[] {
  const saida: Trecho[] = [];
  let resto = linha;

  const empurra = (v: string) => {
    if (v === "") return;
    const ultimo = saida[saida.length - 1];
    if (ultimo && ultimo.t === "texto") ultimo.v += v;
    else saida.push({ t: "texto", v });
  };

  let guarda = 0;
  while (resto !== "" && guarda++ < 500) {
    const mLink = LINK.exec(resto);
    const mNeg = NEGRITO.exec(resto);
    const mIta = ITALICO.exec(resto);

    const candidatos = [
      mLink ? { i: mLink.index, tipo: "link" as const, m: mLink } : null,
      mNeg ? { i: mNeg.index, tipo: "negrito" as const, m: mNeg } : null,
      mIta ? { i: mIta.index, tipo: "italico" as const, m: mIta } : null,
    ].filter((c) => c !== null);

    if (candidatos.length === 0) {
      empurra(resto);
      break;
    }

    // O que começa antes ganha; empatando, o link, depois o negrito. O empate
    // acontece de verdade: `**a**` casa negrito no índice 0 e itálico também.
    const peso = { link: 0, negrito: 1, italico: 2 };
    candidatos.sort((a, b) => a.i - b.i || peso[a.tipo] - peso[b.tipo]);
    const escolhido = candidatos[0];

    empurra(resto.slice(0, escolhido.i));

    if (escolhido.tipo === "link") {
      const rotulo = escolhido.m[1];
      const href = escolhido.m[2].trim();
      if (urlDeLinkSegura(href)) {
        saida.push({ t: "link", v: rotulo, href, externo: eExterno(href) });
      } else {
        // Não some: vira o texto literal, para o engano ficar visível.
        empurra(escolhido.m[0]);
      }
    } else if (escolhido.tipo === "negrito") {
      saida.push({ t: "negrito", v: escolhido.m[1] });
    } else {
      saida.push({ t: "italico", v: escolhido.m[1] });
    }

    resto = resto.slice(escolhido.i + escolhido.m[0].length);
  }

  return saida;
}

// ============================================================ os blocos

const FIGURA = /^!\[([^\]\n]*)\]\(([^)\s]+)\)$/;

/**
 * O corpo inteiro vira blocos.
 *
 * Linha em branco separa. Dentro de um parágrafo, quebras de linha viram
 * espaço — como em qualquer editor de texto corrido, e para que um parágrafo
 * escrito com a janela estreita não vire cinco parágrafos na tela de quem lê.
 */
export function blocos(corpo: string): Bloco[] {
  const linhas = corpo.replace(/\r\n/g, "\n").split("\n");
  const saida: Bloco[] = [];

  let paragrafo: string[] = [];
  let citacao: string[] = [];
  let lista: { ordenada: boolean; itens: string[] } | null = null;

  const fechaParagrafo = () => {
    if (paragrafo.length === 0) return;
    saida.push({ b: "paragrafo", trechos: trechos(paragrafo.join(" ")) });
    paragrafo = [];
  };
  const fechaCitacao = () => {
    if (citacao.length === 0) return;
    saida.push({ b: "citacao", trechos: trechos(citacao.join(" ")) });
    citacao = [];
  };
  const fechaLista = () => {
    if (lista === null) return;
    saida.push({
      b: "lista",
      ordenada: lista.ordenada,
      itens: lista.itens.map((i) => trechos(i)),
    });
    lista = null;
  };
  const fechaTudo = () => {
    fechaParagrafo();
    fechaCitacao();
    fechaLista();
  };

  for (const bruta of linhas) {
    const linha = bruta.trimEnd();
    const seca = linha.trim();

    if (seca === "") {
      fechaTudo();
      continue;
    }

    if (/^-{3,}$/.test(seca)) {
      fechaTudo();
      saida.push({ b: "separador" });
      continue;
    }

    const mFig = FIGURA.exec(seca);
    if (mFig) {
      fechaTudo();
      const url = mFig[2].trim();
      const alt = mFig[1].trim();
      // Figura sem endereço aceitável não vira imagem quebrada: vira o texto,
      // pelo mesmo motivo do link.
      if (urlDeFiguraSegura(url)) saida.push({ b: "figura", url, alt });
      else saida.push({ b: "paragrafo", trechos: [{ t: "texto", v: seca }] });
      continue;
    }

    const mSub = /^(#{2,3})\s+(.*)$/.exec(seca);
    if (mSub) {
      fechaTudo();
      const texto = mSub[2].trim();
      saida.push({
        b: "subtitulo",
        nivel: mSub[1].length === 2 ? 2 : 3,
        texto,
        ancora: slugDe(texto) || "secao",
      });
      continue;
    }

    const mCit = /^>\s?(.*)$/.exec(seca);
    if (mCit) {
      fechaParagrafo();
      fechaLista();
      citacao.push(mCit[1].trim());
      continue;
    }

    const mNum = /^(\d{1,2})[.)]\s+(.*)$/.exec(seca);
    const mItem = /^-\s+(.*)$/.exec(seca);

    if (mItem || mNum) {
      fechaParagrafo();
      fechaCitacao();
      const ordenada = mNum !== null && mItem === null;
      const texto = (mItem ? mItem[1] : mNum![2]).trim();
      if (lista === null || lista.ordenada !== ordenada) {
        fechaLista();
        lista = { ordenada, itens: [] };
      }
      lista.itens.push(texto);
      continue;
    }

    fechaCitacao();
    fechaLista();
    paragrafo.push(seca);
  }

  fechaTudo();
  return saida;
}

// ============================================================ o que se lê deles

/** O texto sem marcação nenhuma — para contar palavras e sugerir o resumo. */
export function textoPuro(lista: Bloco[]): string {
  const doTrecho = (t: Trecho) => t.v;
  const partes: string[] = [];

  for (const bl of lista) {
    if (bl.b === "paragrafo" || bl.b === "citacao") partes.push(bl.trechos.map(doTrecho).join(""));
    else if (bl.b === "subtitulo") partes.push(bl.texto);
    else if (bl.b === "lista") partes.push(bl.itens.map((i) => i.map(doTrecho).join("")).join(" "));
  }

  return partes.join("\n\n").trim();
}

/** O primeiro parágrafo de verdade — o que a vitrine mostra quando não há resumo. */
export function primeiroParagrafo(lista: Bloco[]): string {
  for (const bl of lista) {
    if (bl.b === "paragrafo") {
      const t = bl.trechos.map((x) => x.v).join("").trim();
      if (t !== "") return t;
    }
  }
  return "";
}

export function palavras(corpo: string): number {
  return textoPuro(blocos(corpo)).split(/\s+/).filter(Boolean).length;
}

/** As figuras do corpo, na ordem — a tela usa para avisar de alternativa vazia. */
export function figurasDoCorpo(lista: Bloco[]): { url: string; alt: string }[] {
  return lista.filter((b) => b.b === "figura").map((b) => ({ url: b.url, alt: b.alt }));
}

export function subtitulos(lista: Bloco[]): { nivel: 2 | 3; texto: string; ancora: string }[] {
  return lista
    .filter((b) => b.b === "subtitulo")
    .map((b) => ({ nivel: b.nivel, texto: b.texto, ancora: b.ancora }));
}

export function links(lista: Bloco[]): { rotulo: string; href: string; externo: boolean }[] {
  const saida: { rotulo: string; href: string; externo: boolean }[] = [];
  const varre = (ts: Trecho[]) => {
    for (const t of ts) if (t.t === "link") saida.push({ rotulo: t.v, href: t.href, externo: t.externo });
  };
  for (const bl of lista) {
    if (bl.b === "paragrafo" || bl.b === "citacao") varre(bl.trechos);
    else if (bl.b === "lista") bl.itens.forEach(varre);
  }
  return saida;
}

/**
 * A leitura de um corpo, respeitando o formato gravado.
 *
 * `'texto'` é o de antes da 0054: parágrafo puro, e **nenhum caractere
 * reinterpretado**. Um texto publicado em 0051 que tenha `*` no meio continua
 * com `*` no meio. É a invariante 2 da 0054 chegando na tela.
 */
export function lerCorpo(corpo: string, formato: string): Bloco[] {
  if (formato !== "marcacao") {
    return corpo
      .replace(/\r\n/g, "\n")
      .split(/\n\s*\n/)
      .map((p) => p.trim())
      .filter((p) => p.length > 0)
      .map((p) => ({ b: "paragrafo", trechos: [{ t: "texto", v: p }] }) as Bloco);
  }
  return blocos(corpo);
}
