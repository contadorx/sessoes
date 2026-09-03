import { describe, it, expect } from "vitest";
import {
  PISO_POR_RECIBO,
  prazoDoAno,
  diasEntre,
  faseDoPrazo,
  fraseDoPrazo,
  pisoDaMulta,
  frasePisoDaMulta,
  lerPainel,
  fraseDasFaltas,
  fraseSemCpf,
  rotuloEstado,
  diaBr,
  type PainelBruto,
  fraseDoRegime,
  valorParaCsv,
  soDigitos,
  cpfValidoParaArquivo,
  linhaCsv,
  montarArquivo,
  fraseDoArquivo,
  diasParaDesfazer,
  fraseDaJanela,
  fraseDmed,
  fraseNfse,
} from "@/lib/receitasaude";
import { formatar } from "@/lib/dinheiro";

/**
 * Os anos aqui são os mesmos da suíte SQL `0038_receita_saude.sql`: 2025, 2026
 * e o bissexto de 2028. Se as duas contas divergirem, uma das duas falha.
 */

const BRUTO: PainelBruto = {
  ano: 2026,
  ligado: true,
  prazo: "2027-02-28",
  dias_ate_o_prazo: 181,
  pendentes: { n: 4, valor: "800.00" },
  emitidos: { n: 10, valor: "2000.00" },
  dispensados: { n: 1, valor: "300.00" },
  vencidos: { n: 0, valor: "0" },
  divergentes: 0,
  sem_cpf: 2,
  piso_multa: 400,
  faltas_de_fora: { n: 2, valor: "200.00" },
  por_mes: [
    { mes: "2026-07", pendentes: 2, emitidos: 5, vencidos: 0, valor: "1400.00" },
    { mes: "2026-08", pendentes: 2, emitidos: 5, vencidos: 0, valor: "1700.00" },
  ],
};

describe("o prazo", () => {
  it("é o último dia de fevereiro do ano seguinte", () => {
    expect(prazoDoAno(2025)).toBe("2026-02-28");
    expect(prazoDoAno(2026)).toBe("2027-02-28");
  });

  it("respeita o ano bissexto — 2028 fecha em 29/02", () => {
    expect(prazoDoAno(2027)).toBe("2028-02-29");
    expect(prazoDoAno(2031)).toBe("2032-02-29");
  });

  it("não depende do fuso de quem abriu a tela", () => {
    // Data civil não tem fuso: o resultado é o mesmo string, sempre.
    const antes = process.env.TZ;
    try {
      process.env.TZ = "Pacific/Kiritimati";
      expect(prazoDoAno(2027)).toBe("2028-02-29");
      process.env.TZ = "Pacific/Midway";
      expect(prazoDoAno(2027)).toBe("2028-02-29");
    } finally {
      process.env.TZ = antes;
    }
  });

  it("recusa ano fora de faixa em vez de responder errado", () => {
    expect(() => prazoDoAno(1999)).toThrow();
    expect(() => prazoDoAno(2101)).toThrow();
    expect(() => prazoDoAno(2026.5)).toThrow();
  });

  it("conta os dias que faltam, e o sinal quando já passou", () => {
    expect(diasEntre("2026-08-31", "2027-02-28")).toBe(181);
    expect(diasEntre("2027-03-01", "2027-02-28")).toBe(-1);
    expect(diasEntre("2026-08-31", "2026-08-31")).toBe(0);
    expect(() => diasEntre("ontem", "2026-08-31")).toThrow();
  });
});

describe("a fase do alarme", () => {
  it("fica quieta o ano inteiro quando ainda dá tempo", () => {
    expect(faseDoPrazo(181, 4)).toBe("tranquilo");
    expect(faseDoPrazo(61, 4)).toBe("tranquilo");
  });

  it("muda de cor a partir de dois meses do prazo", () => {
    expect(faseDoPrazo(60, 4)).toBe("atencao");
    expect(faseDoPrazo(16, 4)).toBe("atencao");
  });

  it("grita na última quinzena", () => {
    expect(faseDoPrazo(15, 1)).toBe("urgente");
    expect(faseDoPrazo(0, 1)).toBe("urgente");
  });

  it("não grita quando não há nada pendente — alarme que grita à toa vira paisagem", () => {
    expect(faseDoPrazo(3, 0)).toBe("tranquilo");
    expect(faseDoPrazo(60, 0)).toBe("tranquilo");
  });

  it("fecha quando o prazo passou", () => {
    expect(faseDoPrazo(-1, 4)).toBe("fechado");
    expect(faseDoPrazo(-1, 0)).toBe("fechado");
  });
});

