import { describe, it, expect } from "vitest";
import {
  renderizar,
  CORPOS,
  FAMILIAS,
  PROIBIDAS_NO_DISCRETO,
  PROIBIDAS_NA_COBRANCA,
  PROIBIDAS_NA_REGUA,
  type Familia,
  type Modo,
} from "./templates";
import { formatar } from "@/lib/dinheiro";

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

describe("a cobrança não constrange (D2)", () => {
  const MODOS_COBRANCA = MODOS.map((modo) =>
    renderizar("aviso_de_cobranca", {
      nome: "Maria",
      modo,
      inicio: INICIO,
      profissional: "Ana Paula",
      valor_centavos: 10_000,
    }),
  );

  it.each(MODOS_COBRANCA)("$modo: nenhuma palavra de vergonha ou de dívida", (r) => {
    const texto = `${r.texto} ${r.assunto}`.toLowerCase();
    for (const palavra of PROIBIDAS_NA_COBRANCA) {
      expect(texto, `achei "${palavra}"`).not.toContain(palavra);
    }
  });

  it.each(MODOS_COBRANCA)("$modo: diz o valor e remete ao combinado", (r) => {
    // Comparado com o formatador do projeto de propósito: ele usa espaço fixo
    // (U+00A0) entre "R$" e o número, e um literal digitado à mão não bate.
    expect(r.texto).toContain(formatar(10_000));
    expect(r.texto).toContain("combinado");
  });

  it.each(MODOS_COBRANCA)("$modo: devolve a palavra à pessoa", (r) => {
    expect(r.texto).toContain("responder aqui");
  });

  it("sem valor, não inventa número nem imprime vazio", () => {
    const r = renderizar("aviso_de_cobranca", { nome: "Maria", inicio: INICIO });
    expect(r.texto).toContain("o valor combinado");
    expect(r.texto).not.toMatch(/R\$\s*(?![\d])/);
  });
});

