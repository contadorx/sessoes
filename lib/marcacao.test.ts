import { describe, it, expect } from "vitest";
import {
  trechos,
  blocos,
  lerCorpo,
  textoPuro,
  primeiroParagrafo,
  palavras,
  figurasDoCorpo,
  subtitulos,
  links,
  eExterno,
  type Bloco,
} from "@/lib/marcacao";

/**
 * O teste que decide o arquivo é o do grupo "a porta que continua fechada".
 * Ele não confere formatação: confere que **não existe caminho** por onde HTML
 * cru atravesse o interpretador.
 */

describe("a ênfase", () => {
  it("faz negrito e itálico", () => {
    expect(trechos("um **forte** e um *fraco*")).toEqual([
      { t: "texto", v: "um " },
      { t: "negrito", v: "forte" },
      { t: "texto", v: " e um " },
      { t: "italico", v: "fraco" },
    ]);
  });

  it("prefere negrito quando os dois casam no mesmo lugar", () => {
    expect(trechos("**dois**")).toEqual([{ t: "negrito", v: "dois" }]);
  });

  it("deixa asterisco solto em paz — em português ele é asterisco", () => {
    expect(trechos("a nota de rodapé * fica assim")).toEqual([
      { t: "texto", v: "a nota de rodapé * fica assim" },
    ]);
  });
});

describe("os links", () => {
  it("viram link quando o endereço é aceitável", () => {
    expect(trechos("veja o [contrato padrão](/termos) aqui")).toEqual([
      { t: "texto", v: "veja o " },
      { t: "link", v: "contrato padrão", href: "/termos", externo: false },
      { t: "texto", v: " aqui" },
    ]);
  });

  it("marcam o que é de fora, para a tela pôr rel=noopener", () => {
    const r = trechos("[CFP](https://site.cfp.org.br)");
    expect(r[0]).toEqual({
      t: "link",
      v: "CFP",
      href: "https://site.cfp.org.br",
      externo: true,
    });
    expect(eExterno("/blog/x")).toBe(false);
  });

  it("NÃO viram link com javascript: — e não somem, viram o texto escrito", () => {
    const r = trechos("clique em [aqui](javascript:alert(1)) para ver");
    expect(r.every((t) => t.t === "texto")).toBe(true);
    expect(r.map((t) => t.v).join("")).toContain("javascript:alert(1)");
  });

  it("também recusam data: e vbscript:", () => {
    for (const mau of ["data:text/html,<script>x</script>", "vbscript:msgbox", "  javascript:x"]) {
      const r = trechos(`[x](${mau})`);
      expect(r.some((t) => t.t === "link")).toBe(false);
    }
  });

  it("aceitam asterisco dentro do rótulo sem despedaçar o link", () => {
    const r = trechos("[o *manual* do CFP](/blog/manual)");
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ t: "link", href: "/blog/manual" });
  });
});

describe("os blocos", () => {
  const corpo = [
    "## O primeiro assunto",
    "",
    "Um parágrafo escrito",
    "em duas linhas.",
    "",
    "- primeiro item",
    "- segundo item",
    "",
    "1. um",
    "2. dois",
    "",
    "> uma citação",
    "",
    "![Uma sala de atendimento](/blog/sala.png)",
    "",
    "---",
    "",
    "### Um subassunto",
  ].join("\n");

  const bs = blocos(corpo);

  it("reconhece cada forma uma vez", () => {
    expect(bs.map((b) => b.b)).toEqual([
      "subtitulo",
      "paragrafo",
      "lista",
      "lista",
      "citacao",
      "figura",
      "separador",
      "subtitulo",
    ]);
  });

  it("junta as linhas de um parágrafo em vez de virar dois", () => {
    const p = bs[1];
    expect(p.b).toBe("paragrafo");
    if (p.b === "paragrafo") {
      expect(p.trechos.map((t) => t.v).join("")).toBe("Um parágrafo escrito em duas linhas.");
    }
  });

  it("separa lista com marca de lista numerada", () => {
    const a = bs[2];
    const b = bs[3];
    if (a.b === "lista" && b.b === "lista") {
      expect(a.ordenada).toBe(false);
      expect(b.ordenada).toBe(true);
      expect(a.itens).toHaveLength(2);
    } else {
      throw new Error("não vieram duas listas");
    }
  });

  it("dá âncora a cada subtítulo, para citar direto", () => {
    expect(subtitulos(bs)).toEqual([
      { nivel: 2, texto: "O primeiro assunto", ancora: "o-primeiro-assunto" },
      { nivel: 3, texto: "Um subassunto", ancora: "um-subassunto" },
    ]);
  });

  it("a figura carrega a alternativa que a pessoa escreveu", () => {
    expect(figurasDoCorpo(bs)).toEqual([
      { url: "/blog/sala.png", alt: "Uma sala de atendimento" },
    ]);
  });

  it("figura com endereço recusado vira texto, não imagem quebrada", () => {
    const b = blocos("![x](javascript:alert(1))");
    expect(b[0].b).toBe("paragrafo");
    expect(figurasDoCorpo(b)).toEqual([]);
  });

  it("figura em http simples é recusada — conteúdo misto some em produção", () => {
    expect(figurasDoCorpo(blocos("![x](http://exemplo.com/a.png)"))).toEqual([]);
    expect(figurasDoCorpo(blocos("![x](https://exemplo.com/a.png)"))).toHaveLength(1);
  });
});

