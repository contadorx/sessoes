import { describe, it, expect } from "vitest";
import {
  escaparCsv,
  valorCsv,
  comBom,
  nomeDoMes,
  nomeDoArquivo,
  resumoDoRetrato,
  fraseDoFiscal,
  rotuloEstado,
  rotuloTipo,
  mesAFechar,
  primeiroDia,
  type RetratoPasta,
  type PastaLinha,
} from "@/lib/contador";
import { formatar } from "@/lib/dinheiro";

/**
 * A string desagradável é a mesma da suíte SQL `0039_pasta_do_contador.sql`:
 * uma descrição com ponto e vírgula, aspas e acento. Se as duas escapatórias
 * divergirem, o CSV que o contador abre tem uma coluna a mais e a soma dele não
 * bate — e ninguém descobre isso olhando o arquivo.
 */
const FEIA = 'Sala "A"; segunda e quarta';

const RETRATO: RetratoPasta = {
  competencia: "2026-07",
  de: "2026-07-01",
  ate: "2026-07-31",
  versao: 1,
  substitui: null,
  conta: { nome: "Ana Solo", cidade: "São Paulo" },
  profissional: { nome: "Ana Ferreira", documento: "12345678901" },
  receitas: {
    total: "380.00",
    lancamentos: 2,
    pessoas: 1,
    por_tipo: { sessao: "380.00" },
  },
  despesas: {
    total: "1200.00",
    lancamentos: 2,
    por_categoria: { aluguel: "900.00", supervisao: "300.00" },
  },
  sobra: "-820.00",
  fiscal: { recibos_pendentes: 2, recibos_emitidos: 0, prazo_receita_saude: "2027-02-28" },
  aviso: "Regime de caixa.",
};

describe("o CSV", () => {
  it("escapa igual ao banco: aspas dobradas, sempre entre aspas", () => {
    expect(escaparCsv(FEIA)).toBe('"Sala ""A""; segunda e quarta"');
  });

  it("o ponto e vírgula digitado não vira coluna nova", () => {
    const campo = escaparCsv(FEIA);
    // Fora das aspas não sobra separador nenhum.
    expect(campo.startsWith('"')).toBe(true);
    expect(campo.endsWith('"')).toBe(true);
    expect(campo.slice(1, -1).replace(/""/g, "")).not.toContain('"');
  });

  it("aguenta vazio e nulo sem quebrar a linha", () => {
    expect(escaparCsv("")).toBe('""');
    expect(escaparCsv(null)).toBe('""');
    expect(escaparCsv(undefined)).toBe('""');
  });

  it("o valor sai com vírgula decimal, como o Excel em português espera", () => {
    expect(valorCsv(20000)).toBe("200,00");
    expect(valorCsv(123450)).toBe("1234,50");
    expect(valorCsv(5)).toBe("0,05");
    expect(valorCsv(0)).toBe("0,00");
  });

  it("nunca separa milhar — separador de milhar com vírgula decimal é ambíguo", () => {
    expect(valorCsv(123456789)).toBe("1234567,89");
    expect(valorCsv(123456789)).not.toContain(".");
  });

  it("preserva o sinal", () => {
    expect(valorCsv(-82000)).toBe("-820,00");
  });

  it("recusa centavos fracionários em vez de arredondar em silêncio", () => {
    expect(() => valorCsv(10.5)).toThrow();
  });

  it("o download leva o BOM; o que fica guardado, não", () => {
    const csv = "data;tipo\n01/07/2026;Receita";
    expect(comBom(csv).charCodeAt(0)).toBe(0xfeff);
    expect(comBom(csv).slice(1)).toBe(csv);
    expect(csv.charCodeAt(0)).not.toBe(0xfeff);
  });
});

