import { describe, it, expect } from "vitest";
import {
  renderizar,
  FAMILIAS,
  PROIBIDAS_NO_DISCRETO,
  type Familia,
} from "./templates";

/**
 * A fronteira D3 escrita como teste.
 *
 * O modo discreto não é um enfeite de interface: é a promessa que faz uma pessoa
 * aceitar receber mensagem no celular que ela divide com a família. Um template
 * novo que a esqueça reprova aqui antes de chegar perto de um número real.
 */

const INICIO = "2026-03-03T18:00:00.000Z"; // terça, 15h em São Paulo
const EXPIRA = "2026-03-03T19:20:00.000Z";

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
    const texto = (
      discreto(familia).texto +
      " " +
      discreto(familia).assunto
    ).toLowerCase();

    for (const palavra of PROIBIDAS_NO_DISCRETO) {
      expect(texto).not.toContain(palavra);
    }
  });

  it.each(FAMILIAS)("%s não cita o profissional, mesmo recebendo o nome", (familia) => {
    const r = discreto(familia);
    expect(r.texto).not.toContain("Ana Paula");
    expect(r.texto).not.toContain("Ferreira");
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
    });
    expect(r.modo).toBe("discreto");
  });
});

describe("modo completo", () => {
  it("cita o profissional quando o nome vem junto", () => {
    const r = renderizar("lembrete_de_sessao", {
      nome: "Maria",
      modo: "completo",
      inicio: INICIO,
      profissional: "Ana Paula",
    });
    expect(r.texto).toContain("Ana Paula");
    expect(r.variaveis).toContain("Ana Paula");
  });

  it("sem o nome do profissional, a frase continua correta em português", () => {
    const r = renderizar("lembrete_de_sessao", {
      nome: "Maria",
      modo: "completo",
      inicio: INICIO,
    });
    expect(r.texto).not.toContain("com  ");
    expect(r.texto).not.toContain("undefined");
    expect(r.texto).toContain("sessão");
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
    expect(r.texto).toContain("16:20");
  });
});

describe("o que chega quebrado não vira mensagem quebrada", () => {
  it("data inválida não imprime 'Invalid Date'", () => {
    const r = renderizar("lembrete_de_sessao", { nome: "Maria", inicio: "amanhã" });
    expect(r.texto).not.toMatch(/invalid/i);
    expect(r.texto).toContain("no horário combinado");
  });

  it("sem data nenhuma, idem", () => {
    const r = renderizar("lembrete_de_sessao", { nome: "Maria" });
    expect(r.texto).not.toMatch(/undefined|null|NaN/);
  });

  it("sem nome, não sai 'Oi undefined'", () => {
    const r = renderizar("lembrete_de_sessao", {});
    expect(r.texto).not.toMatch(/undefined/);
  });

  it("template fora das quatro famílias é recusado", () => {
    expect(() => renderizar("promocao", { nome: "Maria" })).toThrow(/desconhecido/i);
  });
});

describe("o nome do template segue o modo", () => {
  it.each(FAMILIAS)("%s tem um nome por modo", (familia) => {
    const d = renderizar(familia, { nome: "Maria", modo: "discreto" });
    const c = renderizar(familia, { nome: "Maria", modo: "completo" });
    expect(d.nomeDoTemplate).toBe(`sessoes_${familia}_discreto`);
    expect(c.nomeDoTemplate).toBe(`sessoes_${familia}_completo`);
    expect(d.nomeDoTemplate).not.toBe(c.nomeDoTemplate);
  });
});
