import { describe, it, expect } from "vitest";
import {
  iniciaisDoNome,
  tituloDoEvento,
  rotuloDoModo,
  rotuloDaDirecao,
  horasDesde,
  fraseDaDefasagem,
  fraseDoEstado,
  fraseDaFila,
  rotuloDaAcao,
  lerEstadoHistorico,
  lerDia,
  lerHistorico,
  comValor,
  rotuloEstadoHistorico,
  diaBr,
  type PainelCalendario,
} from "./calendario";

/**
 * Os valores esperados destes testes são os mesmos da suíte SQL 0040
 * (verificações 9, 10, 11 e 25 a 29). Quando um dos dois lados mudar sozinho,
 * é aqui ou lá que aparece — que é o ponto de escrever duas vezes.
 */

// ============================================================ o título

describe("iniciaisDoNome — o mesmo de public.iniciais_do_nome", () => {
  it("engole as partículas", () => {
    expect(iniciaisDoNome("Maria Fernanda de Souza")).toBe("M. F. S.");
    expect(iniciaisDoNome("João Pedro dos Santos")).toBe("J. P. S.");
    expect(iniciaisDoNome("Ana e Silva")).toBe("A. S.");
  });

  it("aguenta nome de uma palavra só", () => {
    expect(iniciaisDoNome("Madonna")).toBe("M.");
  });

  it("devolve vazio para vazio — e não estoura", () => {
    expect(iniciaisDoNome("")).toBe("");
    expect(iniciaisDoNome("   ")).toBe("");
  });

  it("não se perde com espaço a mais", () => {
    expect(iniciaisDoNome("  Maria   Fernanda  ")).toBe("M. F.");
  });
});

describe("tituloDoEvento — o que a Google vai ver", () => {
  it("o padrão não diz quem", () => {
    expect(tituloDoEvento("discreto", "Maria Fernanda de Souza")).toBe("Sessão");
  });

  it("iniciais identificam para ela e não para quem passa", () => {
    expect(tituloDoEvento("iniciais", "Maria Fernanda de Souza")).toBe("Sessão · M. F. S.");
  });

  it("completo é o único que diz o nome", () => {
    expect(tituloDoEvento("completo", "Maria Fernanda de Souza")).toBe(
      "Sessão · Maria Fernanda de Souza",
    );
  });

  it("o nome nunca escapa pelos outros dois modos", () => {
    const nome = "Zebulon Improvável Kryzanowski";
    expect(tituloDoEvento("discreto", nome)).not.toContain("Zebulon");
    expect(tituloDoEvento("iniciais", nome)).not.toContain("Zebulon");
    expect(tituloDoEvento("iniciais", nome)).not.toContain("Kryzanowski");
  });

  it("sem nome, cai no discreto em vez de sair com título quebrado", () => {
    expect(tituloDoEvento("iniciais", "")).toBe("Sessão");
    expect(tituloDoEvento("completo", "   ")).toBe("Sessão");
  });
});

describe("os rótulos dizem a consequência, não só o nome", () => {
  it("o modo completo avisa o que custa", () => {
    expect(rotuloDoModo("completo").explica).toMatch(/sensível/);
  });
  it("só escrever avisa que a fila fica cega", () => {
    expect(rotuloDaDirecao("escrever").explica).toMatch(/pode oferecer uma hora/);
  });
  it("o discreto se apresenta como padrão", () => {
    expect(rotuloDoModo("discreto").explica).toMatch(/padrão/);
  });
});

// ======================================================== a defasagem

describe("horasDesde", () => {
  const agora = new Date("2026-08-31T12:00:00Z");

  it("conta horas inteiras", () => {
    expect(horasDesde("2026-08-31T09:30:00Z", agora)).toBe(2);
  });
  it("nunca sincronizou devolve null", () => {
    expect(horasDesde(null, agora)).toBeNull();
    expect(horasDesde(undefined, agora)).toBeNull();
  });
  it("carimbo ilegível devolve null em vez de NaN", () => {
    expect(horasDesde("nem data", agora)).toBeNull();
  });
});

