import { describe, it, expect } from "vitest";
import {
  CATEGORIAS,
  rotuloCategoria,
  lerPainel,
  fraseDasDuasColunas,
  fraseDoRecuperado,
  fraseDoAgendado,
  fraseSemRegistro,
  nomeDoMes,
  limitesDoMes,
  mesAnterior,
  mesSeguinte,
  competenciaDoDia,
  type PainelBruto,
} from "@/lib/financeiro";
import { formatar } from "@/lib/dinheiro";

/**
 * Os números aqui são os mesmos da suíte SQL `0037_financeiro.sql`: recebido de
 * R$ 300, despesas de R$ 1.500 em três lançamentos. Se as duas contas
 * divergirem, uma das duas falha e a outra diz onde.
 *
 * Nenhuma asserção de dinheiro compara com string literal: `formatar()` usa
 * **espaço não separável** depois do "R$", e um literal digitado com espaço
 * comum nunca bate.
 */

const BRUTO: PainelBruto = {
  de: "2026-07-01",
  ate: "2026-07-31",
  realizado: { valor: "400.00", sessoes: 2 },
  recebido: {
    valor: "300.00",
    cobrancas: 2,
    por_tipo: { falta: "100.00", sessao: "200.00" },
  },
  em_aberto: { valor: "0", cobrancas: 0 },
  perdoado: { valor: "0", cobrancas: 0 },
  despesas: {
    valor: "1500.00",
    lancamentos: 3,
    por_categoria: [
      { categoria: "aluguel", valor: "900.00", lancamentos: 1 },
      { categoria: "supervisao", valor: "600.00", lancamentos: 2 },
    ],
  },
  sobra: "-1200.00",
  recuperado: { encaixes: 1, valor_encaixes: "200.00", faltas: 1, valor_faltas: "100.00" },
  sem_registro: { sessoes: 1, valor: "200.00" },
};

describe("as duas colunas", () => {
  it("traduz o painel para centavos inteiros", () => {
    const p = lerPainel(BRUTO);
    expect(p.realizado.centavos).toBe(40000);
    expect(p.recebido.centavos).toBe(30000);
    expect(p.despesas.centavos).toBe(150000);
  });

  it("a sobra é recebido menos despesa — e bate com a do banco", () => {
    const p = lerPainel(BRUTO);
    expect(p.sobra).toBe(-120000);
    expect(p.sobra).toBe(Math.round(Number(BRUTO.sobra) * 100));
  });

  it("não existe função que some realizado com recebido", () => {
    const p = lerPainel(BRUTO);
    // A soma seria 700 — dinheiro que não existe. O que existe é cada coluna.
    expect(p.realizado.centavos + p.recebido.centavos).toBe(70000);
    expect(Object.keys(p)).not.toContain("total");
    expect(Object.keys(p)).not.toContain("lucro");
  });

  it("o painel do banco também não traz um total", () => {
    expect(Object.keys(BRUTO)).not.toContain("total");
  });

  it("a frase diz, em português, por que não se somam", () => {
    const f = fraseDasDuasColunas(lerPainel(BRUTO));
    expect(f).toContain(formatar(40000));
    expect(f).toContain(formatar(30000));
    expect(f).toContain("não se somam");
  });

  it("mês vazio tem frase própria, sem número", () => {
    const vazio = lerPainel({
      ...BRUTO,
      realizado: { valor: "0", sessoes: 0 },
      recebido: { valor: "0", cobrancas: 0, por_tipo: {} },
    });
    expect(fraseDasDuasColunas(vazio)).toBe("Mês sem atendimento e sem entrada registrada.");
  });

  it("o recebido vem quebrado por tipo, na ordem de leitura", () => {
    const p = lerPainel(BRUTO);
    expect(p.recebido.porTipo.map((t) => t.tipo)).toEqual(["sessao", "falta"]);
    expect(p.recebido.porTipo[0].centavos).toBe(20000);
  });

  it("por_tipo ausente não quebra a tela", () => {
    const p = lerPainel({
      ...BRUTO,
      recebido: { valor: "0", cobrancas: 0, por_tipo: {} },
    });
    expect(p.recebido.porTipo).toEqual([]);
  });
});

describe("o que voltou para o mês", () => {
  it("soma encaixe realizado e falta paga", () => {
    const f = fraseDoRecuperado(lerPainel(BRUTO));
    expect(f).toContain(formatar(30000));
    expect(f).toContain("1 hora que a fila preencheu");
    expect(f).toContain("1 falta que você decidiu cobrar");
  });

  it("sem nada recuperado, não inventa frase", () => {
    const p = lerPainel({
      ...BRUTO,
      recuperado: { encaixes: 0, valor_encaixes: "0", faltas: 0, valor_faltas: "0" },
    });
    expect(fraseDoRecuperado(p)).toBe("");
  });

  it("pluraliza quando há mais de um", () => {
    const p = lerPainel({
      ...BRUTO,
      recuperado: { encaixes: 3, valor_encaixes: "600.00", faltas: 2, valor_faltas: "200.00" },
    });
    expect(fraseDoRecuperado(p)).toContain("3 horas que a fila preencheu");
    expect(fraseDoRecuperado(p)).toContain("2 faltas que você decidiu cobrar");
  });
});

