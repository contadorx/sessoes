import { describe, it, expect } from "vitest";
import {
  rotuloCamada,
  explicaCamada,
  blocos,
  fraseDosBlocos,
  fraseSemEvolucao,
  rotuloModalidade,
  prazoDeGuarda,
  somarAnos,
  fraseDoPrazo,
  diaBr,
  rotuloEncerramento,
  MODALIDADES,
  FREQUENCIAS,
  frequenciaNaLista,
  type RegistroDoPaciente,
} from "./registro";

const vazio: RegistroDoPaciente = {
  identificacao: { nome: "Maria Fernanda Reis", nascimento: "1990-04-12", documento: null, responsaveis: [] },
  demanda: null,
  encerramento: null,
  registro_id: null,
  sem_evolucao: [],
  evolucoes: [],
};

const reg = (p: Partial<RegistroDoPaciente> = {}): RegistroDoPaciente => ({ ...vazio, ...p });

// ============================================== as duas camadas do CFP

describe("as camadas, ditas por consequência", () => {
  it("a explicação da gaveta responde a pergunta que ela faz de verdade", () => {
    // A pergunta não é "o que é Registro Documental"; é "o paciente vai ver?".
    expect(explicaCamada("documental")).toMatch(/não sai na cópia/i);
    expect(explicaCamada("prontuario")).toMatch(/vai junto/i);
  });

  it("a camada do prontuário cita o direito de acesso, que é o motivo dela existir", () => {
    expect(explicaCamada("prontuario")).toMatch(/001\/2009/);
  });

  it("rótulos curtos", () => {
    expect(rotuloCamada("documental")).toBe("gaveta");
    expect(rotuloCamada("prontuario")).toBe("prontuário");
  });
});

// ================================================ os quatro blocos

describe("os quatro blocos do conteúdo mínimo", () => {
  it("são quatro, na ordem do Manual", () => {
    const b = blocos(vazio);
    expect(b.map((x) => x.n)).toEqual([1, 2, 3, 4]);
    expect(b[0].nome).toMatch(/Identificação/);
    expect(b[1].nome).toMatch(/demanda/);
    expect(b[2].nome).toMatch(/Evolução/);
    expect(b[3].nome).toMatch(/encerramento/);
  });

  it("a identificação já vem completa do cadastro — não se digita duas vezes", () => {
    expect(blocos(vazio)[0].completo).toBe(true);
    expect(blocos(vazio)[0].onde).toBe("cadastro");
  });

  it("registro em branco diz que está em branco", () => {
    const sem = reg({ identificacao: { nome: "", nascimento: null, documento: null, responsaveis: [] } });
    expect(fraseDosBlocos(sem)).toBe("O registro ainda está em branco.");
  });

  it("com identificação só, faltam três", () => {
    expect(fraseDosBlocos(vazio)).toBe("Falta os blocos 2, 3 e 4.");
  });

  it("um bloco só, no singular", () => {
    const quase = reg({
      demanda: { texto: "ansiedade", objetivos: null, frequencia: null, modalidade: "presencial", em: null },
      evolucoes: [
        { id: "1", sessao_id: "s", dia: "2026-08-01", texto: "x", camada: "prontuario", criado_em: "", editado_em: null },
      ],
    });
    expect(fraseDosBlocos(quase)).toBe("Falta o bloco 4.");
  });

  it("os quatro cheios", () => {
    const cheio = reg({
      demanda: { texto: "ansiedade", objetivos: "dormir", frequencia: "semanal", modalidade: "misto", em: null },
      evolucoes: [
        { id: "1", sessao_id: "s", dia: "2026-08-01", texto: "x", camada: "prontuario", criado_em: "", editado_em: null },
      ],
      encerramento: { em: "2026-08-30T12:00:00Z", tipo: "alta" },
    });
    expect(fraseDosBlocos(cheio)).toMatch(/estão preenchidos/);
  });

  it("a frase nunca cobra — diz o que falta e para por aí", () => {
    const f = [fraseDosBlocos(vazio), fraseDosBlocos(reg())].join(" ");
    expect(f).not.toMatch(/precisa|obrigat|deveria|pendente|urgente/i);
  });
});

describe("o buraco é anunciado, não silencioso", () => {
  it("sem horas em aberto, não fala nada", () => {
    expect(fraseSemEvolucao(vazio)).toBe("");
  });

  it("uma e várias", () => {
    expect(fraseSemEvolucao(reg({ sem_evolucao: [{ sessao_id: "a", dia: "2026-08-01" }] }))).toMatch(
      /Uma sessão aconteceu/,
    );
    expect(
      fraseSemEvolucao(
        reg({
          sem_evolucao: [
            { sessao_id: "a", dia: "2026-08-01" },
            { sessao_id: "b", dia: "2026-08-08" },
            { sessao_id: "c", dia: "2026-08-15" },
          ],
        }),
      ),
    ).toBe("3 sessões aconteceram e ainda não têm evolução escrita.");
  });
});

describe("modalidade — conteúdo mínimo desde a Res. 09/2024", () => {
  it("as três, e a ausência dita", () => {
    expect(MODALIDADES).toHaveLength(3);
    expect(rotuloModalidade("presencial")).toBe("presencial");
    expect(rotuloModalidade("remoto")).toBe("remoto");
    expect(rotuloModalidade("misto")).toBe("os dois");
    expect(rotuloModalidade(null)).toBe("não registrada");
  });
});

// ================================================ o prazo de guarda

