import { describe, it, expect } from "vitest";
import {
  ordemDeTentativa,
  pesoDaClasse,
  furaJanelaDeSilencio,
  NA_MAO,
  type Situacao,
} from "./roteamento";

const TODOS = ["whatsapp", "email", "sms"] as const;

/** A cascata como o banco a semeia hoje — e ela é configuração, não código. */
const ROTA_URGENTE = ["whatsapp", "email", "sms"] as const;
const ROTA_ROTINA = ["whatsapp", "email"] as const;

const base: Situacao = {
  preferido: "whatsapp",
  classe: "rotina",
  disponiveis: TODOS,
  rota: ROTA_ROTINA,
};

describe("ordemDeTentativa", () => {
  it("começa pelo canal que a paciente escolheu", () => {
    expect(ordemDeTentativa(base)[0]).toBe("whatsapp");
    expect(ordemDeTentativa({ ...base, preferido: "email" })[0]).toBe("email");
  });

  it("a mão dela é sempre o último degrau, nunca o segundo", () => {
    for (const classe of ["urgente", "rotina", "documento"] as const) {
      const ordem = ordemDeTentativa({ ...base, classe });
      expect(ordem.at(-1), classe).toBe(NA_MAO);
      expect(ordem.indexOf(NA_MAO), classe).toBe(ordem.length - 1);
    }
  });

  /*
    O SMS custa 40× o e-mail (`precos_canal`: 8.000 contra 200 milésimos de
    centavo). Ele é o degrau antes do silêncio, e só para urgente.
  */
  it("a rota configurada decide os degraus — o SMS entra onde ela mandar", () => {
    expect(ordemDeTentativa({ ...base, classe: "rotina", rota: ROTA_ROTINA })).not.toContain("sms");

    const urgente = ordemDeTentativa({ ...base, classe: "urgente", rota: ROTA_URGENTE });
    expect(urgente).toEqual(["whatsapp", "email", "sms", NA_MAO]);
  });

  /*
    A decisão "vale gastar quarenta vezes mais para não perder esta oferta?" é
    de risco contra dinheiro, e sai de `rota_do_canal` — não de um commit. Tirar
    o SMS da cascata é uma linha do banco, e a ordem muda sem tocar em código.
  */
  it("tirar o SMS da rota tira o degrau, sem tocar em código", () => {
    const semSms = ordemDeTentativa({ ...base, classe: "urgente", rota: ["whatsapp", "email"] });
    expect(semSms).toEqual(["whatsapp", "email", NA_MAO]);
  });

  it("sem rota configurada, o padrão não inventa degrau caro", () => {
    const semRota = ordemDeTentativa({ ...base, classe: "urgente", rota: undefined });
    expect(semRota).toEqual(["whatsapp", NA_MAO]);
  });

  it("a rota pode pôr o e-mail na frente do SMS ou o contrário", () => {
    const invertida = ordemDeTentativa({
      ...base, classe: "urgente", preferido: "whatsapp", rota: ["sms", "email"],
    });
    expect(invertida).toEqual(["whatsapp", "sms", "email", NA_MAO]);
  });

  it("documento não tem cascata: e-mail ou a mão dela, e nada de canal não oficial", () => {
    const ordem = ordemDeTentativa({ ...base, classe: "documento" });
    expect(ordem).toEqual(["email", NA_MAO]);
    expect(ordem).not.toContain("whatsapp");
    expect(ordem).not.toContain("sms");
  });

  it("documento sem e-mail espera a mão dela — nunca desce para o WhatsApp", () => {
    const ordem = ordemDeTentativa({ ...base, classe: "documento", disponiveis: ["whatsapp", "sms"] });
    expect(ordem).toEqual([NA_MAO]);
  });

  it("canal sem provedor não é degrau, nem que a rota o peça", () => {
    expect(ordemDeTentativa({ ...base, classe: "urgente", rota: ROTA_URGENTE, disponiveis: ["email"] }))
      .toEqual(["email", NA_MAO]);
    expect(ordemDeTentativa({ ...base, classe: "urgente", rota: ROTA_URGENTE, disponiveis: [] }))
      .toEqual([NA_MAO]);
  });

  it("canal com disjuntor aberto sai da ordem, mesmo estando na rota", () => {
    const ordem = ordemDeTentativa({
      ...base, classe: "urgente", rota: ROTA_URGENTE, interrompidos: ["whatsapp"],
    });
    expect(ordem).toEqual(["email", "sms", NA_MAO]);
  });

  it("sem telefone não se tenta WhatsApp nem SMS; sem e-mail não se tenta e-mail", () => {
    expect(ordemDeTentativa({ ...base, classe: "urgente", rota: ROTA_URGENTE, temTelefone: false }))
      .toEqual(["email", NA_MAO]);
    expect(ordemDeTentativa({ ...base, classe: "urgente", rota: ROTA_URGENTE, temEmail: false }))
      .toEqual(["whatsapp", "sms", NA_MAO]);
  });

  it("nunca repete um canal, nem quando a rota repete o preferido", () => {
    const ordem = ordemDeTentativa({
      ...base, preferido: "email", classe: "urgente", rota: ROTA_URGENTE,
    });
    expect(new Set(ordem).size).toBe(ordem.length);
    expect(ordem).toEqual(["email", "whatsapp", "sms", NA_MAO]);
  });

  /*
    O que a rota NÃO pode: documento por canal não oficial. É a fronteira 8, e
    ela não é configuração — nem por engano de quem edita a tabela.
  */
  it("a rota não fura a fronteira do documento", () => {
    const ordem = ordemDeTentativa({
      ...base, classe: "documento", rota: ["whatsapp", "sms", "email"],
    });
    expect(ordem).toEqual(["email", NA_MAO]);
  });
});

