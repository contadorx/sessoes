import { describe, it, expect } from "vitest";
import {
  ocorrenciasNoMes,
  previsaoDoMes,
  explicacaoDoMesDeCinco,
  proximoMesDeCinco,
  estadoDoPacote,
  rotuloDoPacote,
  rotuloModelo,
  diaBr,
  MODELOS,
  type Combinado,
  type PacoteLinha,
} from "@/lib/cobranca";
import { formatar } from "@/lib/dinheiro";

/**
 * Os dois meses de referência do projeto inteiro. Os mesmos valores estão em
 * `supabase/tests/0033_modelos_de_cobranca.sql` (verificações 1 a 3): se a
 * conta do banco e a da tela divergirem, uma das duas suítes falha.
 */
const MARCO = { ano: 2026, mes: 3 }; // cinco terças
const ABRIL = { ano: 2026, mes: 4 }; // quatro terças
const TERCA = 2;

describe("quantas vezes o dia cai no mês", () => {
  it("março/2026 tem cinco terças", () => {
    expect(ocorrenciasNoMes(TERCA, MARCO.ano, MARCO.mes)).toBe(5);
  });

  it("abril/2026 tem quatro terças", () => {
    expect(ocorrenciasNoMes(TERCA, ABRIL.ano, ABRIL.mes)).toBe(4);
  });

  it("fevereiro de ano bissexto começando no dia certo tem cinco", () => {
    // 2032: 1º de fevereiro é domingo, 29 dias → cinco domingos.
    expect(ocorrenciasNoMes(0, 2032, 2)).toBe(5);
    expect(ocorrenciasNoMes(1, 2032, 2)).toBe(4);
  });

  it("todo mês tem quatro ou cinco de cada dia, nunca outra coisa", () => {
    for (let ano = 2026; ano <= 2030; ano++) {
      for (let mes = 1; mes <= 12; mes++) {
        for (let dia = 0; dia <= 6; dia++) {
          const n = ocorrenciasNoMes(dia, ano, mes);
          expect(n === 4 || n === 5).toBe(true);
        }
      }
    }
  });

  it("a soma dos sete dias é o número de dias do mês", () => {
    // A prova de que nenhum dia é contado duas vezes nem esquecido — inclusive
    // em fevereiro bissexto, que é onde este tipo de laço costuma errar.
    for (const [ano, mes, dias] of [
      [2026, 2, 28],
      [2028, 2, 29],
      [2026, 3, 31],
      [2026, 4, 30],
    ] as const) {
      let soma = 0;
      for (let d = 0; d <= 6; d++) soma += ocorrenciasNoMes(d, ano, mes);
      expect(soma).toBe(dias);
    }
  });
});

const FIXO: Combinado = {
  modelo: "mensal",
  diaSemana: TERCA,
  valorCentavos: 20_000,
  mensalidadeCentavos: 75_000,
};

const POR_SESSAO: Combinado = { ...FIXO, mensalidadeCentavos: null };

