import { describe, it, expect } from "vitest";
import {
  montar,
  faltamObrigatorios,
  marcadoresDesconhecidos,
  estadoDoAceite,
  rotuloDoAceite,
  diaBrasileiro,
  TEXTO_PADRAO,
  MARCADORES,
  type DadosDoContrato,
  type AceiteLinha,
} from "@/lib/contrato";
import { formatar } from "@/lib/dinheiro";

const MARIA: DadosDoContrato = {
  nome: "Maria Reis Alcântara",
  profissional: "Ana Ferreira",
  crp: "06/123456",
  diaSemana: 2,
  hora: "15:00",
  duracaoMin: 50,
  valorCentavos: 123_450,
  politicaHoras: 24,
  politicaPercentual: 50,
  cidade: "São Paulo",
  data: "2026-03-03",
};

describe("a substituição", () => {
  it("troca todos os marcadores", () => {
    const t = montar(TEXTO_PADRAO, MARIA);
    expect(t).not.toContain("{{");
    expect(t).toContain("Maria Reis Alcântara");
    expect(t).toContain("Ana Ferreira");
    expect(t).toContain("terça, 15h");
    expect(t).toContain("50 minutos");
    expect(t).toContain("03/03/2026");
    expect(t).toContain("São Paulo");
  });

  it("o mesmo marcador repetido é trocado em todas as ocorrências", () => {
    const t = montar("{{nome}} e {{nome}} e {{nome}}", MARIA);
    expect(t).toBe("Maria Reis Alcântara e Maria Reis Alcântara e Maria Reis Alcântara");
  });

  it("um nome com $& não vira lixo — a troca não passa por regex", () => {
    // `String.replace` interpreta `$&` no valor de substituição. Se a montagem
    // usasse replace com string, um paciente chamado "A$&B" quebraria o texto
    // do próprio contrato dele.
    const t = montar("Nome: {{nome}}.", { ...MARIA, nome: "A$&B" });
    expect(t).toBe("Nome: A$&B.");
  });

  it("marcador desconhecido não é tocado — some no banco só quando existir", () => {
    const t = montar("Olá {{nome}}, {{inventado}}", MARIA);
    expect(t).toContain("{{inventado}}");
  });

  it("sem CRP e sem cidade, sai um travessão em vez de vazio", () => {
    const t = montar("CRP {{crp}} em {{cidade}}", { ...MARIA, crp: "  ", cidade: "" });
    expect(t).toBe("CRP — em —");
  });
});

describe("dinheiro, horário e política — os espelhos do banco", () => {
  /**
   * Estes quatro casos existem duas vezes no projeto, com as mesmas strings:
   * aqui e em `supabase/tests/0031_contratos.sql` (verificação 21). Se a função
   * `reais()` do banco e o `formatar()` daqui divergirem — inclusive no espaço
   * fino depois do "R$" —, um dos dois lados falha e o outro aponta onde.
   */
  it("R$ 1.234,50 com o espaço fino do Intl", () => {
    expect(formatar(123_450)).toBe("R$ 1.234,50");
  });

  it("R$ 200,00", () => {
    expect(formatar(20_000)).toBe("R$ 200,00");
  });

  it("R$ 0,00", () => {
    expect(formatar(0)).toBe("R$ 0,00");
  });

  it("R$ 1.000.000,00 — os dois pontos de milhar", () => {
    expect(formatar(100_000_000)).toBe("R$ 1.000.000,00");
  });

  it("o valor entra no texto exatamente como sai do banco", () => {
    expect(montar("Valor: {{valor}}.", MARIA)).toBe("Valor: R$ 1.234,50.");
  });

  it("a política entra por extenso, e é a mesma frase da tela", () => {
    expect(montar("{{politica}}", MARIA)).toBe(
      "desmarcar com menos de 24 horas cobra 50%",
    );
    expect(montar("{{politica}}", { ...MARIA, politicaPercentual: 0 })).toBe(
      "falta não é cobrada",
    );
    expect(montar("{{politica}}", { ...MARIA, politicaPercentual: 100 })).toBe(
      "desmarcar com menos de 24 horas cobra a sessão inteira",
    );
    expect(montar("{{politica}}", { ...MARIA, politicaHoras: 0 })).toBe(
      "falta cobra 50% em qualquer aviso",
    );
  });

  it("a data civil não passa por fuso nenhum", () => {
    expect(diaBrasileiro("2026-01-01")).toBe("01/01/2026");
    expect(diaBrasileiro("2026-12-31")).toBe("31/12/2026");
  });
});

