import { describe, it, expect } from "vitest";
import {
  fraseDosPacientes,
  fraseDaSaida_pacientes,
  ESSENCIAIS,
  ehEssencial,
  nivelDoAviso,
  fraseDoTeto,
  fraseDoQueParou,
  fraseDaSaida,
  fraseDoRestante,
  filaPausada,
  fraseDaFilaPausada,
  rotuloEstadoMensagem,
  terminal,
  type Teto,
  type EstadoMensagem,
  type Pacientes,
} from "./teto";

const teto = (p: Partial<Teto> = {}): Teto => ({
  tem_teto: true,
  limite: 60,
  usadas: 10,
  restantes: 50,
  estourou: false,
  pct: 16,
  ...p,
});

const cheio = teto({ usadas: 60, restantes: 0, estourou: true, pct: 100 });
const semTeto: Teto = {
  tem_teto: false,
  limite: null,
  usadas: 0,
  restantes: null,
  estourou: false,
  pct: 0,
};

// ============================================ a regra que decide tudo

describe("o teto não alcança o paciente", () => {
  it("os três essenciais são exatamente os que o paciente não descobre de outro jeito", () => {
    // Um lembrete que não sai é alguém que perde a sessão. Um aviso de
    // desmarque que não sai é alguém indo ao consultório à toa. Uma
    // confirmação de encaixe que não sai é pior do que nunca ter oferecido.
    expect([...ESSENCIAIS].sort()).toEqual([
      "aviso_de_desmarque",
      "encaixe_confirmado",
      "lembrete_de_sessao",
    ]);
  });

  it("o lembrete de véspera é essencial — e isto é o teste que não pode cair", () => {
    expect(ehEssencial("lembrete_de_sessao")).toBe(true);
    expect(ehEssencial("aviso_de_desmarque")).toBe(true);
    expect(ehEssencial("encaixe_confirmado")).toBe(true);
  });

  it("o que gera negócio novo é barrável — ela faz à mão se precisar", () => {
    for (const t of [
      "oferta_de_vaga",
      "oferta_de_vaga_fixa",
      "aviso_de_cobranca",
      "lembrete_de_pagamento",
    ]) {
      expect(ehEssencial(t), `${t} não deveria ser essencial`).toBe(false);
    }
  });

  it("um template desconhecido não é essencial por acaso", () => {
    // Fecha para o lado seguro do produto (o template novo é barrável) e
    // ruidoso para o lado do desenvolvimento: quem criar o oitavo template
    // tem que classificá-lo no banco, e a FK obriga.
    expect(ehEssencial("template_que_ainda_nao_existe")).toBe(false);
  });
});

// ============================================ quando avisar

describe("nivelDoAviso — nem cedo demais, nem tarde demais", () => {
  it("num mês normal, silêncio", () => {
    expect(nivelDoAviso(teto({ pct: 16 }))).toBe("nenhum");
    expect(nivelDoAviso(teto({ pct: 69 }))).toBe("nenhum");
  });

  it("a partir de 70% avisa", () => {
    expect(nivelDoAviso(teto({ pct: 70 }))).toBe("perto");
    expect(nivelDoAviso(teto({ pct: 99 }))).toBe("perto");
  });

  it("estourado é estado, não aviso", () => {
    expect(nivelDoAviso(cheio)).toBe("estourou");
  });

  it("plano sem teto nunca avisa", () => {
    expect(nivelDoAviso(semTeto)).toBe("nenhum");
    expect(nivelDoAviso({ ...semTeto, pct: 100 })).toBe("nenhum");
  });
});

// ============================================ o que a tela diz

describe("as frases — dizem o que parou E o que continua", () => {
  it("plano sem teto não gera frase nenhuma", () => {
    expect(fraseDoTeto(semTeto)).toBe("");
    expect(fraseDoRestante(semTeto)).toMatch(/não tem limite/);
  });

  it("no meio do mês diz o número, sem drama", () => {
    expect(fraseDoTeto(teto({ usadas: 22 }))).toBe("22 de 60 mensagens usadas neste mês.");
  });

  it("uma só, no singular", () => {
    expect(fraseDoRestante(teto({ restantes: 1 }))).toMatch(/Falta 1 mensagem/);
  });

  it("estourado, a frase mais importante é a do que CONTINUA saindo", () => {
    // "Você atingiu o limite" sozinho deixa ela imaginando o pior — e o pior
    // aqui é exatamente o que não acontece.
    const f = fraseDoQueParou(cheio);
    expect(f).toMatch(/Lembrete de véspera/);
    expect(f).toMatch(/continuam saindo/);
    expect(f).toMatch(/nenhum limite nosso alcança/);
  });

  it("...e ela diz o que parou, com nome", () => {
    const f = fraseDoQueParou(cheio);
    expect(f).toMatch(/fila de encaixe está pausada/);
    expect(f).toMatch(/cobrança/);
  });

  it("...e oferece a saída sem decidir por ela", () => {
    const f = fraseDaSaida(cheio);
    expect(f).toMatch(/seu WhatsApp/);
    expect(f).not.toMatch(/assine|contrate|faça upgrade|melhore/i);
  });

  it("nenhuma frase culpa a psicóloga pelo próprio uso", () => {
    const todas = [
      fraseDoTeto(cheio),
      fraseDoQueParou(cheio),
      fraseDaSaida(cheio),
      fraseDoRestante(cheio),
      fraseDaFilaPausada(cheio),
    ].join(" ");
    expect(todas).not.toMatch(/excedeu|abusou|exagerou|demais|indevid|irregular/i);
  });

  it("nem transforma o limite em venda", () => {
    // O limite é meu, não um defeito dela. Uma tela de limite que vira anúncio
    // é a que faz a pessoa desconfiar de todo o resto.
    const todas = [fraseDoTeto(cheio), fraseDoQueParou(cheio), fraseDaSaida(cheio)].join(" ");
    expect(todas).not.toMatch(/R\$|assine agora|aproveite|oferta|desconto/i);
  });
});

