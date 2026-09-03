import { describe, expect, it } from "vitest";
import {
  rotuloHorario,
  rotuloPolitica,
  classificarCancelamento,
  multaDeFalta,
  resumoDoEnquadre,
  combinadoTocado,
  PADRAO_ENQUADRE,
  type CamposDoCombinado,
} from "./enquadre";
import { paraCentavos } from "./dinheiro";

describe("enquadre — como o combinado aparece", () => {
  it("mostra o horário do jeito que ela fala", () => {
    expect(rotuloHorario(2, "15:00")).toBe("terça, 15h");
    expect(rotuloHorario(4, "19:30")).toBe("quinta, 19h30");
    expect(rotuloHorario(0, "08:00")).toBe("domingo, 8h");
  });

  it("escreve a política em português", () => {
    expect(rotuloPolitica({ horas: 24, percentual: 50 })).toBe(
      "desmarcar com menos de 24 horas cobra 50%",
    );
    expect(rotuloPolitica({ horas: 48, percentual: 100 })).toBe(
      "desmarcar com menos de 48 horas cobra a sessão inteira",
    );
    expect(rotuloPolitica({ horas: 24, percentual: 0 })).toBe("falta não é cobrada");
    expect(rotuloPolitica({ horas: 0, percentual: 100 })).toBe(
      "falta cobra 100% em qualquer aviso",
    );
  });

  it("resume o enquadre inteiro numa linha", () => {
    expect(
      resumoDoEnquadre({
        dia_semana: 2,
        hora: "15:00",
        duracao_min: 50,
        valor: "200.00",
        politica_horas: 24,
        politica_percentual: 50,
      }),
    ).toContain("terça, 15h · 50 min ·");
  });
});

describe("D2 — o cancelamento se classifica sozinho", () => {
  const sessao = new Date("2026-09-01T18:00:00Z"); // terça, 15h em São Paulo
  const politica = { horas: 24, percentual: 50 };

  it("o caso do protótipo: desmarcou às 11h42, três horas antes — é tardio", () => {
    const aviso = new Date("2026-09-01T14:42:00Z"); // 11h42 em SP
    expect(classificarCancelamento(sessao, aviso, politica)).toBe("cancelada_tarde");
  });

  it("desmarcou com dois dias — está dentro do combinado", () => {
    const aviso = new Date("2026-08-30T18:00:00Z");
    expect(classificarCancelamento(sessao, aviso, politica)).toBe("cancelada_cedo");
  });

  it("exatamente no limite conta como dentro do prazo", () => {
    const aviso = new Date("2026-08-31T18:00:00Z"); // 24h cravadas
    expect(classificarCancelamento(sessao, aviso, politica)).toBe("cancelada_cedo");
  });

  it("um minuto depois do limite já é tardio", () => {
    const aviso = new Date("2026-08-31T18:01:00Z");
    expect(classificarCancelamento(sessao, aviso, politica)).toBe("cancelada_tarde");
  });

  it("avisar depois da sessão começar é sempre tardio", () => {
    const aviso = new Date("2026-09-01T19:00:00Z");
    expect(classificarCancelamento(sessao, aviso, politica)).toBe("cancelada_tarde");
    expect(
      classificarCancelamento(sessao, aviso, { horas: 0, percentual: 100 }),
    ).toBe("cancelada_tarde");
  });

  it("política de zero hora cobra sempre, menos quem avisa antes da hora exata", () => {
    const antes = new Date("2026-09-01T17:59:00Z");
    expect(classificarCancelamento(sessao, antes, { horas: 0, percentual: 100 })).toBe(
      "cancelada_cedo",
    );
  });
});

describe("D2 — quanto o sistema cobra sem ela precisar falar", () => {
  const politica = { horas: 24, percentual: 50 };
  const sessao = paraCentavos("200.00");

  it("50% de R$ 200 na falta tardia", () => {
    expect(multaDeFalta(sessao, "cancelada_tarde", politica)).toBe(10000);
  });

  it("nada quando avisou dentro do prazo — avisar cedo compensa para os dois", () => {
    expect(multaDeFalta(sessao, "cancelada_cedo", politica)).toBe(0);
  });

  it("quem não cobra falta não cobra nem no tardio", () => {
    expect(multaDeFalta(sessao, "cancelada_tarde", { horas: 24, percentual: 0 })).toBe(0);
  });

  it("valor social também é proporcional, sem arredondar para cima", () => {
    // Sessão social de R$ 70 com 50% = R$ 35,00
    expect(multaDeFalta(paraCentavos("70.00"), "cancelada_tarde", politica)).toBe(3500);
    // R$ 83,33 com 30% = R$ 24,999 → R$ 25,00
    expect(
      multaDeFalta(paraCentavos("83.33"), "cancelada_tarde", { horas: 24, percentual: 30 }),
    ).toBe(2500);
  });

  it("a ponta a ponta da política: desmarcou 3h antes de uma sessão de R$ 200", () => {
    const inicio = new Date("2026-09-01T18:00:00Z");
    const aviso = new Date("2026-09-01T15:00:00Z");
    const classe = classificarCancelamento(inicio, aviso, politica);
    expect(classe).toBe("cancelada_tarde");
    expect(multaDeFalta(sessao, classe, politica)).toBe(10000);
  });
});

// ============================================ a seção do combinado foi tocada?

describe("combinadoTocado", () => {
  const intocado: CamposDoCombinado = {
    hora: "",
    valor: "",
    dia_semana: String(PADRAO_ENQUADRE.dia_semana),
    duracao_min: String(PADRAO_ENQUADRE.duracao_min),
    modelo_cobranca: PADRAO_ENQUADRE.modelo_cobranca,
    mensalidade_valor: "",
    social: false,
    falta_cobra_a_parte: false,
    politica_horas: String(PADRAO_ENQUADRE.politica_horas),
    politica_percentual: String(PADRAO_ENQUADRE.politica_percentual),
    confirmacao_horas_antes: "",
  };

  it("a seção como o formulário a desenha é intocada", () => {
    expect(combinadoTocado(intocado)).toBe(false);
  });

  it("campo em branco também é intocado — vazio não é zero", () => {
    expect(
      combinadoTocado({
        ...intocado,
        dia_semana: "",
        duracao_min: "",
        politica_horas: "",
        politica_percentual: "",
        modelo_cobranca: "",
      }),
    ).toBe(false);
  });

  it("hora ou valor sozinhos já contam", () => {
    expect(combinadoTocado({ ...intocado, hora: "15:00" })).toBe(true);
    expect(combinadoTocado({ ...intocado, valor: "200" })).toBe(true);
  });

  /*
    O caso que dava o defeito: ela mexe em tudo, menos em hora e valor. Antes
    isto devolvia "sem combinado" e a paciente era criada com o combinado
    inteiro jogado fora, sem aviso nenhum na tela.
  */
  it("cada campo da seção, sozinho, é suficiente", () => {
    const mexidas: Partial<CamposDoCombinado>[] = [
      { dia_semana: "4" },
      { duracao_min: "60" },
      { modelo_cobranca: "mensal" },
      { mensalidade_valor: "800" },
      { social: true },
      { falta_cobra_a_parte: true },
      { politica_horas: "48" },
      { politica_percentual: "100" },
      { confirmacao_horas_antes: "24" },
    ];
    for (const mexida of mexidas) {
      expect(combinadoTocado({ ...intocado, ...mexida }), JSON.stringify(mexida)).toBe(true);
    }
  });

  it("número que não é número conta como mexida, e cai na validação", () => {
    expect(combinadoTocado({ ...intocado, politica_percentual: "abc" })).toBe(true);
  });
});
