import { describe, it, expect } from "vitest";
import * as ausencias from "./ausencias";
import {
  aconteceu,
  eAusencia,
  podeAnotar,
  rotuloDesfecho,
  sinalDoDesfecho,
  rotuloOrigem,
  rotuloCobranca,
  fraseDasUltimas,
  fraseDaSequencia,
  fraseDesdeAUltima,
  fraseDoTotal,
  fraseDaComposicao,
  diaCurto,
  porMes,
  nomeDoMes,
  DESFECHOS,
  type PainelAusencias,
  type LinhaDoTempo,
} from "./ausencias";

const vazio: PainelAusencias = {
  sessoes: 0,
  realizadas: 0,
  faltas: 0,
  cancelou_cedo: 0,
  cancelou_tarde: 0,
  ausencias: 0,
  seguidas: 0,
  ultimos: [],
  primeira: null,
  ultima: null,
  ultima_realizada: null,
  dias_desde_a_ultima_realizada: null,
  com_nota: 0,
};

const painel = (p: Partial<PainelAusencias> = {}): PainelAusencias => ({ ...vazio, ...p });

// ================================================ a fronteira do doc 07

describe("o módulo inteiro não interpreta — é a linha do doc 07", () => {
  /**
   * Gêmeo da verificação nº 9 da suíte SQL: lá o teste varre as chaves do jsonb,
   * aqui varre os nomes exportados. As duas metades do sistema guardam a mesma
   * fronteira, e é por isso que ela está escrita duas vezes.
   */
  it("não exporta nada com cara de juízo clínico", () => {
    const proibidos = [
      "risco", "escore", "score", "alerta", "abandono", "padrao", "padrão",
      "atencao", "atenção", "grave", "preocup", "sinaliza", "diagnost",
      "avaliar", "classificar", "gravidade",
    ];
    for (const nome of Object.keys(ausencias)) {
      for (const p of proibidos) {
        expect(
          nome.toLowerCase().includes(p),
          `o módulo exporta "${nome}" — isso é leitura clínica, e a leitura é dela`,
        ).toBe(false);
      }
    }
  });

  it("nenhuma frase carrega adjetivo de julgamento", () => {
    const adjetivos = /preocupante|grave|ruim|alarmante|crítico|critico|atenção|alerta|risco/i;
    const casos: PainelAusencias[] = [
      vazio,
      painel({ sessoes: 10, realizadas: 1, faltas: 9, ausencias: 9, seguidas: 9,
               ultimos: ["falta","falta","falta","falta","falta","falta","falta","falta"],
               dias_desde_a_ultima_realizada: 200 }),
      painel({ sessoes: 5, realizadas: 5, ultimos: ["realizada","realizada"],
               dias_desde_a_ultima_realizada: 3 }),
    ];
    for (const p of casos) {
      const tudo = [
        fraseDasUltimas(p),
        fraseDaSequencia(p),
        fraseDesdeAUltima(p),
        fraseDoTotal(p),
        fraseDaComposicao(p),
      ].join(" ");
      expect(tudo).not.toMatch(adjetivos);
    }
  });

  it("o sinal da faixa não é semáforo — cor de julgamento é juízo desenhado", () => {
    expect(sinalDoDesfecho("realizada")).toBe("●");
    expect(sinalDoDesfecho("falta")).toBe("○");
    expect(sinalDoDesfecho("cancelada_cedo")).toBe("○");
    expect(sinalDoDesfecho("cancelada_tarde")).toBe("○");
  });
});

// ==================================================== onde a nota cabe

describe("podeAnotar — gêmea do gatilho nota_so_na_ausencia", () => {
  it("cabe nas três ausências", () => {
    expect(podeAnotar("falta")).toBe(true);
    expect(podeAnotar("cancelada_cedo")).toBe(true);
    expect(podeAnotar("cancelada_tarde")).toBe(true);
  });

  it("NÃO cabe na sessão realizada — evolução é prontuário, e prontuário é fase 3", () => {
    expect(podeAnotar("realizada")).toBe(false);
  });

  it("nem no que ainda não aconteceu", () => {
    expect(podeAnotar("prevista")).toBe(false);
    expect(podeAnotar("confirmada")).toBe(false);
  });
});

