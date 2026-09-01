import { describe, it, expect } from "vitest";
import * as anamnese from "./anamnese";
import {
  roteiroPadrao,
  secoesEscritas,
  fraseDoProgresso,
  fraseDoAviso,
  fraseDoLimite,
  rotuloEstado,
  rotuloModelo,
  podeFechar,
  diaBr,
  MODELOS,
  AVISO_DE_FECHAMENTO,
  type Anamnese,
  type Aviso,
} from "./anamnese";

const an = (p: Partial<Anamnese> = {}): Anamnese => ({
  id: "a",
  modelo: "adulto",
  estado: "aberta",
  conteudo: roteiroPadrao("adulto").map((titulo) => ({ titulo, texto: "" })),
  medicacao_atual: null,
  fechada_em: null,
  criado_em: "2026-09-01T12:00:00Z",
  adendos: [],
  ...p,
});

const aviso = (p: Partial<Aviso> = {}): Aviso => ({
  mostrar: false,
  sessoes: 0,
  limite: 3,
  existe: false,
  estado: null,
  anamnese_id: null,
  ...p,
});

// ================================================ a fronteira do doc 11

describe("a anamnese é da sala, e o módulo prova isso pelo que NÃO tem", () => {
  it("não exporta nada que monte formulário para o paciente", () => {
    const proibidos = ["formulario", "formulário", "token", "publico", "público", "link", "convite", "enviar"];
    for (const nome of Object.keys(anamnese)) {
      for (const p of proibidos) {
        expect(
          nome.toLowerCase().includes(p),
          `o módulo exporta "${nome}" — pergunta clínica não vai por formulário ao paciente (fronteira 6)`,
        ).toBe(false);
      }
    }
  });

  it("os três roteiros são títulos de seção, nunca perguntas", () => {
    // Um roteiro com "?" é questionário; questionário com campo fixo é
    // instrumento clínico, e instrumento clínico é de outra profissão.
    for (const m of MODELOS) {
      for (const titulo of roteiroPadrao(m.valor)) {
        expect(titulo, `"${titulo}" no roteiro ${m.valor}`).not.toMatch(/\?/);
        expect(titulo.length).toBeLessThan(60);
      }
    }
  });
});

// ==================================================== os roteiros

describe("roteiroPadrao — gêmeo de public.roteiro_padrao", () => {
  it("os três são diferentes", () => {
    expect(roteiroPadrao("adulto")).not.toEqual(roteiroPadrao("infantil"));
    expect(roteiroPadrao("casal")).not.toEqual(roteiroPadrao("adulto"));
  });

  it("o infantil fala de escola e de desenvolvimento; o adulto não", () => {
    const inf = roteiroPadrao("infantil").join(" | ");
    expect(inf).toMatch(/Escola/);
    expect(inf).toMatch(/desenvolvimento/);
    expect(roteiroPadrao("adulto").join(" | ")).not.toMatch(/Escola/);
  });

  it("o de casal fala dos dois, e não de um", () => {
    const c = roteiroPadrao("casal").join(" | ");
    expect(c).toMatch(/os dois|cada um/i);
  });

  it("nenhum é curto demais para ser um roteiro", () => {
    for (const m of MODELOS) {
      expect(roteiroPadrao(m.valor).length).toBeGreaterThanOrEqual(6);
    }
  });

  it("os três modelos têm quando usar, não só nome", () => {
    for (const m of MODELOS) {
      expect(m.quando.length).toBeGreaterThan(10);
    }
  });
});

// ==================================================== progresso e fechamento

describe("secoesEscritas e fraseDoProgresso", () => {
  it("sem anamnese", () => {
    expect(secoesEscritas(null)).toBe(0);
    expect(fraseDoProgresso(null)).toBe("Ainda não há anamnese.");
  });

  it("aberta e em branco diz quantas seções esperam", () => {
    expect(fraseDoProgresso(an())).toBe("Aberta, 7 seções em branco.");
  });

  it("aberta e parcial conta as escritas", () => {
    const a = an();
    a.conteudo[0].texto = "Crises de ansiedade.";
    a.conteudo[2].texto = "Trabalha em escala.";
    expect(secoesEscritas(a)).toBe(2);
    expect(fraseDoProgresso(a)).toBe("Aberta · 2 de 7 seções escritas.");
  });

  it("espaço em branco não conta como escrito", () => {
    const a = an();
    a.conteudo[0].texto = "    ";
    expect(secoesEscritas(a)).toBe(0);
  });

  it("fechada diz quantas e quantos adendos vieram depois", () => {
    const a = an({ estado: "fechada", fechada_em: "2026-09-10T12:00:00Z" });
    a.conteudo[0].texto = "x";
    expect(fraseDoProgresso(a)).toBe("Fechada com 1 de 7 seções escritas.");

    a.adendos = [{ id: "1", texto: "y", criado_em: "2026-10-01T12:00:00Z" }];
    expect(fraseDoProgresso(a)).toMatch(/Um adendo depois disso\./);

    a.adendos.push({ id: "2", texto: "z", criado_em: "2026-11-01T12:00:00Z" });
    expect(fraseDoProgresso(a)).toMatch(/2 adendos depois disso\./);
  });
});

