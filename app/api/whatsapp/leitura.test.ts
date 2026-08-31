import { describe, it, expect } from "vitest";
import { lerGupshup } from "./route";

/**
 * O tradutor do provedor.
 *
 * É a única parte da B10 que roda em TypeScript, e por isso a única que precisa
 * de teste aqui — todo o resto (idempotência, vínculo, opt-out) mora no banco,
 * onde está `supabase/tests/0021_respostas.sql`.
 *
 * O que se testa é o comportamento diante de coisa torta, porque é isso que
 * chega: figurinha, áudio, evento de entrega, corpo de outro formato. Nada
 * disso pode virar exceção — exceção aqui faz o provedor reentregar para sempre.
 */

describe("mensagem de texto", () => {
  it("extrai id, telefone e texto", () => {
    const r = lerGupshup({
      app: "sessoes",
      type: "message",
      payload: {
        id: "ABEG123",
        source: "5511900000002",
        type: "text",
        payload: { text: "SIM" },
      },
    });
    expect(r).toEqual({
      tipo: "mensagem",
      id: "ABEG123",
      de: "5511900000002",
      texto: "SIM",
    });
  });

  it("o botão de resposta rápida também é resposta", () => {
    const r = lerGupshup({
      type: "message",
      payload: {
        id: "ABEG124",
        source: "5511900000002",
        type: "button_reply",
        payload: { title: "Parar de receber" },
      },
    });
    expect(r.tipo).toBe("mensagem");
    expect(r.texto).toBe("Parar de receber");
  });

  it("áudio e figurinha chegam como texto vazio, não como erro", () => {
    const r = lerGupshup({
      type: "message",
      payload: { id: "ABEG125", source: "5511900000002", type: "audio", payload: { url: "..." } },
    });
    expect(r.tipo).toBe("mensagem");
    expect(r.texto).toBe("");
  });

  it("sem id ou sem remetente não dá para fazer nada — ignora", () => {
    expect(lerGupshup({ type: "message", payload: { source: "551190000" } }).tipo)
      .toBe("ignorar");
    expect(lerGupshup({ type: "message", payload: { id: "x" } }).tipo).toBe("ignorar");
  });
});

describe("evento de entrega", () => {
  it("entregue e lido viram entregue", () => {
    for (const type of ["delivered", "read"]) {
      const r = lerGupshup({ type: "message-event", payload: { gsId: "g1", type } });
      expect(r).toEqual({ tipo: "entrega", id: "g1", estado: "entregue" });
    }
  });

  it("failed vira falhou", () => {
    const r = lerGupshup({ type: "message-event", payload: { gsId: "g2", type: "failed" } });
    expect(r.estado).toBe("falhou");
  });

  it("enfileirado e enviado não são notícia — ignora", () => {
    expect(lerGupshup({ type: "message-event", payload: { gsId: "g3", type: "enqueued" } }).tipo)
      .toBe("ignorar");
    expect(lerGupshup({ type: "message-event", payload: { gsId: "g4", type: "sent" } }).tipo)
      .toBe("ignorar");
  });
});

describe("o que não é nada disso", () => {
  it.each([null, undefined, "", 0, [], "texto solto"])("%s não estoura", (corpo) => {
    expect(() => lerGupshup(corpo)).not.toThrow();
    expect(lerGupshup(corpo).tipo).toBe("ignorar");
  });

  it("tipo desconhecido do provedor é ignorado, não é erro", () => {
    expect(lerGupshup({ type: "user-event", payload: { phone: "5511" } }).tipo).toBe("ignorar");
  });

  it("payload faltando não estoura", () => {
    expect(lerGupshup({ type: "message" }).tipo).toBe("ignorar");
    expect(lerGupshup({ type: "message-event" }).tipo).toBe("ignorar");
  });
});
