import { describe, it, expect } from "vitest";
import {
  caixaMarcada,
  cpfBr,
  digitos,
  documentoBr,
  lerCentavos,
  lerValor,
  mascaraCnpj,
  mascaraCpf,
  mascaraDocumento,
  mascaraTelefone,
  paraCampo,
} from "@/lib/formato";

/**
 * O S1 que abriu a B48: `1.200` virava R$ 1,20, calado.
 *
 * O produto tinha duas normalizações locais e incompatíveis. `Number("1.200")`
 * é `1.2` e passa por `Number.isFinite(v) && v >= 0` sem reclamar; do outro
 * lado, `"1200.00".replace(/\./g, "")` vira `"120000"` e grava cem vezes mais.
 * Nenhuma das duas mostrava erro — e o número atravessava cobrança, Pix,
 * recibo e carnê-leão.
 *
 * Estes casos são a fronteira entre as duas leituras, e é por isso que o
 * parser fareja a **vírgula decimal** em vez de contar pontos.
 */
describe("lerCentavos — o que ela digitou é o que fica gravado", () => {
  it.each([
    ["200", 20_000, "o caso simples"],
    ["200,00", 20_000, "com centavos em vírgula"],
    ["R$ 200,00", 20_000, "com o cifrão que ela cola junto"],
    ["  200,00  ", 20_000, "com o espaço que sobra da colagem"],
    ["1.200", 120_000, "o S1: milhar em ponto, sem centavos"],
    ["1.200,50", 120_050, "milhar em ponto e centavos em vírgula"],
    ["1200,50", 120_050, "sem o milhar"],
    ["1200.50", 120_050, "o que sai de planilha em inglês"],
    ["1200.00", 120_000, "o outro S1: cem vezes mais, na direção contrária"],
    ["1.200.000,00", 120_000_000, "dois milhares"],
    ["0", 0, "zero é legível — quem decide se serve é quem chama"],
    ["0,00", 0, "zero com centavos também"],
  ])("%s → %i centavos (%s)", (bruto, esperado) => {
    expect(lerCentavos(bruto)).toBe(esperado);
  });

  it.each([
    ["", "vazio"],
    ["combinar", "palavra"],
    ["R$", "só o cifrão"],
    ["12,345", "três casas decimais não é dinheiro"],
    ["-200", "campo digitado não recebe sinal"],
    ["1,2,3", "pontuação que não é número"],
    ["12.3456", "quatro casas depois do ponto não é nem milhar nem centavo"],
    ["1.20.30", "dois pontos que não são milhar"],
    ["1.2000", "milhar tem exatamente três casas"],
  ])("recusa %s (%s)", (bruto) => {
    expect(lerCentavos(bruto)).toBeNull();
  });

  it("nunca lança — quem digita errado vê recusa, não erro 500", () => {
    for (const bruto of ["", "abc", "R$ R$", "...", ",,,", "-", "1e10"]) {
      expect(() => lerCentavos(bruto)).not.toThrow();
    }
  });
});

describe("lerValor — o mesmo parser, com zero recusado", () => {
  it("aceita o que lerCentavos aceita, acima de zero", () => {
    expect(lerValor("1.200")).toBe(120_000);
    expect(lerValor("1200.00")).toBe(120_000);
  });

  it("recusa zero: na colagem, 0 não é 'de graça', é linha em branco", () => {
    expect(lerValor("0")).toBeNull();
    expect(lerValor("0,00")).toBeNull();
  });
});

/**
 * A caixa desmarcada não envia nada — e era isso que o produto esquecia.
 *
 * `form.get("ativo") !== "nao"` devolve `true` para a caixa desmarcada, porque
 * `null !== "nao"`. As duas caixas da fila eram escreve-sempre-verdadeiro, e
 * uma delas é a que decide se a pessoa recebe oferta de vaga. Quem descobria
 * era a paciente.
 */
describe("caixaMarcada — desmarcado é ausente, e ausente é falso", () => {
  const comValor = (v: string | null) => {
    const f = new FormData();
    if (v !== null) f.set("caixa", v);
    return f;
  };

  it("marcada, com qualquer um dos valores que o HTML manda", () => {
    for (const v of ["sim", "1", "on", "true", ""]) {
      expect(caixaMarcada(comValor(v), "caixa")).toBe(true);
    }
  });

  it("desmarcada não manda nada, e isso é falso", () => {
    expect(caixaMarcada(comValor(null), "caixa")).toBe(false);
  });

  it("o defeito exato: null !== 'nao' seria true", () => {
    const f = comValor(null);
    expect(f.get("caixa") !== "nao").toBe(true); // o que o produto fazia
    expect(caixaMarcada(f, "caixa")).toBe(false); // o que ele faz agora
  });
});

