import { describe, expect, it } from "vitest";
import {
  normalizarTelefone,
  formatarTelefone,
  cpfValido,
  validarPaciente,
} from "./paciente";

describe("telefone — guardar de um jeito só", () => {
  it("aceita o que a pessoa realmente digita", () => {
    expect(normalizarTelefone("(11) 98765-4321")).toBe("5511987654321");
    expect(normalizarTelefone("11987654321")).toBe("5511987654321");
    expect(normalizarTelefone("+55 11 98765 4321")).toBe("5511987654321");
    expect(normalizarTelefone("1132654321")).toBe("551132654321"); // fixo
  });

  it("vazio é vazio, não erro", () => {
    expect(normalizarTelefone("")).toBeNull();
    expect(normalizarTelefone("   ")).toBeNull();
  });

  it("recusa o que não é telefone", () => {
    expect(() => normalizarTelefone("123")).toThrow();
    expect(() => normalizarTelefone("1".repeat(20))).toThrow();
  });

  it("volta bonito para a tela", () => {
    expect(formatarTelefone("5511987654321")).toBe("(11) 98765-4321");
    expect(formatarTelefone("551132654321")).toBe("(11) 3265-4321");
    expect(formatarTelefone(null)).toBe("—");
  });
});

describe("CPF — recusar no cadastro, não na hora do recibo", () => {
  it("aceita CPF com dígito certo", () => {
    expect(cpfValido("529.982.247-25")).toBe(true);
    expect(cpfValido("52998224725")).toBe(true);
  });

  it("recusa dígito verificador errado", () => {
    expect(cpfValido("529.982.247-26")).toBe(false);
    expect(cpfValido("12345678900")).toBe(false);
  });

  it("recusa os repetidos, que passam na conta mas não existem", () => {
    expect(cpfValido("00000000000")).toBe(false);
    expect(cpfValido("11111111111")).toBe(false);
    expect(cpfValido("99999999999")).toBe(false);
  });

  it("recusa tamanho errado", () => {
    expect(cpfValido("529982247")).toBe(false);
    expect(cpfValido("")).toBe(false);
  });
});

describe("validarPaciente — o critério de pronto da B4", () => {
  const maria = {
    nome: "Maria Fernanda Reis",
    telefone: "(11) 98765-4321",
    email: "",
    cpf: "",
    estado: "em_atendimento",
    msg_canal: "whatsapp",
    msg_modo: "discreto",
    observacao: "",
  };

  it("cadastra a Maria Fernanda com WhatsApp em modo discreto", () => {
    const r = validarPaciente(maria);
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    expect(r.dados).toMatchObject({
      nome: "Maria Fernanda Reis",
      telefone: "5511987654321",
      estado: "em_atendimento",
      msg_canal: "whatsapp",
      msg_modo: "discreto",
      email: null,
      cpf: null,
    });
  });

  it("o padrão é discreto — o D3 não depende de ninguém lembrar", () => {
    const r = validarPaciente({ nome: "Ana", telefone: "11999999999" });
    expect(r.ok && r.dados.msg_modo).toBe("discreto");
    expect(r.ok && r.dados.msg_canal).toBe("whatsapp");
  });

  it("não deixa prometer aviso por um canal que não existe no cadastro", () => {
    const semTelefone = validarPaciente({ ...maria, telefone: "" });
    expect(semTelefone.ok).toBe(false);
    expect(semTelefone.ok === false && semTelefone.erros[0]).toMatch(/WhatsApp/);

    const soEmail = validarPaciente({ ...maria, telefone: "", msg_canal: "email" });
    expect(soEmail.ok).toBe(false);
    expect(soEmail.ok === false && soEmail.erros[0]).toMatch(/e-mail/);
  });

  it("quem escolhe não avisar não precisa de contato nenhum", () => {
    const r = validarPaciente({ nome: "Caio Nogueira", msg_canal: "nao_avisar" });
    expect(r.ok).toBe(true);
    expect(r.ok && r.dados.telefone).toBeNull();
  });

  it("junta todos os problemas de uma vez, em vez de um por vez", () => {
    const r = validarPaciente({
      nome: "A",
      telefone: "123",
      email: "nao-e-email",
      cpf: "11111111111",
      msg_canal: "whatsapp",
    });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.erros.length).toBeGreaterThanOrEqual(4);
  });

  it("normaliza e-mail para minúsculo, para não duplicar paciente", () => {
    const r = validarPaciente({
      nome: "Bia",
      email: "  Bia@Exemplo.COM.BR ",
      msg_canal: "email",
    });
    expect(r.ok && r.dados.email).toBe("bia@exemplo.com.br");
  });
});

/**
 * O erro precisa saber de qual campo ele veio.
 *
 * O produto tinha zero `aria-invalid` e zero erros ao lado do campo: toda
 * mensagem caía numa lista no fim do formulário. Num cadastro de duas telas e
 * meia em 375 px, "Telefone inválido" no rodapé quer dizer "está errado em
 * algum lugar aí atrás".
 */
describe("o erro tem dono", () => {
  it("cada problema aponta o campo que o causou", () => {
    const r = validarPaciente({ nome: "A", telefone: "abc", email: "nao-e-email", cpf: "111" });
    expect(r.ok).toBe(false);
    if (r.ok) return;

    expect(r.porCampo.nome).toBe("O nome precisa de ao menos duas letras.");
    expect(r.porCampo.telefone).toBeDefined();
    expect(r.porCampo.email).toBe("E-mail inválido.");
    expect(r.porCampo.cpf).toBe("CPF inválido.");
  });

  it("porCampo e erros são a mesma lista, e nada se perde entre as duas", () => {
    const r = validarPaciente({ nome: "", telefone: "", msg_canal: "whatsapp" });
    expect(r.ok).toBe(false);
    if (r.ok) return;

    for (const frase of Object.values(r.porCampo)) {
      expect(r.erros).toContain(frase);
    }
    expect(r.erros.length).toBeGreaterThanOrEqual(Object.keys(r.porCampo).length);
  });

  it("o canal escolhido decide de quem é a falta", () => {
    const semTelefone = validarPaciente({ nome: "Ana", telefone: "", msg_canal: "whatsapp" });
    expect(semTelefone.ok).toBe(false);
    if (!semTelefone.ok) {
      expect(semTelefone.porCampo.telefone).toBe("Para avisar por WhatsApp, informe o telefone.");
    }

    const semEmail = validarPaciente({ nome: "Ana", telefone: "", msg_canal: "email" });
    expect(semEmail.ok).toBe(false);
    if (!semEmail.ok) {
      expect(semEmail.porCampo.email).toBe("Para avisar por e-mail, informe o e-mail.");
      expect(semEmail.porCampo.telefone).toBeUndefined();
    }
  });
});
