import { describe, it, expect } from "vitest";
import { mascarar } from "./adaptadores";

/**
 * Log é lugar de depurar, não de guardar dado de contato. A LGPD (doc 07) não
 * abre exceção para "só no log da Vercel".
 */
describe("mascarar", () => {
  it("mostra as pontas do telefone e esconde o meio", () => {
    expect(mascarar("5511900000001")).toBe("5511*****0001");
  });

  it("não deixa o número inteiro passar", () => {
    const m = mascarar("5511987654321");
    expect(m).not.toContain("98765");
    expect(m).toContain("*");
  });

  it("no e-mail, preserva o domínio e corta o resto", () => {
    expect(mascarar("otavio@exemplo.com.br")).toBe("ot***@exemplo.com.br");
  });

  it("número curto demais some inteiro em vez de vazar quase tudo", () => {
    expect(mascarar("12345")).toBe("***");
  });
});
