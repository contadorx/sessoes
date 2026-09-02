import { describe, it, expect } from "vitest";
import {
  lerCockpit,
  quatroNumeros,
  perdaTotalCentavos,
  perdasComPeso,
  acaoDaPerda,
  fraseDoCockpit,
  fraseDoProtegido,
  fraseDoAlemDoDeclarado,
  fraseDosAlertas,
  type CockpitBruto,
} from "@/lib/risco";
import * as modulo from "@/lib/risco";
import { formatar } from "@/lib/dinheiro";

/**
 * Os números são os da suíte SQL `0059_receita_em_risco.sql`: 300 minutos
 * vendáveis e 60 protegidos, 100 minutos atendidos (33,3%), 50 minutos pagos
 * (16,7%), R$ 400 reconhecidos em 5 horas (R$ 80 por hora).
 *
 * Os testes que decidem o arquivo são os de "o que ele se recusa a dizer": sem
 * semana declarada não existe 0%, nada elogia ocupação alta, e a hora nunca
 * vendida não ganha botão.
 */

const BRUTO: CockpitBruto = {
  de: "2026-09-03",
  ate: "2026-09-03",
  ocupacao_realizada: 33.3,
  ocupacao_paga: 16.7,
  receita_por_hora: "80.00",
  receita_reconhecida: "400.00",
  minutos: { realizada: 100, paga: 50, reservada: 50, vendavel: 300, protegido: 60 },
  capacidade: {
    de: "2026-09-03",
    ate: "2026-09-03",
    dias: 1,
    sem_janela: false,
    vendavel_min: 300,
    registro_min: 60,
    descanso_min: 0,
    declarado_min: 360,
    fora: { ferias: 0, feriado: 0, bloqueio: 0, total: 0 },
  },
  completude: { sessoes: 4, completas: 4, resolvidas: 3, repostas: 0 },
  alem_do_declarado: false,
  causas: [
    { causa: "falta_sem_cobranca", n: 1, valor: "200.00", acao: "propor_cobranca" },
    { causa: "falta_com_cobranca", n: 0, valor: "0", acao: null },
    { causa: "cancelada_nao_revendida", n: 0, valor: "0", acao: "ver_ofertas" },
    { causa: "reposta", n: 0, valor: "0", acao: "rever_politica" },
    { causa: "atendida_nao_recebida", n: 1, valor: "200.00", acao: "regua" },
    { causa: "abaixo_do_valor", n: 0, valor: "0", acao: "ver_contrato" },
    { causa: "hora_nunca_vendida", n: null, valor: null, minutos: 100, acao: null },
  ],
};

const SEM_JANELA: CockpitBruto = {
  ...BRUTO,
  ocupacao_realizada: null,
  ocupacao_paga: null,
  receita_por_hora: null,
  receita_reconhecida: "0",
  minutos: { realizada: 0, paga: 0, reservada: 0, vendavel: 0, protegido: 0 },
  capacidade: {
    ...BRUTO.capacidade,
    sem_janela: true,
    vendavel_min: 0,
    registro_min: 0,
    declarado_min: 0,
  },
  causas: BRUTO.causas.map((c) => ({ ...c, n: 0, valor: "0", minutos: 0 })),
};

describe("os quatro números", () => {
  it("saem com os mesmos valores da suíte SQL", () => {
    const c = lerCockpit(BRUTO);
    expect(c.ocupacaoRealizada).toBe(33.3);
    expect(c.ocupacaoPaga).toBe(16.7);
    expect(c.receitaPorHora).toBe(8000);
    expect(c.receitaCentavos).toBe(40000);
  });

  it("são sempre quatro, e a lista não se pede pela metade", () => {
    const q = quatroNumeros(lerCockpit(BRUTO));
    expect(q).toHaveLength(4);
    expect(q.map((x) => x.chave)).toEqual(["realizada", "paga", "por_hora", "perda"]);
  });

  it("a perda soma as causas com valor, e não a falta já cobrada", () => {
    // 200 (falta sem cobrança) + 200 (atendida e não recebida).
    expect(perdaTotalCentavos(lerCockpit(BRUTO))).toBe(40000);
  });

  it("a perda não conta a falta com cobrança — ela não é perda, é a política", () => {
    const com = lerCockpit({
      ...BRUTO,
      causas: BRUTO.causas.map((c) =>
        c.causa === "falta_com_cobranca" ? { ...c, n: 3, valor: "300.00" } : c,
      ),
    });
    expect(perdaTotalCentavos(com)).toBe(40000);
  });

  it("ocupação paga nunca é maior que a realizada nos dados do banco", () => {
    const c = lerCockpit(BRUTO);
    expect(c.minutos.paga).toBeLessThanOrEqual(c.minutos.realizada);
  });
});