describe("as máscaras acompanham quem está digitando", () => {
  it.each([
    ["", ""],
    ["1", "1"],
    ["123", "123"],
    ["1234", "123.4"],
    ["1234567", "123.456.7"],
    ["12345678901", "123.456.789-01"],
    ["123456789012345", "123.456.789-01"],
    ["123.456.789-01", "123.456.789-01"],
  ])("mascaraCpf(%s) = %s", (bruto, esperado) => {
    expect(mascaraCpf(bruto)).toBe(esperado);
  });

  it.each([
    ["12345678000199", "12.345.678/0001-99"],
    ["12345", "12.345"],
  ])("mascaraCnpj(%s) = %s", (bruto, esperado) => {
    expect(mascaraCnpj(bruto)).toBe(esperado);
  });

  it("o campo é CPF ou CNPJ, e a máscara troca sozinha no 12º dígito", () => {
    expect(mascaraDocumento("12345678901")).toBe("123.456.789-01");
    expect(mascaraDocumento("123456789012")).toBe("12.345.678/9012");
    expect(mascaraDocumento("12345678000199")).toBe("12.345.678/0001-99");
  });

  it.each([
    ["", ""],
    ["11", "11"],
    ["1198765", "(11) 9876-5"],
    ["1187654321", "(11) 8765-4321"],
    ["11987654321", "(11) 98765-4321"],
    ["5511987654321", "(11) 98765-4321"],
  ])("mascaraTelefone(%s) = %s", (bruto, esperado) => {
    expect(mascaraTelefone(bruto)).toBe(esperado);
  });

  it("mascarar duas vezes não estraga — o onChange reaplica a cada tecla", () => {
    for (const f of [mascaraCpf, mascaraCnpj, mascaraTelefone, mascaraDocumento]) {
      for (const bruto of ["12345678901", "12345678000199", "11987654321", ""]) {
        expect(f(f(bruto))).toBe(f(bruto));
      }
    }
  });
});

describe("como CPF e CNPJ aparecem prontos", () => {
  it("cpfBr põe travessão quando não há onze dígitos", () => {
    expect(cpfBr("12345678901")).toBe("123.456.789-01");
    expect(cpfBr(null)).toBe("—");
    expect(cpfBr("123")).toBe("—");
  });

  it("documentoBr mostra o que está gravado quando não é nem CPF nem CNPJ", () => {
    expect(documentoBr("12345678901")).toBe("123.456.789-01");
    expect(documentoBr("12345678000199")).toBe("12.345.678/0001-99");
    expect(documentoBr(null)).toBeNull();
    expect(documentoBr("123")).toBe("123");
  });

  it("digitos joga fora tudo que não é número", () => {
    expect(digitos("(11) 98765-4321")).toBe("11987654321");
    expect(digitos(null)).toBe("");
  });
});

/**
 * O campo de dinheiro nasce em português.
 *
 * `deCentavos` põe ponto porque é assim que o número vai para o banco — e era
 * ela que preenchia o campo "cobrar quanto" da caixa "A decidir". Ela lia
 * `200.00` num campo que ia decidir quanto cobrar de uma paciente, e `200.00`
 * em português é duzentos mil.
 */
describe("o valor inicial do campo se lê em português", () => {
  it("põe vírgula nos centavos e ponto no milhar", () => {
    expect(paraCampo(20000)).toBe("200,00");
    expect(paraCampo(120050)).toBe("1.200,50");
    expect(paraCampo(100000000)).toBe("1.000.000,00");
    expect(paraCampo(5)).toBe("0,05");
    expect(paraCampo(0)).toBe("0,00");
    expect(paraCampo(-12345)).toBe("-123,45");
  });

  /** A volta tem de fechar: o que o campo mostra, o parser aceita. */
  it("o que ele escreve, `lerCentavos` lê de volta", () => {
    for (const c of [0, 5, 99, 100, 20000, 120050, 999999, 100000000]) {
      expect(lerCentavos(paraCampo(c)), `${c} → ${paraCampo(c)}`).toBe(c);
    }
  });
});