describe("fraseDaDefasagem — a decisão 4 escrita na tela", () => {
  const agora = new Date("2026-08-31T12:00:00Z");
  const base: PainelCalendario = {
    ligado: true,
    estado: "ligado",
    direcao: "duas_vias",
    modo_titulo: "discreto",
  };

  it("desligado não fala nada", () => {
    expect(fraseDaDefasagem({ ligado: false }, agora)).toBe("");
  });

  it("quem pediu só para escrever é avisado de que não se lê", () => {
    expect(fraseDaDefasagem({ ...base, direcao: "escrever" }, agora)).toMatch(/só escrever/);
  });

  it("nunca lido diz que nunca leu", () => {
    expect(fraseDaDefasagem(base, agora)).toBe("Ainda não li a sua agenda nenhuma vez.");
  });

  it("menos de uma hora", () => {
    expect(fraseDaDefasagem({ ...base, sincronizado_em: "2026-08-31T11:30:00Z" }, agora)).toMatch(
      /menos de uma hora/,
    );
  });

  it("horas no singular e no plural", () => {
    expect(fraseDaDefasagem({ ...base, sincronizado_em: "2026-08-31T11:00:00Z" }, agora)).toBe(
      "Li a sua agenda há 1 hora.",
    );
    expect(fraseDaDefasagem({ ...base, sincronizado_em: "2026-08-31T07:00:00Z" }, agora)).toBe(
      "Li a sua agenda há 5 horas.",
    );
  });

  it("passado de um dia, diz o que NÃO sabe — é o ponto da frase", () => {
    const f = fraseDaDefasagem({ ...base, sincronizado_em: "2026-08-29T12:00:00Z" }, agora);
    expect(f).toMatch(/2 dias/);
    expect(f).toMatch(/continua bloqueado/);
    expect(f).toMatch(/não vi/);
  });
});

describe("fraseDoEstado", () => {
  it("expirado explica que o bloqueio continua", () => {
    expect(fraseDoEstado({ ligado: true, estado: "expirado" })).toMatch(/continuam bloqueadas/);
  });
  it("pausado explica que nada some", () => {
    expect(fraseDoEstado({ ligado: true, estado: "pausado" })).toMatch(/continua valendo/);
  });
  it("sem calendário", () => {
    expect(fraseDoEstado({ ligado: false })).toBe("Nenhuma agenda ligada.");
  });
});

describe("fraseDaFila — inclusive o que desistiu de sair", () => {
  it("fila vazia", () => {
    expect(fraseDaFila({ ligado: true })).toBe("Nada foi para a sua agenda ainda.");
  });

  it("conta os três estados", () => {
    const f = fraseDaFila({ ligado: true, espelhados: 12, pendentes: 2, falhados: 1 });
    expect(f).toBe("12 sessões estão lá · 2 esperando para ir · 1 que eu desisti de mandar.");
  });

  it("uma só, no singular", () => {
    expect(fraseDaFila({ ligado: true, espelhados: 1 })).toBe("1 sessão está lá.");
  });

  it("o que falhou nunca é escondido", () => {
    expect(fraseDaFila({ ligado: true, falhados: 3 })).toMatch(/desisti/);
  });
});

describe("rotuloDaAcao", () => {
  it("as três ações", () => {
    expect(rotuloDaAcao("criar")).toBe("criar o evento");
    expect(rotuloDaAcao("atualizar")).toBe("atualizar o evento");
    expect(rotuloDaAcao("remover")).toBe("tirar o evento");
  });
});

// ================================================= o histórico de fora

describe("lerEstadoHistorico — ninguém exporta com os nossos nomes", () => {
  it("aceita o vocabulário de quem está migrando", () => {
    expect(lerEstadoHistorico("compareceu")).toBe("realizada");
    expect(lerEstadoHistorico("Atendido")).toBe("realizada");
    expect(lerEstadoHistorico("faltou")).toBe("falta");
    expect(lerEstadoHistorico("não compareceu")).toBe("falta");
    expect(lerEstadoHistorico("desmarcou")).toBe("cancelada_cedo");
    expect(lerEstadoHistorico("cancelamento tardio")).toBe("cancelada_tarde");
  });

  it("vazio é realizada — é o caso comum de uma planilha de atendimentos", () => {
    expect(lerEstadoHistorico("")).toBe("realizada");
  });

  it("o que não dá para ler não é chutado", () => {
    expect(lerEstadoHistorico("talvez")).toBeNull();
    expect(lerEstadoHistorico("xpto")).toBeNull();
  });
});

describe("lerDia", () => {
  it("aceita ISO e brasileiro", () => {
    expect(lerDia("2024-03-05")).toBe("2024-03-05");
    expect(lerDia("05/03/2024")).toBe("2024-03-05");
    expect(lerDia("5/3/24")).toBe("2024-03-05");
    expect(lerDia("05.03.2024")).toBe("2024-03-05");
  });

  it("recusa data que não existe em vez de consertar sozinha", () => {
    // O `Date` do JS transforma 31/02 em 02/03 sem reclamar. Uma data que se
    // conserta sozinha enche a linha do tempo de sessão em dia errado.
    expect(lerDia("31/02/2024")).toBeNull();
    expect(lerDia("31/04/2024")).toBeNull();
    expect(lerDia("00/01/2024")).toBeNull();
  });

  it("29 de fevereiro existe em ano bissexto e não existe fora dele", () => {
    expect(lerDia("29/02/2024")).toBe("2024-02-29");
    expect(lerDia("29/02/2025")).toBeNull();
  });

  it("o que não é data devolve null", () => {
    expect(lerDia("")).toBeNull();
    expect(lerDia("terça")).toBeNull();
  });
});

