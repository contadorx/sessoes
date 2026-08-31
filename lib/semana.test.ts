import { describe, expect, it } from "vitest";
import {
  somarDias,
  diaDaSemana,
  segundaDa,
  semanaDe,
  rotuloSemana,
  faixaDeHoras,
  minutosNoDia,
  posicaoNaGrade,
  porDiaDaSemana,
} from "./semana";

describe("aritmética de dia civil", () => {
  it("soma e subtrai sem escorregar de fuso", () => {
    expect(somarDias("2026-09-01", 1)).toBe("2026-09-02");
    expect(somarDias("2026-09-01", -1)).toBe("2026-08-31");
    expect(somarDias("2026-09-30", 1)).toBe("2026-10-01");
    expect(somarDias("2026-12-31", 1)).toBe("2027-01-01");
  });

  it("atravessa fevereiro sem susto", () => {
    expect(somarDias("2028-02-28", 1)).toBe("2028-02-29"); // bissexto
    expect(somarDias("2026-02-28", 1)).toBe("2026-03-01");
  });

  it("conhece o dia da semana", () => {
    expect(diaDaSemana("2026-09-01")).toBe(2); // terça
    expect(diaDaSemana("2026-08-30")).toBe(0); // domingo
  });

  it("recusa formato que não é dia", () => {
    expect(() => somarDias("01/09/2026", 1)).toThrow();
  });
});

describe("a semana do produto vai de segunda a domingo", () => {
  it("acha a segunda a partir de qualquer dia", () => {
    expect(segundaDa("2026-09-01")).toBe("2026-08-31"); // terça → segunda
    expect(segundaDa("2026-08-31")).toBe("2026-08-31"); // a própria segunda
    expect(segundaDa("2026-09-06")).toBe("2026-08-31"); // domingo fecha a semana
  });

  it("monta os sete dias em ordem", () => {
    const s = semanaDe("2026-09-01");
    expect(s.inicio).toBe("2026-08-31");
    expect(s.fim).toBe("2026-09-06");
    expect(s.dias).toHaveLength(7);
    expect(s.dias[0]).toBe("2026-08-31");
    expect(s.dias[6]).toBe("2026-09-06");
  });

  it("escreve o rótulo do jeito que se fala", () => {
    expect(rotuloSemana(semanaDe("2026-09-08"))).toBe("7 – 13 de setembro");
    expect(rotuloSemana(semanaDe("2026-09-01"))).toBe("31 de agosto – 6 de setembro");
    expect(rotuloSemana(semanaDe("2026-12-31"))).toContain("2026");
    expect(rotuloSemana(semanaDe("2026-12-31"))).toContain("2027");
  });
});

describe("posicionar na grade", () => {
  // Terça 01/09/2026, 15h–15h50 em São Paulo = 18:00–18:50 UTC.
  const terca15h = { inicio: "2026-09-01T18:00:00Z", fim: "2026-09-01T18:50:00Z" };

  it("lê a hora no fuso de São Paulo, não no do servidor", () => {
    expect(minutosNoDia(terca15h.inicio)).toBe(15 * 60);
    expect(minutosNoDia(terca15h.fim)).toBe(15 * 60 + 50);
  });

  it("a sessão das 23h30 pertence ao próprio dia", () => {
    expect(minutosNoDia("2026-10-01T02:30:00Z")).toBe(23 * 60 + 30);
  });

  it("posiciona com folga a partir do topo da grade", () => {
    const p = posicaoNaGrade(terca15h, 8);
    expect(p.topo).toBe(7);
    expect(p.altura).toBeCloseTo(50 / 60, 5);
  });

  it("a faixa abre com folga dos dois lados", () => {
    // 15h00–15h50 com meia hora de folga: começa às 14h e sobe até as 17h,
    // porque 15h50 + 30min já passa das 16h.
    expect(faixaDeHoras([terca15h])).toEqual([14, 17]);
  });

  it("cobre da primeira à última sessão da semana", () => {
    const cedo = { inicio: "2026-09-01T11:00:00Z", fim: "2026-09-01T11:50:00Z" }; // 8h
    expect(faixaDeHoras([terca15h, cedo])).toEqual([7, 17]);
  });

  it("sem sessão, mostra o miolo do dia de trabalho", () => {
    expect(faixaDeHoras([])).toEqual([8, 20]);
  });
});

describe("agrupar na semana", () => {
  it("cada sessão cai no dia civil de São Paulo", () => {
    const dias = semanaDe("2026-09-01").dias;
    const mapa = porDiaDaSemana(
      [
        { inicio: "2026-09-01T18:00:00Z", id: "a" }, // terça 15h
        { inicio: "2026-09-02T02:30:00Z", id: "b" }, // terça 23h30 em SP
        { inicio: "2026-09-03T13:00:00Z", id: "c" }, // quinta 10h
      ],
      dias,
    );

    expect(mapa["2026-09-01"].map((s) => s.id)).toEqual(["a", "b"]);
    expect(mapa["2026-09-03"].map((s) => s.id)).toEqual(["c"]);
    expect(mapa["2026-09-04"]).toEqual([]);
  });

  it("ignora o que está fora da semana em vez de estourar", () => {
    const dias = semanaDe("2026-09-01").dias;
    const mapa = porDiaDaSemana([{ inicio: "2026-10-20T18:00:00Z", id: "x" }], dias);
    expect(Object.values(mapa).flat()).toHaveLength(0);
  });
});
