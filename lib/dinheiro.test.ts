import { describe, expect, it } from "vitest";
import { paraCentavos, deCentavos, formatar, percentual, somar } from "./dinheiro";

describe("dinheiro — entrada e saída do numeric", () => {
  it("lê a string que o supabase devolve para numeric(12,2)", () => {
    expect(paraCentavos("200.00")).toBe(20000);
    expect(paraCentavos("200")).toBe(20000);
    expect(paraCentavos("200.5")).toBe(20050);
    expect(paraCentavos("0.05")).toBe(5);
    expect(paraCentavos("200,50")).toBe(20050);
  });

  it("não perde centavo em valor que o float estragaria", () => {
    // 0.1 + 0.2 em float dá 0.30000000000000004; aqui é inteiro.
    expect(somar(paraCentavos("0.10"), paraCentavos("0.20"))).toBe(30);
    expect(deCentavos(somar(paraCentavos("0.10"), paraCentavos("0.20")))).toBe("0.30");
    expect(paraCentavos("1234567.89")).toBe(123456789);
  });

  it("volta para o formato do numeric", () => {
    expect(deCentavos(20000)).toBe("200.00");
    expect(deCentavos(5)).toBe("0.05");
    expect(deCentavos(0)).toBe("0.00");
  });

  it("recusa float disfarçado de centavo", () => {
    expect(() => deCentavos(200.5)).toThrow(/inteiro/);
    expect(() => formatar(0.1 + 0.2)).toThrow(/inteiro/);
  });

  it("recusa entrada que não é dinheiro", () => {
    expect(() => paraCentavos("")).toThrow();
    expect(() => paraCentavos("abc")).toThrow();
    expect(() => paraCentavos("200.999")).toThrow();
    expect(() => paraCentavos(Number.NaN)).toThrow();
  });
});

describe("dinheiro — sinal é contrato (a cicatriz do FinanceiroX)", () => {
  it("atravessa a leitura e a escrita sem virar módulo", () => {
    expect(paraCentavos("-200.00")).toBe(-20000);
    expect(deCentavos(-20000)).toBe("-200.00");
    expect(deCentavos(paraCentavos("-0.05"))).toBe("-0.05");
  });

  it("sobrevive à soma", () => {
    expect(somar(20000, -5000)).toBe(15000);
    expect(somar(-20000, -5000)).toBe(-25000);
    expect(somar(20000, -20000)).toBe(0);
  });

  it("sobrevive ao percentual, com arredondamento simétrico", () => {
    expect(percentual(-20000, 50)).toBe(-10000);
    expect(percentual(20000, 50)).toBe(10000);
    // 33,333% de 1,00 arredonda igual dos dois lados do zero
    expect(percentual(100, 33.333)).toBe(33);
    expect(percentual(-100, 33.333)).toBe(-33);
    expect(percentual(105, 50)).toBe(53);
    expect(percentual(-105, 50)).toBe(-53);
  });

  it("nenhuma função devolve o módulo do valor", () => {
    const negativos = [-1, -50, -20000, -123456789];
    for (const v of negativos) {
      expect(percentual(v, 100)).toBeLessThan(0);
      expect(somar(v, 0)).toBeLessThan(0);
      expect(deCentavos(v).startsWith("-")).toBe(true);
    }
  });
});

describe("dinheiro — a política de falta (D2)", () => {
  it("cobra 50% de uma sessão de R$ 200", () => {
    const sessao = paraCentavos("200.00");
    const multa = percentual(sessao, 50);
    expect(multa).toBe(10000);
    expect(formatar(multa)).toBe(brl(100));
    expect(deCentavos(multa)).toBe("100.00");
  });

  it("cobra 100% e 0% sem surpresa", () => {
    const sessao = paraCentavos("180.00");
    expect(percentual(sessao, 100)).toBe(18000);
    expect(percentual(sessao, 0)).toBe(0);
  });

  it("arredonda o percentual quebrado para o centavo", () => {
    // 30% de R$ 183,33 = R$ 54,999 → R$ 55,00
    expect(percentual(paraCentavos("183.33"), 30)).toBe(5500);
  });
});

/** O Intl usa espaço não separável entre "R$" e o número; não escrever à mão. */
function brl(n: number): string {
  return n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}
