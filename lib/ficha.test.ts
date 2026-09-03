import { describe, it, expect } from "vitest";
import { CAMPOS, ehMenor, idadeEm, validarFicha, type EntradaFicha } from "./ficha";

const HOJE = "2026-09-03";

const cheia = (over: Partial<EntradaFicha> = {}): EntradaFicha => ({
  nome: "Maria Fernanda Reis",
  nascimento: "1990-04-12",
  cpf: "529.982.247-25",
  telefone: "11987654321",
  email: "maria@exemplo.com.br",
  msg_canal: "whatsapp",
  msg_modo: "discreto",
  ...over,
});

describe("a idade sai certa na véspera do aniversário", () => {
  it("conta o aniversário que ainda não chegou", () => {
    expect(idadeEm("2008-09-04", HOJE)).toBe(17);
    expect(idadeEm("2008-09-03", HOJE)).toBe(18);
    expect(idadeEm("2008-09-02", HOJE)).toBe(18);
  });

  /**
   * A véspera é o caso que decide, e ele decide uma exigência legal: quem faz
   * 18 amanhã ainda precisa de responsável hoje. Um `>=` no lugar errado aqui
   * deixaria o registro de um adolescente nascer sem quem responde por ele.
   */
  it("menor de idade é quem ainda não fez 18", () => {
    expect(ehMenor("2008-09-04", HOJE)).toBe(true);
    expect(ehMenor("2008-09-03", HOJE)).toBe(false);
  });
});

describe("o que a paciente manda", () => {
  it("uma ficha completa passa", () => {
    const r = validarFicha(cheia(), HOJE);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.dados.cpf).toBe("52998224725");
      expect(r.dados.telefone).toBe("5511987654321");
      expect(r.dados.responsaveis).toEqual([]);
    }
  });

  /**
   * O CPF é opcional **de propósito**, e é a decisão mais discutível da build.
   *
   * Ele é o campo que trava a linha na importação do Carnê-Leão, então exigi-lo
   * aqui resolveria a "parte chata" do Receita Saúde de uma vez. Mas quem não
   * tem o número à mão no minuto em que abre o link ficaria sem mandar o resto
   * — e o resto é o que faz a primeira sessão acontecer.
   */
  it("sem CPF ela continua conseguindo mandar", () => {
    const r = validarFicha(cheia({ cpf: "" }), HOJE);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.dados.cpf).toBeNull();
  });

  it("CPF com dígito errado é recusado, e a frase diz o que fazer", () => {
    const r = validarFicha(cheia({ cpf: "111.111.111-11" }), HOJE);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.porCampo.cpf).toMatch(/confira/i);
  });

  it("nascimento é obrigatório — sem ele não dá para saber se há responsável", () => {
    const r = validarFicha(cheia({ nascimento: "" }), HOJE);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.porCampo.nascimento).toBeTruthy();
  });

  it("nascimento no futuro é recusado", () => {
    const r = validarFicha(cheia({ nascimento: "2027-01-01" }), HOJE);
    expect(r.ok).toBe(false);
  });

  it("quem escolhe WhatsApp precisa ter telefone", () => {
    const r = validarFicha(cheia({ telefone: "", msg_canal: "whatsapp" }), HOJE);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.porCampo.telefone).toBeTruthy();
  });

  it("quem prefere não ser avisada não precisa de canal nenhum", () => {
    const r = validarFicha(cheia({ telefone: "", email: "", msg_canal: "nao_avisar" }), HOJE);
    expect(r.ok).toBe(true);
  });
});

/**
 * O critério de pronto da build: menor de idade exige responsável, e o dado vai
 * para onde o cadastro de responsáveis da B13 espera encontrá-lo.
 */
describe("menor de 18 não entra sem responsável", () => {
  it("recusa quando falta", () => {
    const r = validarFicha(cheia({ nascimento: "2012-05-10" }), HOJE);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.porCampo.responsavel_nome).toMatch(/respons/i);
  });

  it("aceita quando vem, e devolve no formato de `pacientes.responsaveis`", () => {
    const r = validarFicha(
      cheia({
        nascimento: "2012-05-10",
        responsavel_nome: "João Carlos Reis",
        responsavel_documento: "529.982.247-25",
        responsavel_telefone: "11912345678",
      }),
      HOJE,
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.dados.responsaveis).toEqual([
        { nome: "João Carlos Reis", documento: "52998224725", telefone: "5511912345678" },
      ]);
    }
  });

  it("adulto que informa responsável mesmo assim não é barrado", () => {
    const r = validarFicha(cheia({ responsavel_nome: "Alguém de Confiança" }), HOJE);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.dados.responsaveis).toHaveLength(1);
  });
});

/**
 * A fronteira 6, do lado da lista.
 *
 * `CAMPOS` é fechada, e o que a validação devolve não pode conter nada além
 * dela — é o que impede um campo novo de viajar para o banco por engano. A
 * outra metade da trava está em `salvar_ficha`, que recusa a chamada inteira, e
 * a terceira em `testes/nenhuma-pergunta-clinica.test.ts`, que varre a tela.
 */
describe("nada além dos campos administrativos sai daqui", () => {
  it("o objeto validado tem exatamente as chaves de CAMPOS", () => {
    const r = validarFicha(cheia(), HOJE);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(Object.keys(r.dados).sort()).toEqual([...CAMPOS].sort());
    }
  });

  it("campo estranho no formulário não atravessa", () => {
    const r = validarFicha(
      { ...cheia(), o_que_te_traz: "ansiedade no trabalho" } as EntradaFicha,
      HOJE,
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(JSON.stringify(r.dados)).not.toContain("ansiedade");
      expect(Object.keys(r.dados)).not.toContain("o_que_te_traz");
    }
  });
});
