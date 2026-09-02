import { describe, it, expect } from "vitest";
import {
  emMinutos,
  emHhmm,
  duracao,
  minutosDaFaixa,
  problemaNaSemana,
  semanaEmMinutos,
  lerCapacidade,
  protegido,
  fraseDaCapacidade,
  fraseDaSemana,
  porDia,
  semanaSugerida,
  eProtegido,
  DESTINOS,
  type Faixa,
  type CapacidadeBruta,
} from "@/lib/capacidade";
import * as modulo from "@/lib/capacidade";

/**
 * Os números aqui são **os mesmos da suíte SQL `0055_capacidade_declarada.sql`**:
 * a semana de 09–12 atendimento, 12–13 registro e 13–14 descanso nos sete dias,
 * que dá 180 + 60 + 60 minutos por dia. Se as duas contas divergirem, uma das
 * duas falha.
 *
 * E o teste que decide o arquivo é o do grupo "a fronteira": nenhuma função
 * deste módulo pode devolver, calcular ou nomear "hora ociosa".
 */

const SEMANA_DA_SUITE: Faixa[] = [0, 1, 2, 3, 4, 5, 6].flatMap((d) => [
  { dia: d, inicio: "09:00", fim: "12:00", destino: "atendimento" as const },
  { dia: d, inicio: "12:00", fim: "13:00", destino: "registro" as const },
  { dia: d, inicio: "13:00", fim: "14:00", destino: "descanso" as const },
]);

describe("os minutos", () => {
  it("lê e escreve hora", () => {
    expect(emMinutos("09:00")).toBe(540);
    expect(emMinutos("9:30")).toBe(570);
    expect(emHhmm(540)).toBe("09:00");
    expect(emHhmm(1425)).toBe("23:45");
  });

  it("recusa hora inválida em vez de devolver NaN em silêncio", () => {
    expect(() => emMinutos("nove")).toThrow();
    expect(() => emMinutos("25:00")).toThrow();
    expect(() => emMinutos("09:99")).toThrow();
  });

  it("escreve a duração como quem olha a própria semana, não como planilha", () => {
    expect(duracao(180)).toBe("3h");
    expect(duracao(210)).toBe("3h30");
    expect(duracao(45)).toBe("45min");
    expect(duracao(0)).toBe("0");
    expect(duracao(180)).not.toContain(".");
  });

  it("mede a faixa", () => {
    expect(minutosDaFaixa({ inicio: "09:00", fim: "12:00" })).toBe(180);
  });
});

describe("a conferência da semana", () => {
  it("aceita a semana da suíte", () => {
    expect(problemaNaSemana(SEMANA_DA_SUITE)).toBeNull();
  });

  it("recusa faixa que termina antes de começar", () => {
    const p = problemaNaSemana([{ dia: 1, inicio: "14:00", fim: "09:00", destino: "atendimento" }]);
    expect(p).toContain("termina antes de começar");
  });

  it("recusa sobreposição, dizendo quais faixas — a invariante 4 da 0055", () => {
    const p = problemaNaSemana([
      { dia: 1, inicio: "09:00", fim: "12:00", destino: "atendimento" },
      { dia: 1, inicio: "11:00", fim: "13:00", destino: "registro" },
    ]);
    expect(p).toContain("09:00");
    expect(p).toContain("11:00");
    expect(p).toContain("infla a capacidade");
  });

  it("deixa passar faixas que só encostam — encostar não é sobrepor", () => {
    expect(
      problemaNaSemana([
        { dia: 1, inicio: "09:00", fim: "12:00", destino: "atendimento" },
        { dia: 1, inicio: "12:00", fim: "13:00", destino: "registro" },
      ]),
    ).toBeNull();
  });

  it("deixa passar o mesmo horário em dias diferentes", () => {
    expect(
      problemaNaSemana([
        { dia: 1, inicio: "09:00", fim: "12:00", destino: "atendimento" },
        { dia: 2, inicio: "09:00", fim: "12:00", destino: "atendimento" },
      ]),
    ).toBeNull();
  });
});

describe("a soma da semana", () => {
  it("bate com a suíte SQL: 180 + 60 + 60 por dia, sete dias", () => {
    const s = semanaEmMinutos(SEMANA_DA_SUITE);
    expect(s.vendavel).toBe(180 * 7);
    expect(s.registro).toBe(60 * 7);
    expect(s.descanso).toBe(60 * 7);
    expect(s.declarado).toBe(300 * 7);
  });

  it("vendável e declarado nunca são a mesma coisa quando há hora protegida", () => {
    const s = semanaEmMinutos(SEMANA_DA_SUITE);
    expect(s.vendavel).not.toBe(s.declarado);
  });

  it("sem faixa, tudo zero e sem exceção", () => {
    expect(semanaEmMinutos([])).toEqual({ vendavel: 0, registro: 0, descanso: 0, declarado: 0 });
  });
});

