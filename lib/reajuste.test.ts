import { describe, it, expect } from "vitest";
import {
  dataPorExtenso,
  diasDeAviso,
  fraseDaPausa,
  fraseDoReajuste,
  primeiroDoMesQueVem,
} from "./reajuste";
import { formatar } from "@/lib/dinheiro";

const HOJE = "2026-09-03";

describe("a antecedência é uma conta, não um palpite", () => {
  it("conta os dias entre hoje e a virada", () => {
    expect(diasDeAviso(HOJE, "2026-10-01")).toBe(28);
    expect(diasDeAviso(HOJE, "2026-09-04")).toBe(1);
    expect(diasDeAviso(HOJE, HOJE)).toBe(0);
  });

  /**
   * Atravessa a virada do horário de verão sem perder nem ganhar um dia — as
   * datas são puras e a conta é feita ao meio-dia UTC, que é a lei nº 3 pelo
   * caminho mais barato.
   */
  it("não escorrega na virada de mês nem de ano", () => {
    expect(diasDeAviso("2026-12-20", "2027-01-01")).toBe(12);
    expect(diasDeAviso("2026-02-27", "2026-03-01")).toBe(2);
  });

  it("o dia 1º do mês que vem, inclusive em dezembro", () => {
    expect(primeiroDoMesQueVem("2026-09-03")).toBe("2026-10-01");
    expect(primeiroDoMesQueVem("2026-12-31")).toBe("2027-01-01");
    expect(primeiroDoMesQueVem("2026-01-31")).toBe("2026-02-01");
  });

  it("a data por extenso sai em São Paulo, não em UTC", () => {
    // Meia-noite UTC de 1º/10 ainda é 30/09 em São Paulo. O meio-dia resolve.
    expect(dataPorExtenso("2026-10-01")).toBe("1 de outubro");
  });
});

/**
 * O tom, escrito como teste.
 *
 * O arquivo da build é explícito: sem pedir desculpa e sem justificar com
 * inflação. E a regra da casa acrescenta: sem sugerir valor — nem percentual,
 * nem comparação, nem "abaixo do valor de referência". Um número sugerido vira
 * âncora, e a âncora decide por ela.
 */
describe("a frase do reajuste não pede desculpa nem sugere nada", () => {
  const PROIBIDAS = [
    "infelizmente",
    "lamento",
    "desculp",
    "inflação",
    "inflacao",
    "custo",
    "reajuste anual",
    "recomend",
    "sugir",
    "sugest",
    "mercado",
    "referência",
    "%",
  ];

  const casos = [
    fraseDoReajuste(20000, 24000, HOJE, "2026-10-01"),
    fraseDoReajuste(20000, 24000, HOJE, "2026-09-04"),
    fraseDoReajuste(20000, 24000, HOJE, HOJE),
    fraseDaPausa("2026-10-12", "2026-10-25", 2),
    fraseDaPausa("2026-10-12", "2026-10-25", 0),
    fraseDaPausa("2026-10-12", "2026-10-12", 1),
  ];

  it.each(casos)("%s", (frase) => {
    const t = frase.toLowerCase();
    for (const p of PROIBIDAS) {
      expect(t, `"${frase}" contém "${p}"`).not.toContain(p);
    }
  });
});

describe("a frase do reajuste diz o que não muda", () => {
  it("nomeia os dois valores, a data, e o que acontece com o que já está marcado", () => {
    const f = fraseDoReajuste(20000, 24000, HOJE, "2026-10-01");
    // Os valores vêm de `formatar`, não escritos à mão: ele usa espaço
    // inquebrável entre o "R$" e o número, e um literal com espaço comum passa
    // a testar a minha digitação em vez de testar a frase.
    expect(f).toContain(formatar(20000));
    expect(f).toContain(formatar(24000));
    expect(f).toContain("1 de outubro");
    expect(f).toContain("daqui a 28 dias");
    // A metade que tira o medo: o passado não é reescrito.
    expect(f).toContain(`mantêm ${formatar(20000)}`);
  });

  it("com a virada hoje, não inventa 'daqui a 0 dias'", () => {
    expect(fraseDoReajuste(20000, 24000, HOJE, HOJE)).toContain("a partir de hoje");
    expect(fraseDoReajuste(20000, 24000, HOJE, "2026-09-04")).toContain("a partir de amanhã");
  });
});

describe("a pausa diz as duas consequências", () => {
  it("a agenda e a conta do mês, nesta ordem", () => {
    const f = fraseDaPausa("2026-10-12", "2026-10-25", 2);
    expect(f).toContain("12 de outubro a 25 de outubro");
    expect(f).toContain("2 sessões saem");
    expect(f).toContain("conta do mês");
  });

  it("sem sessão no período, não promete conta nenhuma", () => {
    const f = fraseDaPausa("2026-10-12", "2026-10-25", 0);
    expect(f).toContain("Não há sessão marcada");
    expect(f).not.toContain("conta do mês");
  });

  it("um dia só não vira intervalo", () => {
    expect(fraseDaPausa("2026-10-12", "2026-10-12", 1)).toContain("De 12 de outubro.");
  });
});
