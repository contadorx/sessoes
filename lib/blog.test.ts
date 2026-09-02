import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  slugDe,
  slugValido,
  urlDeLinkSegura,
  urlDeFiguraSegura,
  estadoDoPost,
  rotuloDoEstado,
  explicaEstado,
  podeApagar,
  podeTrocarEndereco,
  porQueNaoApaga,
  paragrafos,
  minutosDeLeitura,
  linksValidos,
  problemaNosLinks,
  problemaNoPost,
  dataCurta,
  dataPorExtenso,
} from "./blog";

/**
 * Os mesmos valores esperados da suíte 0051.
 *
 * Onde uma regra existe dos dois lados — o `check` da coluna e a conferência da
 * tela —, o teste daqui usa **o mesmo caso** que a verificação de lá. Não é
 * duplicação: é o que faz uma divergência entre banco e app aparecer como teste
 * vermelho em vez de aparecer como um formulário que recusa o que o banco
 * aceita, ou pior, que aceita o que o banco recusa.
 */

const POST_BASE = {
  titulo: "Um título qualquer",
  slug: "um-titulo-qualquer",
  corpo: "Um corpo com mais de vinte caracteres para passar no check.",
  figura_url: "",
  figura_alt: "",
  resumo: "",
};

describe("o endereço", () => {
  it("deriva do título, e o acento vira letra", () => {
    expect(slugDe("A sessão que não aconteceu")).toBe("a-sessao-que-nao-aconteceu");
    expect(slugDe("Receita Saúde: o que muda")).toBe("receita-saude-o-que-muda");
  });

  it("não termina em hífen, nem quando o corte de 80 cai no meio de uma palavra", () => {
    const s = slugDe("a".repeat(78) + " palavra");
    expect(s.endsWith("-")).toBe(false);
    expect(s.length).toBeLessThanOrEqual(80);
  });

  it("aceita o que a coluna aceita", () => {
    expect(slugValido("a-sessao-que-nao-aconteceu")).toBe(true);
    expect(slugValido("post1")).toBe(true);
  });

  // Verificação 20 da suíte 0051, do lado de cá.
  it("recusa maiúscula, espaço e hífen solto — o endereço vai para a barra de alguém", () => {
    expect(slugValido("Suite 0051 Errado")).toBe(false);
    expect(slugValido("com espaco")).toBe(false);
    expect(slugValido("-comeca-com-hifen")).toBe(false);
    expect(slugValido("termina-com-hifen-")).toBe(false);
    expect(slugValido("dois--hifens")).toBe(false);
    expect(slugValido("ab")).toBe(false);
  });
});

describe("as URLs", () => {
  // Verificação 18 da suíte 0051.
  it("javascript: não é endereço de link", () => {
    expect(urlDeLinkSegura("javascript:alert(1)")).toBe(false);
    expect(urlDeLinkSegura("  javascript:alert(1)")).toBe(false);
  });

  // Verificação 19 da suíte 0051.
  it("data: não é figura", () => {
    expect(urlDeFiguraSegura("data:text/html,<script>alert(1)</script>")).toBe(false);
  });

  it("caminho do próprio site e https passam nos dois", () => {
    expect(urlDeLinkSegura("/blog/um-texto")).toBe(true);
    expect(urlDeLinkSegura("https://cfp.org.br")).toBe(true);
    expect(urlDeFiguraSegura("/blog/foto.png")).toBe(true);
    expect(urlDeFiguraSegura("https://exemplo.com/foto.png")).toBe(true);
  });

  it("figura é mais estreita que link: http simples vira conteúdo misto e some", () => {
    expect(urlDeLinkSegura("http://exemplo.com")).toBe(true);
    expect(urlDeFiguraSegura("http://exemplo.com/foto.png")).toBe(false);
  });
});

