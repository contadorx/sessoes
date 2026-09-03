import { describe, it, expect } from "vitest";
import {
  instrumentoConfiavel,
  avaliarDisjuntor,
  deveSondar,
  cronSuspeito,
  podeReenviar,
  eventoDoProvedor,
  AMOSTRA_MINIMA,
  type Disjuntor,
} from "./entrega";

const FECHADO: Disjuntor = { estado: "fechado", motivo: "nunca abriu", desde: null };
const AGORA = "2026-09-03T18:00:00.000Z";

/*
  A trava contra a conclusão falsa. Se ela estiver errada, um webhook
  desconfigurado derruba o canal que está funcionando, duplica todo e-mail
  enviado e queima a cota do segundo provedor — sem uma linha de erro.
*/
describe("instrumentoConfiavel", () => {
  it("base vazia é confiável por vacuidade: não há o que concluir nem o que reenviar", () => {
    expect(instrumentoConfiavel({ total: 0, confirmadas: 0 })).toBe(true);
  });

  it("saídas sem nenhuma confirmação é falta de instrumento, não prova de perda", () => {
    expect(instrumentoConfiavel({ total: 40, confirmadas: 0 })).toBe(false);
  });

  it("uma confirmação já basta: o webhook está vivo", () => {
    expect(instrumentoConfiavel({ total: 40, confirmadas: 1 })).toBe(true);
  });
});

describe("avaliarDisjuntor", () => {
  it("não se mexe abaixo da amostra mínima, em direção nenhuma", () => {
    const poucas = { total: AMOSTRA_MINIMA - 1, confirmadas: 0, semConfirmacao: AMOSTRA_MINIMA - 1 };
    expect(avaliarDisjuntor(FECHADO, poucas, AGORA)).toBe(FECHADO);

    const aberto: Disjuntor = { estado: "aberto", motivo: "…", desde: AGORA };
    expect(avaliarDisjuntor(aberto, { total: 4, confirmadas: 4, semConfirmacao: 0 }, AGORA)).toBe(aberto);
  });

  it("abre quando a perda passa do limite, com o motivo escrito", () => {
    const d = avaliarDisjuntor(FECHADO, { total: 10, confirmadas: 5, semConfirmacao: 5 }, AGORA);
    expect(d.estado).toBe("aberto");
    expect(d.motivo).toContain("5 de 10");
    expect(d.motivo).toContain("50%");
    expect(d.desde).toBe(AGORA);
  });

  it("não abre logo abaixo do limite", () => {
    const d = avaliarDisjuntor(FECHADO, { total: 10, confirmadas: 7, semConfirmacao: 3 }, AGORA);
    expect(d.estado).toBe("fechado");
  });

  /*
    O ponto do arquivo inteiro. Um disjuntor que fecha no relógio devolve o
    tráfego a um caminho quebrado e refaz o estrago em silêncio.
  */
  it("aberto NÃO fecha enquanto houver qualquer perda na amostra", () => {
    const aberto: Disjuntor = { estado: "aberto", motivo: "…", desde: AGORA };
    const d = avaliarDisjuntor(aberto, { total: 20, confirmadas: 19, semConfirmacao: 1 }, AGORA);
    expect(d.estado).toBe("aberto");
  });

  it("fecha só com amostra recente sem perda nenhuma", () => {
    const aberto: Disjuntor = { estado: "aberto", motivo: "…", desde: AGORA };
    const d = avaliarDisjuntor(aberto, { total: 8, confirmadas: 8, semConfirmacao: 0 }, AGORA);
    expect(d.estado).toBe("fechado");
    expect(d.motivo).toContain("8 mensagens seguidas");
  });
});

describe("deveSondar", () => {
  const aberto: Disjuntor = { estado: "aberto", motivo: "…", desde: "2026-09-03T12:00:00.000Z" };

  it("fechado nunca sonda", () => {
    expect(deveSondar(FECHADO, new Date("2026-09-04T12:00:00.000Z"))).toBe(false);
  });

  it("aberto há pouco não sonda", () => {
    expect(deveSondar(aberto, new Date("2026-09-03T14:00:00.000Z"))).toBe(false);
  });

  it("aberto há mais que o prazo, sonda — é o único jeito de haver amostra", () => {
    expect(deveSondar(aberto, new Date("2026-09-03T18:30:00.000Z"))).toBe(true);
  });

  it("data podre não vira sonda", () => {
    expect(deveSondar({ estado: "aberto", motivo: "…", desde: "ontem" }, new Date())).toBe(false);
  });
});

describe("cronSuspeito", () => {
  it("nunca rodou é suspeito", () => {
    expect(cronSuspeito(null, new Date())).toBe(true);
  });

  it("rodou agora não é", () => {
    expect(cronSuspeito("2026-09-03T17:50:00.000Z", new Date("2026-09-03T18:00:00.000Z"))).toBe(false);
  });

  it("três ciclos sem notícia é", () => {
    expect(cronSuspeito("2026-09-03T17:00:00.000Z", new Date("2026-09-03T18:00:00.000Z"))).toBe(true);
  });
});

describe("podeReenviar", () => {
  it("reenvia até o teto e para", () => {
    expect(podeReenviar(0)).toBe(true);
    expect(podeReenviar(1)).toBe(true);
    expect(podeReenviar(2)).toBe(false);
  });
});

describe("eventoDoProvedor", () => {
  it("entende os dois provedores, nas três grafias", () => {
    for (const e of ["delivered", "MessageSent", "message_sent", "Message Sent", "SENT"]) {
      expect(eventoDoProvedor(e), e).toBe("entregue");
    }
  });

  it("bounce e recusa são falha, e falha não se reenvia", () => {
    for (const e of ["bounce", "hard_bounce", "MessageBounced", "MessageDeliveryFailed", "blocked", "spam"]) {
      expect(eventoDoProvedor(e), e).toBe("falhou");
    }
  });

  it("o que ninguém previu é ignorado, nunca entrega", () => {
    for (const e of ["opened", "clicked", "", null, undefined, "evento_do_futuro"]) {
      expect(eventoDoProvedor(e as string), String(e)).toBe("ignorado");
    }
  });
});
