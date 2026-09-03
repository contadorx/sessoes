import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  PLANOS,
  plano,
  nomeDoPlano,
  precoDoPlano,
  faixaTotal,
  ondeAEscadaDesce,
  ROTULO_POR_VIR,
  type CodigoDePlano,
} from "./planos";

/**
 * Estes testes são o gêmeo da suíte SQL 0064, com os mesmos valores esperados.
 * A suíte prova o banco; estes provam a página. A aritmética está escrita duas
 * vezes de propósito: é assim que se pega divergência entre as duas camadas —
 * que foi, literalmente, o defeito que originou a build (o banco achava que a
 * Clínica custava R$ 249 com cinco profissionais).
 */

describe("o código é do sistema, o nome é dela", () => {
  it("os quatro códigos são os que o banco guarda", () => {
    // Se algum destes mudar, a chave estrangeira de `contas.plano` cai junto
    // com a URL `?criar&plano=solo` e os metadados do cadastro.
    expect(PLANOS.map((p) => p.codigo)).toEqual(["gratis", "solo", "pro", "clinica"]);
  });

  it("os quatro nomes são os do doc 25, revisão 4", () => {
    expect(PLANOS.map((p) => p.nome)).toEqual([
      "Gratuito",
      "Consultório",
      "Consultório Completo",
      "Clínica",
    ]);
  });

  it("nenhum nome é do vocabulário velho", () => {
    // Meio-rename é pior que nenhum: ela lê "Consultório Completo" na landing e
    // "Pro" no e-mail de cobrança, e conclui que são dois produtos.
    for (const p of PLANOS) {
      expect(["Pro", "Solo", "Grátis"]).not.toContain(p.nome);
    }
  });

  it("um plano que a tela não conhece aparece feio, em vez de sumir", () => {
    expect(nomeDoPlano("solo")).toBe("Consultório");
    expect(nomeDoPlano("plano_que_alguem_criar")).toBe("plano_que_alguem_criar");
  });

  it("pedir um plano inexistente é erro, e não silêncio", () => {
    expect(() => plano("inexistente" as CodigoDePlano)).toThrow();
  });
});

describe("a escada não desce", () => {
  it("o preço sobe do primeiro ao último degrau", () => {
    const precos = PLANOS.map((p) => p.precoCentavos);
    expect(precos).toEqual([0, 6900, 12900, 24900]);
    for (let i = 1; i < precos.length; i++) {
      expect(precos[i]).toBeGreaterThan(precos[i - 1]);
    }
  });

  it("de 1 a 8 profissionais, a faixa nunca desce — é o defeito da build", () => {
    // Antes da 0064: Pro 200 fixo, Clínica 60 por profissional. Uma clínica de
    // uma pessoa pagava R$ 120 a mais para receber 140 sessões a menos. Com
    // quatro profissionais o defeito sumia (240 > 200), e é por isso que o
    // teste varre a escada inteira em vez de conferir um caso.
    for (let n = 1; n <= 8; n++) {
      expect(ondeAEscadaDesce(n)).toBeNull();
    }
  });

  it("...e o teste pegaria o defeito antigo se ele voltasse", () => {
    // A prova de que a varredura acima não passa a vazio. Com a faixa velha da
    // Clínica (60 por profissional), a escada desce em 1, 2 e 3 — e não em 4.
    const desceCom = (faixaClinica: number, n: number) =>
      faixaClinica * n < (PLANOS.find((p) => p.codigo === "pro")!.faixa ?? 0);
    expect(desceCom(60, 1)).toBe(true);
    expect(desceCom(60, 3)).toBe(true);
    expect(desceCom(60, 4)).toBe(false);
  });

  it("a Clínica de uma profissional empata com o Completo", () => {
    expect(faixaTotal("clinica", 1)).toBe(faixaTotal("pro", 1));
    expect(faixaTotal("clinica", 1)).toBe(200);
  });

  it("a de quatro quadruplica", () => {
    expect(faixaTotal("clinica", 4)).toBe(800);
  });

  it("zero profissionais conta como uma, e não como zero", () => {
    // Faixa de zero faria `acima` ser verdade para quem não atendeu ninguém —
    // é a correção da 0060c, e ela vale nos dois lados.
    expect(faixaTotal("clinica", 0)).toBe(200);
    expect(precoDoPlano("clinica", 0)).toBe(24900);
  });
});

