import { describe, it, expect } from "vitest";
import {
  montarBrCode,
  brCodeValido,
  crc16,
  lerTlv,
  tipoDaChave,
  apenasAscii,
  limparTxid,
} from "./pix";

/**
 * O BR Code tem uma propriedade cruel: **um código errado parece certo.**
 *
 * É uma string de duzentos caracteres que ninguém lê. Se o CRC estiver errado,
 * se o tamanho de um campo estiver deslocado por um, se um acento passar, o
 * resultado não é um erro no nosso lado — é o aplicativo do banco do paciente
 * dizendo "código inválido", e a psicóloga sem saber por quê.
 *
 * Por isso o teste é estrutural, e não um "gerou alguma coisa".
 */

const BASE = {
  chave: "12345678901",
  nome: "Ana Paula Ferreira",
  cidade: "Sao Paulo",
};

describe("CRC-16/CCITT-FALSE", () => {
  it('bate com o valor de conferência do padrão ("123456789" → 29B1)', () => {
    // Este é o check value publicado do CRC-16/CCITT-FALSE. É o único jeito de
    // provar que é *este* CRC, e não um dos outros seis chamados de "CRC16".
    expect(crc16("123456789")).toBe("29B1");
  });

  it("sempre devolve quatro dígitos em maiúsculas", () => {
    for (const t of ["", "a", "Sessões", "0".repeat(200)]) {
      expect(crc16(t)).toMatch(/^[0-9A-F]{4}$/);
    }
  });
});

describe("o código gerado", () => {
  const codigo = montarBrCode({ ...BASE, valorCentavos: 20_000, txid: "COB123" });

  it("passa na própria verificação", () => {
    expect(brCodeValido(codigo)).toBe(true);
  });

  it("qualquer caractere alterado invalida o código", () => {
    // Se isto falhar, o CRC não está protegendo nada.
    for (const i of [10, 50, codigo.length - 20]) {
      const trocado =
        codigo.slice(0, i) + (codigo[i] === "0" ? "1" : "0") + codigo.slice(i + 1);
      expect(brCodeValido(trocado), `posição ${i}`).toBe(false);
    }
  });

  it("os campos obrigatórios estão lá, com os valores do padrão", () => {
    const campos = lerTlv(codigo);
    expect(campos.get("00")).toBe("01"); // formato
    expect(campos.get("52")).toBe("0000"); // categoria
    expect(campos.get("53")).toBe("986"); // real
    expect(campos.get("58")).toBe("BR"); // país
    expect(campos.get("26")).toContain("br.gov.bcb.pix");
    expect(campos.get("26")).toContain("12345678901");
  });

  it("o valor vai com ponto decimal e dois dígitos", () => {
    expect(lerTlv(codigo).get("54")).toBe("200.00");
    expect(lerTlv(montarBrCode({ ...BASE, valorCentavos: 18_050 })).get("54")).toBe("180.50");
    expect(lerTlv(montarBrCode({ ...BASE, valorCentavos: 120_050 })).get("54")).toBe("1200.50");
  });

  it("sem valor, o campo simplesmente não existe", () => {
    const semValor = montarBrCode(BASE);
    expect(lerTlv(semValor).get("54")).toBeUndefined();
    expect(brCodeValido(semValor)).toBe(true);
  });

  it("os tamanhos declarados batem com o conteúdo", () => {
    // Um deslocamento de um caractere é o defeito mais comum em TLV, e o mais
    // difícil de ver a olho.
    let reconstruido = "";
    for (const [id, valor] of lerTlv(codigo)) {
      reconstruido += id + String(valor.length).padStart(2, "0") + valor;
    }
    expect(reconstruido).toBe(codigo);
  });
});

describe("o que vem torto do cadastro", () => {
  it("acento no nome não entra no código", () => {
    const codigo = montarBrCode({ ...BASE, nome: "Ana Paula Ferreira Gonçalves" });
    expect(codigo).not.toMatch(/[^\x20-\x7E]/);
    expect(lerTlv(codigo).get("59")!).not.toContain("ç");
  });

  it("nome e cidade são cortados nos limites do padrão", () => {
    const codigo = montarBrCode({
      chave: BASE.chave,
      nome: "Maria Fernanda dos Santos Oliveira Reis",
      cidade: "Sao Jose do Rio Preto",
    });
    expect(lerTlv(codigo).get("59")!.length).toBeLessThanOrEqual(25);
    expect(lerTlv(codigo).get("60")!.length).toBeLessThanOrEqual(15);
    expect(brCodeValido(codigo)).toBe(true);
  });

  it("nome vazio não gera campo vazio", () => {
    const codigo = montarBrCode({ ...BASE, nome: "   ", cidade: "" });
    expect(lerTlv(codigo).get("59")!.length).toBeGreaterThan(0);
    expect(lerTlv(codigo).get("60")!.length).toBeGreaterThan(0);
    expect(brCodeValido(codigo)).toBe(true);
  });

  it("txid perde o que não é letra ou número", () => {
    expect(limparTxid("cobrança #12/3")).toBe("cobranca123");
    expect(limparTxid("a".repeat(40))).toHaveLength(25);
  });

  it("sem txid, usa o identificador vazio do padrão", () => {
    expect(lerTlv(montarBrCode(BASE)).get("62")).toContain("***");
  });

  it("apenasAscii não devolve espaço solto na ponta", () => {
    expect(apenasAscii("Maria Fernanda Reis de Souza", 15)).toBe("Maria Fernanda");
  });
});

describe("a chave", () => {
  it.each([
    ["12345678901", "cpf"],
    ["12345678000199", "cnpj"],
    ["+5511900000001", "telefone"],
    ["ana@consultorio.com.br", "email"],
    ["123e4567-e89b-12d3-a456-426614174000", "aleatoria"],
  ])("%s é %s", (chave, tipo) => {
    expect(tipoDaChave(chave)).toBe(tipo);
  });

  it.each([
    "123.456.789-01",
    "11 90000-0001",
    "5511900000001",
    "ana@",
    "chave qualquer",
    "",
  ])("%s não é chave válida", (chave) => {
    expect(tipoDaChave(chave)).toBeNull();
  });

  it("gerar com chave inválida lança em vez de produzir um código impagável", () => {
    expect(() => montarBrCode({ ...BASE, chave: "123.456.789-01" })).toThrow(/chave pix/i);
  });

  it("valor negativo ou quebrado também lança", () => {
    expect(() => montarBrCode({ ...BASE, valorCentavos: -100 })).toThrow(/centavos/i);
    expect(() => montarBrCode({ ...BASE, valorCentavos: 0 })).toThrow(/centavos/i);
    expect(() => montarBrCode({ ...BASE, valorCentavos: 10.5 })).toThrow(/centavos/i);
  });
});

describe("brCodeValido", () => {
  it("recusa lixo", () => {
    expect(brCodeValido("")).toBe(false);
    expect(brCodeValido("nao é um código")).toBe(false);
    expect(brCodeValido("0002010102126304ABCD")).toBe(false);
  });
});