describe("podeFechar — em branco não fecha", () => {
  it("anamnese sem uma linha escrita não fecha", () => {
    expect(podeFechar(an())).toBe(false);
  });

  it("com uma linha, fecha", () => {
    const a = an();
    a.conteudo[0].texto = "Procurou por indicação.";
    expect(podeFechar(a)).toBe(true);
  });

  it("fechada não fecha de novo", () => {
    const a = an({ estado: "fechada" });
    a.conteudo[0].texto = "x";
    expect(podeFechar(a)).toBe(false);
  });

  it("sem anamnese, não", () => {
    expect(podeFechar(null)).toBe(false);
  });

  it("o aviso de fechamento diz que não tem volta — armadilha é ação sem volta que não avisa", () => {
    expect(AVISO_DE_FECHAMENTO).toMatch(/não se reescreve/);
    expect(AVISO_DE_FECHAMENTO).toMatch(/nem reabre/);
    expect(AVISO_DE_FECHAMENTO).toMatch(/adendo/);
  });
});

// ==================================================== o aviso da terceira

describe("fraseDoAviso — fala do registro dela, nunca do paciente", () => {
  it("sem aviso, silêncio", () => {
    expect(fraseDoAviso(aviso())).toBe("");
  });

  it("quando não há anamnese nenhuma", () => {
    expect(fraseDoAviso(aviso({ mostrar: true, sessoes: 3, existe: false }))).toBe(
      "3 sessões realizadas e a anamnese ainda não foi começada.",
    );
  });

  it("quando há e está aberta", () => {
    expect(
      fraseDoAviso(aviso({ mostrar: true, sessoes: 5, existe: true, estado: "aberta" })),
    ).toBe("5 sessões realizadas e a anamnese ainda está aberta.");
  });

  it("uma sessão, no singular", () => {
    expect(fraseDoAviso(aviso({ mostrar: true, sessoes: 1, limite: 1 }))).toMatch(/1 sessão /);
  });

  it("nenhuma frase julga o paciente — é sobre o papel, não sobre a pessoa", () => {
    const casos = [
      aviso({ mostrar: true, sessoes: 3 }),
      aviso({ mostrar: true, sessoes: 12, existe: true, estado: "aberta" }),
    ];
    for (const c of casos) {
      const f = fraseDoAviso(c) + " " + fraseDoLimite(c);
      expect(f).not.toMatch(/atras|abandon|risco|preocup|negligen|esquec|falha|pendênc/i);
    }
  });

  it("a frase não manda fazer nada — diz o estado e para", () => {
    const f = fraseDoAviso(aviso({ mostrar: true, sessoes: 3 }));
    expect(f).not.toMatch(/precisa|deve|obrigat|urgente|agora/i);
  });
});

describe("fraseDoLimite — o número é dito como provisório", () => {
  it("mostra o número que o banco devolveu, e não um número próprio", () => {
    expect(fraseDoLimite(aviso({ limite: 3 }))).toMatch(/3ª sessão/);
    expect(fraseDoLimite(aviso({ limite: 5 }))).toMatch(/5ª sessão/);
  });

  it("diz que vai ser revisto com uma psicóloga", () => {
    expect(fraseDoLimite(aviso())).toMatch(/ponto de partida/);
    expect(fraseDoLimite(aviso())).toMatch(/psicóloga/);
  });
});

describe("rótulos e datas", () => {
  it("estados e modelos", () => {
    expect(rotuloEstado("aberta")).toBe("aberta");
    expect(rotuloEstado("fechada")).toBe("fechada");
    expect(rotuloModelo("infantil")).toBe("Infantil");
    expect(rotuloModelo("casal")).toBe("Casal");
  });

  it("diaBr aceita timestamp inteiro", () => {
    expect(diaBr("2026-03-05T18:00:00Z")).toBe("05/03/2026");
    expect(diaBr("2026-03-05")).toBe("05/03/2026");
  });
});