describe("o formato gravado", () => {
  const cru = "Um texto com *asterisco* e ## cerquilha no meio.";

  it("em 'texto' nada é reinterpretado — é a invariante 2 da 0054", () => {
    const b = lerCorpo(cru, "texto");
    expect(b).toHaveLength(1);
    expect(b[0]).toEqual({ b: "paragrafo", trechos: [{ t: "texto", v: cru }] });
  });

  it("em 'marcacao' o mesmo texto ganha ênfase", () => {
    const b = lerCorpo(cru, "marcacao");
    const p = b[0];
    if (p.b !== "paragrafo") throw new Error("não veio parágrafo");
    expect(p.trechos.some((t) => t.t === "italico")).toBe(true);
  });

  it("formato desconhecido cai no seguro, não no interpretador", () => {
    const b = lerCorpo(cru, "qualquer-coisa");
    expect(b[0]).toEqual({ b: "paragrafo", trechos: [{ t: "texto", v: cru }] });
  });
});

describe("o que se lê da árvore", () => {
  const corpo = "## Título\n\nO **primeiro** parágrafo.\n\nO segundo.\n\n- item";

  it("o texto puro sai sem marcação nenhuma", () => {
    expect(textoPuro(blocos(corpo))).toBe("Título\n\nO primeiro parágrafo.\n\nO segundo.\n\nitem");
  });

  it("o primeiro parágrafo pula o subtítulo", () => {
    expect(primeiroParagrafo(blocos(corpo))).toBe("O primeiro parágrafo.");
  });

  it("conta palavras sem contar asterisco", () => {
    expect(palavras("**uma** *duas* três")).toBe(3);
  });

  it("lista os links de parágrafo, citação e item", () => {
    const c = "[a](/a)\n\n> [b](/b)\n\n- [c](/c)";
    expect(links(blocos(c)).map((l) => l.href)).toEqual(["/a", "/b", "/c"]);
  });
});

/**
 * O varredor que reprova `dangerously` + `SetInnerHTML` no repositório inteiro
 * mora em `lib/blog.test.ts` desde a 0051 e continua valendo para este arquivo
 * também. Ele não é repetido aqui: dois varredores da mesma coisa é o começo de
 * um deles ficar para trás.
 */
describe("a porta que continua fechada", () => {
  it("HTML no corpo é texto, e nada mais", () => {
    const b = blocos('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>');
    expect(b.every((x) => x.b === "paragrafo")).toBe(true);
    const t = textoPuro(b);
    expect(t).toContain("<script>");
    // sai como conteúdo de texto — quem monta a tela cria nós de texto do React
    expect(b.some((x) => x.b === "figura")).toBe(false);
  });

  it("não existe nó capaz de carregar HTML na árvore inteira", () => {
    // Percorre tudo o que o interpretador sabe produzir e confere que cada nó
    // cai num dos casos conhecidos. Um caso novo com nome parecido com html
    // reprova aqui antes de chegar na tela.
    const permitidos = new Set(["paragrafo", "subtitulo", "lista", "citacao", "figura", "separador"]);
    const corpo = [
      "## t", "p", "- i", "1. n", "> c", "![a](/b.png)", "---",
      "<div>x</div>", "[l](/x) **n** *i*",
    ].join("\n\n");
    for (const bl of blocos(corpo) as Bloco[]) {
      expect(permitidos.has(bl.b)).toBe(true);
      expect(Object.keys(bl)).not.toContain("html");
      expect(Object.keys(bl)).not.toContain("dangerously" + "SetInnerHTML");
    }
  });

});
