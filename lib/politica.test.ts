import { describe, it, expect } from "vitest";
import {
  multaSugerida,
  ajusteValido,
  problemaNoAjuste,
  lerHistorico,
  fraseDoHistorico,
  fraseDaEspera,
  fraseDoAviso,
  fraseDaCaixa,
  rotuloMotivo,
  DECISOES,
  type HistoricoBruto,
} from "@/lib/politica";
import * as modulo from "@/lib/politica";
import { formatar } from "@/lib/dinheiro";

/**
 * O `Intl` põe um espaço **fino e inquebrável** depois do "R$", e um literal
 * digitado à mão nunca bate com ele. A lição já custou tempo na 0031: quando o
 * teste precisa do dinheiro formatado, ele chama `formatar` em vez de escrever
 * o texto.
 */

/**
 * Os números são os da suíte SQL `0058_politica_assistida.sql`: 50% de R$ 200
 * dá R$ 100 (verificação 2), 40% de R$ 300 dá R$ 120 (verificação 10), o
 * ajuste para R$ 50 vale (12), R$ 250 sobre uma sessão de R$ 200 não vale (13)
 * e zero não vale (14).
 *
 * O teste que decide o arquivo é o de "o módulo não decide": nada aqui devolve
 * recomendação, e nada ordena proposta por gravidade.
 */

describe("a multa sugerida", () => {
  it("é a mesma conta do banco", () => {
    expect(multaSugerida(20000, 50)).toBe(10000);
    expect(multaSugerida(30000, 40)).toBe(12000);
    expect(multaSugerida(20000, 0)).toBe(0);
  });

  it("arredonda meio-centavo para longe do zero, como o `multa_da_politica`", () => {
    // 33% de R$ 15,05 = 496,65 centavos → 497, e não 496.
    expect(multaSugerida(1505, 33)).toBe(497);
  });
});

describe("o ajuste tem as duas bordas", () => {
  it("cobrar menos vale", () => {
    expect(ajusteValido(5000, 20000)).toBe(true);
    expect(problemaNoAjuste(5000, 20000)).toBeNull();
  });

  it("cobrar o valor cheio da política vale", () => {
    expect(ajusteValido(10000, 20000)).toBe(true);
  });

  it("cobrar exatamente o valor da sessão vale — é o teto, não o proibido", () => {
    expect(ajusteValido(20000, 20000)).toBe(true);
  });

  it("acima do valor da sessão não vale, e a frase diz o teto", () => {
    expect(ajusteValido(25000, 20000)).toBe(false);
    expect(problemaNoAjuste(25000, 20000)).toContain(formatar(20000));
  });

  it("zero não vale, e a frase manda perdoar", () => {
    expect(ajusteValido(0, 20000)).toBe(false);
    expect(problemaNoAjuste(0, 20000)).toContain("perdoa");
  });

  it("negativo e quebrado também não", () => {
    expect(ajusteValido(-100, 20000)).toBe(false);
    expect(ajusteValido(10.5, 20000)).toBe(false);
    expect(ajusteValido(NaN, 20000)).toBe(false);
  });
});