describe("a capacidade do período", () => {
  const BRUTA: CapacidadeBruta = {
    de: "2026-09-02",
    ate: "2026-09-08",
    dias: 7,
    sem_janela: false,
    vendavel_min: 180 * 7,
    registro_min: 60 * 7,
    descanso_min: 60 * 7,
    declarado_min: 300 * 7,
    fora: { ferias: 0, feriado: 0, bloqueio: 0, total: 0 },
  };

  it("traduz sem mexer nos números", () => {
    const c = lerCapacidade(BRUTA);
    expect(c.vendavel).toBe(1260);
    expect(c.declarado).toBe(2100);
    expect(protegido(c)).toBe(840);
  });

  it("estoura quando o banco devolve soma incoerente, em vez de mostrar o errado", () => {
    expect(() => lerCapacidade({ ...BRUTA, declarado_min: 999 })).toThrow(/incoerente/);
  });

  it("a frase diz o vendável e nomeia o protegido — nunca chama de vago", () => {
    const f = fraseDaCapacidade(lerCapacidade(BRUTA));
    expect(f).toContain("21h de atendimento");
    expect(f).toContain("14h");
    expect(f).toContain("não hora vaga");
  });

  it("a frase separa cada motivo de ausência", () => {
    const f = fraseDaCapacidade(
      lerCapacidade({
        ...BRUTA,
        vendavel_min: 180 * 4,
        registro_min: 60 * 4,
        descanso_min: 60 * 4,
        declarado_min: 300 * 4,
        fora: { ferias: 300 * 2, feriado: 300, bloqueio: 0, total: 300 * 3 },
      }),
    );
    expect(f).toContain("férias");
    expect(f).toContain("feriado");
    expect(f).not.toContain("bloqueada");
  });

  it("quem não declarou ouve isso, e não um zero acusador", () => {
    const f = fraseDaCapacidade(
      lerCapacidade({
        ...BRUTA,
        sem_janela: true,
        vendavel_min: 0,
        registro_min: 0,
        descanso_min: 0,
        declarado_min: 0,
      }),
    );
    expect(f).toContain("ainda não declarou");
    expect(f).toContain("não significa que você não trabalhou");
    expect(f).not.toContain("0%");
  });
});

describe("a fronteira do doc 11", () => {
  it("registro e descanso são protegidos, atendimento não", () => {
    expect(eProtegido("registro")).toBe(true);
    expect(eProtegido("descanso")).toBe(true);
    expect(eProtegido("atendimento")).toBe(false);
  });

  it("nenhuma frase do módulo chama hora protegida de ociosa, vaga ou perdida", () => {
    const BRUTA: CapacidadeBruta = {
      de: "2026-09-02", ate: "2026-09-08", dias: 7, sem_janela: false,
      vendavel_min: 180 * 7, registro_min: 60 * 7, descanso_min: 60 * 7,
      declarado_min: 300 * 7,
      fora: { ferias: 60, feriado: 60, bloqueio: 60, total: 180 },
    };
    const tudo = [
      fraseDaCapacidade(lerCapacidade(BRUTA)),
      fraseDaSemana(SEMANA_DA_SUITE),
      ...DESTINOS.map((d) => `${d.rotulo} ${d.ajuda}`),
    ].join(" ");

    expect(tudo).not.toMatch(/ocios|desperdi|perdid|subutiliz|capacidade não usada/i);

    // "hora vaga" pode aparecer — mas só negada. O que a fronteira proíbe é
    // AFIRMAR que hora protegida é hora vaga; dizer que ela não é, é o ponto.
    for (const m of tudo.matchAll(/hora vaga/gi)) {
      const antes = tudo.slice(Math.max(0, (m.index ?? 0) - 24), m.index);
      expect(antes).toMatch(/\b(não|nunca|nem)\b/i);
    }
  });

  it("nenhuma frase sugere preencher a agenda ou procurar paciente", () => {
    const tudo = [
      fraseDaSemana(SEMANA_DA_SUITE),
      ...DESTINOS.map((d) => d.ajuda),
    ].join(" ");
    expect(tudo).not.toMatch(/preench|ofereç|oferec|divulg|convid|captar|prospect/i);
  });

  it("o módulo não exporta nada com nome de ócio nem de vaga", () => {
    // Guarda contra a função que alguém vai querer escrever no dia em que o
    // cockpit do P5 pedir "um número só". O import de estrela é de propósito:
    // ele enxerga o que for acrescentado depois, sem ninguém atualizar a lista.
    for (const nome of Object.keys(modulo)) {
      expect(nome).not.toMatch(/ocios|vaga|vago|livre|desperdic/i);
    }
    expect(Object.keys(modulo).length).toBeGreaterThan(10);
  });
});

describe("a semana sugerida", () => {
  it("é válida e cobre os dias úteis", () => {
    const s = semanaSugerida();
    expect(problemaNaSemana(s)).toBeNull();
    expect(porDia(s).map((g) => g.dia)).toEqual([1, 2, 3, 4, 5]);
  });

  it("já vem com registro e descanso — o padrão é onde se ensina que isso é trabalho", () => {
    const s = semanaEmMinutos(semanaSugerida());
    expect(s.registro).toBeGreaterThan(0);
    expect(s.descanso).toBeGreaterThan(0);
    expect(s.vendavel).toBe(7 * 60 * 5);
  });

  it("agrupa por dia em ordem de horário", () => {
    const g = porDia(semanaSugerida())[0];
    expect(g.faixas.map((f) => f.inicio)).toEqual(["09:00", "12:00", "13:00", "17:00"]);
    expect(g.nome).toBeTruthy();
  });
});
