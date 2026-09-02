import { describe, it, expect } from "vitest";
import {
  CORTE_TITULO,
  CORTE_DESCRICAO,
  ondeCorta,
  conferencia,
  quantosFaltam,
  metaDoPost,
  jsonLdDoPost,
  jsonLdSeguro,
  chamadaDaVitrine,
  type PostParaConferir,
} from "@/lib/seo";

/**
 * Os testes que decidem este arquivo são dois, e nenhum dos dois é sobre
 * formatação:
 *
 *   · "não inventa regra que a documentação não tem" — a conferência não pode
 *     reprovar por contagem de palavras nem por descrição longa, porque a
 *     documentação do Google diz que não existe nem limite nem mínimo;
 *   · "o JSON-LD não fecha o script" — a única defesa real do bloco de dados
 *     estruturados.
 */

const BASE: PostParaConferir = {
  titulo: "Como registrar a sessão sem virar tarefa de domingo",
  slug: "registrar-a-sessao",
  resumo: "O que o Manual do CFP pede no registro, e o que dá para fazer em dois minutos entre um atendimento e outro.",
  corpo: [
    "## O que a norma pede",
    "",
    "O Manual de 2025 lista quatro blocos, e o [texto oficial](/blog/manual) explica cada um.",
    "",
    "![Uma mesa com caderno](/blog/mesa.png)",
  ].join("\n"),
  formato: "marcacao",
  figura_url: "/blog/capa.png",
  figura_alt: "Uma sala de atendimento com duas poltronas",
  figura_largura: 1200,
  figura_altura: 630,
  canonica: "",
  indexavel: true,
};

const item = (p: PostParaConferir, id: string) => {
  const i = conferencia(p).find((x) => x.id === id);
  if (!i) throw new Error(`item ${id} não existe na conferência`);
  return i;
};

describe("onde a frase costuma cortar", () => {
  it("diz o que sobra, e não recusa", () => {
    expect(ondeCorta("abc", 10)).toEqual({ cabe: "abc", sobra: "" });
    expect(ondeCorta("abcdefghij", 4)).toEqual({ cabe: "abcd", sobra: "efghij" });
  });

  it("os números são observação, e ficam nas faixas em que a busca de fato corta", () => {
    expect(CORTE_TITULO).toBeGreaterThanOrEqual(50);
    expect(CORTE_TITULO).toBeLessThanOrEqual(70);
    expect(CORTE_DESCRICAO).toBeGreaterThanOrEqual(120);
    expect(CORTE_DESCRICAO).toBeLessThanOrEqual(200);
  });
});

describe("a conferência não inventa regra que a documentação não tem", () => {
  it("texto curto NÃO é reprovado — não existe contagem mágica de palavras", () => {
    const p = { ...BASE, corpo: "Um texto de trinta palavras não é pecado nenhum, e reprovar por isso ensina a encher linguiça." };
    expect(item(p, "tamanho").estado).toBe("ok");
    expect(item(p, "tamanho").frase).toContain("Não existe número mínimo");
  });

  it("resumo longo NÃO é reprovado — a documentação diz que não há limite", () => {
    const p = { ...BASE, resumo: "a".repeat(320) };
    const r = item(p, "resumo");
    expect(r.estado).toBe("ok");
    expect(r.frase).toContain("Não há limite");
  });

  it("nenhuma frase promete posição na busca", () => {
    const tudo = conferencia(BASE).map((i) => i.frase).join(" ");
    expect(tudo).not.toMatch(/primeira página|rankear|ranquear|melhora sua posição|sobe no Google/i);
  });

  it("nenhum item é uma nota", () => {
    for (const i of conferencia(BASE)) {
      expect(["ok", "atencao", "falta"]).toContain(i.estado);
      expect(i).not.toHaveProperty("nota");
      expect(i).not.toHaveProperty("pontos");
      expect(i).not.toHaveProperty("peso");
    }
  });

  it("o subtítulo ausente em texto longo é acessibilidade, e a frase diz isso", () => {
    const p = { ...BASE, corpo: "palavra ".repeat(500) };
    const s = item(p, "subtitulos");
    expect(s.estado).toBe("atencao");
    expect(s.frase).toContain("não muda posição");
  });
});

