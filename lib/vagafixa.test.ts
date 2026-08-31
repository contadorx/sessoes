import { describe, it, expect } from "vitest";
import {
  horarioSemanal,
  estadoDaVaga,
  rotuloDaVaga,
  proximoPasso,
  rotuloMotivo,
  quantosNaFrente,
  MOTIVOS,
  type VagaLinha,
} from "@/lib/vagafixa";

const BASE: VagaLinha = {
  id: "v",
  dia_semana: 2,
  hora: "15:00",
  duracao_min: 50,
  motivo: "alta",
  valor_anterior: "200.00",
  aberta_em: "2026-08-01T12:00:00Z",
  fechada_em: null,
  fechada_por: null,
  novo_paciente: null,
  oferecida_a: null,
  ficou_com: null,
};

describe("o horário que se repete", () => {
  it("sai no plural — é um compromisso semanal, não uma hora", () => {
    expect(horarioSemanal(2, "15:00")).toBe("às terças, 15h");
    expect(horarioSemanal(1, "09:30")).toBe("às segundas, 9h30");
  });

  it("um dia que já termina em s não ganha outro", () => {
    // "sábado" → "sábados"; e nada de "sábadoss" se algum dia vier no plural.
    expect(horarioSemanal(6, "10:00")).toBe("às sábados, 10h");
  });

  it("dia inválido não quebra a tela", () => {
    expect(horarioSemanal(9, "10:00")).toContain("10h");
  });
});

describe("o estado da vaga", () => {
  it("aberta enquanto ninguém recebeu", () => {
    expect(estadoDaVaga(BASE)).toBe("aberta");
    expect(proximoPasso(BASE)).toContain("Oferecer");
  });

  it("oferecida enquanto alguém tem a oferta viva", () => {
    const v = { ...BASE, oferecida_a: "Dora" };
    expect(estadoDaVaga(v)).toBe("oferecida");
    expect(rotuloDaVaga(v)).toContain("Dora");
    expect(rotuloDaVaga(v)).toContain("próxima da fila");
    expect(proximoPasso(v)).toBe("");
  });

  it("preenchida diz que ainda falta o combinado — e é a frase que importa", () => {
    // Sem isso ela acha que está tudo pronto, e a pessoa fica com um horário
    // sem valor, sem política de falta e sem contrato.
    const v = {
      ...BASE,
      fechada_em: "2026-08-10T12:00:00Z",
      fechada_por: "preenchida",
      novo_paciente: "p",
      ficou_com: "Eva",
    };
    expect(estadoDaVaga(v)).toBe("preenchida");
    expect(rotuloDaVaga(v)).toContain("Eva");
    expect(rotuloDaVaga(v)).toContain("valor");
    expect(rotuloDaVaga(v)).toContain("contrato");
    expect(proximoPasso(v)).toBe("Abrir o combinado");
  });

  it("sem takers explica e não culpa ninguém", () => {
    const v = { ...BASE, fechada_em: "x", fechada_por: "sem_takers" };
    expect(estadoDaVaga(v)).toBe("sem_takers");
    expect(rotuloDaVaga(v)).toContain("fila de entrada");
    expect(proximoPasso(v)).toBe("");
  });

  it("fechada ganha de oferecida — o que valeu, valeu", () => {
    const v = { ...BASE, oferecida_a: "Dora", fechada_em: "x", fechada_por: "preenchida", ficou_com: "Eva" };
    expect(estadoDaVaga(v)).toBe("preenchida");
  });

  it("nenhuma frase manda ela correr", () => {
    for (const f of [
      BASE,
      { ...BASE, oferecida_a: "Dora" },
      { ...BASE, fechada_em: "x", fechada_por: "preenchida", ficou_com: "Eva" },
      { ...BASE, fechada_em: "x", fechada_por: "sem_takers" },
      { ...BASE, fechada_em: "x", fechada_por: "cancelada" },
    ]) {
      const t = rotuloDaVaga(f).toLowerCase();
      for (const p of ["urgente", "perdendo", "prejuízo", "!", "rápido"]) {
        expect(t).not.toContain(p);
      }
    }
  });
});

describe("os motivos", () => {
  it("são quatro, e alta e abandono estão entre eles", () => {
    expect(MOTIVOS).toHaveLength(4);
    expect(rotuloMotivo("alta")).toBe("alta");
    expect(rotuloMotivo("abandono")).toBe("abandono");
  });

  it("motivo desconhecido aparece como veio", () => {
    expect(rotuloMotivo("inventado")).toBe("inventado");
  });
});

describe("quantos a cascata ainda alcança", () => {
  it("conta só quem está elegível", () => {
    const lista = [
      { paciente_id: "a", nome: "A", elegivel: true, motivo: "na fila de entrada", ordem: 1 },
      { paciente_id: "b", nome: "B", elegivel: false, motivo: "fora da janela", ordem: 2 },
      { paciente_id: "c", nome: "C", elegivel: true, motivo: "na fila de entrada", ordem: 3 },
    ];
    expect(quantosNaFrente(lista)).toBe(2);
  });

  it("fila vazia é zero, não NaN", () => {
    expect(quantosNaFrente([])).toBe(0);
  });
});