describe("o estado de um texto", () => {
  it("são três, e não dois", () => {
    expect(estadoDoPost({ publicado_em: null, visivel: false })).toBe("rascunho");
    expect(estadoDoPost({ publicado_em: "2026-09-01", visivel: true })).toBe("no_ar");
    expect(estadoDoPost({ publicado_em: "2026-09-01", visivel: false })).toBe("fora_do_ar");
  });

  it("rascunho e fora do ar não se confundem — um apaga, o outro não", () => {
    expect(podeApagar({ publicado_em: null })).toBe(true);
    expect(podeApagar({ publicado_em: "2026-09-01" })).toBe(false);
    expect(podeTrocarEndereco({ publicado_em: null })).toBe(true);
    expect(podeTrocarEndereco({ publicado_em: "2026-09-01" })).toBe(false);
  });

  it("o rótulo é curto e a explicação fala de consequência, não de definição", () => {
    expect(rotuloDoEstado("no_ar")).toBe("no ar");
    expect(rotuloDoEstado("fora_do_ar")).toBe("fora do ar");
    for (const e of ["rascunho", "no_ar", "fora_do_ar"] as const) {
      expect(explicaEstado(e).length).toBeGreaterThan(20);
    }
    // "Fica guardado" é a metade que importa: sem ela, tirar do ar parece apagar.
    expect(explicaEstado("fora_do_ar")).toMatch(/guardad/i);
  });

  it("a recusa de apagar manda para o caminho certo, em vez de só negar", () => {
    expect(porQueNaoApaga()).toMatch(/tire do ar/i);
  });
});

describe("o corpo", () => {
  it("linha em branco separa parágrafo, e só isso", () => {
    expect(paragrafos("um\n\ndois\n\n\ntrês")).toEqual(["um", "dois", "três"]);
    expect(paragrafos("uma linha\nquebrada")).toEqual(["uma linha\nquebrada"]);
    expect(paragrafos("   \n\n  ")).toEqual([]);
  });

  it("aguenta quebra de linha do Windows", () => {
    expect(paragrafos("um\r\n\r\ndois")).toEqual(["um", "dois"]);
  });

  it("o tempo de leitura nunca é zero minuto", () => {
    expect(minutosDeLeitura("uma frase curta")).toBe(1);
    expect(minutosDeLeitura("palavra ".repeat(400))).toBe(2);
  });
});