describe("somarAnos", () => {
  it("soma simples", () => {
    expect(somarAnos("2026-09-01", 5)).toBe("2031-09-01");
    expect(somarAnos("2000-01-31", 23)).toBe("2023-01-31");
  });

  it("29 de fevereiro cai no dia 28 quando o ano de destino não é bissexto", () => {
    // O erro clássico aqui é o `Date` empurrar para 1º de março e o prazo
    // andar um dia. Num prontuário, um dia é um dia.
    expect(somarAnos("2024-02-29", 1)).toBe("2025-02-28");
    expect(somarAnos("2024-02-29", 4)).toBe("2028-02-29");
  });

  it("não muda o mês", () => {
    expect(somarAnos("2026-01-31", 1)).toBe("2027-01-31");
    expect(somarAnos("2026-03-31", 1)).toBe("2027-03-31");
  });
});

describe("prazoDeGuarda — a mesma conta do elegiveis_para_eliminacao", () => {
  it("adulto: conta do último registro", () => {
    const p = prazoDeGuarda("2026-09-01", "1986-04-12", 5);
    expect(p).toEqual({ guardarAte: "2031-09-01", motivo: "ultimo_registro" });
  });

  it("sem data de nascimento, só resta a regra geral", () => {
    const p = prazoDeGuarda("2026-09-01", null, 5);
    expect(p.motivo).toBe("ultimo_registro");
  });

  it("MENOR: a ficha de quem foi atendido aos 9 guarda até os 23, não até os 14", () => {
    // Atendida em 2026 com 9 anos (nascida em 2017).
    const p = prazoDeGuarda("2026-09-01", "2017-05-20", 5);
    expect(p.motivo).toBe("maioridade");
    expect(p.guardarAte).toBe("2040-05-20"); // 2017 + 18 + 5
    // E o ponto todo: o prazo do menor é MAIOR que o da regra geral.
    expect(p.guardarAte > "2031-09-01").toBe(true);
  });

  it("adolescente perto dos 18: ainda assim a maioridade manda", () => {
    const p = prazoDeGuarda("2026-09-01", "2009-01-10", 5);
    expect(p.motivo).toBe("maioridade");
    expect(p.guardarAte).toBe("2032-01-10");
  });

  it("quem já era adulto no último registro cai na regra geral, mesmo com nascimento", () => {
    const p = prazoDeGuarda("2026-09-01", "1990-04-12", 5);
    expect(p.motivo).toBe("ultimo_registro");
    expect(p.guardarAte).toBe("2031-09-01");
  });

  it("a retenção da conta estica as duas contas", () => {
    // Uma conta que adota a leitura mais dura do Manual (20 anos) guarda a
    // ficha da criança até ela ter 38.
    const p = prazoDeGuarda("2026-09-01", "2017-05-20", 20);
    expect(p.guardarAte).toBe("2055-05-20");
    expect(p.motivo).toBe("maioridade");
  });

  it("na fronteira exata, a regra geral não perde por empate", () => {
    // Nascida em 2003-09-01: maioridade + 5 = 2026-09-01, igual ao prazo do
    // último registro de 2021-09-01 + 5. Empate resolve pelo motivo geral.
    const p = prazoDeGuarda("2021-09-01", "2003-09-01", 5);
    expect(p.guardarAte).toBe("2026-09-01");
    expect(p.motivo).toBe("ultimo_registro");
  });
});

describe("fraseDoPrazo — prazo sem motivo não se obedece", () => {
  it("o do menor explica por que é mais longo", () => {
    const f = fraseDoPrazo({ guardarAte: "2040-05-20", motivo: "maioridade" });
    expect(f).toMatch(/20\/05\/2040/);
    expect(f).toMatch(/maioridade/);
    expect(f).toMatch(/antes dos 18/);
  });

  it("o geral diz de onde conta", () => {
    const f = fraseDoPrazo({ guardarAte: "2031-09-01", motivo: "ultimo_registro" });
    expect(f).toMatch(/01\/09\/2031/);
    expect(f).toMatch(/último registro/);
  });
});

describe("rótulos e datas", () => {
  it("diaBr", () => {
    expect(diaBr("2026-03-05")).toBe("05/03/2026");
  });
  it("os três encerramentos", () => {
    expect(rotuloEncerramento("alta")).toBe("alta");
    expect(rotuloEncerramento("abandono")).toBe("abandono");
    expect(rotuloEncerramento("encaminhamento")).toBe("encaminhamento");
  });
});

describe("a frequência virou seleção, com uma saída", () => {
  it("a lista tem as cinco comuns, e 'semanal' é a primeira", () => {
    // A ordem é a do que aparece mais, não a do intervalo: quem está
    // preenchendo quer achar "semanal" no primeiro olhar.
    expect(FREQUENCIAS[0]).toBe("semanal");
    expect(FREQUENCIAS).toHaveLength(5);
  });

  it("reconhece o que está na lista", () => {
    expect(frequenciaNaLista("semanal")).toBe(true);
    expect(frequenciaNaLista("quinzenal")).toBe(true);
  });

  it("e o que veio de antes, escrito à mão, não vira nada da lista", () => {
    // A ficha antiga podia ter "1x por semana" no campo livre. Trocar isso por
    // "semanal" seria o software reescrevendo registro clínico para caber num
    // select — o campo abre em "outra", com o texto intacto.
    expect(frequenciaNaLista("1x por semana")).toBe(false);
    expect(frequenciaNaLista("quinzenal, às vezes semanal")).toBe(false);
    expect(frequenciaNaLista(null)).toBe(false);
  });

  it("a lista não descreve frequência com adjetivo nem com juízo", () => {
    // Doc 07: o sistema não opina sobre frequência de atendimento. "ideal",
    // "recomendada", "mínima" seriam o software entrando na decisão clínica.
    for (const f of FREQUENCIAS) {
      expect(f).not.toMatch(/ideal|recomend|m[íi]nim|adequad|correto/i);
    }
  });
});