describe("aconteceu e eAusencia", () => {
  it("só realizada aconteceu", () => {
    expect(aconteceu("realizada")).toBe(true);
    expect(aconteceu("falta")).toBe(false);
    expect(aconteceu("prevista")).toBe(false);
  });

  it("previsto não é ausência — ainda não é passado", () => {
    expect(eAusencia("prevista")).toBe(false);
    expect(eAusencia("confirmada")).toBe(false);
  });

  it("os quatro desfechos são exatamente os do banco", () => {
    expect(DESFECHOS).toEqual(["realizada", "falta", "cancelada_cedo", "cancelada_tarde"]);
  });
});

// ==================================================== as frases

describe("fraseDasUltimas", () => {
  it("sem histórico, diz isso", () => {
    expect(fraseDasUltimas(vazio)).toBe("Ainda não houve nenhuma hora marcada com desfecho.");
  });

  it("todas aconteceram", () => {
    expect(fraseDasUltimas(painel({ ultimos: ["realizada", "realizada", "realizada"] }))).toBe(
      "As últimas 3 horas aconteceram.",
    );
  });

  it("nenhuma aconteceu", () => {
    expect(fraseDasUltimas(painel({ ultimos: ["falta", "cancelada_tarde"] }))).toBe(
      "As últimas 2 horas não aconteceram.",
    );
  });

  it("a mistura é uma fração, não um rótulo", () => {
    expect(
      fraseDasUltimas(
        painel({ ultimos: ["realizada", "falta", "realizada", "cancelada_cedo", "falta"] }),
      ),
    ).toBe("3 das últimas 5 horas não aconteceram.");
  });

  it("uma só, no singular", () => {
    expect(fraseDasUltimas(painel({ ultimos: ["falta"] }))).toBe("A última hora não aconteceu.");
    expect(fraseDasUltimas(painel({ ultimos: ["realizada"] }))).toBe("A última hora aconteceu.");
  });
});

describe("fraseDaSequencia", () => {
  it("cadeia zerada não fala nada — silêncio é melhor que 'nenhuma'", () => {
    expect(fraseDaSequencia(painel({ seguidas: 0 }))).toBe("");
  });

  it("uma, e mais de uma", () => {
    expect(fraseDaSequencia(painel({ seguidas: 1 }))).toBe("A última não aconteceu.");
    expect(fraseDaSequencia(painel({ seguidas: 4 }))).toBe("As últimas 4 seguidas não aconteceram.");
  });
});

describe("fraseDesdeAUltima", () => {
  it("nunca houve", () => {
    expect(fraseDesdeAUltima(vazio)).toBe("Nenhuma sessão realizada até agora.");
  });

  it("hoje e ontem têm nome, não número", () => {
    expect(fraseDesdeAUltima(painel({ dias_desde_a_ultima_realizada: 0 }))).toBe(
      "A última sessão aconteceu hoje.",
    );
    expect(fraseDesdeAUltima(painel({ dias_desde_a_ultima_realizada: 1 }))).toBe(
      "A última sessão aconteceu ontem.",
    );
  });

  it("dentro do mês, conta dias", () => {
    expect(fraseDesdeAUltima(painel({ dias_desde_a_ultima_realizada: 12 }))).toBe(
      "A última sessão aconteceu há 12 dias.",
    );
  });

  it("passando de um mês, traduz — e continua sem opinar", () => {
    const f = fraseDesdeAUltima(painel({ dias_desde_a_ultima_realizada: 95 }));
    expect(f).toMatch(/95 dias/);
    expect(f).toMatch(/3 meses/);
    expect(f).not.toMatch(/sumiu|abandon|risco/i);
  });

  it("um mês exato, no singular", () => {
    expect(fraseDesdeAUltima(painel({ dias_desde_a_ultima_realizada: 31 }))).toMatch(/1 mês/);
  });
});