describe("a frase do prazo", () => {
  it("diz quantos faltam e até quando", () => {
    const f = fraseDoPrazo(181, 4, "2027-02-28");
    expect(f).toContain("4 recibos a emitir");
    expect(f).toContain("28/02/2027");
    expect(f).toContain("181 dias");
  });

  it("trata hoje e amanhã sem contar dias", () => {
    expect(fraseDoPrazo(0, 1, "2027-02-28")).toContain("o prazo é hoje");
    expect(fraseDoPrazo(1, 1, "2027-02-28")).toContain("o prazo é amanhã");
  });

  it("nunca diz que está tudo em dia havendo pendência", () => {
    const f = fraseDoPrazo(-1, 3, "2026-02-28");
    expect(f).toContain("já não é aceita");
    expect(f).not.toContain("Nada");
  });

  it("com o prazo fechado e nada pendente, diz isso e só isso", () => {
    expect(fraseDoPrazo(-1, 0, "2026-02-28")).toContain("Nada ficou pendente");
  });

  it("não ameaça em lugar nenhum", () => {
    const todas = [
      fraseDoPrazo(181, 4, "2027-02-28"),
      fraseDoPrazo(0, 1, "2027-02-28"),
      fraseDoPrazo(-1, 3, "2026-02-28"),
      fraseDoPrazo(90, 0, "2027-02-28"),
    ].join(" ");
    expect(todas).not.toMatch(/você vai ser multad|será multad|processo|dívida ativa/i);
  });
});

describe("o piso da multa", () => {
  it("é R$ 100 por recibo, pendente ou vencido", () => {
    expect(PISO_POR_RECIBO).toBe(10000);
    expect(pisoDaMulta(4)).toBe(40000);
    expect(pisoDaMulta(4, 2)).toBe(60000);
    expect(pisoDaMulta(0)).toBe(0);
  });

  it("bate com o número que o banco devolve", () => {
    expect(pisoDaMulta(BRUTO.pendentes.n, BRUTO.vencidos.n)).toBe(BRUTO.piso_multa * 100);
  });

  it("a frase diz que é piso, com a regra citada — nunca uma estimativa", () => {
    const f = frasePisoDaMulta(4);
    expect(f).toContain("R$ 100 por mês-calendário ou fração");
    expect(f).toContain("no mínimo");
    expect(f).toContain(formatar(40000));
    expect(f).not.toMatch(/estimativa|você deve|total da multa/i);
  });

  it("cala quando não há nada pendente", () => {
    expect(frasePisoDaMulta(0)).toBe("");
  });

  it("recusa contagem inválida", () => {
    expect(() => pisoDaMulta(-1)).toThrow();
    expect(() => pisoDaMulta(1.5)).toThrow();
  });
});

describe("o painel", () => {
  it("traduz para centavos e calcula a fase", () => {
    const p = lerPainel(BRUTO);
    expect(p.pendentes.centavos).toBe(80000);
    expect(p.emitidos.centavos).toBe(200000);
    expect(p.fase).toBe("tranquilo");
    expect(p.pisoMulta).toBe(40000);
  });

  it("não traz campo de estimativa de multa", () => {
    const p = lerPainel(BRUTO);
    expect(Object.keys(p)).not.toContain("multaEstimada");
    expect(Object.keys(p)).not.toContain("multaTotal");
    expect(Object.keys(BRUTO)).not.toContain("multa_estimada");
  });

  it("as faltas aparecem, com o motivo de estarem fora", () => {
    const f = fraseDasFaltas(lerPainel(BRUTO));
    expect(f).toContain(formatar(20000));
    expect(f).toContain("não é atendimento prestado");
    expect(f).toContain("contador");
  });

  it("sem faltas, não inventa frase", () => {
    const p = lerPainel({ ...BRUTO, faltas_de_fora: { n: 0, valor: "0" } });
    expect(fraseDasFaltas(p)).toBe("");
  });

  it("avisa do CPF que falta — é o que trava a digitação", () => {
    const f = fraseSemCpf(lerPainel(BRUTO));
    expect(f).toContain("2 pessoas estão sem CPF");
    expect(f).toContain("exige o CPF");
  });

  it("com um só, fala no singular", () => {
    const p = lerPainel({ ...BRUTO, sem_cpf: 1 });
    expect(fraseSemCpf(p)).toContain("1 pessoa está sem CPF");
  });

  it("cala quando todo mundo tem CPF", () => {
    const p = lerPainel({ ...BRUTO, sem_cpf: 0 });
    expect(fraseSemCpf(p)).toBe("");
  });

  it("o mês a mês chega em centavos", () => {
    const p = lerPainel(BRUTO);
    expect(p.porMes).toHaveLength(2);
    expect(p.porMes[1]).toEqual({
      mes: "2026-08",
      pendentes: 2,
      emitidos: 5,
      vencidos: 0,
      centavos: 170000,
    });
  });

  it("com o prazo vencido e pendências, a fase fecha", () => {
    const p = lerPainel({
      ...BRUTO,
      ano: 2024,
      prazo: "2025-02-28",
      dias_ate_o_prazo: -549,
      pendentes: { n: 0, valor: "0" },
      vencidos: { n: 3, valor: "600.00" },
    });
    expect(p.fase).toBe("fechado");
    expect(p.pisoMulta).toBe(30000);
  });
});