describe("os links", () => {
  // Verificação 24 da suíte 0051: três itens entram, dois saem.
  it("a linha pela metade é ignorada, e não recusa a lista inteira", () => {
    const lista = [
      { rotulo: "primeiro", url: "https://exemplo.invalido/a" },
      { rotulo: "", url: "https://exemplo.invalido/vazio" },
      { rotulo: "segundo", url: "/interno" },
    ];
    expect(linksValidos(lista)).toHaveLength(2);
    expect(problemaNosLinks(lista)).toBeNull();
  });

  it("mas uma URL que vira código é recusada, e a frase diz qual", () => {
    const p = problemaNosLinks([{ rotulo: "clique aqui", url: "javascript:alert(1)" }]);
    expect(p).toMatch(/clique aqui/);
    expect(p).toMatch(/https:\/\//);
  });
});

describe("o que a tela recusa antes de enviar", () => {
  it("um post inteiro e correto não tem problema", () => {
    expect(problemaNoPost(POST_BASE)).toBeNull();
  });

  it("a ordem das recusas é a ordem em que dá para resolver", () => {
    // Sem título e sem corpo: quem esqueceu o título ainda não escreveu nada,
    // então a frase tem de falar do título. É a lição da 0037b.
    const p = problemaNoPost({ ...POST_BASE, titulo: "", corpo: "" });
    expect(p).toMatch(/título/i);
  });

  it("corpo curto não vai ao ar — o mesmo check do banco", () => {
    expect(problemaNoPost({ ...POST_BASE, corpo: "curto" })).toMatch(/curto/i);
  });

  // Verificação 17 da suíte 0051.
  it("figura sem alternativa é recusada, e a frase diz por quê", () => {
    const p = problemaNoPost({ ...POST_BASE, figura_url: "/blog/foto.png", figura_alt: "" });
    expect(p).toMatch(/leitor de tela/i);
  });

  it("figura com alternativa passa", () => {
    expect(
      problemaNoPost({ ...POST_BASE, figura_url: "/blog/foto.png", figura_alt: "uma grade de horários" }),
    ).toBeNull();
  });

  it("resumo grande demais é recusado antes de o banco recusar", () => {
    expect(problemaNoPost({ ...POST_BASE, resumo: "x".repeat(401) })).toMatch(/resumo/i);
  });
});

describe("as datas", () => {
  it("curta é a do resto do produto", () => {
    expect(dataCurta("2026-09-03T10:00:00Z")).toBe("03/09/2026");
    expect(dataCurta(null)).toBe("—");
  });

  it("por extenso assina o texto publicado", () => {
    expect(dataPorExtenso("2026-09-03T10:00:00Z")).toBe("3 de setembro de 2026");
    expect(dataPorExtenso(null)).toBe("");
  });
});

// =====================================================================
// As duas verificações de estrutura
// =====================================================================
//
// Elas varrem arquivo, e não comportamento. Existem porque as duas tentações
// que elas guardam chegam **depois**, num dia em que a razão vai parecer boa:
// "só um negrito no post" e "só um aviso de que estamos ajustando".

function arquivos(dir: string, ext: string[]): string[] {
  const fora = new Set(["node_modules", ".next", ".git", "dist", "coverage"]);
  const achados: string[] = [];
  for (const nome of readdirSync(dir)) {
    if (fora.has(nome)) continue;
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) achados.push(...arquivos(caminho, ext));
    else if (ext.some((e) => nome.endsWith(e))) achados.push(caminho);
  }
  return achados;
}

const RAIZ = join(__dirname, "..");