describe("o Gratuito não tem faixa, e não ter faixa não é ter faixa infinita", () => {
  it("a faixa do Gratuito é nula", () => {
    expect(faixaTotal("gratis")).toBeNull();
    expect(faixaTotal("gratis", 5)).toBeNull();
  });

  it("o limite dele é o canal, e ele é o único manual", () => {
    // As duas metades juntas. Sem faixa E com canal automático, o Gratuito
    // seria o plano pago de graça.
    expect(plano("gratis").canal).toBe("manual");
    for (const p of PLANOS.filter((x) => x.codigo !== "gratis")) {
      expect(p.canal).toBe("plataforma");
    }
  });
});

describe("o preço com profissionais", () => {
  it("a Clínica de cinco custa R$ 405, que é o número da landing", () => {
    // O plano-base já inclui uma profissional: 24900 + 4 × 3900.
    expect(precoDoPlano("clinica", 5)).toBe(40500);
  });

  it("a Clínica de uma custa a base, sem acréscimo", () => {
    expect(precoDoPlano("clinica", 1)).toBe(24900);
  });

  it("plano de preço fixo ignora o número de profissionais", () => {
    expect(precoDoPlano("solo", 9)).toBe(6900);
    expect(precoDoPlano("pro", 9)).toBe(12900);
    expect(precoDoPlano("gratis", 9)).toBe(0);
  });

  it("só a Clínica tem acréscimo por profissional", () => {
    for (const p of PLANOS) {
      if (p.codigo === "clinica") expect(p.precoPorProfissionalCentavos).toBe(3900);
      else expect(p.precoPorProfissionalCentavos).toBeNull();
    }
  });
});

describe("recursos é o que existe; porVir é o que não existe", () => {
  it("as duas listas são disjuntas em todo plano", () => {
    // No banco isto é uma restrição (`check (not (recursos && por_vir))`).
    // Aqui é este teste. Uma linha não pode ser vendida e prometida ao mesmo
    // tempo.
    for (const p of PLANOS) {
      const r = new Set(p.recursos.map((x) => x.toLowerCase()));
      for (const v of p.porVir) {
        expect(r.has(v.toLowerCase())).toBe(false);
      }
    }
  });

  it("nenhuma das oito palavras mortas está sendo vendida", () => {
    // Briefing, radar de furo e portal do paciente foram mortos pelo doc 30;
    // NFS-e é a B38; salas, repasse e fila cruzada são fase 4. "Fila limitada"
    // era falsa no sentido inverso: a fila do Gratuito é inteira.
    const mortas = [
      "briefing",
      "radar de furo",
      "portal do paciente",
      "nfs-e",
      "salas",
      "repasse",
      "fila cruzada",
      "fila limitada",
    ];
    for (const p of PLANOS) {
      const texto = p.recursos.join(" | ").toLowerCase();
      for (const m of mortas) {
        expect(texto, `${p.codigo} vende "${m}"`).not.toContain(m);
      }
    }
  });

  it("...e quatro delas estão em porVir, porque sumir não é resolver", () => {
    const prometido = PLANOS.flatMap((p) => p.porVir)
      .join(" | ")
      .toLowerCase();
    for (const m of ["nfs-e", "repasse", "salas", "fila cruzada"]) {
      expect(prometido).toContain(m);
    }
  });

  it("todo plano diz o que faz", () => {
    for (const p of PLANOS) {
      expect(p.recursos.length).toBeGreaterThan(0);
    }
  });

  it("o número próprio só é prometido onde ele vai morar", () => {
    // Decisão do Leandro em 02/09 (migração 0065): o número próprio é o
    // Consultório Completo inteiro, e não um add-on de R$ 19 comprável no
    // Consultório. Uma promessa no cartão errado é pior que promessa nenhuma —
    // a pessoa assina o plano de baixo esperando o recurso que nunca vem nele.
    for (const p of PLANOS) {
      const promete = p.porVir.join(" ").toLowerCase().includes("número próprio");
      const deveria = p.codigo === "pro" || p.codigo === "clinica";
      expect(promete, `${p.codigo}: promessa de número próprio no cartão errado`).toBe(deveria);
    }
  });

  it("...e não há preço de add-on em lugar nenhum", () => {
    // O que não existe não tem preço. O número próprio depende de BSP com
    // Embedded Signup e Coexistence, que não existem — e preço de coisa
    // inexistente é o defeito que a 0064 inteira existe para fechar.
    const tudo = PLANOS.flatMap((p) => [...p.recursos, ...p.porVir]).join(" ");
    expect(tudo).not.toMatch(/R\$\s*\d/);
  });

  it("o Gratuito não promete nada", () => {
    // Uma lista de "em breve" no plano de entrada é lida por quem está
    // avaliando como "ainda não serve".
    expect(plano("gratis").porVir).toEqual([]);
  });

  it("o rótulo do bloco diz as três coisas de uma vez", () => {
    // Que não existe, que está vindo, e que não está no preço. Faltando
    // qualquer uma, a lista vira promessa vendida.
    expect(ROTULO_POR_VIR).toMatch(/não existe/i);
    expect(ROTULO_POR_VIR).toMatch(/não está no preço/i);
  });
});