describe("o histórico conta, e não aconselha", () => {
  const BRUTO: HistoricoBruto = {
    realizadas: 18,
    faltas: 1,
    tardias: 1,
    cobradas: 1,
    pagas: 1,
    perdoadas: 1,
    valor_perdoado: "120.00",
    ultima_decisao: null,
  };

  it("soma falta e desmarque tardio numa coisa só: ausência", () => {
    const h = lerHistorico(BRUTO);
    expect(h.ausencias).toBe(2);
    expect(h.valorPerdoadoCentavos).toBe(12000);
  });

  it("a frase traz os números e o denominador", () => {
    const f = fraseDoHistorico(lerHistorico(BRUTO));
    expect(f).toContain("2 ausências");
    expect(f).toContain("20 horas reservadas");
    expect(f).toContain(formatar(12000));
  });

  it("sem história nenhuma, não mostra uma coluna de zeros", () => {
    const f = fraseDoHistorico(
      lerHistorico({ ...BRUTO, realizadas: 0, faltas: 0, tardias: 0, cobradas: 0, pagas: 0, perdoadas: 0, valor_perdoado: 0 }),
    );
    expect(f).toBe("Sem histórico ainda com esta pessoa.");
  });

  it("quem nunca faltou aparece como quem nunca faltou", () => {
    const f = fraseDoHistorico(
      lerHistorico({ ...BRUTO, faltas: 0, tardias: 0, cobradas: 0, pagas: 0, perdoadas: 0, valor_perdoado: 0 }),
    );
    expect(f).toContain("nenhuma ausência");
  });

  it("nenhuma frase do histórico conclui coisa alguma", () => {
    const casos = [
      { ...BRUTO },
      { ...BRUTO, faltas: 5, tardias: 3, perdoadas: 4 },
      { ...BRUTO, realizadas: 0, faltas: 0, tardias: 0 },
    ].map((b) => fraseDoHistorico(lerHistorico(b)));

    for (const f of casos) {
      expect(f).not.toMatch(/reincid|recomend|sugir|sugest|deveria|precisa cobrar|padrão de/i);
    }
  });

  it("o módulo não exporta nada que decida por ela", () => {
    for (const nome of Object.keys(modulo)) {
      expect(nome).not.toMatch(/sugerirDecisao|recomendar|decidirSozinh|ordenarPorGravidade|risco/i);
    }
  });
});

describe("a espera não vira urgência", () => {
  it("diz a idade, e só", () => {
    expect(fraseDaEspera(0)).toBe("de hoje");
    expect(fraseDaEspera(1)).toBe("de ontem");
    expect(fraseDaEspera(12)).toContain("12 dias");
  });

  it("e nunca fala em prazo, vencimento ou atraso — proposta não caduca", () => {
    for (const d of [0, 1, 3, 30, 400]) {
      expect(fraseDaEspera(d)).not.toMatch(/venc|prazo|expira|atrasad|urgente/i);
    }
  });
});

describe("o que acontece com o aviso, dito na hora de decidir", () => {
  it("agendado diz a hora e que dá para desfazer", () => {
    const f = fraseDoAviso("agendado", "2026-09-02T18:30:00-03:00");
    expect(f).toContain("18:30");
    expect(f).toContain("desfazer");
  });

  it("quem pediu silêncio não recebe, e a tela devolve a conversa para ela", () => {
    expect(fraseDoAviso("silencio_do_paciente", null)).toContain("não receber mensagens");
  });

  it("a trava de segurança aparece no momento da decisão, e não depois", () => {
    // Era "o teto do plano". A OP8 tirou o teto de mensagens do produto, e a
    // frase passou a dizer o que de fato segurou: uma trava contra envio
    // repetido. Dizer "o seu plano atingiu o limite" sobre uma trava técnica
    // manda a pessoa procurar solução comercial para um problema que não é dela.
    const f = fraseDoAviso("barrado_no_teto", null);
    expect(f).toContain("trava de segurança");
    expect(f).not.toContain("plano");
    expect(f).toContain("cobrança fica registrada");
  });

  it("perdão não fala de aviso nenhum", () => {
    expect(fraseDoAviso(null, null)).toBe("");
  });
});

describe("as duas decisões", () => {
  it("são duas, e a que não cobra tem nome de coisa que ela faz", () => {
    expect(DECISOES).toHaveLength(2);
    expect(DECISOES.map((d) => d.valor)).toEqual(["cobrar", "perdoar"]);
    expect(DECISOES[1].rotulo).toBe("Não cobrar");
  });

  it("perdoar diz que ninguém recebe mensagem", () => {
    expect(DECISOES[1].explica).toMatch(/ninguém recebe/i);
  });

  it("a caixa vazia não acusa ninguém de nada", () => {
    const f = fraseDaCaixa(0);
    expect(f).toContain("Nenhuma decisão");
    expect(f).not.toMatch(/pendente há|atrasad/i);
  });

  it("a caixa cheia diz a parte incômoda: sem decisão, nada sai", () => {
    expect(fraseDaCaixa(3)).toContain("nada é cobrado");
  });

  it("o motivo é escrito em português de gente", () => {
    expect(rotuloMotivo("cancelada_tarde")).toBe("desmarcou em cima da hora");
    expect(rotuloMotivo("falta")).toBe("não veio");
    expect(rotuloMotivo("coisa_nova")).toBe("coisa_nova");
  });
});
