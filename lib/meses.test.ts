import { describe, it, expect } from "vitest";
import { formatar } from "@/lib/dinheiro";
import {
  nomeDoMes,
  diaCurto,
  emReais,
  horarios,
  marcaDoPago,
  marcaDoRecibo,
  marcasDoMes,
  MARCAS,
  type LinhaDoMes,
} from "@/lib/meses";

/** Um mês inteiro pago, com recibo dentro da janela. */
function linha(x: Partial<LinhaDoMes> = {}): LinhaDoMes {
  return {
    competencia: "2026-08-01",
    combinado: 1300,
    quantos: 5,
    aberto: 0,
    pago: 1300,
    perdoado: 0,
    pago_em: "2026-09-02T15:00:00+00:00",
    recibo: null,
    recibo_numero: null,
    recibo_em: null,
    recibo_na_janela: false,
    ...x,
  };
}

describe("o mês tem nome, e o fuso é decisão (lei 3)", () => {
  it("competência é data pura e não pode andar um dia para trás", () => {
    // "2026-08-01" é meia-noite UTC, que em São Paulo ainda é 31 de julho.
    // Sem o meio-dia, a competência de agosto vira julho na tela.
    expect(nomeDoMes("2026-08-01")).toBe("agosto de 2026");
    expect(nomeDoMes("2026-01-01")).toBe("janeiro de 2026");
  });

  it("sem data não inventa mês", () => {
    expect(nomeDoMes(null)).toBe("o mês");
    expect(nomeDoMes("banana")).toBe("o mês");
  });

  it("o dia curto também não inventa", () => {
    expect(diaCurto(null)).toBe("—");
    expect(diaCurto("2026-09-02T15:00:00+00:00")).toBe("02/09");
  });
});

describe("o dinheiro passa pela mesma função da tela dela", () => {
  it("reais do banco viram centavos inteiros", () => {
    expect(emReais(1300)).toBe(formatar(130000));
    expect(emReais("260.00")).toBe(formatar(26000));
  });

  it("valor ausente ou quebrado é zero, nunca NaN na tela", () => {
    expect(emReais(null)).toBe(formatar(0));
    expect(emReais("x")).toBe(formatar(0));
  });
});

describe("quantos horários", () => {
  it("por extenso até nove", () => {
    expect(horarios(1)).toBe("um horário");
    expect(horarios(5)).toBe("cinco horários");
    expect(horarios(12)).toBe("12 horários");
  });

  it("zero não vira 'nenhum'... vira 'nenhum horário', que é o fato", () => {
    expect(horarios(0)).toBe("nenhum horário");
  });
});

describe("a marca do pago — e o mês parcial não é um mês pago", () => {
  /*
    Este é o caso que o banco tem hoje na conta de demonstração: agosto com
    R$ 1.040 pagos, R$ 260 em aberto e `pago_em` preenchido. Uma linha que
    lesse `pago_em` primeiro escreveria "pago em 02/09" sobre um mês que ainda
    deve — o campo que não faz o que ela digitou, com dinheiro dentro.
  */
  it("sobrando valor, o mês está em aberto mesmo com pago_em preenchido", () => {
    const l = linha({ combinado: 1300, pago: 1040, aberto: 260 });
    expect(marcaDoPago(l)).toBe("em_aberto");
    const marca = marcasDoMes(l, true).find((m) => m.chave === "pago");
    expect(marca?.texto).toBe(`${formatar(26000)} em aberto`);
  });

  it("nada em aberto e algo pago, o mês está pago, com a data", () => {
    expect(marcaDoPago(linha())).toBe("pago");
    expect(marcasDoMes(linha(), true).find((m) => m.chave === "pago")?.texto).toBe(
      "pago em 02/09",
    );
  });

  it("perdoado só ganha quando não há nem aberto nem pago", () => {
    expect(marcaDoPago(linha({ pago: 0, perdoado: 260, pago_em: null }))).toBe("perdoado");
    expect(marcaDoPago(linha({ pago: 1040, perdoado: 260 }))).toBe("pago");
  });

  it("mês sem dinheiro nenhum não recebe palavra", () => {
    const l = linha({ combinado: 0, quantos: 0, pago: 0, pago_em: null });
    expect(marcaDoPago(l)).toBe("nada");
    expect(marcasDoMes(l, true).find((m) => m.chave === "pago")?.texto).toBe("—");
  });

  /*
    Achado da suíte 0066, rodada contra o banco depois da 0095: um recibo
    trimestral cria três competências, e as cobranças podem estar lançadas em
    uma só. As outras duas vinham com `combinado: 0, quantos: 0` — e a tela
    escrevia "R$ 0,00 · nenhum horário" ao lado de um recibo de R$ 800.
  */
  it("mês que só existe por causa do documento não escreve R$ 0,00", () => {
    const l = linha({ combinado: 0, quantos: 0, pago: 0, pago_em: null, recibo: "d1", recibo_em: "2026-02-15T12:00:00Z" });
    expect(marcasDoMes(l, true).find((m) => m.chave === "combinado")?.texto).toBe("—");
  });
});