describe("a conferência cobra o que de fato está documentado", () => {
  it("título comprido avisa onde costuma cortar, sem reprovar", () => {
    const p = { ...BASE, titulo: "Um título propositalmente muito comprido para ultrapassar a largura que cabe num celular pequeno" };
    const t = item(p, "titulo");
    expect(t.estado).toBe("atencao");
    expect(t.frase).toContain("corta pela largura da tela");
  });

  it("endereço só de números é apontado", () => {
    expect(item({ ...BASE, slug: "2026-09-02" }, "endereco").estado).toBe("atencao");
    expect(item(BASE, "endereco").estado).toBe("ok");
  });

  it("resumo vazio falta — é o que o buscador mostra e o que a vitrine usa", () => {
    expect(item({ ...BASE, resumo: "" }, "resumo").estado).toBe("falta");
  });

  it("capa sem alternativa falta, e a frase fala de leitor de tela", () => {
    const c = item({ ...BASE, figura_alt: "" }, "capa");
    expect(c.estado).toBe("falta");
    expect(c.frase).toContain("leitor de tela");
  });

  it("capa sem medidas é atenção, e a frase explica o pulo do texto", () => {
    const c = item({ ...BASE, figura_largura: null, figura_altura: null }, "capa");
    expect(c.estado).toBe("atencao");
    expect(c.frase).toContain("pula");
  });

  it("figura do corpo sem alternativa falta", () => {
    const p = { ...BASE, corpo: "Um parágrafo qualquer.\n\n![](/blog/x.png)" };
    expect(item(p, "figuras").estado).toBe("falta");
  });

  it("link com rótulo vago é apontado, com o rótulo na frase", () => {
    const p = { ...BASE, corpo: "Veja o material [clique aqui](/blog/x) para abrir." };
    const l = item(p, "links");
    expect(l.estado).toBe("atencao");
    expect(l.frase).toContain("clique aqui");
  });

  it("texto sem link nenhum é atenção", () => {
    expect(item({ ...BASE, corpo: "Um texto sem link nenhum, e nada mais." }, "links").estado)
      .toBe("atencao");
  });

  it("a canônica e o não indexável só aparecem quando existem", () => {
    expect(conferencia(BASE).some((i) => i.id === "canonica")).toBe(false);
    expect(conferencia(BASE).some((i) => i.id === "indexavel")).toBe(false);
    expect(conferencia({ ...BASE, canonica: "https://x.invalido/a" }).some((i) => i.id === "canonica")).toBe(true);
    expect(conferencia({ ...BASE, indexavel: false }).some((i) => i.id === "indexavel")).toBe(true);
  });

  it("um texto pronto não tem nada faltando", () => {
    expect(quantosFaltam(conferencia(BASE))).toBe(0);
  });

  it("um texto vazio tem o que falta, na ordem em que dá para resolver", () => {
    const vazio: PostParaConferir = {
      titulo: "", slug: "", resumo: "", corpo: "", formato: "marcacao",
      figura_url: "", figura_alt: "", figura_largura: null, figura_altura: null,
      canonica: "", indexavel: true,
    };
    const ids = conferencia(vazio).filter((i) => i.estado === "falta").map((i) => i.id);
    expect(ids.slice(0, 3)).toEqual(["titulo", "endereco", "resumo"]);
  });
});

describe("a conferência respeita o formato gravado", () => {
  it("em texto puro, asterisco não vira ênfase nem some da contagem", () => {
    const p = { ...BASE, formato: "texto", corpo: "Um *asterisco* que é asterisco mesmo." };
    expect(item(p, "tamanho").frase).toContain("6 palavras");
  });
});

