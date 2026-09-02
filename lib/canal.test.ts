import { describe, it, expect } from "vitest";
import {
  CANAIS,
  linkDoWhatsapp,
  espera,
  rotuloDoQueE,
  primeiroNaFila,
  fraseDoManual,
  fraseDoQueMudaNoPago,
  SEM_RESUMO,
  type NaMao,
  type ResumoManual,
} from "./canal";

const msg = (p: Partial<NaMao> = {}): NaMao => ({
  id: "m1",
  template: "aviso_de_cobranca",
  destino: "5511999998888",
  params: {},
  paciente_id: "p1",
  paciente: "Ana",
  espera_desde: "2026-09-02T12:00:00Z",
  oferta_id: null,
  ...p,
});

const res = (p: Partial<ResumoManual> = {}): ResumoManual => ({
  manual: true,
  na_mao_agora: 0,
  mais_antiga_horas: null,
  enviadas_no_mes: 0,
  mediana_minutos: null,
  ...p,
});

describe("a escada tem os degraus que o produto tem", () => {
  it("dois, e o terceiro não está aqui porque não existe", () => {
    // "Automático E do número dela" é o quadrante vazio do mercado (claude/24) e
    // depende de BSP com Embedded Signup. Um valor que o produto não entrega
    // vira, na primeira semana, uma linha de página de preço.
    expect([...CANAIS]).toEqual(["manual", "plataforma"]);
    expect(CANAIS).not.toContain("proprio");
  });
});

describe("o link", () => {
  it("monta o wa.me com o texto pronto", () => {
    const l = linkDoWhatsapp("5511999998888", "Oi, Ana. Abriu um horário.");
    expect(l).toBe("https://wa.me/5511999998888?text=Oi%2C%20Ana.%20Abriu%20um%20hor%C3%A1rio.");
  });

  it("tira o que não é dígito", () => {
    expect(linkDoWhatsapp("+55 (11) 99999-8888", "oi")).toContain("wa.me/5511999998888");
  });

  it("sem destino, não há botão", () => {
    // Um botão que abre o WhatsApp em branco é pior do que um botão que não
    // existe, porque ela descobre depois de sair da tela.
    expect(linkDoWhatsapp(null, "oi")).toBeNull();
    expect(linkDoWhatsapp("", "oi")).toBeNull();
  });

  it("número curto demais também não vira link", () => {
    expect(linkDoWhatsapp("99998888", "oi")).toBeNull();
  });
});

describe("espera — a unidade sobe conforme o tempo passa", () => {
  const base = new Date("2026-09-02T12:00:00Z");

  it("minutos, horas e dias", () => {
    expect(espera("2026-09-02T11:58:00Z", base)).toBe("há 2 min");
    expect(espera("2026-09-02T09:00:00Z", base)).toBe("há 3 horas");
    expect(espera("2026-08-31T12:00:00Z", base)).toBe("há 2 dias");
  });

  it("singular no singular", () => {
    expect(espera("2026-09-02T11:00:00Z", base)).toBe("há 1 hora");
    expect(espera("2026-09-01T12:00:00Z", base)).toBe("há 1 dia");
  });

  it("acabou de chegar não vira 'há 0 min'", () => {
    expect(espera("2026-09-02T11:59:40Z", base)).toBe("agora");
  });
});

describe("o rótulo diz o que é antes de ela abrir", () => {
  it("vaga e cobrança são conversas de temperaturas diferentes", () => {
    expect(rotuloDoQueE("oferta_de_vaga")).toBe("oferecer a vaga");
    expect(rotuloDoQueE("aviso_de_cobranca")).toBe("avisar da cobrança");
    expect(rotuloDoQueE("lembrete_de_pagamento")).toBe("lembrar do pagamento");
  });

  it("um template novo não quebra a tela", () => {
    expect(rotuloDoQueE("template_que_alguem_criar")).toBe("mandar");
  });
});

