import { describe, it, expect } from "vitest";
import {
  MIN_HORAS,
  MAX_HORAS,
  HORAS_SUGERIDAS,
  OPCOES_DE_HORAS,
  horasValidas,
  problemaNasHoras,
  rotuloConfirmacao,
  explicaConfirmacao,
  acaoDaConfirmacao,
  apareceNoDia,
  lerResposta,
  fraseDaResposta,
  fraseDoAjuste,
  type RespostaBruta,
  type EixoConfirmacao,
} from "@/lib/confirmacao";
import * as modulo from "@/lib/confirmacao";

/**
 * O teste que decide o arquivo está em "as duas fronteiras": **o silêncio não
 * tem ação**, e nenhuma frase do módulo sugere liberar um horário por conta
 * própria.
 *
 * Os números são os da suíte SQL `0057_confirmacao_ativa.sql`: faixa de 2 a
 * 168 horas, e 24 como o que a prática de campo mostrou.
 */

const TODOS: EixoConfirmacao[] = [
  "nao_pedida", "pendente", "confirmada", "recusada", "silenciosa",
];

describe("o ajuste", () => {
  it("a faixa é a mesma do banco", () => {
    expect(MIN_HORAS).toBe(2);
    expect(MAX_HORAS).toBe(168);
    expect(horasValidas(2)).toBe(true);
    expect(horasValidas(168)).toBe(true);
    expect(horasValidas(1)).toBe(false);
    expect(horasValidas(169)).toBe(false);
    expect(horasValidas(24.5)).toBe(false);
  });

  it("nulo é válido, e é o padrão", () => {
    expect(horasValidas(null)).toBe(true);
    expect(problemaNasHoras(null)).toBeNull();
    expect(fraseDoAjuste(null)).toContain("É o padrão");
  });

  it("a sugestão é 24, que é o que a prática mostrou", () => {
    expect(HORAS_SUGERIDAS).toBe(24);
    expect(OPCOES_DE_HORAS.some((o) => o.valor === 24)).toBe(true);
  });

  it("as recusas explicam o motivo, e são diferentes nas duas pontas", () => {
    expect(problemaNasHoras(1)).toContain("não dá tempo de reagir");
    expect(problemaNasHoras(200)).toContain("ninguém lembra");
    expect(problemaNasHoras(1)).not.toBe(problemaNasHoras(200));
  });

  it("todas as opções oferecidas cabem na faixa do banco", () => {
    for (const o of OPCOES_DE_HORAS) expect(horasValidas(o.valor)).toBe(true);
  });
});

describe("os estados", () => {
  it("os cinco têm rótulo e explicação", () => {
    for (const e of TODOS) {
      expect(rotuloConfirmacao(e).length).toBeGreaterThan(3);
      expect(explicaConfirmacao(e).length).toBeGreaterThan(15);
    }
  });

  it("o que não foi perguntado não aparece na faixa do dia", () => {
    expect(apareceNoDia("nao_pedida")).toBe(false);
    expect(apareceNoDia("pendente")).toBe(true);
    expect(apareceNoDia("silenciosa")).toBe(true);
  });

  it("um estado desconhecido não estoura a tela", () => {
    expect(rotuloConfirmacao("coisa_nova")).toBe("coisa_nova");
    expect(explicaConfirmacao("coisa_nova")).toBe("");
  });
});

describe("as duas fronteiras", () => {
  it("o SILÊNCIO não tem ação — e é a decisão do build", () => {
    expect(acaoDaConfirmacao("silenciosa")).toBeNull();
  });

  it("nem a pendente, nem a confirmada, nem a que não foi perguntada", () => {
    expect(acaoDaConfirmacao("pendente")).toBeNull();
    expect(acaoDaConfirmacao("confirmada")).toBeNull();
    expect(acaoDaConfirmacao("nao_pedida")).toBeNull();
  });

  it("só a recusa explícita tem ação, porque é o que ela já faz", () => {
    const a = acaoDaConfirmacao("recusada");
    expect(a).not.toBeNull();
    expect(a!.tipo).toBe("cancelar");
  });

  it("a explicação do silêncio diz que ele não quer dizer ausência", () => {
    const t = explicaConfirmacao("silenciosa");
    expect(t).toContain("Não quer dizer que a pessoa não vem");
    expect(t).not.toMatch(/liberar|libere|vagar/i);
  });

  it("a explicação da recusa deixa claro de quem é a decisão", () => {
    const t = explicaConfirmacao("recusada");
    expect(t).toContain("decisão sua");
    expect(t).toContain("política");
  });

  it("nenhuma frase do módulo manda o sistema liberar sozinho", () => {
    const tudo = [
      ...TODOS.map((e) => `${rotuloConfirmacao(e)} ${explicaConfirmacao(e)}`),
      fraseDoAjuste(null),
      fraseDoAjuste(24),
    ].join(" ");
    expect(tudo).not.toMatch(/liberamos|libera automaticamente|cancela sozinh|cancelamos/i);
  });

  it("o módulo não exporta nada que libere ou cancele por conta própria", () => {
    for (const nome of Object.keys(modulo)) {
      expect(nome).not.toMatch(/liberarPorSilencio|cancelarPorSilencio|autoLiberar/i);
    }
  });
});

describe("os dois números", () => {
  const BRUTA: RespostaBruta = {
    de: "2026-09-01",
    ate: "2026-09-30",
    pedidas: 10,
    confirmadas: 6,
    recusadas: 2,
    silenciosas: 2,
    pendentes: 0,
    antecedencia_media_h: "18.4",
  };

  it("a taxa conta quem respondeu de qualquer jeito", () => {
    const r = lerResposta(BRUTA);
    expect(r.responderam).toBe(8);
    expect(r.taxa).toBe(80);
    expect(r.antecedenciaH).toBe(18.4);
  });

  it("recusar é responder — quem avisou que não vem respondeu", () => {
    const r = lerResposta({ ...BRUTA, confirmadas: 0, recusadas: 8 });
    expect(r.taxa).toBe(80);
  });

  it("sem ninguém perguntado, a taxa é nula e não zero", () => {
    const r = lerResposta({ ...BRUTA, pedidas: 0, confirmadas: 0, recusadas: 0, silenciosas: 0, antecedencia_media_h: null });
    expect(r.taxa).toBeNull();
    expect(fraseDaResposta(r)).toContain("Nenhuma confirmação pedida");
  });

  it("a frase diz o número e a antecedência", () => {
    const f = fraseDaResposta(lerResposta(BRUTA));
    expect(f).toContain("8 de 10");
    expect(f).toContain("80%");
    expect(f).toContain("18,4 horas");
  });

  it("com taxa baixa, a frase manda desligar — é o critério de pronto do P3", () => {
    const f = fraseDaResposta(lerResposta({ ...BRUTA, confirmadas: 2, recusadas: 1, silenciosas: 7 }));
    expect(f).toContain("30%");
    expect(f).toContain("vale desligar");
  });

  it("com taxa boa, não fica sugerindo nada", () => {
    expect(fraseDaResposta(lerResposta(BRUTA))).not.toContain("vale desligar");
  });

  it("sem resposta nenhuma, a antecedência não vira zero inventado", () => {
    const r = lerResposta({ ...BRUTA, confirmadas: 0, recusadas: 0, silenciosas: 10, antecedencia_media_h: null });
    expect(r.antecedenciaH).toBeNull();
    expect(fraseDaResposta(r)).not.toContain("horas antes da sessão");
  });
});