describe("a marca do recibo, e a janela de 90 dias da 0066", () => {
  it("sem documento, não emitido", () => {
    expect(marcaDoRecibo(linha(), true)).toBe("nao_emitido");
    expect(marcaDoRecibo(linha(), false)).toBe("nao_emitido");
  });

  /*
    Desde a 0096 a página do paciente recebe `recibo` nulo quando o documento
    está fora da janela — ela mostra que o recibo existe sem entregar o endereço
    dele. Ler o id como sinal de existência faria a página dizer "ainda não
    emitido" sobre um recibo emitido, e mandar a pessoa cobrar dela um papel que
    ela já fez.
  */
  it("id nulo e data preenchida é recibo guardado, nunca 'não emitido'", () => {
    const l = linha({ recibo: null, recibo_numero: null, recibo_em: "2026-03-02T12:00:00Z", recibo_na_janela: false });
    expect(marcaDoRecibo(l, true)).toBe("guardado");
    expect(marcasDoMes(l, true).find((m) => m.chave === "recibo")?.texto).toBe(
      "emitido em 02/03",
    );
  });

  it("na página do paciente, fora da janela é guardado — a porta responderia 404", () => {
    const l = linha({ recibo: "d1", recibo_numero: 12, recibo_em: "2026-03-02T12:00:00Z", recibo_na_janela: false });
    expect(marcaDoRecibo(l, true)).toBe("guardado");
    expect(marcasDoMes(l, true).find((m) => m.chave === "recibo")?.texto).toBe(
      "emitido em 02/03",
    );
  });

  it("na tela dela não há janela: o mesmo recibo está disponível", () => {
    const l = linha({ recibo: "d1", recibo_numero: 12, recibo_em: "2026-03-02T12:00:00Z", recibo_na_janela: false });
    expect(marcaDoRecibo(l, false)).toBe("disponivel");
  });

  it("dentro da janela, disponível nos dois lados", () => {
    const l = linha({ recibo: "d1", recibo_numero: 12, recibo_em: "2026-09-01T12:00:00Z", recibo_na_janela: true });
    expect(marcaDoRecibo(l, true)).toBe("disponivel");
    expect(marcaDoRecibo(l, false)).toBe("disponivel");
  });
});

describe("as mesmas marcas, na mesma ordem, nos dois lugares", () => {
  it("três marcas, e a ordem é a do §5.4", () => {
    expect(MARCAS).toEqual(["combinado", "pago", "recibo"]);
    expect(marcasDoMes(linha(), true).map((m) => m.chave)).toEqual([...MARCAS]);
    expect(marcasDoMes(linha(), false).map((m) => m.chave)).toEqual([...MARCAS]);
  });

  it("os rótulos não mudam de lado — só o texto pode", () => {
    const dela = marcasDoMes(linha(), false).map((m) => m.rotulo);
    const dele = marcasDoMes(linha(), true).map((m) => m.rotulo);
    expect(dela).toEqual(dele);
  });

  /*
    A quarta marca do §5.4 é **Comprovante**, e ela não está aqui porque a
    tabela `comprovantes` não existe: é da B53, bloqueada pela cláusula do doc
    18. Este teste é o que impede alguém de acrescentá-la como enfeite antes de
    haver o que ela mostre — a promessa que o software não cumpre.
  */
  it("comprovante não aparece enquanto não existir", () => {
    for (const lado of [true, false]) {
      const chaves = marcasDoMes(linha(), lado).map((m) => m.chave) as string[];
      expect(chaves).not.toContain("comprovante");
    }
  });

  it("nenhuma marca sai vazia — travessão é resposta, string vazia é defeito", () => {
    const vazia = linha({ combinado: 0, quantos: 0, pago: 0, pago_em: null });
    for (const lado of [true, false]) {
      for (const m of marcasDoMes(vazia, lado)) {
        expect(m.rotulo.trim().length).toBeGreaterThan(0);
        expect(m.texto.trim().length).toBeGreaterThan(0);
      }
    }
  });
});
