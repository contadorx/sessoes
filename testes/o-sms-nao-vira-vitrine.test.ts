import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { CANAIS_OFERECIDOS, CANAIS } from "@/lib/paciente";

/**
 * O SMS é medida de crise, e medida de crise não vira item de menu.
 *
 * A DECISÃO, DE 03/09
 *
 * O canal existe, é construído e é testado — e **não aparece em tela nenhuma**.
 * Ele entra quando uma mensagem **urgente** não tem mais por onde sair, e só aí.
 *
 * O motivo está no banco desde sempre, em `precos_canal`, e em milésimos de
 * centavo: e-mail **200** · WhatsApp **4.500** · SMS **8.000**. O SMS custa
 * **quarenta vezes** o e-mail e chega ao mesmo lugar em quase todo caso. Como
 * último degrau antes do silêncio ele vale o preço; como opção de cadastro, é
 * uma conta que estoura sem ninguém ter pedido nada — e quem escolheria seria
 * justamente quem não tem como saber o que custa: a paciente, na pré-ficha.
 *
 * ONDE ELE ESTAVA, ANTES DESTA VARREDURA
 *
 * Em dois lugares que alguém vê: o cadastro da paciente (`CANAIS` inteiro no
 * `select`) e a **pré-ficha pública**, que é preenchida pela própria paciente.
 *
 * O que esta varredura **não** faz: proibir o valor `sms` no banco. Conta que já
 * escolheu SMS continua recebendo por SMS, e a cascata continua podendo usá-lo.
 * O que ela reprova é o SMS voltar a ser **oferecido**.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      arquivos(caminho, res);
    } else if (/\.tsx$/.test(e.name) && !/\.test\.tsx$/.test(e.name)) {
      res.push(caminho);
    }
  }
  return res;
}

function semComentarios(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
    .replace(/(^|[^:"'`\\])\/\/[^\n]*/g, (_, antes) => antes);
}

describe("o SMS não vira vitrine", () => {
  it("a lista oferecida não tem SMS, e a do banco continua tendo", () => {
    expect(CANAIS_OFERECIDOS).not.toContain("sms");
    expect(CANAIS).toContain("sms");
  });

  /*
    A varredura é sobre `<option value="sms">`, que é a forma de oferecer numa
    tela. O painel do operador é a exceção declarada: lá quem escolhe sou eu,
    não ela, e o operador precisa poder forçar o canal para investigar.
  */
  it("nenhuma tela da paciente ou dela oferece SMS como opção", () => {
    const oferecem: string[] = [];

    for (const arquivo of arquivos(join(RAIZ, "app")).concat(arquivos(join(RAIZ, "components")))) {
      if (arquivo.endsWith("NegocioAcoes.tsx")) continue; // o painel do operador
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      if (/<option[^>]*value=["'`]sms["'`]/.test(fonte)) {
        oferecem.push(relative(RAIZ, arquivo));
      }
    }

    expect(oferecem, oferecem.join("\n")).toEqual([]);
  });

  it("nenhum plano promete SMS", () => {
    const planos = readFileSync(join(RAIZ, "lib", "planos.ts"), "utf8");
    expect(/\bsms\b/i.test(semComentarios(planos))).toBe(false);
  });
});
