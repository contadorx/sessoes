import { describe, it, expect, vi, beforeEach } from "vitest";

/**
 * O pior defeito que este produto teve no ar, escrito como teste.
 *
 * O adaptador sem provedor devolvia `ok: true` com um id inventado, e o worker
 * então chamava `marcar_enviada`. Colhido em produção em 02/09:
 *
 *   template            estado    provedor    provedor_msg_id
 *   lembrete_de_sessao  enviada   registro    registro:1788346982148
 *
 * A tela dizia à psicóloga que a paciente tinha sido avisada. A paciente não
 * tinha recebido nada — e ela não tinha como conferir, porque a única prova que
 * o produto oferecia era a própria linha que ele mesmo escreveu.
 *
 * O critério da B43 é uma frase: **nenhuma linha fica `enviada` sem que um
 * provedor real tenha aceitado**. Aqui isso é verificável sem banco — o que se
 * observa é qual RPC o worker chama.
 */

/** Um dublê de `supabase` que só anota o que foi chamado. */
function supabaseFalso(lote: unknown[]) {
  const chamadas: { fn: string; args: unknown }[] = [];

  const respostas: Record<string, unknown> = {
    expirar_ofertas: 0,
    expirar_ofertas_fixas: 0,
    destravar_mensagens: 0,
    reservar_mensagens: lote,
    passar_para_a_sua_mao: true,
    marcar_enviada: null,
    marcar_falha: "pendente",
    desistir_mensagem: null,
  };

  return {
    chamadas,
    cliente: {
      rpc(fn: string, args?: unknown) {
        chamadas.push({ fn, args });
        return Promise.resolve({ data: respostas[fn] ?? null, error: null });
      },
    },
  };
}

const mensagem = (over: Record<string, unknown> = {}) => ({
  id: "11111111-1111-1111-1111-111111111111",
  canal: "whatsapp",
  template: "lembrete_de_sessao",
  params: { nome: "Ana", inicio: "2026-09-10T18:00:00.000Z", modo: "discreto" },
  destino: "5511999998888",
  tentativas: 1,
  ...over,
});

let supa: ReturnType<typeof supabaseFalso>;

vi.mock("@/lib/supabase/servico", () => ({
  supabaseServico: () => supa.cliente,
}));

beforeEach(() => {
  vi.spyOn(console, "info").mockImplementation(() => {});
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("sem provedor, o worker não afirma entrega", () => {
  it("nunca chama marcar_enviada", async () => {
    supa = supabaseFalso([mensagem()]);
    const { despacharPendentes } = await import("./worker");

    await despacharPendentes();

    const chamadas = supa.chamadas.map((c) => c.fn);
    expect(chamadas).not.toContain("marcar_enviada");
  });

  it("põe a mensagem na mão dela, com o motivo escrito", async () => {
    supa = supabaseFalso([mensagem()]);
    const { despacharPendentes } = await import("./worker");

    const r = await despacharPendentes();

    const naMao = supa.chamadas.find((c) => c.fn === "passar_para_a_sua_mao");
    expect(naMao).toBeDefined();
    expect(naMao?.args).toMatchObject({
      p_mensagem: "11111111-1111-1111-1111-111111111111",
    });
    expect((naMao?.args as { p_motivo: string }).p_motivo).toMatch(/provedor/i);
    expect(r.naSuaMao).toBe(1);
    expect(r.enviadas).toBe(0);
  });

  /**
   * Não é falha, e a diferença importa: `marcar_falha` insistiria quatro vezes
   * e, na quinta, escreveria `falhou` na trilha. A tela passaria a dizer que a
   * mensagem falhou — um segundo fato inventado, agora no sentido contrário,
   * sobre uma mensagem que ninguém chegou a tentar entregar.
   */
  it("não marca falha nem desiste — não houve tentativa", async () => {
    supa = supabaseFalso([mensagem()]);
    const { despacharPendentes } = await import("./worker");

    const r = await despacharPendentes();

    const chamadas = supa.chamadas.map((c) => c.fn);
    expect(chamadas).not.toContain("marcar_falha");
    expect(chamadas).not.toContain("desistir_mensagem");
    expect(r.falhas).toBe(0);
    expect(r.desistidas).toBe(0);
  });

  /**
   * O S1-B da B43, pela porta de trás.
   *
   * `confirmacao_de_sessao` já entrou em `FAMILIAS` antes desta build, mas o
   * pedido de confirmação continua sendo a mensagem que, quando não sai, faz a
   * agenda dizer "não respondeu" sobre uma pergunta que nunca foi feita. Ele
   * tem que chegar à mão dela como qualquer outra — nunca a `falhou`.
   */
  it("o pedido de confirmação também vai para a mão dela, nunca para falhou", async () => {
    supa = supabaseFalso([mensagem({ template: "confirmacao_de_sessao" })]);
    const { despacharPendentes } = await import("./worker");

    const r = await despacharPendentes();

    expect(supa.chamadas.map((c) => c.fn)).toContain("passar_para_a_sua_mao");
    expect(supa.chamadas.map((c) => c.fn)).not.toContain("marcar_falha");
    expect(r.naSuaMao).toBe(1);
  });

  /**
   * A recusa vem antes de renderizar, então um template que o worker não sabe
   * montar também acaba na mão dela — onde a caixa diz, na cara, que não
   * conseguiu montar o texto. É melhor do que `falhou` numa trilha que ninguém
   * abre: ali ela vê, e pode mandar do jeito dela.
   */
  it("nem um template impossível de montar vira falha enquanto não há provedor", async () => {
    supa = supabaseFalso([mensagem({ template: "isto_nao_existe" })]);
    const { despacharPendentes } = await import("./worker");

    await despacharPendentes();

    expect(supa.chamadas.map((c) => c.fn)).toContain("passar_para_a_sua_mao");
    expect(supa.chamadas.map((c) => c.fn)).not.toContain("marcar_falha");
  });

  it("o lote inteiro vai para a mão dela, não só o primeiro", async () => {
    supa = supabaseFalso([
      mensagem({ id: "11111111-1111-1111-1111-111111111111" }),
      mensagem({ id: "22222222-2222-2222-2222-222222222222" }),
      mensagem({ id: "33333333-3333-3333-3333-333333333333" }),
    ]);
    const { despacharPendentes } = await import("./worker");

    const r = await despacharPendentes();

    expect(supa.chamadas.filter((c) => c.fn === "passar_para_a_sua_mao")).toHaveLength(3);
    expect(r.naSuaMao).toBe(3);
    expect(r.reservadas).toBe(3);
  });
});