describe("as fronteiras que um arquivo guarda", () => {
  /**
   * O corpo de um post é texto, e continua texto.
   *
   * `dangerouslySetInnerHTML` no caminho do blog transformaria a página inicial
   * do produto num lugar onde uma string do banco vira execução. E o dia em que
   * isso vai ser proposto é o dia em que eu quiser um negrito.
   */
  it("não existe dangerouslySetInnerHTML em lugar nenhum do repositório", () => {
    // A primeira versão desta verificação reprovou o `lib/blog.ts` — que cita a
    // palavra num comentário, justamente para explicar por que ela é proibida.
    // É o mesmo defeito da verificação 3 da suíte 0051 (que acusou as views
    // `v_leitura*` do Panorama) e o da 22 da 0044: **asserção larga acusa o
    // código certo, e o preço é aprender a ignorar o alarme.** Comentário sai
    // da varredura; o que sobra é código que executa.
    const culpados = arquivos(RAIZ, [".tsx", ".ts"])
      .filter((f) => !f.endsWith("blog.test.ts"))
      .filter((f) =>
        readFileSync(f, "utf8")
          .replace(/\/\*[\s\S]*?\*\//g, "")
          .replace(/^\s*\/\/.*$/gm, "")
          .includes("dangerously" + "SetInnerHTML"),
      );
    expect(culpados).toEqual([]);
  });

  /**
   * O produto está em produção, e a página diz isso.
   *
   * O Leandro foi explícito: *"tira o ainda em construção, vamos operar como
   * operacional; eu decido aqui quando estiver ok"*. A decisão é dele e o
   * software não a repete de volta — mas uma frase dessas volta sozinha na
   * próxima seção que alguém escrever com pressa, e é por isso que ela vira
   * teste em vez de virar cuidado.
   *
   * A varredura é só do que o visitante lê (`app/(site)`, `app/entrar`,
   * `components/site`): o comentário de código que **explica** por que a frase
   * saiu precisa poder citá-la.
   */
  it("nenhuma tela pública diz que o produto ainda não está pronto", () => {
    const PROIBIDO = [
      /em constru[çc][ãa]o/i,
      /em breve/i,
      /lista de espera/i,
      /pre[çc]o em estudo/i,
      /vers[ãa]o beta/i,
      /acesso por convite/i,
    ];

    const publicos = [
      join(RAIZ, "app", "(site)"),
      join(RAIZ, "app", "entrar"),
      join(RAIZ, "components", "site"),
    ].flatMap((d) => arquivos(d, [".tsx"]));

    const culpados: string[] = [];
    for (const f of publicos) {
      // Comentário de bloco e de linha saem: eles são a memória de por que a
      // frase foi embora, e apagá-los para o teste passar seria apagar o
      // motivo. O que sobra é o que a pessoa lê na tela.
      const visivel = readFileSync(f, "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "");
      for (const p of PROIBIDO) {
        if (p.test(visivel)) culpados.push(`${f} → ${p}`);
      }
    }
    expect(culpados).toEqual([]);
  });

  /**
   * "Psicólogas de verdade" saiu, e não volta.
   *
   * A primeira auditoria pediu a troca por soar defensivo, e eu mantive a frase
   * com a divergência registrada em comentário, porque o pedido do Leandro
   * tinha sido explícito. A terceira leitura trouxe o argumento que faltava, e
   * ele não é de tom: a expressão **implica que existem psicólogas
   * não-verdadeiras**. O que se queria dizer era o contraste com software feito
   * sobre suposição, e isso se diz sem a implicação.
   *
   * Vira teste pelo mesmo motivo do "em construção": uma frase assim volta
   * sozinha na próxima seção escrita com pressa.
   */
  it("nenhuma tela pública chama alguém de psicóloga de verdade", () => {
    const publicos = [
      join(RAIZ, "app", "(site)"),
      join(RAIZ, "app", "entrar"),
      join(RAIZ, "components", "site"),
    ].flatMap((d) => arquivos(d, [".tsx"]));

    const culpados = publicos.filter((f) =>
      /psic[óo]log[ao]s?\s+de\s+verdade/i.test(
        readFileSync(f, "utf8")
          .replace(/\/\*[\s\S]*?\*\//g, "")
          .replace(/^\s*\/\/.*$/gm, ""),
      ),
    );
    expect(culpados).toEqual([]);
  });

  /**
   * **Botão que nomeia um plano pago tem de carregar o plano.**
   *
   * "Começar no Solo" e "Começar no Pro" apontavam os dois para o mesmo
   * `/entrar?criar`: a escolha morria no clique, e o rótulo prometia um começo
   * que não acontece — toda conta nasce no Grátis, porque quem abre assinatura
   * é uma pessoa (OP5).
   *
   * O teste não cobra o texto do rótulo, cobra a **coerência**: se o botão
   * nomeia Solo ou Pro, o destino tem de levar essa informação. Assim continua
   * possível reescrever a copy sem reabrir o buraco, e impossível reabri-lo por
   * distração.
   */
  /**
   * **Nenhuma tela pública promete tempo no ar.**
   *
   * O doc 20 escreveu a recusa na própria B40: *"não entra: SLA de
   * disponibilidade. Prometer uptime que não se mede é a mesma classe de erro
   * que 'seus dados estão 100% seguros'"*. E a página de segurança já abre
   * dizendo que evita adjetivo não conferível.
   *
   * A frase perigosa não chega escrita como SLA. Ela chega como "sempre
   * disponível", "sem interrupção", "seguro" — num parágrafo de vendas, seis
   * meses depois, escrito com pressa.
   */
  it("nenhuma tela pública promete tempo no ar ou segurança absoluta", () => {
    const PROIBIDO = [
      /\bSLA\b/,
      /uptime/i,
      /100\s*%\s*(seguro|segura|dispon)/i,
      /sempre\s+dispon[íi]vel/i,
      /disponibilidade\s+garantida/i,
      /sem\s+interrup[çc][ãa]o/i,
      /totalmente\s+seguro/i,
    ];

    // **A página do incidente sai da varredura, e o motivo é o de sempre.**
    // Ela é a única tela que **cita** as frases proibidas — para recusá-las:
    // "não existe SLA de disponibilidade aqui" e "a mesma classe de frase que
    // 'seus dados estão 100% seguros'". Asserção larga acusa o código certo, e
    // o preço não é o falso positivo: é aprender a ignorar o alarme (lição da
    // 0044, da 0051 e do próprio teste de `dangerouslySetInnerHTML` acima).
    //
    // A dispensa vem com contrapartida: a verificação seguinte exige que a
    // página **contenha a recusa**. Ela não fica fora do teste; fica dentro de
    // outro.
    const publicos = [
      join(RAIZ, "app", "(site)"),
      join(RAIZ, "app", "entrar"),
      join(RAIZ, "components", "site"),
    ]
      .flatMap((d) => arquivos(d, [".tsx"]))
      .filter((f) => !f.endsWith(join("incidente", "page.tsx")));

    const culpados: string[] = [];
    for (const f of publicos) {
      const visivel = readFileSync(f, "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "");
      for (const pr of PROIBIDO) {
        if (pr.test(visivel)) culpados.push(`${f} → ${pr}`);
      }
    }
    expect(culpados).toEqual([]);
  });

  /** A contrapartida da dispensa acima: a página tem de recusar, e por escrito. */
  it("a página do incidente recusa o SLA em vez de calar sobre ele", () => {
    const pagina = readFileSync(
      join(RAIZ, "app", "(site)", "incidente", "page.tsx"),
      "utf8",
    )
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");

    expect(pagina).toMatch(/N[ãa]o existe SLA/i);
    expect(pagina).toMatch(/n[ãa]o h[áa] promessa de que n[ãa]o vai acontecer/i);
  });

  /**
   * A página do incidente diz o número, ou não serve para nada.
   *
   * O critério de pronto da B40 é *"dá para executar às três da manhã sem
   * pensar"*, e metade do plano é obrigação dela. Uma página que dissesse
   * "avisamos rapidamente" devolveria para a psicóloga exatamente a pergunta
   * que ela não tem como responder sozinha: **quanto tempo eu tenho?**
   */
  it("a página do incidente traz os prazos e a autoridade, com número", () => {
    const pagina = readFileSync(
      join(RAIZ, "app", "(site)", "incidente", "page.tsx"),
      "utf8",
    )
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");

    expect(pagina).toMatch(/24\s+horas/);
    expect(pagina).toMatch(/tr[êe]s\s+dias\s+[úu]teis/);
    expect(pagina).toMatch(/ANPD/);
    // De quem é o dever: é a parte que mais custa e a que ninguém escreve.
    expect(pagina).toMatch(/controladora/);
    expect(pagina).toMatch(/operador/);
  });

  it("o botão que nomeia um plano pago leva o plano no destino", () => {
    const pagina = readFileSync(join(RAIZ, "app", "(site)", "page.tsx"), "utf8");
    const bloco = pagina.slice(
      pagina.indexOf("const PLANOS = ["),
      pagina.indexOf("];", pagina.indexOf("const PLANOS = [")),
    );

    const cartoes = bloco.split(/\n  \{/).slice(1);
    const culpados: string[] = [];

    for (const c of cartoes) {
      const cta = /cta:\s*"([^"]*)"/.exec(c)?.[1] ?? "";
      const href = /href:\s*"([^"]*)"/.exec(c)?.[1] ?? "";
      if (!/\b(Solo|Pro)\b/.test(cta)) continue;
      if (!href.includes("plano=")) culpados.push(`${cta} → ${href}`);
    }

    expect(culpados).toEqual([]);
  });
});
