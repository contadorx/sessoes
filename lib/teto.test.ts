import { describe, it, expect } from "vitest";
import {
  fraseDosPacientes,
  fraseDaSaida_pacientes,
  ESSENCIAIS,
  ehEssencial,
  motivoDoFreio,
  rotuloEstadoMensagem,
  terminal,
  SEM_TETO,
  type EstadoMensagem,
  type Pacientes,
} from "./teto";

// ============================================================================
// Esta suíte perdeu metade do tamanho em 02/09/2026, e é a metade certa.
//
// Ela testava as frases do teto de mensagens do plano: quando avisar, o que
// dizer ao estourar, como a fila explica que pausou. A migração 0060 tirou esse
// teto do produto — a unidade cobrada passou a ser a sessão —, e as frases
// deixaram de existir junto com o comportamento que descreviam.
//
// O que sobrou é o que não dependia do teto ser comercial: a classificação dos
// templates, os estados da mensagem, e o limite de pacientes que a 0048 já
// tinha desligado. E o que entrou no lugar está em `faixa.test.ts`.
// ============================================================================

describe("a classificação dos templates sobrevive ao teto", () => {
  it("os três essenciais são exatamente os que o paciente não descobre de outro jeito", () => {
    expect([...ESSENCIAIS].sort()).toEqual(
      ["aviso_de_desmarque", "encaixe_confirmado", "lembrete_de_sessao"].sort(),
    );
  });

  it("o lembrete de véspera é essencial — e isto é o teste que não pode cair", () => {
    expect(ehEssencial("lembrete_de_sessao")).toBe(true);
    expect(ehEssencial("aviso_de_desmarque")).toBe(true);
    expect(ehEssencial("encaixe_confirmado")).toBe(true);
  });

  it("o que gera negócio novo não é essencial — mas hoje também não é barrado", () => {
    // A distinção continua existindo e continua obrigatória para todo template
    // novo. O que mudou é que nenhum plano a usa para barrar: desde a 0060 a
    // oferta de vaga e o aviso de cobrança saem em qualquer plano.
    expect(ehEssencial("oferta_de_vaga")).toBe(false);
    expect(ehEssencial("oferta_de_vaga_fixa")).toBe(false);
    expect(ehEssencial("aviso_de_cobranca")).toBe(false);
    expect(ehEssencial("lembrete_de_pagamento")).toBe(false);
  });

  it("um template desconhecido não é essencial por acaso", () => {
    expect(ehEssencial("template_que_alguem_inventar")).toBe(false);
  });
});

describe("o teto mensal existe no tipo e não existe em plano nenhum", () => {
  it("o valor de repouso é 'sem teto', e não 'teto zero'", () => {
    // Zero seria um teto de zero mensagens, que barraria tudo. A ausência de
    // teto é `tem_teto: false` — a mesma distinção entre nulo e zero que o P5
    // fez para a ocupação.
    expect(SEM_TETO.tem_teto).toBe(false);
    expect(SEM_TETO.limite).toBeNull();
    expect(SEM_TETO.estourou).toBe(false);
  });
});

describe("os freios técnicos são traduzíveis, e só isso", () => {
  it("cada freio tem uma explicação em português", () => {
    expect(motivoDoFreio("mensagens_por_conta_hora")).toMatch(/mesma hora/);
    expect(motivoDoFreio("mensagens_por_paciente_dia")).toMatch(/mesma pessoa/);
  });

  it("um freio novo não quebra a tela", () => {
    expect(motivoDoFreio("freio_que_ainda_nao_existe")).toBe("trava de segurança");
  });

  it("nenhuma explicação de freio menciona plano, preço ou upgrade", () => {
    // Freio técnico que fala de plano é produto disfarçado — e a suíte 0060
    // varre o banco pela mesma razão.
    const todas = [
      motivoDoFreio("mensagens_por_conta_hora"),
      motivoDoFreio("mensagens_por_paciente_dia"),
      motivoDoFreio("qualquer_outro"),
    ].join(" ");
    expect(todas).not.toMatch(/plano|assinar|upgrade|R\$|limite do seu/i);
  });
});

describe("rotuloEstadoMensagem — a barrada diz que não saiu", () => {
  it("todo estado tem rótulo", () => {
    const todos: EstadoMensagem[] = [
      "pendente",
      "enviando",
      "enviada",
      "entregue",
      "falhou",
      "cancelada",
      "barrada_no_teto",
    ];
    for (const e of todos) {
      expect(rotuloEstadoMensagem(e).length).toBeGreaterThan(0);
    }
  });

  it("barrada_no_teto diz explicitamente que NÃO saiu", () => {
    // O modo de falha ruim é a mensagem sumir da tela e ela descobrir semanas
    // depois que ninguém foi cobrado.
    expect(rotuloEstadoMensagem("barrada_no_teto")).toMatch(/não saiu/);
  });

  it("...e não chama mais isso de limite do plano", () => {
    // Porque não é: desde a 0060 o que barra é uma trava de segurança contra
    // laço, e chamar as duas coisas pelo mesmo nome é o começo de confundi-las.
    expect(rotuloEstadoMensagem("barrada_no_teto")).not.toMatch(/plano/);
    expect(rotuloEstadoMensagem("barrada_no_teto")).toMatch(/trava de segurança/);
  });

  it("barrada é terminal — virar o mês não reenvia", () => {
    expect(terminal("barrada_no_teto")).toBe(true);
    expect(terminal("entregue")).toBe(true);
    expect(terminal("cancelada")).toBe(true);
  });

  it("...e pendente e falhou não são", () => {
    expect(terminal("pendente")).toBe(false);
    expect(terminal("falhou")).toBe(false);
    expect(terminal("enviando")).toBe(false);
  });
});

describe("pacientes: medida, não porteiro (0048)", () => {
  const pac = (p: Partial<Pacientes> = {}): Pacientes => ({
    tem_limite: false,
    limite: null,
    ativos: 12,
    restantes: null,
    lotou: false,
    ...p,
  });

  it("hoje NENHUM plano limita paciente — o registro é a parte que não se cobra", () => {
    expect(fraseDosPacientes(pac())).toMatch(/não tem limite/);
    expect(fraseDaSaida_pacientes(pac())).toBe("");
  });

  it("a máquina continua funcionando se um plano voltar a limitar", () => {
    const p = pac({ tem_limite: true, limite: 5, ativos: 3, restantes: 2 });
    expect(fraseDosPacientes(p)).toBe("3 de 5 pacientes ativos.");
  });

  it("quando lota, a saída vem junto — limite sem saída é parede", () => {
    const p = pac({ tem_limite: true, limite: 5, ativos: 5, restantes: 0, lotou: true });
    expect(fraseDaSaida_pacientes(p)).not.toBe("");
    expect(fraseDaSaida_pacientes(p)).toMatch(/arquivar/i);
  });

  it("...e a saída diz que a ficha continua guardada", () => {
    const p = pac({ tem_limite: true, limite: 5, ativos: 5, restantes: 0, lotou: true });
    expect(fraseDaSaida_pacientes(p)).toMatch(/guardada|histórico/i);
  });

  it("a frase não empurra o plano pago", () => {
    const p = pac({ tem_limite: true, limite: 5, ativos: 5, restantes: 0, lotou: true });
    const tudo = fraseDosPacientes(p) + " " + fraseDaSaida_pacientes(p);
    expect(tudo).not.toMatch(/assine|aproveite|R\$|upgrade/i);
  });

  it("sem limite, quarenta pacientes não geram aviso", () => {
    expect(fraseDosPacientes(pac({ ativos: 40 }))).toMatch(/não tem limite/);
  });
});
