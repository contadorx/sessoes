import { describe, expect, it } from "vitest";
import { rotuloJanela, montarJanela, tempoDeEspera, hora } from "./janela";

describe("a janela escrita como ela fala", () => {
  it("sem janela é qualquer horário", () => {
    expect(rotuloJanela([])).toBe("qualquer horário");
    expect(rotuloJanela(null)).toBe("qualquer horário");
    expect(rotuloJanela([{}])).toBe("qualquer horário");
  });

  it("o caso do protótipo: terça ou quarta, depois das 13h", () => {
    expect(rotuloJanela([{ dias: [2, 3], de: "13:00" }])).toBe(
      "terça ou quarta, depois das 13h",
    );
  });

  it("faixa fechada", () => {
    expect(rotuloJanela([{ de: "07:00", ate: "12:00" }])).toBe("das 7h às 12h");
  });

  it("só o limite de cima", () => {
    expect(rotuloJanela([{ ate: "12:00" }])).toBe("até as 12h");
  });

  it("dias corridos viram intervalo", () => {
    expect(rotuloJanela([{ dias: [1, 2, 3, 4, 5] }])).toBe("de segunda a sexta");
  });

  it("dois dias soltos ficam com 'ou'", () => {
    expect(rotuloJanela([{ dias: [1, 5] }])).toBe("segunda ou sexta");
  });

  it("três dias soltos listam e fecham com 'ou'", () => {
    expect(rotuloJanela([{ dias: [1, 3, 5] }])).toBe("segunda, quarta ou sexta");
  });

  it("meia hora aparece", () => {
    expect(hora("14:30")).toBe("14h30");
    expect(hora("09:00")).toBe("9h");
  });

  it("várias janelas se juntam", () => {
    expect(rotuloJanela([{ dias: [2], de: "14:00" }, { dias: [5], ate: "11:00" }])).toBe(
      "terça, depois das 14h ou sexta, até as 11h",
    );
  });
});

describe("montar a janela a partir do formulário", () => {
  it("campo vazio não vira restrição", () => {
    expect(montarJanela({})).toEqual([]);
    expect(montarJanela({ dias: [] })).toEqual([]);
    expect(montarJanela({ de: "" })).toEqual([]);
  });

  it("escolher os sete dias é o mesmo que não escolher nenhum", () => {
    expect(montarJanela({ dias: [0, 1, 2, 3, 4, 5, 6] })).toEqual([]);
  });

  it("guarda os dias em ordem", () => {
    expect(montarJanela({ dias: [4, 2] })).toEqual([{ dias: [2, 4] }]);
  });

  it("monta o caso do protótipo", () => {
    expect(montarJanela({ dias: [2, 3], de: "13:00" })).toEqual([
      { dias: [2, 3], de: "13:00" },
    ]);
  });

  it("ignora hora malformada em vez de gravar lixo", () => {
    expect(montarJanela({ de: "13h" })).toEqual([]);
  });

  it("ida e volta: o que se monta é o que se lê", () => {
    const j = montarJanela({ dias: [2, 3], de: "13:00" });
    expect(rotuloJanela(j)).toBe("terça ou quarta, depois das 13h");
  });
});

describe("o tempo de espera, que ordena a fila", () => {
  const agora = new Date("2026-09-01T12:00:00Z");

  it("conta os dias desde a última sessão", () => {
    expect(tempoDeEspera("2026-08-21T12:00:00Z", agora)).toBe("11 dias sem sessão");
    expect(tempoDeEspera("2026-08-26T12:00:00Z", agora)).toBe("6 dias sem sessão");
  });

  it("singular no primeiro dia", () => {
    expect(tempoDeEspera("2026-08-31T12:00:00Z", agora)).toBe("1 dia sem sessão");
  });

  it("quem nunca teve sessão vai para o topo da fila", () => {
    expect(tempoDeEspera(null, agora)).toBe("ainda sem sessão");
  });

  it("quem foi hoje não conta dia", () => {
    expect(tempoDeEspera("2026-09-01T09:00:00Z", agora)).toBe("sessão hoje");
  });
});