// ============================================ a fila

describe("filaPausada — o sintoma que não pode ser mudo", () => {
  it("com teto estourado a fila não oferece", () => {
    expect(filaPausada(cheio)).toBe(true);
    expect(fraseDaFilaPausada(cheio)).toMatch(/não vai oferecer esta vaga/);
  });

  it("com folga, a fila anda e não há frase", () => {
    expect(filaPausada(teto())).toBe(false);
    expect(fraseDaFilaPausada(teto())).toBe("");
  });

  it("plano pago nunca tem fila pausada", () => {
    expect(filaPausada(semTeto)).toBe(false);
  });

  it("a frase diz o motivo — 'a fila não fez nada' sem motivo vira defeito aparente", () => {
    // O pior sintoma possível: ela cancela uma sessão, vê a fila não fazer
    // nada, e conclui que o produto quebrou.
    expect(fraseDaFilaPausada(cheio)).toMatch(/limite de mensagens/);
  });
});

// ============================================ o estado da mensagem

describe("rotuloEstadoMensagem — a barrada diz que não saiu", () => {
  it("todo estado tem rótulo", () => {
    const estados: EstadoMensagem[] = [
      "pendente", "enviando", "enviada", "entregue", "falhou", "cancelada", "barrada_no_teto",
    ];
    for (const e of estados) {
      expect(rotuloEstadoMensagem(e).length).toBeGreaterThan(2);
    }
  });

  it("barrada_no_teto diz explicitamente que NÃO saiu", () => {
    // O modo de falha ruim seria ela sumir da tela, e a psicóloga descobrir
    // semanas depois que ninguém foi cobrado.
    expect(rotuloEstadoMensagem("barrada_no_teto")).toMatch(/não saiu/);
    expect(rotuloEstadoMensagem("barrada_no_teto")).toMatch(/limite/);
  });

  it("barrada é terminal — virar o mês não reenvia", () => {
    // Um aviso de cobrança de trinta dias atrás não é uma mensagem atrasada,
    // é uma mensagem que não faz mais sentido.
    expect(terminal("barrada_no_teto")).toBe(true);
    expect(terminal("cancelada")).toBe(true);
    expect(terminal("entregue")).toBe(true);
  });

  it("...e pendente e falhou não são", () => {
    expect(terminal("pendente")).toBe(false);
    expect(terminal("falhou")).toBe(false);
  });
});

// ============================================ o limite que a cliente vê (OP3)

describe("o limite de pacientes — o único que aparece na tela", () => {
  const pac = (p: Partial<Pacientes> = {}): Pacientes => ({
    tem_limite: true, limite: 5, ativos: 2, restantes: 3, lotou: false, ...p,
  });
  const lotado = pac({ ativos: 5, restantes: 0, lotou: true });
  const semLimite: Pacientes = {
    tem_limite: false, limite: null, ativos: 40, restantes: null, lotou: false,
  };

  it("se explica em uma frase, com o número na frente", () => {
    // É este o teste da decisão inteira: o limite antigo precisava de três
    // frases e de um conceito nosso ("mensagem não-essencial") para virar
    // entendimento. Este cabe numa linha.
    expect(fraseDosPacientes(pac())).toBe("2 de 5 pacientes ativos.");
    expect(fraseDosPacientes(lotado)).toMatch(/vai até 5 pacientes ativos/);
  });

  it("plano pago não mostra limite nenhum", () => {
    expect(fraseDosPacientes(semLimite)).toMatch(/não tem limite/);
    expect(fraseDaSaida_pacientes(semLimite)).toBe("");
  });

  it("quando lota, a saída vem junto — limite sem saída é parede", () => {
    const f = fraseDaSaida_pacientes(lotado);
    expect(f).toMatch(/[Aa]rquivar/);
    expect(f).toMatch(/devolve a vaga/);
  });

  it("...e a saída diz que a ficha continua guardada", () => {
    // O medo certo de quem lê "arquivar" é perder o histórico — que é
    // obrigação de guarda de cinco anos, não consumo de plano. Se a frase não
    // disser isso, ninguém arquiva e o limite vira parede na prática.
    expect(fraseDaSaida_pacientes(lotado)).toMatch(/continua guardada|histórico/);
  });

  it("a frase não empurra o plano pago", () => {
    // "Mude de plano" é uma saída legítima e está na mensagem do banco, onde
    // ela é resposta a uma ação bloqueada. Na tela, em repouso, o limite
    // informa — não vende.
    const todas = [fraseDosPacientes(lotado), fraseDaSaida_pacientes(lotado)].join(" ");
    expect(todas).not.toMatch(/assine|contrate|upgrade|R\$|aproveite/i);
  });

  it("sem limite, quarenta pacientes não geram aviso", () => {
    expect(fraseDaSaida_pacientes(semLimite)).toBe("");
  });
});
