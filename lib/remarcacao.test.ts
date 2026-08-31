import { describe, it, expect } from "vitest";
import {
  porqueDaOpcao,
  ganhoDaOpcao,
  rotuloPublico,
  quando,
  convite,
  custoEmCentavos,
  PROIBIDAS_NO_CONVITE,
  type Custo,
} from "@/lib/remarcacao";

describe("por que cada hora está na lista", () => {
  it("cada motivo tem uma explicação, e ela diz o que a hora faz pela agenda", () => {
    expect(porqueDaOpcao("buraco")).toContain("buraco");
    expect(porqueDaOpcao("grade")).toContain("vazia");
    expect(porqueDaOpcao("adjacente")).toContain("encosta");
  });

  it("motivo desconhecido não inventa explicação", () => {
    expect(porqueDaOpcao("qualquer")).toBe("");
  });

  it("o buraco é o que tapa; o adjacente só não atrapalha", () => {
    expect(ganhoDaOpcao("buraco")).toBe("tapa");
    expect(ganhoDaOpcao("grade")).toBe("aproveita");
    expect(ganhoDaOpcao("adjacente")).toBe("neutro");
  });

  it("a explicação do motivo nunca vai para o lado do paciente", () => {
    // `porqueDaOpcao` conta que **outra pessoa** desmarcou aquela hora. É
    // informação sobre um terceiro, e por isso só existe na tela dela — o
    // teste guarda a fronteira: nada aqui pode entrar no convite.
    for (const m of ["buraco", "grade", "adjacente"]) {
      expect(convite("Maria Reis", "https://x/y")).not.toContain(porqueDaOpcao(m));
    }
  });
});

describe("o que a página pública diz", () => {
  const ESTADOS = ["inexistente", "aberta", "escolhida", "expirada", "cancelada"] as const;

  it("todo estado tem uma frase", () => {
    for (const e of ESTADOS) {
      expect(rotuloPublico(e).length).toBeGreaterThan(10);
    }
  });

  it("nenhuma frase nomeia terapia, sessão ou consultório", () => {
    for (const e of ESTADOS) {
      const t = rotuloPublico(e).toLowerCase();
      for (const p of PROIBIDAS_NO_CONVITE) {
        expect(t).not.toContain(p);
      }
    }
  });

  it("nenhuma frase pressiona", () => {
    for (const e of ESTADOS) {
      const t = rotuloPublico(e).toLowerCase();
      for (const p of ["urgente", "última chance", "imediat", "obrigat", "!"]) {
        expect(t).not.toContain(p);
      }
    }
  });
});

describe("o convite que ela manda", () => {
  it("usa só o primeiro nome", () => {
    expect(convite("Maria Reis Alcântara", "https://x/y")).toContain("Oi, Maria.");
    expect(convite("Maria Reis Alcântara", "https://x/y")).not.toContain("Alcântara");
  });

  it("leva o link inteiro", () => {
    expect(convite("Maria", "https://sessoes.com.br/p/remarcar/abc")).toContain(
      "https://sessoes.com.br/p/remarcar/abc",
    );
  });

  it("não nomeia nada — a tela de bloqueio é lida por quem passa", () => {
    const t = convite("Maria", "https://x/y").toLowerCase();
    for (const p of PROIBIDAS_NO_CONVITE) {
      expect(t).not.toContain(p);
    }
  });

  it("nome vazio não produz 'Oi, .'", () => {
    expect(convite("   ", "https://x/y")).toContain("Oi, tudo bem.");
  });
});

describe("as horas na tela", () => {
  it("sai no fuso de São Paulo, sempre", () => {
    // 2026-03-03T18:00:00Z = terça, 3 de março às 15:00 em São Paulo.
    const t = quando("2026-03-03T18:00:00Z");
    expect(t).toContain("terça");
    expect(t).toContain("15:00");
    expect(t).toContain("março");
  });

  it("data impossível não vira 'Invalid Date' na cara da pessoa", () => {
    expect(quando("banana")).toBe("—");
    expect(quando(null)).toBe("—");
    expect(quando(undefined)).toBe("—");
  });
});

describe("o aviso de custo", () => {
  const base: Custo = { tardia: true, modelo: "avulso", valor: "100.00", texto: "x" };

  it("numeric vem do banco como string e vira centavos inteiros", () => {
    expect(custoEmCentavos(base)).toBe(10_000);
    expect(custoEmCentavos({ ...base, valor: "0" })).toBe(0);
    expect(custoEmCentavos({ ...base, valor: 62.5 })).toBe(6_250);
  });

  it("sem custo, zero — e nunca NaN na tela", () => {
    expect(custoEmCentavos(null)).toBe(0);
    expect(custoEmCentavos({ ...base, valor: "" })).toBe(0);
    expect(custoEmCentavos({ ...base, valor: "abacaxi" })).toBe(0);
  });

  it("arredonda meio-centavo para longe do zero, como o resto do projeto", () => {
    expect(custoEmCentavos({ ...base, valor: "0.005" })).toBe(1);
  });
});
