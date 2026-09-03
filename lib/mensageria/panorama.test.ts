import { describe, it, expect } from "vitest";
import { lerPanorama, fraseDoPanorama, type Panorama } from "./panorama";

const AGORA = new Date("2026-09-03T18:00:00.000Z");

const vazio: Panorama = {
  em: AGORA.toISOString(),
  varreduras: [{ nome: "entrega:email", em: "2026-09-03T17:55:00.000Z", cega: false }],
  disjuntores: [{ canal: "email", conta_id: null, estado: "fechado", motivo: "nunca abriu", desde: "x" }],
  saida: [],
  na_mao_dela: [],
  entrada: { recebidas_24h: 0, nao_entendidas_24h: 0 },
};

describe("lerPanorama", () => {
  it("tudo em ordem não inventa achado", () => {
    expect(lerPanorama(vazio, AGORA)).toEqual([]);
    expect(fraseDoPanorama([])).toBe("");
  });

  /*
    Cego vem primeiro porque envenena o resto: sem confirmação nenhuma a
    varredura não conclui perda, então "zero perdidas" não significa "está tudo
    bem" — significa "não sei". Mostrar isso como saúde é a mentira que a B43 e
    a B50 consertaram em outras telas.
  */
  it("cego vem antes de tudo, e a frase de topo diz que o resto não vale", () => {
    const p: Panorama = {
      ...vazio,
      varreduras: [{ nome: "entrega:email", em: AGORA.toISOString(), cega: true }],
      saida: [{ canal: "email", estado: "barrada_no_teto", n: 3 }],
      disjuntores: [{ canal: "email", conta_id: null, estado: "aberto", motivo: "5 de 10", desde: "x" }],
    };
    const achados = lerPanorama(p, AGORA);
    expect(achados[0].gravidade).toBe("cego");
    expect(fraseDoPanorama(achados)).toContain("não está medindo");
  });

  it("varredura que nunca rodou é 'parado', e é o único sintoma de cron morto", () => {
    const achados = lerPanorama({ ...vazio, varreduras: [] }, AGORA);
    expect(achados).toHaveLength(1);
    expect(achados[0].gravidade).toBe("parado");
    expect(achados[0].titulo).toContain("nunca rodou");
  });

  it("três ciclos sem passar também é 'parado'", () => {
    const p = { ...vazio, varreduras: [{ nome: "entrega:email", em: "2026-09-03T16:00:00.000Z", cega: false }] };
    expect(lerPanorama(p, AGORA)[0].gravidade).toBe("parado");
  });

  it("disjuntor aberto é degradado, e diz que só fecha por evidência", () => {
    const p: Panorama = {
      ...vazio,
      disjuntores: [{ canal: "email", conta_id: null, estado: "aberto", motivo: "5 de 10 não confirmaram", desde: "ontem" }],
    };
    const a = lerPanorama(p, AGORA);
    expect(a[0].gravidade).toBe("degradado");
    expect(a[0].frase).toContain("nunca pelo relógio");
  });

  it("barrada no teto aparece — é o caminho mais silencioso de todos", () => {
    const a = lerPanorama({ ...vazio, saida: [{ canal: "email", estado: "barrada_no_teto", n: 4 }] }, AGORA);
    expect(a[0].titulo).toContain("4 mensagens barradas");
  });

  /*
    O plural de "mensagem" é "mensagens". O `${n > 1 ? "s" : ""}` que serve para
    "conta" produz *mensagems*, e foi assim que este teste nasceu — o erro já
    estava escrito e ia para a tela.
  */
  it("o plural de palavra em -m é -ns, e o singular continua singular", () => {
    const uma = lerPanorama({ ...vazio, saida: [{ canal: "email", estado: "barrada_no_teto", n: 1 }] }, AGORA);
    expect(uma[0].titulo).toBe("1 mensagem barrada no teto");

    const varias = lerPanorama({ ...vazio, saida: [{ canal: "email", estado: "barrada_no_teto", n: 2 }] }, AGORA);
    expect(varias[0].titulo).toBe("2 mensagens barradas no teto");
    expect(varias[0].titulo).not.toContain("mensagems");
  });

  it("resposta não entendida só vira achado acima de um quinto", () => {
    const pouco = { ...vazio, entrada: { recebidas_24h: 10, nao_entendidas_24h: 1 } };
    expect(lerPanorama(pouco, AGORA)).toEqual([]);

    const muito = { ...vazio, entrada: { recebidas_24h: 10, nao_entendidas_24h: 3 } };
    const a = lerPanorama(muito, AGORA);
    expect(a[0].frase).toContain("a fila parece quebrada");
  });

  /*
    Mensagem na mão dela não é defeito: é o desenho enquanto não há provedor.
    Entra como "quieto", por último, e some quando não há nenhuma.
  */
  it("na mão dela é 'quieto', e nunca sobe na frente de um defeito", () => {
    const p: Panorama = {
      ...vazio,
      na_mao_dela: [{ conta_id: "c1", n: 16, mais_antiga: "2026-09-01T10:00:00.000Z" }],
      saida: [{ canal: "email", estado: "enviando", n: 2 }],
    };
    const a = lerPanorama(p, AGORA);
    expect(a[0].gravidade).toBe("degradado");
    expect(a.at(-1)?.gravidade).toBe("quieto");
    expect(a.at(-1)?.frase).toContain("não uma falha");
  });
});
