import { describe, it, expect } from "vitest";
import {
  calcular,
  nivelDaFaixa,
  fraseDaFaixa,
  fraseDoQueNaoMuda,
  fraseDoConvite,
  fraseDoRestante,
  fraseDoQueConta,
  SEM_FAIXA,
  type Faixa,
} from "./faixa";

// Os mesmos valores esperados da suíte 0060 no banco. Se a aritmética divergir,
// uma das duas está errada — e é para isso que o gêmeo existe.
const gratis = (usadas: number, prof = 1) => calcular(8, prof, usadas);
const pro = (usadas: number) => calcular(200, 1, usadas, true);

describe("a aritmética, gêmea de faixa_da_conta", () => {
  it("conta nova: faixa de 8, nada gasto, nada acima", () => {
    const f = gratis(0);
    expect(f.tem_faixa).toBe(true);
    expect(f.limite).toBe(8);
    expect(f.limite_total).toBe(8);
    expect(f.restantes).toBe(8);
    expect(f.acima).toBe(false);
    expect(f.pct).toBe(0);
  });

  it("multiplica por profissional que atende — é assim que a Clínica existe sem segunda coluna", () => {
    expect(gratis(11, 2).limite_total).toBe(16);
    expect(gratis(11, 2).acima).toBe(false);
    expect(gratis(11, 1).acima).toBe(true);
  });

  it("uma conta sem profissional nenhum tem a faixa de uma pessoa, e não faixa zero", () => {
    // Faixa zero faria `acima` ser verdade para quem não atendeu ninguém — o
    // produto acusando alguém de estourar um limite de nada.
    expect(gratis(0, 0).limite_total).toBe(8);
    expect(gratis(0, 0).acima).toBe(false);
  });

  it("restantes nunca é negativo", () => {
    expect(gratis(20).restantes).toBe(0);
  });

  it("acima é estritamente maior — bater no número não é passar dele", () => {
    expect(gratis(8).acima).toBe(false);
    expect(gratis(9).acima).toBe(true);
  });

  it("pct passa de 100 e não estanca", () => {
    // Mesma recusa do P5: passar do declarado é fato. Estancar em 100 esconde a
    // informação de quem precisa dela.
    expect(gratis(11).pct).toBe(137);
    expect(gratis(6).pct).toBe(75);
  });

  it("plano sem faixa continua contando as sessões, e não finge que são zero", () => {
    const f = calcular(null, 1, 42);
    expect(f.tem_faixa).toBe(false);
    expect(f.limite_total).toBeNull();
    expect(f.usadas).toBe(42);
    expect(f.acima).toBe(false);
  });

  it("o valor de repouso não inventa faixa nenhuma", () => {
    expect(SEM_FAIXA.tem_faixa).toBe(false);
    expect(SEM_FAIXA.acima).toBe(false);
  });
});

describe("nivelDaFaixa — nem cedo demais, nem tarde demais", () => {
  it("num mês normal, silêncio", () => {
    expect(nivelDaFaixa(gratis(0))).toBe("nenhum");
    expect(nivelDaFaixa(gratis(5))).toBe("nenhum");
  });

  it("a partir de 70% avisa", () => {
    expect(nivelDaFaixa(gratis(6))).toBe("perto");
  });

  it("acima é estado, não aviso", () => {
    expect(nivelDaFaixa(gratis(11))).toBe("acima");
  });

  it("o fair-use NUNCA vira aviso — ele é número meu, não faixa dela", () => {
    // A página de preços diz que o Pro não tem faixa. Avisar a pessoa de que
    // ela está perto de um limite que a página diz não existir seria a página
    // mentindo numa das duas pontas.
    expect(nivelDaFaixa(pro(199))).toBe("nenhum");
    expect(nivelDaFaixa(pro(400))).toBe("nenhum");
    expect(fraseDaFaixa(pro(400))).toBe("");
  });
});

describe("as frases — dizem o que NÃO muda antes de qualquer outra coisa", () => {
  it("plano sem faixa não gera frase de estado", () => {
    expect(fraseDaFaixa(calcular(null, 1, 42))).toBe("");
    expect(fraseDoRestante(calcular(null, 1, 42))).toMatch(/não tem faixa/);
  });

  it("no meio do mês diz o número, sem drama", () => {
    expect(fraseDaFaixa(gratis(6))).toBe("6 de 8 sessões este mês.");
  });

  it("uma só, no singular", () => {
    expect(fraseDaFaixa(gratis(1))).toBe("1 de 8 sessão este mês.");
    expect(fraseDoRestante(gratis(7))).toBe("Falta 1 sessão para o fim da faixa deste mês.");
  });

  it("acima da faixa, a frase mais importante é a do que continua funcionando", () => {
    const f = gratis(11);
    const nada = fraseDoQueNaoMuda(f);
    expect(nada).not.toBe("");
    expect(nada).toMatch(/agenda continua/i);
    expect(nada).toMatch(/fila continua/i);
    expect(nada).toMatch(/mensagens.*continuam saindo/i);
  });

  it("...e diz, com todas as letras, que não há cobrança por sessão extra", () => {
    // É o atrito da iClinic (R$ 0,31 por mensagem excedente) que a política do
    // claude/25 ataca de frente. Se um dia alguém puser excedente, esta frase
    // vira mentira e o teste cai junto.
    expect(fraseDoQueNaoMuda(gratis(11))).toMatch(/não há cobrança/i);
  });

  it("o convite é convite: fala do próximo ciclo, não de agora", () => {
    const c = fraseDoConvite(gratis(11));
    expect(c).toMatch(/próximo ciclo/i);
    expect(c).toMatch(/vale olhar/i);
  });

  it("nenhuma frase acusa a psicóloga de ter trabalhado demais", () => {
    const f = gratis(30);
    const todas = [
      fraseDaFaixa(f),
      fraseDoQueNaoMuda(f),
      fraseDoConvite(f),
      fraseDoRestante(f),
    ].join(" ");
    expect(todas).not.toMatch(/excedeu|violou|indevid|abus|irregular|atenção!/i);
  });

  it("nem transforma a faixa em vitrine", () => {
    const f = gratis(11);
    const todas = [fraseDaFaixa(f), fraseDoQueNaoMuda(f), fraseDoConvite(f)].join(" ");
    expect(todas).not.toMatch(/R\$|assine agora|aproveite|oferta|desconto/i);
  });

  it("abaixo da faixa não há convite nenhum", () => {
    expect(fraseDoConvite(gratis(3))).toBe("");
    expect(fraseDoQueNaoMuda(gratis(3))).toBe("");
  });
});

describe("o que conta, dito para quem for conferir na mão", () => {
  it("nomeia a desmarcação no prazo como a exceção", () => {
    // Ela vai contar na cabeça e chegar a outro número. Um número que ela não
    // consegue reproduzir é um número em que ela não confia.
    expect(fraseDoQueConta()).toMatch(/dentro do prazo não conta/i);
    expect(fraseDoQueConta()).toMatch(/falta/i);
  });
});

describe("a faixa não é uma cerca — e isso é testável do lado do app", () => {
  it("nenhuma função deste módulo devolve permissão", () => {
    // O módulo inteiro só descreve. Se um dia aparecer aqui um `podeCriarSessao`
    // ou um `bloqueado`, este teste é o lugar onde alguém explica por quê.
    const f: Faixa = gratis(999);
    const chaves = Object.keys(f);
    expect(chaves).not.toContain("bloqueado");
    expect(chaves).not.toContain("pode_criar");
    expect(chaves).not.toContain("travado");
  });
});