describe("as horas sem registro", () => {
  it("diz quantas e quanto", () => {
    const f = fraseSemRegistro(lerPainel(BRUTO));
    expect(f).toContain("1 hora sem registro");
    expect(f).toContain(formatar(20000));
  });

  it("cala quando está tudo registrado", () => {
    const p = lerPainel({ ...BRUTO, sem_registro: { sessoes: 0, valor: "0" } });
    expect(fraseSemRegistro(p)).toBe("");
  });
});

describe("as categorias", () => {
  it("são dez, fixas", () => {
    expect(CATEGORIAS).toHaveLength(10);
    expect(new Set(CATEGORIAS.map((c) => c.valor)).size).toBe(10);
  });

  it("nenhum rótulo promete abatimento de imposto", () => {
    const proibidas = /dedut|abate|imposto de renda|livro caixa|carn/i;
    for (const c of CATEGORIAS) {
      expect(`${c.rotulo} ${c.exemplo}`).not.toMatch(proibidas);
    }
  });

  it("traduz a categoria e devolve o cru quando não conhece", () => {
    expect(rotuloCategoria("supervisao")).toBe("Supervisão");
    expect(rotuloCategoria("inventada")).toBe("inventada");
  });

  it("a quebra por categoria chega em centavos", () => {
    const p = lerPainel(BRUTO);
    expect(p.despesas.porCategoria[1]).toEqual({
      categoria: "supervisao",
      centavos: 60000,
      lancamentos: 2,
    });
  });
});

describe("o mês", () => {
  it("tem nome em português", () => {
    expect(nomeDoMes("2026-08")).toBe("agosto de 2026");
    expect(nomeDoMes("2026-03")).toBe("março de 2026");
  });

  it("conhece o próprio tamanho, sem depender do relógio de quem abriu", () => {
    expect(limitesDoMes("2026-02")).toEqual({ de: "2026-02-01", ate: "2026-02-28" });
    expect(limitesDoMes("2028-02")).toEqual({ de: "2028-02-01", ate: "2028-02-29" });
    expect(limitesDoMes("2026-12")).toEqual({ de: "2026-12-01", ate: "2026-12-31" });
  });

  it("anda para trás e para a frente, atravessando o ano", () => {
    expect(mesAnterior("2026-01")).toBe("2025-12");
    expect(mesSeguinte("2026-12")).toBe("2027-01");
    expect(mesAnterior("2026-08")).toBe("2026-07");
    expect(mesSeguinte("2026-08")).toBe("2026-09");
  });

  it("sai do dia para a competência", () => {
    expect(competenciaDoDia("2026-08-31")).toBe("2026-08");
  });

  it("recusa competência inventada em vez de responder errado", () => {
    expect(() => limitesDoMes("2026-13")).toThrow();
    expect(() => mesAnterior("agosto")).toThrow();
    expect(() => competenciaDoDia("ontem")).toThrow();
  });
});

/*
  O número em serifa de 26 px da agenda somava sessão que ainda não aconteceu, e
  a mesma tela do Financeiro, que só conta `realizada`, mostrava zero para o
  mesmo fato. A `0090` separou os dois no banco; aqui é a frase do que ficou de
  fora da soma.
*/
describe("fraseDoAgendado — o que a fila preencheu e ainda não aconteceu", () => {
  it("some quando não há nada marcado", () => {
    expect(fraseDoAgendado(0, 0)).toBe("");
    expect(fraseDoAgendado(-100, 2)).toBe("");
  });

  it("diz o valor e as horas, sem chamar de ganho", () => {
    // `formatar` usa espaço não-quebrável entre "R$" e o número, como o pt-BR
    // manda — comparar com literal de teclado reprova por um caractere que a
    // tela desenha igual.
    const f = fraseDoAgendado(75000, 2.5);
    expect(f).toContain(formatar(75000));
    expect(f).toContain("2,5 horas");
    expect(f).toContain("ainda não aconteceram");
    expect(f).not.toMatch(/recuperad|ganho|entrou|voltou/i);
  });

  it("sem horas, fala só do valor", () => {
    expect(fraseDoAgendado(20000, 0)).toBe(
      `Mais ${formatar(20000)} já marcados, que ainda não aconteceram.`,
    );
  });
});