describe("a ordem: a vaga primeiro, e depois a mais antiga", () => {
  it("oferta vem antes de cobrança, mesmo sendo mais nova", () => {
    // A vaga é a única que caduca por natureza: enquanto ela não sai, a hora
    // continua vazia e ninguém foi convidado.
    const vaga = msg({ id: "v", oferta_id: "of1", espera_desde: "2026-09-02T13:00:00Z" });
    const cobranca = msg({ id: "c", espera_desde: "2026-09-02T08:00:00Z" });
    expect([cobranca, vaga].sort(primeiroNaFila).map((m) => m.id)).toEqual(["v", "c"]);
  });

  it("entre duas do mesmo tipo, a que espera há mais tempo", () => {
    const velha = msg({ id: "velha", espera_desde: "2026-09-02T08:00:00Z" });
    const nova = msg({ id: "nova", espera_desde: "2026-09-02T11:00:00Z" });
    expect([nova, velha].sort(primeiroNaFila).map((m) => m.id)).toEqual(["velha", "nova"]);
  });
});

describe("a frase da medida — números dela, e nenhuma comparação inventada", () => {
  it("em plano pago não há frase nenhuma", () => {
    expect(fraseDoManual(res({ manual: false }))).toBe("");
    expect(fraseDoManual(SEM_RESUMO)).toBe("");
  });

  it("caixa vazia explica a regra sem cobrar nada", () => {
    const f = fraseDoManual(res());
    expect(f).toMatch(/saem do seu WhatsApp/);
    expect(f).toMatch(/Nada está esperando/);
  });

  it("conta o que espera, no singular e no plural", () => {
    expect(fraseDoManual(res({ na_mao_agora: 1 }))).toMatch(/1 mensagem esperando/);
    expect(fraseDoManual(res({ na_mao_agora: 4 }))).toMatch(/4 mensagens esperando/);
  });

  it("diz há quanto tempo a mais antiga está parada", () => {
    expect(fraseDoManual(res({ na_mao_agora: 2, mais_antiga_horas: 6 }))).toMatch(/há 6 horas/);
  });

  it("e o que ela costuma levar, quando já mandou alguma", () => {
    const f = fraseDoManual(res({ enviadas_no_mes: 5, mediana_minutos: 194 }));
    expect(f).toMatch(/você mandou 5/);
    expect(f).toMatch(/3 horas depois/);
  });

  it("NUNCA compara com uma média do automático", () => {
    // O claude/25 propõe "no automático a média é 5". A segunda metade é uma
    // afirmação sobre dados que ninguém mediu — é o tipo de número que a
    // auditoria de 01/09 tirou da landing inteira.
    const f = fraseDoManual(res({ na_mao_agora: 3, mais_antiga_horas: 9, enviadas_no_mes: 7, mediana_minutos: 200 }));
    expect(f).not.toMatch(/no automático|em média o|comparado|outras psicólogas|quem paga/i);
  });

  it("e não acusa ninguém de demorar", () => {
    // "Você demorou" é uma frase sobre ela. "A vaga ficou parada" é uma frase
    // sobre a vaga, que é o que de fato aconteceu.
    const f = fraseDoManual(res({ na_mao_agora: 3, mais_antiga_horas: 30, enviadas_no_mes: 2, mediana_minutos: 600 }));
    expect(f).not.toMatch(/demor|atras|esquec|perdeu|devia/i);
  });

  it("não vira vitrine", () => {
    const f = fraseDoManual(res({ na_mao_agora: 3, mais_antiga_horas: 9 })) + " " + fraseDoQueMudaNoPago();
    expect(f).not.toMatch(/R\$|assine|aproveite|desconto|oferta especial/i);
  });
});

describe("o que muda no pago é dito sem prometer resultado de terceiro", () => {
  it("fala do que o sistema faz, não do que a paciente vai fazer", () => {
    const f = fraseDoQueMudaNoPago();
    expect(f).toMatch(/saem sozinhas/);
    expect(f).not.toMatch(/preenche|mais vagas|garante|dobra|aumenta/i);
  });
});