describe("fair-use e a frase do cartão andam juntos", () => {
  it("quem diz 'sem faixa' no cartão tem fairUse ligado", () => {
    // Com fairUse, o `lib/faixa.ts` cala: nivelDaFaixa devolve "nenhum" e
    // fraseDoRestante diz que o plano não tem faixa. Sem ele, a tela começaria
    // a contar sessões que a página promete não contar.
    for (const p of PLANOS) {
      const diz = p.recursos.join(" ").toLowerCase().includes("sem faixa");
      expect(diz, `${p.codigo}: cartão e banco discordam`).toBe(p.fairUse);
    }
  });

  it("o Consultório vende a faixa, e por isso a diz no cartão", () => {
    expect(plano("solo").fairUse).toBe(false);
    expect(plano("solo").recursos.join(" ")).toContain("60 sessões");
  });
});

describe("as portas", () => {
  it("cada plano tem uma, e o rótulo diz o que o clique faz", () => {
    // Sem isto, a pessoa comparava os quatro preços, decidia, e não achava onde
    // clicar. E "Começar no Solo" prometia um começo que não acontece: toda
    // conta nasce no Gratuito, porque não existe assinatura self-service.
    for (const p of PLANOS) {
      expect(p.href.length).toBeGreaterThan(0);
      expect(p.cta.length).toBeGreaterThan(0);
      expect(p.cta).not.toMatch(/^Começar no /);
    }
  });

  it("os dois planos de assinatura levam o código na URL", () => {
    expect(plano("solo").href).toContain("plano=solo");
    expect(plano("pro").href).toContain("plano=pro");
  });

  it("a Clínica leva para a conversa, e não para o cadastro", () => {
    // Ela não se contrata sozinha: o número de profissionais muda o preço.
    expect(plano("clinica").href).toBe("/#conversa");
  });
});