describe("lerHistorico", () => {
  const hoje = "2026-08-31";

  it("lê a colagem completa", () => {
    const r = lerHistorico(
      "Maria Fernanda; 05/03/2024; 15h; compareceu; 200\nJoão Pedro; 12/03/2024; 16:00; faltou; R$ 180,00",
      hoje,
    );
    expect(r.erros).toHaveLength(0);
    expect(r.sessoes).toHaveLength(2);
    expect(r.sessoes[0]).toMatchObject({
      linha: 1,
      paciente: "Maria Fernanda",
      dia: "2024-03-05",
      hora: "15:00",
      estado: "realizada",
      valorCentavos: 20000,
    });
    expect(r.sessoes[1].estado).toBe("falta");
    expect(r.sessoes[1].valorCentavos).toBe(18000);
  });

  it("descobre o separador sozinho", () => {
    const ponto = lerHistorico("Maria; 05/03/2024", hoje);
    const tab = lerHistorico("Maria\t05/03/2024", hoje);
    const virgula = lerHistorico("Maria,05/03/2024", hoje);
    expect(ponto.sessoes[0].dia).toBe("2024-03-05");
    expect(tab.sessoes[0].dia).toBe("2024-03-05");
    expect(virgula.sessoes[0].dia).toBe("2024-03-05");
  });

  it("sem hora, assume meio-dia — que não vira véspera em São Paulo", () => {
    const r = lerHistorico("Maria; 05/03/2024", hoje);
    expect(r.sessoes[0].hora).toBe("12:00");
  });

  it("uma linha ruim não derruba as outras", () => {
    const r = lerHistorico(
      "Maria; 05/03/2024\nlinha sem data nenhuma\nJoão; 12/03/2024",
      hoje,
    );
    expect(r.sessoes).toHaveLength(2);
    expect(r.erros).toHaveLength(1);
    expect(r.erros[0].linha).toBe(2);
    expect(r.erros[0].motivo).toMatch(/data/);
  });

  it("o erro diz a linha e o texto, para ela achar na planilha", () => {
    const r = lerHistorico("Maria; 32/13/2024", hoje);
    expect(r.erros[0]).toMatchObject({ linha: 1, texto: "Maria; 32/13/2024" });
  });

  it("histórico é passado — data futura é recusada aqui e no banco", () => {
    const r = lerHistorico("Maria; 05/12/2026", hoje);
    expect(r.sessoes).toHaveLength(0);
    expect(r.erros[0].motivo).toBe("histórico é passado");
  });

  it("hoje ainda não é passado", () => {
    const r = lerHistorico("Maria; 31/08/2026", hoje);
    expect(r.erros[0].motivo).toBe("histórico é passado");
  });

  it("ontem é", () => {
    const r = lerHistorico("Maria; 30/08/2026", hoje);
    expect(r.erros).toHaveLength(0);
    expect(r.sessoes[0].dia).toBe("2026-08-30");
  });

  it("o cabeçalho da planilha some sem virar erro", () => {
    const r = lerHistorico("paciente;data;hora;estado;valor\nMaria; 05/03/2024", hoje);
    expect(r.erros).toHaveLength(0);
    expect(r.sessoes).toHaveLength(1);
  });

  it("linha em branco é ignorada, não é erro", () => {
    const r = lerHistorico("Maria; 05/03/2024\n\n\nJoão; 12/03/2024\n", hoje);
    expect(r.sessoes).toHaveLength(2);
    expect(r.erros).toHaveLength(0);
  });

  it("sem nome não entra", () => {
    const r = lerHistorico("; 05/03/2024", hoje);
    expect(r.erros[0].motivo).toBe("sem nome de paciente");
  });

  it("estado ilegível não vira 'realizada' por conveniência", () => {
    const r = lerHistorico("Maria; 05/03/2024; 15h; talvez", hoje);
    expect(r.sessoes).toHaveLength(0);
    expect(r.erros[0].motivo).toMatch(/o que houve/);
  });

  it("valor ausente é null, não zero", () => {
    const r = lerHistorico("Maria; 05/03/2024; 15h; compareceu", hoje);
    expect(r.sessoes[0].valorCentavos).toBeNull();
  });

  it("comValor conta só quem trouxe valor", () => {
    const r = lerHistorico(
      "Maria; 05/03/2024; 15h; ok; 200\nJoão; 12/03/2024; 16h; ok",
      hoje,
    );
    expect(comValor(r)).toBe(1);
  });
});

describe("rótulos e datas", () => {
  it("os quatro desfechos têm nome de gente", () => {
    expect(rotuloEstadoHistorico("realizada")).toBe("realizada");
    expect(rotuloEstadoHistorico("falta")).toBe("falta");
    expect(rotuloEstadoHistorico("cancelada_cedo")).toBe("cancelada");
    expect(rotuloEstadoHistorico("cancelada_tarde")).toBe("cancelada em cima da hora");
  });

  it("diaBr", () => {
    expect(diaBr("2026-03-05")).toBe("05/03/2026");
  });
});