describe("o resumo", () => {
  it("diz entradas, saídas e saldo, com os números do retrato", () => {
    const t = resumoDoRetrato(RETRATO);
    expect(t).toContain(formatar(38000));
    expect(t).toContain(formatar(120000));
    expect(t).toContain(formatar(-82000));
    expect(t).toContain("julho de 2026");
  });

  it("quebra por tipo e por categoria, em português", () => {
    const t = resumoDoRetrato(RETRATO);
    expect(t).toContain("atendimentos");
    expect(t).toContain("Sala");
    expect(t).toContain("Supervisão");
  });

  it("avisa que é regime de caixa — supor errado sobre isso é mês de retrabalho", () => {
    expect(resumoDoRetrato(RETRATO)).toContain("data de cada linha é a do pagamento");
  });

  it("diz que não há identificação de paciente", () => {
    const t = resumoDoRetrato(RETRATO);
    expect(t).toContain("Sem identificação de pacientes");
    expect(t).toContain("LGPD");
  });

  it("não tem por onde um nome de paciente entrar", () => {
    const t = resumoDoRetrato(RETRATO);
    // O tipo do retrato não guarda paciente; o resumo só lê o que existe nele.
    expect(t).not.toMatch(/paciente:|nome do paciente|Zebulon/i);
    expect(Object.keys(RETRATO)).not.toContain("pacientes");
    expect(Object.keys(RETRATO)).not.toContain("sessoes");
  });

  it("a versão 2 avisa que substitui a anterior", () => {
    const t = resumoDoRetrato({ ...RETRATO, versao: 2, substitui: "2026-08-05T10:00:00Z" });
    expect(t).toContain("Versão 2");
    expect(t).toContain("use este arquivo");
  });

  it("a versão 1 não fala de substituição", () => {
    expect(resumoDoRetrato(RETRATO)).not.toContain("Substitui");
  });

  it("um mês sem nada não inventa quebra", () => {
    const vazio = resumoDoRetrato({
      ...RETRATO,
      receitas: { total: "0", lancamentos: 0, pessoas: 0, por_tipo: {} },
      despesas: { total: "0", lancamentos: 0, por_categoria: {} },
      sobra: "0",
    });
    expect(vazio).toContain("0 lançamentos");
    expect(vazio).toContain(formatar(0));
  });
});

describe("o gancho com o Receita Saúde", () => {
  it("conta o que falta emitir e lembra quem emite", () => {
    const f = fraseDoFiscal(RETRATO);
    expect(f).toContain("2 recibos");
    expect(f).toContain("Quem emite é você");
  });

  it("com tudo emitido, dá a notícia boa e para por aí", () => {
    const f = fraseDoFiscal({
      ...RETRATO,
      fiscal: { ...RETRATO.fiscal, recibos_pendentes: 0, recibos_emitidos: 3 },
    });
    expect(f).toContain("já foram emitidos");
    expect(f).not.toContain("Quem emite");
  });

  it("mês sem recibo nenhum não vira frase", () => {
    const f = fraseDoFiscal({
      ...RETRATO,
      fiscal: { ...RETRATO.fiscal, recibos_pendentes: 0, recibos_emitidos: 0 },
    });
    expect(f).toBe("");
  });
});

describe("os rótulos e as datas", () => {
  const base: PastaLinha = {
    id: "x",
    competencia: "2026-07-01",
    versao: 1,
    estado: "gerada",
    destino: null,
    enviada_em: null,
    erro: null,
    retrato: RETRATO,
  };

  it("sem e-mail configurado, a tela manda ela baixar", () => {
    expect(rotuloEstado(base, false)).toContain("baixe e encaminhe");
  });

  it("com e-mail, diz que está esperando o envio", () => {
    expect(rotuloEstado(base, true)).toContain("aguardando envio");
  });

  it("a falha aparece com o motivo, não como um genérico", () => {
    const r = rotuloEstado({ ...base, estado: "falhou", erro: "caixa cheia" }, true);
    expect(r).toContain("caixa cheia");
  });

  it("o nome do arquivo carrega a versão só quando há mais de uma", () => {
    expect(nomeDoArquivo("2026-07", 1)).toBe("sessoes-2026-07.csv");
    expect(nomeDoArquivo("2026-07", 2)).toBe("sessoes-2026-07-v2.csv");
  });

  it("o mês a fechar é sempre o anterior, atravessando o ano", () => {
    expect(mesAFechar("2026-08-31")).toBe("2026-07");
    expect(mesAFechar("2026-01-05")).toBe("2025-12");
    expect(() => mesAFechar("ontem")).toThrow();
  });

  it("a competência vira o primeiro dia, que é o que o banco espera", () => {
    expect(primeiroDia("2026-07")).toBe("2026-07-01");
    expect(() => primeiroDia("2026-13")).toThrow();
  });

  it("o mês tem nome em português", () => {
    expect(nomeDoMes("2026-03")).toBe("março de 2026");
  });

  it("o tipo desconhecido volta cru em vez de sumir", () => {
    expect(rotuloTipo("sessao")).toBe("atendimentos");
    expect(rotuloTipo("inventado")).toBe("inventado");
  });
});
