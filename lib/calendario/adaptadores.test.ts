import { describe, it, expect, vi, afterEach } from "vitest";
import { registro, adaptadorDoCalendario, DIAS_A_LER } from "./adaptadores";

/**
 * O adaptador ausente não pode fingir.
 *
 * Na mensageria, o `registro` marca a mensagem como enviada — é um modo de
 * operação legítimo, porque o que se está exercitando é a fila. Aqui isso teria
 * consequência: um espelho marcado como `espelhada` sem id de evento do outro
 * lado quebra a atualização e a remoção seguintes, e a sessão remarcada nunca
 * mais acertaria o calendário dela.
 *
 * Estes testes existem para que a diferença não se perca numa refatoração
 * distraída.
 */

afterEach(() => vi.restoreAllMocks());

describe("o adaptador que existe antes do provedor existir", () => {
  it("se declara indisponível — a tela precisa poder dizer isso", () => {
    expect(registro.disponivel).toBe(false);
    expect(adaptadorDoCalendario().disponivel).toBe(false);
  });

  it("recusa escrever em vez de dizer que escreveu", async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    const r = await registro.escrever(
      {
        acao: "criar",
        calendarioExterno: "primary",
        eventoExterno: null,
        titulo: "Sessão",
        inicio: "2026-09-10T18:00:00Z",
        fim: "2026-09-10T18:50:00Z",
      },
      "refresh",
    );
    expect(r.ok).toBe(false);
  });

  it("e recusa de forma NÃO definitiva: a fila espera, não desiste", async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    const r = await registro.escrever(
      {
        acao: "criar",
        calendarioExterno: "primary",
        eventoExterno: null,
        titulo: "Sessão",
        inicio: null,
        fim: null,
      },
      "refresh",
    );
    if (r.ok) throw new Error("devia ter recusado");
    expect(r.definitivo).toBe(false);
  });

  it("a leitura também recusa, e sem marcar o calendário como expirado", async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    const r = await registro.ler({
      calendarioExterno: "primary",
      refreshToken: "refresh",
      syncToken: null,
      de: "2026-09-01",
      ate: "2026-10-31",
    });
    if (r.ok) throw new Error("devia ter recusado");
    // Expirado é um estado que a tela mostra como "autorize de novo". Sem
    // provedor não há autorização vencida — há autorização que nunca existiu.
    expect(r.expirou).toBe(false);
  });
});

describe("o log não carrega nome de paciente", () => {
  it("no modo discreto, o título sai inteiro (é a palavra 'Sessão')", async () => {
    const espia = vi.spyOn(console, "info").mockImplementation(() => {});
    await registro.escrever(
      {
        acao: "criar",
        calendarioExterno: "primary",
        eventoExterno: null,
        titulo: "Sessão",
        inicio: null,
        fim: null,
      },
      "refresh",
    );
    expect(JSON.stringify(espia.mock.calls)).toContain("Sessão");
  });

  it("nos outros modos, só o comprimento — log da Vercel não é armário de consultório", async () => {
    const espia = vi.spyOn(console, "info").mockImplementation(() => {});
    await registro.escrever(
      {
        acao: "criar",
        calendarioExterno: "primary",
        eventoExterno: null,
        titulo: "Sessão · Zebulon Improvável Kryzanowski",
        inicio: null,
        fim: null,
      },
      "refresh",
    );
    const saida = JSON.stringify(espia.mock.calls);
    expect(saida).not.toContain("Zebulon");
    expect(saida).not.toContain("Kryzanowski");
    expect(saida).toContain("caracteres");
  });
});

describe("a janela de leitura cobre a janela da agenda", () => {
  it("lê pelo menos as 8 semanas que a materialização cria", () => {
    // A B5 materializa 8 semanas à frente. Ler menos deixaria justamente o fim
    // da janela — onde a fila oferece as vagas mais distantes — sem proteção.
    expect(DIAS_A_LER).toBeGreaterThanOrEqual(56);
  });
});