describe("os rótulos", () => {
  it("falam a língua da tela, não a do banco", () => {
    expect(rotuloEstado("pendente")).toBe("a emitir");
    expect(rotuloEstado("vencido")).toBe("fora do prazo");
    expect(rotuloEstado("inventado")).toBe("inventado");
  });

  it("a data vira brasileira sem passar por Date", () => {
    expect(diaBr("2027-02-28")).toBe("28/02/2027");
    expect(diaBr("2028-02-29")).toBe("29/02/2028");
  });
});

// ==================================================== 0053 · regime e arquivo

describe("o regime fiscal", () => {
  it("diz que PJ não emite Receita Saúde, e diz o que emite no lugar", () => {
    expect(fraseDoRegime("pj")).toContain("NFS-e");
    expect(fraseDoRegime("pj")).not.toMatch(/Receita Saúde é obrigatório/);
    expect(fraseDoRegime("pf")).toContain("obrigatório");
  });
});

describe("o valor no arquivo", () => {
  it("usa vírgula decimal — com ponto, 200.00 vira duzentos mil na Receita", () => {
    expect(valorParaCsv(20000)).toBe("200,00");
    expect(valorParaCsv(18050)).toBe("180,50");
    expect(valorParaCsv(5)).toBe("0,05");
    expect(valorParaCsv(0)).toBe("0,00");
  });

  it("não põe separador de milhar", () => {
    expect(valorParaCsv(123456789)).toBe("1234567,89");
    expect(valorParaCsv(123456789)).not.toContain(".");
  });

  it("recusa centavo quebrado ou negativo em vez de arredondar em silêncio", () => {
    expect(() => valorParaCsv(10.5)).toThrow();
    expect(() => valorParaCsv(-100)).toThrow();
  });
});

describe("o CPF", () => {
  it("entra só com dígitos", () => {
    expect(soDigitos("390.533.447-05")).toBe("39053344705");
    expect(soDigitos(null)).toBe("");
  });

  it("recusa o que não tem onze dígitos", () => {
    expect(cpfValidoParaArquivo("390.533.447-05")).toBe(true);
    expect(cpfValidoParaArquivo("3905334470")).toBe(false);
    expect(cpfValidoParaArquivo(null)).toBe(false);
  });

  /**
   * O comprimento não bastava. Este CPF vai para a coluna 15 de toda linha, e o
   * e-CAC recusa o arquivo **inteiro** no "Analisar Arquivo" — sem dizer qual
   * linha. Um dígito trocado só aparecia em fevereiro, no prazo.
   */
  it("recusa onze dígitos com o dígito verificador errado", () => {
    expect(cpfValidoParaArquivo("390.533.447-06")).toBe(false);
    expect(cpfValidoParaArquivo("11111111111")).toBe(false);
  });
});

describe("a linha do arquivo", () => {
  const l = { pagoEm: "2026-03-04", centavos: 20000, cpf: "390.533.447-05" };
  const linha = linhaCsv(l, "529.982.247-25", "06/123456");
  const c = linha.split(";");

  it("tem dezesseis campos separados por ponto e vírgula", () => {
    expect(c).toHaveLength(16);
  });

  it("põe os fixos nas posições do manual — os mesmos valores do banco", () => {
    expect(c[0]).toBe("04/03/2026");
    expect(c[1]).toBe("R01.001.001");
    expect(c[2]).toBe("255");
    expect(c[3]).toBe("200,00");
    expect(c[6]).toBe("PF");
    expect(c[7]).toBe("39053344705");
    expect(c[8]).toBe("39053344705");
    expect(c[13]).toBe("S");
    expect(c[14]).toBe("52998224725");
    expect(c[15]).toBe("06/123456");
  });

  it("deixa vazio o que o manual manda deixar vazio", () => {
    for (const i of [4, 5, 9, 10, 11, 12]) expect(c[i]).toBe("");
  });

  it("não tem onde caber nome de paciente: a descrição sai vazia", () => {
    // A linha inteira não pode ter mais letra do que os fixos: PF, S,
    // R01.001.001 e o CRP. Qualquer palavra a mais é dado que vazou.
    const letras = linha.replace(/[0-9;/,.]/g, "");
    expect(letras).toBe("RPFS");
    expect(c[5]).toBe("");
  });

  it("recusa linha sem CPF em vez de emitir uma linha quebrada", () => {
    expect(() => linhaCsv({ ...l, cpf: null }, "52998224725", "06/123456")).toThrow();
  });

  it("recusa arquivo sem o CPF do profissional", () => {
    expect(() => linhaCsv(l, "", "06/123456")).toThrow();
  });
});

