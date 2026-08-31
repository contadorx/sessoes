import { describe, it, expect } from "vitest";
import {
  lerColagem,
  lerDiaDaSemana,
  lerHora,
  lerValor,
  comHorario,
} from "./importacao";

/**
 * O teste desta peça é o teste do critério de pronto da B14: uma psicóloga que
 * nunca viu o sistema chega sozinha à primeira vaga preenchida em meia hora.
 *
 * Por isso quase tudo aqui é sobre **entrada imperfeita**. A colagem vai vir de
 * uma planilha, de uma caderneta ou do WhatsApp, com acento faltando, "R$" no
 * meio, tabulação em vez de ponto e vírgula e uma linha em branco no fim.
 * Recusar isso é recusar a cliente.
 */

describe("o dia da semana, como as pessoas escrevem", () => {
  it.each([
    ["terça", 2],
    ["TERÇA", 2],
    ["terca", 2],
    ["terça-feira", 2],
    ["ter", 2],
    ["segunda", 1],
    ["seg", 1],
    ["domingo", 0],
    ["sábado", 6],
    ["sabado", 6],
    ["quinta-feira", 4],
    ["3", 3],
    ["0", 0],
  ])("%s → %i", (bruto, esperado) => {
    expect(lerDiaDaSemana(bruto)).toBe(esperado);
  });

  it("o que não é dia devolve null em vez de chutar", () => {
    expect(lerDiaDaSemana("qualquer")).toBeNull();
    expect(lerDiaDaSemana("7")).toBeNull();
    expect(lerDiaDaSemana("")).toBeNull();
  });
});

describe("a hora, como as pessoas escrevem", () => {
  it.each([
    ["15", "15:00"],
    ["15h", "15:00"],
    ["15:00", "15:00"],
    ["15h30", "15:30"],
    ["15:30", "15:30"],
    ["9h", "09:00"],
    ["9h5", "09:05"],
    ["08.30", "08:30"],
    [" 14h ", "14:00"],
  ])("%s → %s", (bruto, esperado) => {
    expect(lerHora(bruto)).toBe(esperado);
  });

  it("hora impossível não vira hora possível", () => {
    expect(lerHora("25")).toBeNull();
    expect(lerHora("14h70")).toBeNull();
    expect(lerHora("manhã")).toBeNull();
  });
});

describe("o valor, como as pessoas escrevem", () => {
  it.each([
    ["200", 20_000],
    ["200,00", 20_000],
    ["R$ 200,00", 20_000],
    ["r$200", 20_000],
    ["1.200,50", 120_050],
    ["1200.50", 120_050],
    ["180,5", 18_050],
  ])("%s → %i centavos", (bruto, esperado) => {
    expect(lerValor(bruto)).toBe(esperado);
  });

  it("o que não é número não vira zero silencioso", () => {
    expect(lerValor("combinar")).toBeNull();
    expect(lerValor("0")).toBeNull();
    expect(lerValor("")).toBeNull();
  });
});

describe("a colagem inteira", () => {
  it("lê o formato completo", () => {
    const { pacientes, erros } = lerColagem(
      "Maria Fernanda Reis; 11 90000-0001; terça; 15h; 200",
    );
    expect(erros).toHaveLength(0);
    expect(pacientes[0]).toEqual({
      linha: 1,
      nome: "Maria Fernanda Reis",
      telefone: "5511900000001",
      diaSemana: 2,
      hora: "15:00",
      valorCentavos: 20_000,
    });
  });

  it("descobre o separador sozinha — planilha cola com tabulação", () => {
    const tab = lerColagem("Maria\t11900000001\tterça\t15h\t200");
    const virgula = lerColagem("Maria,11900000001,terça,15h,200");
    expect(tab.pacientes[0].hora).toBe("15:00");
    expect(virgula.pacientes[0].hora).toBe("15:00");
  });

  it("só o nome basta — o resto se preenche depois", () => {
    const { pacientes, erros } = lerColagem("Caio Nogueira");
    expect(erros).toHaveLength(0);
    expect(pacientes[0].nome).toBe("Caio Nogueira");
    expect(pacientes[0].telefone).toBeNull();
    expect(pacientes[0].diaSemana).toBeNull();
  });

  it("ignora linhas em branco e o cabeçalho da planilha", () => {
    const { pacientes, erros } = lerColagem(
      "nome; telefone; dia; hora; valor\n\nMaria; ; terça; 15h; 200\n\n",
    );
    expect(erros).toHaveLength(0);
    expect(pacientes).toHaveLength(1);
  });

  it("erra por linha, e não desiste da importação inteira", () => {
    const { pacientes, erros } = lerColagem(
      ["Maria; 11900000001; terça; 15h; 200", "; ; ; ;", "Caio; 123; segunda; 9h; 180"].join("\n"),
    );
    expect(pacientes).toHaveLength(1);
    expect(erros).toHaveLength(2);
    expect(erros[0]).toMatchObject({ linha: 2, motivo: "sem nome" });
    expect(erros[1].linha).toBe(3);
    expect(erros[1].motivo).toMatch(/telefone/);
  });

  it("o erro diz a linha e o motivo, não 'formato inválido'", () => {
    const { erros } = lerColagem("Maria; 11900000001; sexta-feira; manhã; 200");
    expect(erros[0].motivo).toContain("horário");
    expect(erros[0].motivo).toContain("manhã");
    expect(erros[0].linha).toBe(1);
  });

  it("dia sem hora não vira horário fixo pela metade", () => {
    const { pacientes, erros } = lerColagem("Maria; ; terça; ; 200");
    expect(pacientes).toHaveLength(0);
    expect(erros[0].motivo).toMatch(/dia E da hora/);
  });

  it("nome repetido na colagem é apontado, não duplicado", () => {
    const { pacientes, erros } = lerColagem("Maria; ; ; ;\nmaria; ; ; ;");
    expect(pacientes).toHaveLength(1);
    expect(erros[0].motivo).toMatch(/repetido/);
  });

  it("conta quantos viram horário fixo de verdade", () => {
    const leitura = lerColagem(
      ["Maria; ; terça; 15h; 200", "Caio", "João; ; segunda; 9h; 180"].join("\n"),
    );
    expect(leitura.pacientes).toHaveLength(3);
    expect(comHorario(leitura)).toBe(2);
  });

  it("colagem vazia não estoura", () => {
    expect(lerColagem("")).toEqual({ pacientes: [], erros: [] });
    expect(lerColagem("\n\n  \n")).toEqual({ pacientes: [], erros: [] });
  });
});