describe("o portão do doc 07", () => {
  it("o texto padrão já traz a política e o valor", () => {
    expect(faltamObrigatorios(TEXTO_PADRAO)).toEqual([]);
  });

  it("um texto sem a política de falta não passa", () => {
    const sem = TEXTO_PADRAO.replace("{{politica}}", "o que a gente combinar");
    expect(faltamObrigatorios(sem)).toContain("{{politica}}");
  });

  it("um texto sem o valor não passa", () => {
    const sem = TEXTO_PADRAO.replace("{{valor}}", "o combinado");
    expect(faltamObrigatorios(sem)).toContain("{{valor}}");
  });

  it("erro de digitação em marcador é apontado antes de publicar", () => {
    expect(marcadoresDesconhecidos("Olá {{nome}}, {{politca}} e {{valor}}")).toEqual([
      "{{politca}}",
    ]);
    expect(marcadoresDesconhecidos(TEXTO_PADRAO)).toEqual([]);
  });
});

describe("o texto padrão", () => {
  it("não promete o que não entrega: nada de assinatura digital certificada", () => {
    const t = TEXTO_PADRAO.toLowerCase();
    expect(t).not.toContain("icp-brasil");
    expect(t).not.toContain("certificado digital");
    expect(t).not.toContain("firma reconhecida");
  });

  it("não prende ninguém: sem multa de rescisão nem permanência mínima", () => {
    const t = TEXTO_PADRAO.toLowerCase();
    for (const proibida of [
      "multa",
      "fidelidade",
      "permanência mínima",
      "prazo mínimo",
      "rescisão",
      "juros",
      "protesto",
    ]) {
      expect(t).not.toContain(proibida);
    }
  });

  it("diz o sigilo e diz as exceções — omitir uma delas é pior que não falar", () => {
    expect(TEXTO_PADRAO).toContain("sigiloso");
    expect(TEXTO_PADRAO.toLowerCase()).toContain("judicial");
  });

  it("a regra de desmarcação vem do marcador, nunca escrita à mão", () => {
    // Um número solto no texto desatualiza no primeiro paciente com outra
    // política — e o contrato passa a dizer uma coisa e o sistema a cobrar
    // outra. Só o marcador acompanha o combinado.
    expect(TEXTO_PADRAO).toContain("{{politica}}");
    expect(TEXTO_PADRAO).not.toMatch(/\d+\s*horas/);
  });

  it("todo marcador usado no texto padrão está na lista da tela", () => {
    const conhecidos = new Set<string>(MARCADORES.map((m) => m.chave));
    for (const achado of TEXTO_PADRAO.match(/\{\{[^}]*\}\}/g) ?? []) {
      expect(conhecidos.has(achado)).toBe(true);
    }
  });
});

const BASE: AceiteLinha = {
  id: "a",
  token: "0".repeat(32),
  aceito_em: null,
  aceito_por: null,
  parentesco: null,
  origem: null,
  criado_em: "2026-03-01T12:00:00Z",
  expira_em: "2026-06-01T12:00:00Z",
  revogado_em: null,
  retrato: { contrato_versao: 1 },
};

const AGORA = new Date("2026-03-10T12:00:00Z");

describe("o estado do aceite", () => {
  it("nunca preparado", () => {
    expect(estadoDoAceite(null, AGORA)).toBe("nunca_preparado");
  });

  it("pendente enquanto o link vale", () => {
    expect(estadoDoAceite(BASE, AGORA)).toBe("pendente");
  });

  it("expirado depois da data", () => {
    expect(estadoDoAceite(BASE, new Date("2026-07-01T12:00:00Z"))).toBe("expirado");
  });

  it("aceito ganha do expirado — o que valeu, valeu", () => {
    const a = { ...BASE, aceito_em: "2026-03-05T10:00:00Z", aceito_por: "Maria" };
    expect(estadoDoAceite(a, new Date("2027-01-01T00:00:00Z"))).toBe("aceito");
  });

  it("revogado ganha de tudo", () => {
    const a = {
      ...BASE,
      aceito_em: "2026-03-05T10:00:00Z",
      aceito_por: "Maria",
      revogado_em: "2026-04-01T10:00:00Z",
    };
    expect(estadoDoAceite(a, AGORA)).toBe("revogado");
  });

  it("nenhum rótulo manda ela fazer nada", () => {
    // O sistema informa; quem decide o que fazer com um combinado sem aceite é
    // ela. Um "pendência" ou um "regularize" aqui seria o produto opinando
    // sobre a condução de uma relação clínica.
    for (const estado of [
      "sem_contrato",
      "sem_combinado",
      "nunca_preparado",
      "pendente",
      "expirado",
      "aceito",
      "revogado",
    ] as const) {
      const r = rotuloDoAceite(estado).toLowerCase();
      for (const proibida of ["pendência", "regulariz", "urgente", "obrigat", "!"]) {
        expect(r).not.toContain(proibida);
      }
    }
  });

  it("o rótulo do revogado lembra que o passado continua registrado", () => {
    expect(rotuloDoAceite("revogado")).toContain("continua registrado");
  });
});
