import { describe, it, expect } from "vitest";
import {
  renderizar,
  CORPOS,
  FAMILIAS,
  PROIBIDAS_NO_DISCRETO,
  type Familia,
  type Modo,
} from "./templates";

/**
 * A fronteira D3 escrita como teste — e, junto dela, as regras da Meta.
 *
 * O modo discreto não é enfeite de interface: é a promessa que faz uma pessoa
 * aceitar receber mensagem no celular que ela divide com a família. Um template
 * novo que a esqueça reprova aqui antes de chegar perto de um número real.
 *
 * As regras da Meta estão aqui pelo mesmo motivo prático: template reprovado
 * reinicia dias de espera de aprovação (risco R4), e o defeito é sempre visível
 * no texto — só ninguém olha.
 */

const INICIO = "2026-03-03T18:00:00.000Z"; // terça, 15h em São Paulo
const EXPIRA = "2026-03-03T19:20:00.000Z";
const MODOS: Modo[] = ["discreto", "completo"];

function discreto(familia: Familia) {
  return renderizar(familia, {
    nome: "Maria Fernanda Reis",
    modo: "discreto",
    inicio: INICIO,
    expira_em: EXPIRA,
    profissional: "Ana Paula Ferreira",
  });
}

describe("modo discreto (D3)", () => {
  it.each(FAMILIAS)("%s não diz do que se trata", (familia) => {
    const r = discreto(familia);
    const texto = `${r.texto} ${r.assunto}`.toLowerCase();

    for (const palavra of PROIBIDAS_NO_DISCRETO) {
      expect(texto).not.toContain(palavra);
    }
  });

  it.each(FAMILIAS)("%s não cita o profissional, mesmo recebendo o nome", (familia) => {
    const r = discreto(familia);
    expect(r.texto).not.toContain("Ana Paula");
    expect(r.variaveis.join(" ")).not.toContain("Ana Paula");
  });

  it.each(FAMILIAS)("%s usa só o primeiro nome de quem recebe", (familia) => {
    const r = discreto(familia);
    expect(r.texto).toContain("Maria");
    expect(r.texto).not.toContain("Fernanda");
    expect(r.texto).not.toContain("Reis");
  });

  it("é o modo padrão: sem `modo`, a mensagem sai discreta", () => {
    const r = renderizar("lembrete_de_sessao", { nome: "Caio", inicio: INICIO });
    expect(r.modo).toBe("discreto");
    expect(r.texto.toLowerCase()).not.toContain("sessão");
  });

  it("valor estranho em `modo` também cai no discreto", () => {
    const r = renderizar("lembrete_de_sessao", {
      nome: "Caio",
      modo: "completo_mesmo_por_favor",
      inicio: INICIO,
      profissional: "Ana Paula",
    });
    expect(r.modo).toBe("discreto");
  });
});

describe("na dúvida, cai para o mais discreto", () => {
  it.each(FAMILIAS)(
    "%s: modo completo sem o nome do profissional vira discreto",
    (familia) => {
      const r = renderizar(familia, {
        nome: "Maria",
        modo: "completo",
        inicio: INICIO,
        expira_em: EXPIRA,
      });
      expect(r.modo).toBe("discreto");
      expect(r.nomeDoTemplate).toContain("discreto");
      expect(r.texto.toLowerCase()).not.toContain("sessão");
    },
  );

  it("nome do profissional em branco não conta como nome", () => {
    const r = renderizar("lembrete_de_sessao", {
      nome: "Maria",
      modo: "completo",
      inicio: INICIO,
      profissional: "   ",
    });
    expect(r.modo).toBe("discreto");
  });
});

describe("modo completo", () => {
  it.each(FAMILIAS)("%s cita o profissional quando o nome vem junto", (familia) => {
    const r = renderizar(familia, {
      nome: "Maria",
      modo: "completo",
      inicio: INICIO,
      expira_em: EXPIRA,
      profissional: "Ana Paula",
    });
    expect(r.modo).toBe("completo");
    expect(r.texto).toContain("Ana Paula");
    expect(r.variaveis).toContain("Ana Paula");
  });
});

