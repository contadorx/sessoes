import { describe, it, expect } from "vitest";
import {
  estadoDoObjetivo,
  fraseDoObjetivo,
  fraseDoPlano,
  separar,
  type Objetivo,
} from "./objetivo";

const obj = (over: Partial<Objetivo> = {}): Objetivo => ({
  id: "o1",
  texto: "Retomar o trabalho sem crise de ansiedade",
  revisar_em: null,
  concluido_em: null,
  criado_em: "2026-01-10T12:00:00.000Z",
  ...over,
});

const HOJE = "2026-09-03";

describe("em que pé está o objetivo", () => {
  it("com data no futuro, está aberto", () => {
    expect(estadoDoObjetivo(obj({ revisar_em: "2026-12-01" }), HOJE)).toBe("aberto");
  });

  it("com a data alcançada, é a revisar — e hoje já conta", () => {
    expect(estadoDoObjetivo(obj({ revisar_em: "2026-06-01" }), HOJE)).toBe("a_revisar");
    expect(estadoDoObjetivo(obj({ revisar_em: HOJE }), HOJE)).toBe("a_revisar");
  });

  it("sem data, não é nem aberto nem a revisar", () => {
    expect(estadoDoObjetivo(obj(), HOJE)).toBe("sem_data");
  });

  it("concluído vence qualquer data", () => {
    const o = obj({ revisar_em: "2020-01-01", concluido_em: "2026-08-01T12:00:00.000Z" });
    expect(estadoDoObjetivo(o, HOJE)).toBe("concluido");
  });
});

/**
 * A regra da build, escrita como teste.
 *
 * A data que passou é um combinado dela consigo mesma, e o produto descreve o
 * combinado. Dizer "atrasado" seria atribuir uma falta — e a falta seria de
 * quem? Frequência e condução clínica não são decisão de software: é a
 * fronteira 3, a mesma que matou o alerta de sumiço.
 */
describe("vencido é fato, não alerta", () => {
  const PALAVRAS_DE_JUIZO = [
    "atrasad",
    "pendente",
    "esquec",
    "urgente",
    "precisa",
    "deveria",
    "há quanto tempo",
    "abandon",
  ];

  it("nenhuma frase de objetivo julga", () => {
    const casos = [
      obj({ revisar_em: "2020-01-01" }),
      obj({ revisar_em: "2026-12-01" }),
      obj(),
      obj({ concluido_em: "2026-08-01T12:00:00.000Z" }),
    ];
    for (const o of casos) {
      const frase = fraseDoObjetivo(o, HOJE).toLowerCase();
      for (const p of PALAVRAS_DE_JUIZO) {
        expect(frase, `"${frase}" contém "${p}"`).not.toContain(p);
      }
    }
  });

  it("a frase da data alcançada fala do que ela marcou, não do que faltou", () => {
    expect(fraseDoObjetivo(obj({ revisar_em: "2026-06-01" }), HOJE)).toBe(
      "você marcou para revisar em 01/06/2026",
    );
  });

  it("nenhuma frase do plano julga tampouco", () => {
    const frase = fraseDoPlano(
      [obj({ revisar_em: "2020-01-01" }), obj({ id: "o2", revisar_em: "2026-12-01" })],
      HOJE,
    ).toLowerCase();
    for (const p of PALAVRAS_DE_JUIZO) {
      expect(frase, `"${frase}" contém "${p}"`).not.toContain(p);
    }
    expect(frase).toContain("2 objetivos abertos");
    expect(frase).toContain("1 com a data de revisão alcançada");
  });

  /**
   * Sem objetivo nenhum o produto **não diz nada**. Um "0 objetivos" seria o
   * produto cobrando dela um plano que ela não é obrigada a escrever — e a
   * regra da casa é que nenhuma tela cobra dela um número que ela não tem.
   */
  it("sem objetivo nenhum, o produto se cala", () => {
    expect(fraseDoPlano([], HOJE)).toBe("");
  });

  it("só concluídos: nenhum aberto, e ainda assim sem elogio", () => {
    const frase = fraseDoPlano([obj({ concluido_em: "2026-08-01T12:00:00.000Z" })], HOJE);
    expect(frase).toBe("0 objetivos abertos.");
    expect(frase.toLowerCase()).not.toMatch(/parab|todos|conclu[ií]dos!|meta/);
  });
});

describe("o que falta vem antes do que aconteceu", () => {
  it("separa abertos de concluídos, preservando a ordem do banco", () => {
    const lista = [
      obj({ id: "a", revisar_em: "2026-10-01" }),
      obj({ id: "b", concluido_em: "2026-08-01T12:00:00.000Z" }),
      obj({ id: "c" }),
    ];
    const { abertos, concluidos } = separar(lista);
    expect(abertos.map((o) => o.id)).toEqual(["a", "c"]);
    expect(concluidos.map((o) => o.id)).toEqual(["b"]);
  });
});