describe("pesoDaClasse", () => {
  it("urgente fura a fila: FIFO com duzentos lembretes na frente fecha a vaga vazia", () => {
    expect(pesoDaClasse("urgente")).toBeLessThan(pesoDaClasse("rotina"));
    expect(pesoDaClasse("rotina")).toBeLessThan(pesoDaClasse("documento"));
  });
});

describe("furaJanelaDeSilencio", () => {
  it("rotina e documento nunca furam — a janela existe para não acordar ninguém", () => {
    expect(furaJanelaDeSilencio("rotina", 10, 300)).toBe(false);
    expect(furaJanelaDeSilencio("documento", 10, 300)).toBe(false);
  });

  it("urgente cuja vaga expira antes do fim do silêncio não espera as 8h", () => {
    expect(furaJanelaDeSilencio("urgente", 40, 300)).toBe(true);
  });

  it("urgente que aguenta até o fim do silêncio espera", () => {
    expect(furaJanelaDeSilencio("urgente", 600, 300)).toBe(false);
  });

  it("sem tolerância declarada, espera — na dúvida não se acorda paciente", () => {
    expect(furaJanelaDeSilencio("urgente", null, 300)).toBe(false);
    expect(furaJanelaDeSilencio("urgente", 0, 300)).toBe(false);
  });
});

// ================================================ o custo, que estava no banco

import { custoDaRota, precoEmReais, fraseDoCusto, type Preco } from "./roteamento";

/*
  `precos_canal` está no banco desde sempre — em milésimos de centavo, e-mail
  200, WhatsApp 4.500, SMS 8.000 — e o roteamento nunca olhou para ela. O SMS
  custa quarenta vezes o e-mail para chegar ao mesmo lugar em quase todo caso.
*/
const PRECOS: Preco[] = [
  { canal: "email", centavosMilesimos: 200 },
  { canal: "whatsapp", centavosMilesimos: 4500 },
  { canal: "sms", centavosMilesimos: 8000 },
];

describe("o custo da cascata", () => {
  it("soma o pior caso, que é o número que decide a rota", () => {
    expect(custoDaRota(["whatsapp", "email", "sms"], PRECOS)).toBe(12700);
    expect(custoDaRota(["whatsapp", "email"], PRECOS)).toBe(4700);
    expect(custoDaRota([], PRECOS)).toBe(0);
  });

  it("canal sem preço declarado não inventa número", () => {
    expect(custoDaRota(["sms"], [])).toBe(0);
  });

  it("a unidade é milésimo de centavo, e três casas não arredondam o e-mail para zero", () => {
    expect(precoEmReais(200)).toContain("0,002");
    expect(precoEmReais(8000)).toContain("0,080");
  });

  it("a frase nomeia o degrau mais caro — o total esconde que um responde por quase tudo", () => {
    const f = fraseDoCusto(["whatsapp", "email", "sms"], PRECOS);
    expect(f).toContain("sms");
    expect(f).toContain("63%");
    expect(f).toContain("pior caso");
  });

  it("sem degrau nenhum, diz isso em vez de mostrar zero", () => {
    expect(fraseDoCusto([], PRECOS)).toBe("Sem degrau nenhum configurado.");
  });
});