describe("as regras da Meta (reprovar aqui é barato; lá custa dias)", () => {
  it.each(MODOS)("nenhum corpo %s começa ou termina em variável", (modo) => {
    for (const familia of FAMILIAS) {
      const corpo = CORPOS[modo][familia].trim();
      expect(corpo.startsWith("{{"), `${modo}/${familia} começa em variável`).toBe(false);
      expect(corpo.endsWith("}}"), `${modo}/${familia} termina em variável`).toBe(false);
    }
  });

  it.each(MODOS)("nenhum corpo %s tem duas variáveis coladas", (modo) => {
    for (const familia of FAMILIAS) {
      expect(CORPOS[modo][familia]).not.toMatch(/\}\}\s*\{\{/);
    }
  });

  it.each(MODOS)("as variáveis do corpo %s são 1..n, sem buraco", (modo) => {
    for (const familia of FAMILIAS) {
      const usadas = [...CORPOS[modo][familia].matchAll(/\{\{(\d+)\}\}/g)]
        .map((m) => Number(m[1]))
        .sort((a, b) => a - b);
      const unicas = [...new Set(usadas)];
      expect(unicas, `${modo}/${familia}`).toEqual(
        unicas.map((_, i) => i + 1),
      );
    }
  });

  it.each(FAMILIAS)("%s manda exatamente as variáveis que o corpo pede", (familia) => {
    for (const modo of MODOS) {
      const r = renderizar(familia, {
        nome: "Maria",
        modo,
        inicio: INICIO,
        expira_em: EXPIRA,
        profissional: "Ana Paula",
      });
      const pedidas = new Set(
        [...CORPOS[r.modo][familia].matchAll(/\{\{(\d+)\}\}/g)].map((m) => m[1]),
      );
      expect(r.variaveis).toHaveLength(pedidas.size);
    }
  });

  it.each(FAMILIAS)("%s não deixa nenhum {{n}} por preencher", (familia) => {
    for (const modo of MODOS) {
      const r = renderizar(familia, {
        nome: "Maria",
        modo,
        inicio: INICIO,
        expira_em: EXPIRA,
        profissional: "Ana Paula",
      });
      expect(r.texto).not.toMatch(/\{\{\d+\}\}/);
    }
  });

  it("nenhuma variável sai vazia — a Meta recusa parâmetro em branco", () => {
    const r = renderizar("oferta_de_vaga", { nome: "", modo: "completo" });
    for (const v of r.variaveis) {
      expect(v.trim().length).toBeGreaterThan(0);
    }
  });
});

describe("o horário é sempre de São Paulo (lei nº 3)", () => {
  it.each(FAMILIAS)("%s mostra 15:00, não 18:00 UTC", (familia) => {
    const r = renderizar(familia, { nome: "Maria", inicio: INICIO });
    expect(r.texto).toContain("15:00");
    expect(r.texto).not.toContain("18:00");
  });

  it("o prazo da oferta também", () => {
    const r = renderizar("oferta_de_vaga", {
      nome: "Maria",
      inicio: INICIO,
      expira_em: EXPIRA,
    });
    expect(r.texto).toContain("até às 16:20");
  });

  it("sem prazo, a frase continua em português", () => {
    const r = renderizar("oferta_de_vaga", { nome: "Maria", inicio: INICIO });
    expect(r.texto).toContain("até o fim do dia");
  });
});

describe("o que chega quebrado não vira mensagem quebrada", () => {
  it("data inválida não imprime 'Invalid Date'", () => {
    const r = renderizar("lembrete_de_sessao", { nome: "Maria", inicio: "amanhã" });
    expect(r.texto).not.toMatch(/invalid/i);
    expect(r.texto).toContain("no horário combinado");
  });

  it.each(FAMILIAS)("%s sem dado nenhum não imprime undefined/null/NaN", (familia) => {
    const r = renderizar(familia, {});
    expect(r.texto).not.toMatch(/undefined|null|NaN/);
  });

  it("template fora das quatro famílias é recusado", () => {
    expect(() => renderizar("promocao", { nome: "Maria" })).toThrow(/desconhecido/i);
  });
});

describe("o nome do template segue o modo", () => {
  it.each(FAMILIAS)("%s tem um nome por modo", (familia) => {
    const d = renderizar(familia, { nome: "Maria", modo: "discreto" });
    const c = renderizar(familia, {
      nome: "Maria",
      modo: "completo",
      profissional: "Ana Paula",
    });
    expect(d.nomeDoTemplate).toBe(`sessoes_${familia}_discreto`);
    expect(c.nomeDoTemplate).toBe(`sessoes_${familia}_completo`);
  });
});