/**
 * O espelho que faltava — e é ele, não a lista corrigida, que fecha a B46.
 *
 * A 0064 criou `planos.por_vir` e a restrição `planos_promessa_nao_e_recurso`
 * para que promessa não pudesse ser listada como recurso. E a promessa voltou
 * assim mesmo, no cartão de R$ 129: "permissões por pessoa: quem vê o quê,
 * **com aprovação em etapas**", sem implementação em lugar nenhum.
 *
 * Passou porque **a trava mora na coluna do banco e a landing renderiza a
 * constante do TypeScript**. Eram dois textos do mesmo produto, e o protegido
 * era justamente o que ninguém via.
 *
 * Este bloco lê a migração `0070` do disco e compara as duas listas linha a
 * linha, **nos dois sentidos**. Não precisa de banco para rodar — o que a torna
 * capaz de reprovar num `npm run verificar`, que é onde o defeito teria sido
 * pego. O outro lado do espelho, banco contra a mesma lista, é a suíte
 * `supabase/tests/0070_a_lista_de_planos_e_uma_so.sql`.
 *
 * A comparação ignora maiúscula e acento de caixa, e só isso: o banco escreve o
 * primeiro caractere em minúscula por convenção da casa, e isso é apresentação.
 * Qualquer diferença de **conteúdo** reprova.
 */
describe("a lista do TypeScript e a do banco são a mesma", () => {
  const sql = readFileSync(
    join(import.meta.dirname, "..", "supabase", "migrations", "0070_a_lista_de_planos_e_uma_so.sql"),
    "utf8",
  );

  /**
   * Os `update ... where codigo = 'x';` da migração, um por plano.
   *
   * Recorta por statement antes de procurar o plano: um regex não-guloso a
   * partir do primeiro `update` casaria do começo do arquivo até o `where` do
   * plano pedido, e leria os recursos do plano **anterior** — o que faz o
   * espelho reprovar por engano, e o próximo a mexer nele desconfiar do
   * espelho em vez do código.
   */
  const STATEMENTS = sql
    .split(/;\s*\n/)
    .filter((t) => t.includes("update public.planos set"));

  function daMigracao(codigo: string, campo: "recursos" | "por_vir"): string[] {
    const bloco = STATEMENTS.find((t) => new RegExp(`where codigo = '${codigo}'`).test(t));
    if (!bloco) throw new Error(`a migração não tem o plano ${codigo}`);

    const vazio = new RegExp(`${campo} = '\\{\\}'::text\\[\\]`).test(bloco);
    if (vazio) return [];

    const lista = new RegExp(`${campo} = array\\[([\\s\\S]*?)\\n  \\]`).exec(bloco)?.[1];
    if (!lista) throw new Error(`a migração não tem ${campo} de ${codigo}`);

    return [...lista.matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'"));
  }

  const igual = (a: string) => a.trim().toLowerCase();

  it("a varredura acha os quatro planos na migração", () => {
    // Se a leitura parar de achar, tudo abaixo passaria com listas vazias —
    // que é o modo silencioso de um espelho morrer.
    for (const p of PLANOS) {
      expect(daMigracao(p.codigo, "recursos").length, p.codigo).toBeGreaterThan(0);
    }
  });

  it.each(PLANOS.map((p) => p.codigo))("%s: recursos batem, linha a linha", (codigo) => {
    const p = PLANOS.find((x) => x.codigo === codigo)!;
    expect(daMigracao(codigo, "recursos").map(igual)).toEqual(p.recursos.map(igual));
  });

  it.each(PLANOS.map((p) => p.codigo))("%s: por_vir bate, linha a linha", (codigo) => {
    const p = PLANOS.find((x) => x.codigo === codigo)!;
    expect(daMigracao(codigo, "por_vir").map(igual)).toEqual(p.porVir.map(igual));
  });

  it("nos dois sentidos: nada existe de um lado só", () => {
    for (const p of PLANOS) {
      const noSql = new Set([
        ...daMigracao(p.codigo, "recursos").map(igual),
        ...daMigracao(p.codigo, "por_vir").map(igual),
      ]);
      const noTs = new Set([...p.recursos, ...p.porVir].map(igual));

      for (const linha of noTs) {
        expect(noSql.has(linha), `${p.codigo}: "${linha}" só existe no TypeScript`).toBe(true);
      }
      for (const linha of noSql) {
        expect(noTs.has(linha), `${p.codigo}: "${linha}" só existe no banco`).toBe(true);
      }
    }
  });
});
