import { describe, expect, it } from "vitest";
import { diaEmSP, horaEmSP, inicioDoDiaSP, fimDoDiaSP, deslocamentoSP } from "./tempo";

describe("tempo — o dia é o de São Paulo, não o do servidor", () => {
  it("o caso do critério de pronto da B1: 23h30 de 30/09 é dia 30, não dia 1º", () => {
    // 30/09/2026 23:30 em São Paulo = 01/10/2026 02:30 UTC.
    // Um servidor em UTC (a Vercel) diria "1º de outubro". Está errado.
    const instante = new Date("2026-10-01T02:30:00Z");
    expect(diaEmSP(instante)).toBe("2026-09-30");
    expect(horaEmSP(instante)).toBe("23:30");
  });

  it("e meia hora depois já é o dia seguinte", () => {
    const instante = new Date("2026-10-01T03:30:00Z");
    expect(diaEmSP(instante)).toBe("2026-10-01");
    expect(horaEmSP(instante)).toBe("00:30");
  });

  it("a virada do ano acontece na hora certa", () => {
    expect(diaEmSP(new Date("2027-01-01T02:59:00Z"))).toBe("2026-12-31");
    expect(diaEmSP(new Date("2027-01-01T03:01:00Z"))).toBe("2027-01-01");
  });

  it("meia-noite em ponto sai como 00:00, não 24:00", () => {
    expect(horaEmSP(new Date("2026-09-30T03:00:00Z"))).toBe("00:00");
  });
});

describe("tempo — limites de dia para consulta de agenda", () => {
  it("a meia-noite de São Paulo é 03:00 UTC (sem horário de verão)", () => {
    expect(inicioDoDiaSP("2026-09-30").toISOString()).toBe("2026-09-30T03:00:00.000Z");
  });

  it("o fim do dia é o começo do dia seguinte, exclusivo", () => {
    expect(fimDoDiaSP("2026-09-30").toISOString()).toBe("2026-10-01T03:00:00.000Z");
    expect(fimDoDiaSP("2026-09-30").getTime()).toBe(inicioDoDiaSP("2026-10-01").getTime());
  });

  it("o intervalo [inicio, fim) contém a sessão das 23h30 daquele dia", () => {
    const sessao = new Date("2026-10-01T02:30:00Z"); // 30/09 23h30 em SP
    const inicio = inicioDoDiaSP("2026-09-30");
    const fim = fimDoDiaSP("2026-09-30");
    expect(sessao >= inicio && sessao < fim).toBe(true);
  });

  it("ida e volta: o início do dia pertence ao próprio dia", () => {
    for (const dia of ["2026-01-01", "2026-02-28", "2026-08-31", "2026-12-31"]) {
      expect(diaEmSP(inicioDoDiaSP(dia))).toBe(dia);
    }
  });

  it("recusa formato de dia que não seja AAAA-MM-DD", () => {
    expect(() => inicioDoDiaSP("30/09/2026")).toThrow();
    expect(() => inicioDoDiaSP("2026-9-30")).toThrow();
  });
});

describe("tempo — o deslocamento é perguntado, não presumido", () => {
  it("hoje o Brasil está em GMT-3", () => {
    expect(deslocamentoSP(new Date("2026-08-31T12:00:00Z"))).toBe(-180);
    expect(deslocamentoSP(new Date("2026-01-15T12:00:00Z"))).toBe(-180);
  });

  it("se o horário de verão voltar, o cálculo acompanha sozinho", () => {
    // Em 2018 ainda havia horário de verão: 01/01/2018 era GMT-2.
    expect(deslocamentoSP(new Date("2018-01-01T12:00:00Z"))).toBe(-120);
    expect(deslocamentoSP(new Date("2018-07-01T12:00:00Z"))).toBe(-180);
    // E o dia civil sai certo mesmo assim.
    expect(diaEmSP(new Date("2018-01-01T01:30:00Z"))).toBe("2017-12-31");
  });
});
