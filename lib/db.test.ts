import { describe, expect, it, vi, afterEach } from "vitest";
import type { PostgrestError } from "@supabase/supabase-js";
import { db, dbVoid, ErroDeBanco } from "./db";

const erroFalso = (over: Partial<PostgrestError> = {}): PostgrestError =>
  ({
    name: "PostgrestError",
    message: "duplicate key value violates unique constraint",
    code: "23505",
    details: "Key (email) already exists.",
    hint: "",
    ...over,
  }) as PostgrestError;

afterEach(() => vi.restoreAllMocks());

describe("db() — a lei nº 1", () => {
  it("devolve os dados quando não há erro", async () => {
    const dados = await db("teste.ok", Promise.resolve({ data: [{ id: 1 }], error: null }));
    expect(dados).toEqual([{ id: 1 }]);
  });

  it("LANÇA quando o supabase devolve erro — nunca segue em silêncio", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});

    await expect(
      db("interessados.insert", Promise.resolve({ data: null, error: erroFalso() })),
    ).rejects.toBeInstanceOf(ErroDeBanco);
  });

  it("preserva contexto e código para quem for tratar o erro", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});

    let capturado: unknown;
    try {
      await db("interessados.insert", Promise.resolve({ data: null, error: erroFalso() }));
    } catch (e) {
      capturado = e;
    }

    expect(capturado).toBeInstanceOf(ErroDeBanco);
    const erro = capturado as ErroDeBanco;
    expect(erro.contexto).toBe("interessados.insert");
    expect(erro.codigo).toBe("23505");
    expect(erro.message).toContain("interessados.insert");
  });

  it("loga o erro com contexto antes de lançar", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});

    await db("x.y", Promise.resolve({ data: null, error: erroFalso() })).catch(() => {});

    expect(log).toHaveBeenCalledOnce();
    expect(log.mock.calls[0][1]).toMatchObject({ contexto: "x.y", codigo: "23505" });
  });

  it("o cenário que custou caro: um insert que falhou NÃO passa como sucesso", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});

    let seguiuEmFrente = false;
    try {
      await dbVoid("cobranca.insert", Promise.resolve({ data: null, error: erroFalso() }));
      seguiuEmFrente = true;
    } catch {
      // esperado
    }

    expect(seguiuEmFrente).toBe(false);
  });
});
