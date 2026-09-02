import { describe, it, expect } from "vitest";
import {
  MOMENTOS,
  momentoValido,
  decidir,
  notaValida,
  nps,
  fraseDoNps,
  fraseDaDistribuicao,
  agradecimento,
  PERGUNTA,
  PERGUNTA_ABERTA,
  ANCORA_BAIXA,
  ANCORA_ALTA,
  AMOSTRA_MINIMA,
  NAO_PERGUNTAR,
  type Agregado,
} from "./avaliacao";

describe("os momentos são lista fechada — é ela que impede pedir nota na hora errada", () => {
  it("são exatamente três, e nenhum é dentro de uma cobrança", () => {
    expect([...MOMENTOS].sort()).toEqual(["convite", "fim_do_mes", "perfil"].sort());
  });

  it("um momento inventado não passa", () => {
    expect(momentoValido("depois_de_cobrar")).toBe(false);
    expect(momentoValido("ao_cancelar")).toBe(false);
    expect(momentoValido("apos_erro")).toBe(false);
    expect(momentoValido("perfil")).toBe(true);
  });
});

describe("decidir — quatro portões, e três são silêncios", () => {
  it("conta nova não é convidada: a nota mediria o cadastro", () => {
    expect(decidir(3, 40, false, null)).toEqual({ pedir: false, motivo: "conta nova" });
  });

  it("conta antiga com pouco uso também não", () => {
    expect(decidir(200, 4, false, null)).toEqual({ pedir: false, motivo: "pouco uso" });
  });

  it("assinatura em atraso cala a pergunta — e vem ANTES de qualquer outra razão", () => {
    // Pedir nota a quem está devendo é pedir a nota errada pela razão errada, e
    // ainda mistura a conversa da cobrança com a conversa do produto.
    expect(decidir(400, 90, true, null)).toEqual({
      pedir: false,
      motivo: "assinatura em atraso",
    });
    expect(decidir(400, 90, true, 500)).toEqual({
      pedir: false,
      motivo: "assinatura em atraso",
    });
  });

  it("quem avaliou há pouco não é perguntada de novo", () => {
    expect(decidir(400, 90, false, 30).pedir).toBe(false);
    expect(decidir(400, 90, false, 89).motivo).toBe("avaliou há pouco");
  });

  it("passados 90 dias, pode perguntar de novo", () => {
    expect(decidir(400, 90, false, 90)).toEqual({ pedir: true, motivo: "pode perguntar" });
  });

  it("a fronteira dos portões: 30 dias e 10 sessões", () => {
    expect(decidir(29, 10, false, null).pedir).toBe(false);
    expect(decidir(30, 9, false, null).pedir).toBe(false);
    expect(decidir(30, 10, false, null).pedir).toBe(true);
  });

  it("quando a leitura falha, não se pergunta nada", () => {
    expect(NAO_PERGUNTAR.pedir).toBe(false);
  });
});

describe("a escala", () => {
  it("vai de 0 a 10, inclusive nas pontas", () => {
    expect(notaValida(0)).toBe(true);
    expect(notaValida(10)).toBe(true);
    expect(notaValida(-1)).toBe(false);
    expect(notaValida(11)).toBe(false);
  });

  it("não aceita meia nota", () => {
    expect(notaValida(7.5)).toBe(false);
  });
});

describe("a pergunta, e o que ela escolhe não medir", () => {
  it("pergunta sobre o trabalho, e não sobre recomendar para uma colega", () => {
    // "Você recomendaria para uma colega" mede disposição a expor a própria
    // reputação, que depende de quanto ela gosta da colega. A pergunta é sobre
    // o que o produto promete mexer.
    expect(PERGUNTA).toMatch(/trabalho que não é atender/i);
    expect(PERGUNTA).not.toMatch(/recomend|colega|amiga/i);
  });

  it("a pergunta aberta pede o problema, e não o elogio", () => {
    expect(PERGUNTA_ABERTA).toMatch(/mais trabalho do que devia/i);
    expect(PERGUNTA_ABERTA).not.toMatch(/gostou|melhor|favorita/i);
  });

  it("as âncoras descrevem o fato, e não julgam a resposta", () => {
    // Rotular a ponta baixa de "ruim" convida a pessoa a ser gentil, e a partir
    // daí o instrumento mede a vontade de agradar.
    expect(ANCORA_BAIXA).toBe("não mudou nada");
    expect(ANCORA_ALTA).toBe("mudou muito");
    expect(`${ANCORA_BAIXA} ${ANCORA_ALTA}`).not.toMatch(/ruim|péssimo|ótimo|excelente/i);
  });

  it("o agradecimento é o mesmo para nota 0 e para nota 10", () => {
    // Agradecer mais quem deu 10 é ensinar que a nota alta agrada. Pedir
    // explicação só de quem deu nota baixa é a mesma coisa pelo outro lado.
    expect(agradecimento()).toBe(agradecimento());
    expect(agradecimento()).not.toMatch(/obrigado pela nota alta|que pena|sentimos muito/i);
  });
});

describe("o NPS recusa amostra pequena", () => {
  it("abaixo de cinco respostas o número é NULO, e não zero", () => {
    // Zero é uma afirmação: "tantos promotores quanto detratores". Nulo é a
    // ausência de uma. Mesma distinção que o P5 fez para a ocupação.
    expect(nps(2, 1, 3)).toBeNull();
    expect(nps(0, 0, 4)).toBeNull();
  });

  it("de cinco em diante ele existe", () => {
    expect(nps(3, 1, 5)).toBe(40);
    expect(nps(10, 0, 10)).toBe(100);
    expect(nps(0, 10, 10)).toBe(-100);
  });

  it("a amostra mínima é a do portão 1→2 do doc 04", () => {
    expect(AMOSTRA_MINIMA).toBe(5);
  });
});

describe("a leitura mostra a distribuição, e não só a média", () => {
  const ag = (p: Partial<Agregado> = {}): Agregado => ({
    n: 10,
    media: 7.4,
    promotores: 5,
    neutros: 0,
    detratores: 5,
    nps: 0,
    distribuicao: {},
    por_plano: {},
    ...p,
  });

  it("sem resposta nenhuma, diz isso e não inventa média", () => {
    expect(fraseDoNps(ag({ n: 0, nps: null, media: null }))).toMatch(/Ninguém avaliou/);
    expect(fraseDaDistribuicao(ag({ n: 0 }))).toBe("");
  });

  it("com poucas respostas, diz que são poucas em vez de mostrar um número", () => {
    expect(fraseDoNps(ag({ n: 3, nps: null }))).toMatch(/poucas/i);
    // A frase pode dizer a palavra NPS — o que ela não pode é mostrar um NPS.
    // A primeira redação deste teste proibia a palavra, e reprovou a frase
    // certa: é a mesma classe de erro das varreduras largas no banco.
    expect(fraseDoNps(ag({ n: 3, nps: null }))).not.toMatch(/NPS\s-?\d/);
  });

  it("a distribuição separa os três grupos — média 7,4 pode ser dois produtos diferentes", () => {
    expect(fraseDaDistribuicao(ag())).toBe("5 até 6 · 0 entre 7 e 8 · 5 de 9 para cima.");
  });

  it("uma resposta só é 'resposta', não 'respostas'", () => {
    expect(fraseDoNps(ag({ n: 1, nps: null }))).toMatch(/1 resposta —/);
  });
});