describe("a régua não endurece (D6)", () => {
  const REGUA = MODOS.map((modo) =>
    renderizar("lembrete_de_pagamento", {
      nome: "Maria",
      modo,
      profissional: "Ana Paula",
      valor_centavos: 30_000,
      quantidade: 3,
    }),
  );

  it.each(REGUA)("$modo: nenhuma ameaça, nenhum prazo final", (r) => {
    const texto = `${r.texto} ${r.assunto}`.toLowerCase();
    for (const palavra of [...PROIBIDAS_NA_REGUA, ...PROIBIDAS_NA_COBRANCA]) {
      expect(texto, `achei "${palavra}"`).not.toContain(palavra);
    }
  });

  it.each(REGUA)("$modo: o total é um só, e os horários vêm por extenso", (r) => {
    expect(r.texto).toContain(formatar(30_000));
    expect(r.texto).toContain("três horários");
  });

  it.each(REGUA)("$modo: termina devolvendo a palavra", (r) => {
    expect(r.texto).toContain("responder aqui");
  });

  it("o passo do lembrete não aparece no texto — o tom não muda", () => {
    const primeiro = renderizar("lembrete_de_pagamento", {
      nome: "Maria", valor_centavos: 10_000, quantidade: 1, passo: 1,
    });
    const terceiro = renderizar("lembrete_de_pagamento", {
      nome: "Maria", valor_centavos: 10_000, quantidade: 1, passo: 3,
    });
    // Esta é a regra inteira da B18 numa asserção: o terceiro lembrete é
    // idêntico ao primeiro. Escalonar é o que cobrador faz.
    expect(terceiro.texto).toBe(primeiro.texto);
  });

  it("um horário fica no singular", () => {
    const r = renderizar("lembrete_de_pagamento", {
      nome: "Maria", valor_centavos: 10_000, quantidade: 1,
    });
    expect(r.texto).toContain("um horário");
    expect(r.texto).not.toContain("horários");
  });

  it("quantidade estranha não vira texto estranho", () => {
    for (const quantidade of [0, -3, 2.5, undefined, "muitos"]) {
      const r = renderizar("lembrete_de_pagamento", {
        nome: "Maria", valor_centavos: 10_000, quantidade: quantidade as number,
      });
      expect(r.texto).not.toMatch(/undefined|null|NaN|-\d/);
      expect(r.texto).toContain("horário");
    }
  });

  it("muitos horários usam o número, não uma palavra inventada", () => {
    const r = renderizar("lembrete_de_pagamento", {
      nome: "Maria", valor_centavos: 10_000, quantidade: 12,
    });
    expect(r.texto).toContain("12 horários");
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
  /**
   * Quais famílias falam de **um instante** — descoberto, não listado.
   *
   * Nem todas falam. O lembrete de pagamento cobre vários horários de uma vez,
   * então não nomeia nenhum; a oferta de vaga fixa fala de "às terças, 15h",
   * que se repete; e as duas do B36 falam de um período, não de uma sessão.
   *
   * A versão anterior disto era `SEM_INSTANTE = [...]`, escrita à mão — e ela
   * envelheceu na primeira build que acrescentou família: as duas novas caíram
   * na regra errada e o teste cobrou horário de uma mensagem que não tem
   * horário. A pergunta certa não é "quais são as exceções", é **"o texto muda
   * quando o instante muda?"**. Isso o teste pode perguntar sozinho.
   */
  const COM_HORARIO = FAMILIAS.filter((f) => {
    const a = renderizar(f, { nome: "Maria", inicio: INICIO }).texto;
    const b = renderizar(f, { nome: "Maria", inicio: "2026-03-04T18:00:00.000Z" }).texto;
    return a !== b;
  });

  it.each(COM_HORARIO)("%s mostra 15:00, não 18:00 UTC", (familia) => {
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

describe("a sétima família: o horário que se repete", () => {
  it("diz o dia no plural — é um compromisso, não uma hora", () => {
    const r = renderizar("oferta_de_vaga_fixa", {
      nome: "Maria Reis",
      horario_fixo: "terça, 15h",
      expira_em: "2026-03-04T13:00:00Z",
    });
    expect(r.texto).toContain("às terças, 15h");
    expect(r.texto).toContain("toda semana");
  });

  it("promete a conversa que vem depois — ninguém fica esperando confirmação", () => {
    // O aceite reserva a vaga e **não** cria combinado (0036). Se o texto
    // dissesse "está confirmado", a pessoa esperaria uma agenda que ainda não
    // existe; dizendo "eu falo com você", o silêncio seguinte é o combinado.
    const r = renderizar("oferta_de_vaga_fixa", { nome: "Maria", horario_fixo: "quinta, 9h" });
    expect(r.texto).toContain("falo com você");
    expect(r.texto).not.toContain("confirmado");
  });

  it("um dia que já termina em s não vira 'sábados s'", () => {
    const r = renderizar("oferta_de_vaga_fixa", { nome: "Maria", horario_fixo: "sábados, 10h" });
    expect(r.texto).toContain("às sábados, 10h");
    expect(r.texto).not.toContain("sábadoss");
  });

  it("sem rótulo, não inventa um dia", () => {
    const r = renderizar("oferta_de_vaga_fixa", { nome: "Maria" });
    expect(r.texto).toContain("no dia e hora combinados");
  });

  it("no modo discreto não nomeia a profissional nem a natureza do encontro", () => {
    const r = renderizar("oferta_de_vaga_fixa", {
      nome: "Maria",
      horario_fixo: "terça, 15h",
      modo: "discreto",
      profissional: "Ana Ferreira",
    });
    expect(r.modo).toBe("discreto");
    expect(r.texto).not.toContain("Ana Ferreira");
    for (const p of PROIBIDAS_NO_DISCRETO) {
      expect(r.texto.toLowerCase()).not.toContain(p);
    }
  });
});

/**
 * O espelho da lista de templates — e ele existe por causa de um defeito.
 *
 * O P3 criou `confirmacao_de_sessao` na tabela `templates` do banco e este
 * arquivo não soube. `renderizar()` lança para o que não está em `FAMILIAS`,
 * então toda confirmação enfileirada estouraria no worker — e o defeito era
 * dormente, porque `confirmacao_horas_antes` nasce nulo e ninguém tinha ligado
 * a confirmação ainda.
 *
 * A lista canônica está escrita **duas vezes de propósito**: aqui e na
 * verificação 2 da suíte SQL 0066. Não dá para ler o banco de um teste
 * unitário — o sandbox nem alcança o Supabase —, então a defesa é o espelho:
 * quem acrescentar template de um lado só reprova do outro.
 */
describe("as famílias são as mesmas do banco", () => {
  const NO_BANCO = [
    "aviso_de_cobranca",
    "aviso_de_desmarque",
    // As duas do B36 (migração 0073). Elas entraram no banco e aqui na mesma
    // build, que é a única forma de este espelho servir para alguma coisa.
    "aviso_de_pausa",
    "aviso_de_reajuste",
    "confirmacao_de_sessao",
    "encaixe_confirmado",
    "lembrete_de_pagamento",
    "lembrete_de_sessao",
    "oferta_de_vaga",
    "oferta_de_vaga_fixa",
  ];

  it("nem sobra nem falta família", () => {
    expect([...FAMILIAS].sort()).toEqual(NO_BANCO);
  });

  it("toda família renderiza nos dois modos, em vez de lançar", () => {
    // O defeito não era de conteúdo: era `renderizar` lançando. Este teste é o
    // que teria pegado, e ele varre em vez de listar.
    for (const familia of FAMILIAS) {
      for (const modo of ["discreto", "completo"] as const) {
        const r = renderizar(familia, {
          nome: "Ana Souza",
          modo,
          inicio: "2026-09-10T14:00:00.000Z",
          expira_em: "2026-09-10T12:00:00.000Z",
          profissional: "Karen Lima",
          valor_centavos: 20000,
          quantidade: 2,
          horario_fixo: "terça, 15h",
        });
        expect(r.texto.length, `${familia}/${modo}`).toBeGreaterThan(20);
        expect(r.texto, `${familia}/${modo}`).not.toMatch(/\{\{\d+\}\}/);
      }
    }
  });

  it("a confirmação pede resposta e NÃO carrega link", () => {
    // O link do P7 segue a regra do contrato (B19) e da remarcação (B21):
    // quem manda é ela, de um toque, do próprio WhatsApp. Pôr URL no corpo de
    // um template é risco de reprovação na Meta — e reprovação reinicia dias
    // de espera (risco R4) — para resolver uma coisa que já tem caminho.
    for (const modo of ["discreto", "completo"] as const) {
      const r = renderizar("confirmacao_de_sessao", {
        nome: "Ana",
        modo,
        inicio: "2026-09-10T14:00:00.000Z",
        profissional: "Karen",
      });
      expect(r.texto).toMatch(/SIM/);
      expect(r.texto).not.toMatch(/https?:|sessoes\.com\.br|\/p\//);
    }
  });

  it("o discreto da confirmação não cita a profissional nem a palavra sessão", () => {
    const r = renderizar("confirmacao_de_sessao", {
      nome: "Ana",
      modo: "discreto",
      inicio: "2026-09-10T14:00:00.000Z",
      profissional: "Karen",
    });
    expect(r.texto).not.toMatch(/Karen/);
    expect(r.texto).not.toMatch(/sessão/i);
    expect(r.texto).toMatch(/horário/);
  });
});