describe("sem semana declarada", () => {
  it("os três percentuais são nulos, e não zero", () => {
    const c = lerCockpit(SEM_JANELA);
    expect(c.ocupacaoRealizada).toBeNull();
    expect(c.ocupacaoPaga).toBeNull();
    expect(c.receitaPorHora).toBeNull();
    expect(c.semJanela).toBe(true);
  });

  it("os números aparecem como travessão, e nunca como 0%", () => {
    const q = quatroNumeros(lerCockpit(SEM_JANELA));
    expect(q[0].valor).toBe("—");
    expect(q[1].valor).toBe("—");
    expect(q[2].valor).toBe("—");
  });

  it("a frase fala do que falta declarar, e não contém 0%", () => {
    const f = fraseDoCockpit(lerCockpit(SEM_JANELA));
    expect(f).toContain("ainda não declarou");
    expect(f).not.toContain("0%");
  });
});

describe("o que o módulo se recusa a dizer", () => {
  it("a frase do cockpit nunca fala de ocupação sem falar de receita por hora", () => {
    const f = fraseDoCockpit(lerCockpit(BRUTO));
    expect(f).toContain("33,3%");
    expect(f).toContain(formatar(8000));
  });

  it("passar de 100% é fato, e nenhuma frase parabeniza", () => {
    const alem = lerCockpit({
      ...BRUTO,
      ocupacao_realizada: 116.7,
      alem_do_declarado: true,
      minutos: { ...BRUTO.minutos, realizada: 350 },
    });
    const f = fraseDoAlemDoDeclarado(alem);
    expect(f).toContain("mais horas do que declarou");
    expect(f).not.toMatch(/parab|ótim|excelente|muito bem|sucesso|recorde/i);
  });

  it("quem não passou de 100% não recebe frase nenhuma", () => {
    expect(fraseDoAlemDoDeclarado(lerCockpit(BRUTO))).toBe("");
  });

  it("o tempo protegido aparece, e é dito como capacidade e não como sobra", () => {
    const f = fraseDoProtegido(lerCockpit(BRUTO));
    expect(f).toContain("1,0h");
    expect(f).toContain("registro e descanso");
    expect(f).not.toMatch(/oci|vaga|livre|sobra|desperdi/i);
  });

  it("nenhuma frase do módulo sugere preencher, oferecer ou convidar alguém", () => {
    const c = lerCockpit(BRUTO);
    const tudo = [
      fraseDoCockpit(c),
      fraseDoProtegido(c),
      fraseDoAlemDoDeclarado(lerCockpit({ ...BRUTO, alem_do_declarado: true })),
      fraseDosAlertas({ de: "", ate: "", alertas: [] }),
      ...quatroNumeros(c).map((q) => `${q.rotulo} ${q.nota}`),
    ].join(" ");
    expect(tudo).not.toMatch(/preench|ofere[cç]|divulg|convid|captar|prospect|reativ/i);
  });

  it("nenhum rótulo do cockpit fala em meta, alvo ou ideal", () => {
    const q = quatroNumeros(lerCockpit(BRUTO));
    for (const x of q) {
      expect(`${x.rotulo} ${x.nota}`).not.toMatch(/meta|alvo|ideal|objetivo|deveria/i);
    }
  });

  it("o módulo não exporta nada que devolva ocupação sozinha", () => {
    for (const nome of Object.keys(modulo)) {
      expect(nome).not.toMatch(/^ocupacao|taxaDeOcupacao|ocupacaoDo/i);
    }
  });
});

describe("as perdas com ação", () => {
  it("só aparecem as que têm peso", () => {
    const p = perdasComPeso(lerCockpit(BRUTO));
    expect(p.map((x) => x.causa)).toEqual([
      "falta_sem_cobranca",
      "atendida_nao_recebida",
      "hora_nunca_vendida",
    ]);
  });

  it("a hora nunca vendida aparece por minutos, e sem valor", () => {
    const h = perdasComPeso(lerCockpit(BRUTO)).find((x) => x.causa === "hora_nunca_vendida")!;
    expect(h.minutos).toBe(100);
    expect(h.valor).toBeNull();
  });

  it("e não tem ação — é a decisão do build, e ela é ética", () => {
    expect(acaoDaPerda("hora_nunca_vendida")).toBeNull();
  });

  it("a falta já cobrada também não tem ação: não é problema", () => {
    expect(acaoDaPerda("falta_com_cobranca")).toBeNull();
  });

  it("as cinco que têm ação têm rótulo e destino", () => {
    for (const c of [
      "falta_sem_cobranca",
      "cancelada_nao_revendida",
      "reposta",
      "atendida_nao_recebida",
      "abaixo_do_valor",
    ] as const) {
      const a = acaoDaPerda(c);
      expect(a).not.toBeNull();
      expect(a!.href.startsWith("/")).toBe(true);
    }
  });
});

describe("o alerta que ninguém usou", () => {
  it("sem candidatos, a frase diz que os alertas serviram", () => {
    expect(fraseDosAlertas({ de: "", ate: "", alertas: [] })).toContain("levaram a alguma coisa");
  });

  it("com candidatos, a frase é sobre o alerta e não sobre ela", () => {
    const f = fraseDosAlertas({
      de: "",
      ate: "",
      alertas: [{ causa: "reposta", n: 2, valor: "300", nunca_usado: true }],
    });
    expect(f).toContain("candidato a sumir");
    expect(f).not.toMatch(/você não|você deixou|esqueceu/i);
  });
});