describe("o que vai para a página", () => {
  const post = {
    titulo: "Registrar a sessão",
    slug: "registrar-a-sessao",
    resumo: null,
    corpo: "## Um título\n\nO **primeiro** parágrafo do texto.",
    formato: "marcacao",
    figura_url: "/blog/capa.png",
    figura_alt: "Uma sala",
    canonica: null,
    indexavel: true,
  };

  it("sem resumo, a descrição vem do texto SEM marcação", () => {
    const m = metaDoPost(post, "https://sessoes.com.br");
    expect(m.descricao).toContain("O primeiro parágrafo");
    expect(m.descricao).not.toContain("**");
    expect(m.descricao).not.toContain("##");
  });

  it("a canônica padrão é o próprio endereço", () => {
    expect(metaDoPost(post, "https://sessoes.com.br").canonica)
      .toBe("https://sessoes.com.br/blog/registrar-a-sessao");
  });

  it("a canônica declarada manda", () => {
    const m = metaDoPost({ ...post, canonica: "https://outro.invalido/x" }, "https://sessoes.com.br");
    expect(m.canonica).toBe("https://outro.invalido/x");
  });

  it("com resumo, é ele que vale", () => {
    expect(metaDoPost({ ...post, resumo: "A frase escolhida." }, "https://sessoes.com.br").descricao)
      .toBe("A frase escolhida.");
  });
});

describe("os dados estruturados", () => {
  const p = {
    titulo: "Registrar a sessão",
    slug: "registrar-a-sessao",
    descricao: "A frase.",
    publicado_em: "2026-09-01T12:00:00.000Z",
    atualizado_em: "2026-09-02T12:00:00.000Z",
    figura: "/blog/capa.png",
    autor: "Leandro",
    site: "Sessões",
    base: "https://sessoes.com.br",
  };

  it("declara o que existe e nada além", () => {
    const o = jsonLdDoPost(p);
    expect(o["@type"]).toBe("BlogPosting");
    expect(o.datePublished).toBe("2026-09-01T12:00:00.000Z");
    expect(o.image).toEqual(["https://sessoes.com.br/blog/capa.png"]);
  });

  it("o que não existe fica de fora — não há propriedade obrigatória a preencher", () => {
    const o = jsonLdDoPost({ ...p, publicado_em: null, atualizado_em: null, figura: null });
    expect(o).not.toHaveProperty("datePublished");
    expect(o).not.toHaveProperty("dateModified");
    expect(o).not.toHaveProperty("image");
    expect(o.headline).toBe("Registrar a sessão");
  });

  it("figura já absoluta não ganha o domínio duas vezes", () => {
    const o = jsonLdDoPost({ ...p, figura: "https://cdn.invalido/a.png" });
    expect(o.image).toEqual(["https://cdn.invalido/a.png"]);
  });

  it("O JSON-LD não fecha o script — é a defesa inteira do bloco", () => {
    const s = jsonLdSeguro(jsonLdDoPost({ ...p, titulo: 'Fim </script><script>alert(1)</script>' }));
    expect(s).not.toContain("</script>");
    expect(s).not.toContain("<");
    expect(s).not.toContain(">");
    expect(s).toContain("\\u003c");
    // e continua sendo JSON válido, com o título inteiro dentro
    expect(JSON.parse(s).headline).toContain("script");
  });

  it("escapa também os separadores de linha invisíveis", () => {
    const s = jsonLdSeguro({ a: "um dois tres" });
    expect(s).not.toContain(" ");
    expect(s).not.toContain(" ");
    expect(JSON.parse(s).a).toBe("um dois tres");
  });
});

describe("a frase da vitrine", () => {
  it("prefere o resumo", () => {
    expect(chamadaDaVitrine({ resumo: "A frase.", corpo: "outro", formato: "marcacao" }))
      .toBe("A frase.");
  });

  it("sem resumo, cai no primeiro parágrafo SEM marcação", () => {
    const f = chamadaDaVitrine({
      resumo: null,
      corpo: "## Um título\n\nO **primeiro** parágrafo.",
      formato: "marcacao",
    });
    expect(f).toBe("O primeiro parágrafo.");
    expect(f).not.toContain("**");
    expect(f).not.toContain("#");
  });

  it("corta com reticência em vez de cortar no meio da palavra sem aviso", () => {
    const f = chamadaDaVitrine({ resumo: null, corpo: "a".repeat(400), formato: "marcacao" }, 50);
    expect(f).toHaveLength(48);
    expect(f.endsWith("…")).toBe(true);
  });

  it("num texto de formato antigo, não reinterpreta nada", () => {
    expect(chamadaDaVitrine({ resumo: null, corpo: "Um *asterisco* mesmo.", formato: "texto" }))
      .toBe("Um *asterisco* mesmo.");
  });
});