describe("o arquivo inteiro", () => {
  const brutas = [
    { pagoEm: "2026-03-04", centavos: 20000, cpf: "39053344705" },
    { pagoEm: "2026-03-05", centavos: 18000, cpf: null },
  ];

  it("conta o que olhou, não só o que coube — os mesmos números da suíte 0053", () => {
    const a = montarArquivo(2026, brutas, "52998224725", "06/123456");
    expect(a.linhas).toBe(1);
    expect(a.consideradas).toBe(2);
    expect(a.semCpf).toBe(1);
    expect(a.limiteAtingido).toBe(false);
    expect(a.texto.split("\n")).toHaveLength(1);
  });

  it("não tem linha de cabeçalho", () => {
    const a = montarArquivo(2026, brutas, "52998224725", "06/123456");
    expect(a.texto.split("\n")[0].split(";")[1]).toBe("R01.001.001");
  });

  it("encosta no limite de mil e avisa, em vez de cortar em silêncio", () => {
    const muitas = Array.from({ length: 1002 }, () => ({
      pagoEm: "2026-03-04",
      centavos: 10000,
      cpf: "39053344705",
    }));
    const a = montarArquivo(2026, muitas, "52998224725", "06/123456");
    expect(a.linhas).toBe(1000);
    expect(a.consideradas).toBe(1002);
    expect(a.limiteAtingido).toBe(true);
    expect(fraseDoArquivo(a)).toContain("1000");
  });

  it("recusa PJ e diz o caminho de lá", () => {
    expect(() => montarArquivo(2026, brutas, "52998224725", "06/123456", "pj")).toThrow(
      /NFS-e/,
    );
  });

  it("a frase diz quantas ficaram de fora e por quê", () => {
    const f = fraseDoArquivo(montarArquivo(2026, brutas, "52998224725", "06/123456"));
    expect(f).toContain("1 ficou de fora");
    expect(f).toContain("CPF");
  });
});

describe("a janela de dez dias", () => {
  it("conta da emissão e devolve os mesmos números do banco", () => {
    expect(diasParaDesfazer("2026-03-04", "2026-03-04")).toBe(10);
    expect(diasParaDesfazer("2026-03-04", "2026-03-08")).toBe(6);
    expect(diasParaDesfazer("2026-03-04", "2026-03-14")).toBe(0);
  });

  it("fecha em zero, nunca em negativo", () => {
    expect(diasParaDesfazer("2026-03-04", "2026-04-30")).toBe(0);
  });

  it("não existe para o que não foi emitido", () => {
    expect(diasParaDesfazer(null, "2026-03-04")).toBeNull();
    expect(fraseDaJanela(null)).toBe("");
  });

  it("a frase muda quando fecha, e não promete o que não dá mais", () => {
    expect(fraseDaJanela(0)).toContain("fechou");
    expect(fraseDaJanela(1)).toContain("Último dia");
    expect(fraseDaJanela(7)).toContain("7 dias");
  });
});

describe("as obrigações da PJ", () => {
  it("não inventa o dia da DMED, porque fevereiro tem feriado móvel", () => {
    const f = fraseDmed(2026);
    expect(f).toContain("último dia útil de fevereiro de 2027");
    expect(f).toContain("contador");
    expect(f).not.toMatch(/2[0-9]\/02/);
  });

  it("conta os dias até a NFS-e do IBS/CBS e vira o tempo verbal depois", () => {
    expect(fraseNfse("2026-09-02")).toContain("faltam 29 dias");
    expect(fraseNfse("2026-10-01")).toContain("hoje");
    expect(fraseNfse("2026-11-01")).toContain("desde");
  });
});