describe("fraseDoTotal e fraseDaComposicao", () => {
  it("sem nada", () => {
    expect(fraseDoTotal(vazio)).toBe("Nenhuma hora com desfecho ainda.");
    expect(fraseDaComposicao(vazio)).toBe("");
  });

  it("só realizadas não menciona ausência", () => {
    expect(fraseDoTotal(painel({ sessoes: 8, realizadas: 8 }))).toBe(
      "8 horas · 8 aconteceram.",
    );
  });

  it("com ausências, separa", () => {
    expect(
      fraseDoTotal(painel({ sessoes: 10, realizadas: 7, ausencias: 3 })),
    ).toBe("10 horas · 7 aconteceram · 3 não aconteceram.");
  });

  it("a composição distingue quem avisou de quem não avisou", () => {
    const f = fraseDaComposicao(
      painel({ ausencias: 6, faltas: 2, cancelou_cedo: 3, cancelou_tarde: 1 }),
    );
    expect(f).toBe("2 sem aviso · 3 desmarcadas a tempo · 1 em cima da hora.");
  });

  it("só o que existe aparece", () => {
    expect(fraseDaComposicao(painel({ ausencias: 2, faltas: 2 }))).toBe("2 sem aviso.");
    expect(fraseDaComposicao(painel({ ausencias: 1, cancelou_cedo: 1 }))).toBe(
      "1 desmarcada a tempo.",
    );
  });

  it("singular e plural na hora", () => {
    expect(fraseDoTotal(painel({ sessoes: 1, realizadas: 1 }))).toBe("1 hora · 1 aconteceu.");
    expect(fraseDoTotal(painel({ sessoes: 1, realizadas: 0, ausencias: 1 }))).toBe(
      "1 hora · 0 aconteceram · 1 não aconteceu.",
    );
  });
});

// ==================================================== rótulos e listas

describe("rótulos", () => {
  it("o desfecho é dito como se diz, não como o banco guarda", () => {
    expect(rotuloDesfecho("realizada")).toBe("aconteceu");
    expect(rotuloDesfecho("falta")).toBe("não veio");
    expect(rotuloDesfecho("cancelada_cedo")).toBe("desmarcou a tempo");
    expect(rotuloDesfecho("cancelada_tarde")).toBe("desmarcou em cima da hora");
  });

  it("a origem só fala quando tem o que dizer", () => {
    expect(rotuloOrigem("encaixe")).toBe("entrou numa vaga que abriu");
    expect(rotuloOrigem("importada")).toBe("veio do sistema anterior");
    expect(rotuloOrigem("recorrencia")).toBeNull();
    expect(rotuloOrigem("avulsa")).toBeNull();
  });

  it("o dinheiro da linha, quando há", () => {
    const base: LinhaDoTempo = {
      sessao_id: "x",
      inicio: "2026-03-05T18:00:00Z",
      dia: "2026-03-05",
      estado: "falta",
      origem: "recorrencia",
      valor: "200.00",
      nota: null,
      nota_em: null,
      cobranca_estado: null,
      cobranca_tipo: null,
      cobranca_valor: null,
    };
    expect(rotuloCobranca(base)).toBeNull();
    expect(rotuloCobranca({ ...base, cobranca_estado: "paga" })).toBe("recebido");
    expect(rotuloCobranca({ ...base, cobranca_estado: "perdoada" })).toBe("perdoado");
    expect(rotuloCobranca({ ...base, cobranca_estado: "aberta" })).toBe("em aberto");
  });
});

describe("datas e agrupamento", () => {
  it("o ano some quando é o corrente", () => {
    expect(diaCurto("2026-03-05", "2026-09-01")).toBe("05/03");
    expect(diaCurto("2024-03-05", "2026-09-01")).toBe("05/03/2024");
  });

  it("nomeDoMes", () => {
    expect(nomeDoMes("2026-03")).toBe("março de 2026");
    expect(nomeDoMes("2026-12")).toBe("dezembro de 2026");
  });

  it("porMes preserva a ordem que veio do banco", () => {
    const l = (dia: string): LinhaDoTempo => ({
      sessao_id: dia,
      inicio: `${dia}T18:00:00Z`,
      dia,
      estado: "realizada",
      origem: "recorrencia",
      valor: "200.00",
      nota: null,
      nota_em: null,
      cobranca_estado: null,
      cobranca_tipo: null,
      cobranca_valor: null,
    });
    const grupos = porMes([l("2026-03-12"), l("2026-03-05"), l("2026-02-26")]);
    expect(grupos).toHaveLength(2);
    expect(grupos[0].mes).toBe("2026-03");
    expect(grupos[0].linhas).toHaveLength(2);
    expect(grupos[1].mes).toBe("2026-02");
  });

  it("lista vazia devolve nenhum grupo, e não um grupo vazio", () => {
    expect(porMes([])).toEqual([]);
  });
});