describe("o mês de cinco terças", () => {
  it("valor fixo: cinco terças saem pelo mesmo preço de quatro", () => {
    const cinco = previsaoDoMes(FIXO, MARCO.ano, MARCO.mes);
    const quatro = previsaoDoMes(FIXO, ABRIL.ano, ABRIL.mes);
    expect(cinco.ocorrencias).toBe(5);
    expect(quatro.ocorrencias).toBe(4);
    expect(cinco.centavos).toBe(75_000);
    expect(quatro.centavos).toBe(75_000);
  });

  it("por sessão: cinco terças saem maiores", () => {
    expect(previsaoDoMes(POR_SESSAO, MARCO.ano, MARCO.mes).centavos).toBe(100_000);
    expect(previsaoDoMes(POR_SESSAO, ABRIL.ano, ABRIL.mes).centavos).toBe(80_000);
  });

  it("a frase diz o número, e diz em reais", () => {
    // `formatar` e não a string literal: o Intl põe um espaço fino (U+00A0)
    // depois do "R$", e um literal digitado à mão nunca bate com ele. Já custou
    // uma falha aqui e outra na B19.
    const p = previsaoDoMes(POR_SESSAO, MARCO.ano, MARCO.mes);
    expect(p.frase).toContain("5 terças");
    expect(p.frase).toContain(formatar(100_000));
    expect(p.frase).toContain(formatar(20_000));
  });

  it("no fixo, a frase compara com o outro tamanho de mês", () => {
    expect(previsaoDoMes(FIXO, MARCO.ano, MARCO.mes).frase).toContain("o mesmo de um mês com 4");
    expect(previsaoDoMes(FIXO, ABRIL.ano, ABRIL.mes).frase).toContain("o mesmo de um mês com 5");
  });

  it("avulso e pacote não têm previsão de mês — e não inventam uma", () => {
    for (const modelo of ["avulso", "pacote"] as const) {
      const p = previsaoDoMes({ ...FIXO, modelo }, MARCO.ano, MARCO.mes);
      expect(p.frase).toBe("");
      expect(p.centavos).toBe(0);
    }
  });

  it("a explicação nomeia a consequência, não o campo", () => {
    expect(explicacaoDoMesDeCinco(75_000)).toContain("mesmo preço");
    expect(explicacaoDoMesDeCinco(null)).toContain("maior");
  });

  it("acha um mês de cinco para dar de exemplo", () => {
    const m = proximoMesDeCinco(TERCA, new Date(Date.UTC(2026, 0, 1)));
    expect(m).not.toBeNull();
    expect(ocorrenciasNoMes(TERCA, m!.ano, m!.mes)).toBe(5);
  });
});

describe("os modelos", () => {
  it("são três, e cada um explica o que faz com a falta", () => {
    expect(MODELOS).toHaveLength(3);
    expect(rotuloModelo("mensal")).toBe("mensalidade");
    expect(MODELOS.find((m) => m.valor === "mensal")!.explica).toContain("falta");
    expect(MODELOS.find((m) => m.valor === "pacote")!.explica).toContain("falta");
  });

  it("um modelo desconhecido aparece como veio, sem quebrar a tela", () => {
    expect(rotuloModelo("inventado")).toBe("inventado");
  });
});

const HOJE = "2026-09-01";

const P: PacoteLinha = {
  id: "p",
  quantidade: 4,
  valor: "800.00",
  validade: "2026-12-31",
  vendido_em: "2026-08-01T12:00:00Z",
  cancelado_em: null,
  consumidos: 1,
};

describe("o painel do pacote", () => {
  it("vivo mostra saldo e validade", () => {
    expect(estadoDoPacote(P, HOJE)).toBe("vivo");
    expect(rotuloDoPacote(P, HOJE)).toContain("3 de 4");
    expect(rotuloDoPacote(P, HOJE)).toContain("31/12/2026");
  });

  it("esgotado avisa que as próximas voltam a ser por sessão", () => {
    const e = { ...P, consumidos: 4 };
    expect(estadoDoPacote(e, HOJE)).toBe("esgotado");
    expect(rotuloDoPacote(e, HOJE)).toContain("por sessão");
  });

  it("vencido também avisa — e diz quantos créditos ficaram para trás", () => {
    const v = { ...P, validade: "2026-08-31" };
    expect(estadoDoPacote(v, HOJE)).toBe("vencido");
    expect(rotuloDoPacote(v, HOJE)).toContain("3 créditos sem usar");
    expect(rotuloDoPacote(v, HOJE)).toContain("por sessão");
  });

  it("cancelado não some com o que já foi usado", () => {
    const c = { ...P, cancelado_em: "2026-09-01T10:00:00Z" };
    expect(estadoDoPacote(c, HOJE)).toBe("cancelado");
    expect(rotuloDoPacote(c, HOJE)).toContain("continuam registrados");
  });

  it("cancelado ganha de esgotado e de vencido", () => {
    const c = { ...P, consumidos: 4, validade: "2020-01-01", cancelado_em: "2026-09-01T10:00:00Z" };
    expect(estadoDoPacote(c, HOJE)).toBe("cancelado");
  });

  it("a data civil não passa por fuso nenhum", () => {
    expect(diaBr("2026-01-01")).toBe("01/01/2026");
    expect(diaBr("2026-12-31")).toBe("31/12/2026");
  });
});
