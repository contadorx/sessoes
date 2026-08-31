import { describe, it, expect } from "vitest";
import { config, ehPublica } from "./proxy";

/**
 * O teste que faltava, e que teria evitado o pior defeito do projeto.
 *
 * O `proxy` fecha por padrão — decisão certa, e é ela que faz uma rota nova
 * nascer protegida. Mas "fecha por padrão" tem um custo que ninguém vê: as
 * rotas que **precisam** ser abertas ficam quebradas em silêncio.
 *
 * Foi o que aconteceu. `/api/mensageria`, `/api/whatsapp`, `/api/diario` e
 * `/auth/callback` não têm extensão no caminho, então passavam pelo proxy; e
 * como o cron e o provedor não mandam cookie, todas eram redirecionadas para
 * `/entrar` com um 307. Nada estourava: o cron da Vercel veria um 307 e
 * consideraria sucesso. A fila não andaria, as mensagens não sairiam, a agenda
 * pararia de se estender — e o primeiro sinal seria uma psicóloga dizendo que
 * "o sistema não avisou ninguém".
 *
 * Os testes de banco não pegam isto: lá dentro tudo funciona. O que estava
 * errado era **quem consegue chegar até lá**.
 */

describe("o que precisa passar sem sessão", () => {
  it.each([
    ["/api/mensageria", "o cron de cinco minutos"],
    ["/api/diario", "o cron diário"],
    ["/api/whatsapp", "o provedor entregando a resposta do paciente"],
    ["/auth/callback", "o link de confirmação de e-mail"],
    ["/", "a landing"],
    ["/entrar", "a tela de entrar"],
    ["/p/abc123", "o portal do paciente por link mágico"],
  ])("%s — %s", (caminho) => {
    expect(ehPublica(caminho)).toBe(true);
  });
});

describe("o que continua fechado", () => {
  it.each([
    "/agenda",
    "/fila",
    "/fila/abc",
    "/pacientes",
    "/pacientes/abc",
    "/pacientes/abc/exportar",
    "/comecar",
    "/conta/exportar",
  ])("%s exige sessão", (caminho) => {
    expect(ehPublica(caminho)).toBe(false);
  });

  it("um caminho parecido não engana o prefixo", () => {
    // "/apiario" começa com "/api" mas não com "/api/".
    expect(ehPublica("/apiario")).toBe(false);
    expect(ehPublica("/autorizacoes")).toBe(false);
  });
});

describe("o matcher", () => {
  it("deixa os estáticos e os arquivos com extensão de fora", () => {
    const padrao = new RegExp(config.matcher[0].replace(/^\//, "^/").concat("$"));

    // Estes nunca deveriam acordar o proxy: são públicos por natureza e
    // passar por ele custaria uma consulta de sessão em cada um.
    for (const caminho of [
      "/_next/static/chunk.js",
      "/favicon.ico",
      "/sw.js",
      "/manifest.webmanifest",
      "/icone-192.png",
    ]) {
      expect(padrao.test(caminho), `${caminho} não devia passar pelo proxy`).toBe(false);
    }
  });

  it("mas alcança as rotas de verdade", () => {
    const padrao = new RegExp(config.matcher[0].replace(/^\//, "^/").concat("$"));
    for (const caminho of ["/agenda", "/api/mensageria", "/auth/callback", "/"]) {
      expect(padrao.test(caminho), `${caminho} devia passar pelo proxy`).toBe(true);
    }
  });
});
