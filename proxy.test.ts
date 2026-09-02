import { describe, it, expect } from "vitest";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
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
    [
      `/p/contrato/${"a".repeat(32)}`,
      "o link do contrato: quem chega para aceitar não tem — e não vai criar — conta aqui",
    ],
    [
      `/p/remarcar/${"b".repeat(32)}`,
      "o link da remarcação: idem — e é o link que faz a troca acontecer",
    ],
    ["/panorama", "a página do estudo — é este endereço que vai no post"],
    ["/panorama/pesquisa", "o questionário pela URL limpa"],
    ["/panorama/contato", "as duas portas do fim"],
    ["/panorama/pesquisa.html", "e também pelo caminho com extensão"],
  ])("%s — %s", (caminho) => {
    expect(ehPublica(caminho)).toBe(true);
  });
});

/**
 * O Panorama repetiu o defeito das rotas de máquina, e por isso ganha teste.
 *
 * As páginas da pesquisa são estáticas, mas as URLs limpas do `next.config.ts`
 * não têm extensão — então elas acordam o proxy, e o proxy fecha por padrão.
 * Sem `/panorama/` na lista, divulgar `/panorama` mandaria toda respondente
 * para `/entrar` com um 307. Ninguém veria erro nenhum: a pesquisa
 * simplesmente não teria resposta, e a explicação seria "o link não funciona".
 */
describe("as URLs limpas do Panorama existem de verdade", () => {
  it("cada rewrite aponta para um arquivo que está em public/panorama/", () => {
    const rewrites = [
      ["/panorama", "index.html"],
      ["/panorama/pesquisa", "pesquisa.html"],
      ["/panorama/contato", "contato.html"],
      ["/panorama/protocolo", "protocolo.pdf"],
    ] as const;

    for (const [rota, arquivo] of rewrites) {
      expect(
        existsSync(join(process.cwd(), "public", "panorama", arquivo)),
        `${rota} reescreve para public/panorama/${arquivo}, que não existe`,
      ).toBe(true);
      expect(ehPublica(rota), `${rota} cairia em /entrar`).toBe(true);
    }
  });

  it("o prefixo não abre um caminho parecido", () => {
    expect(ehPublica("/panoramas")).toBe(false);
    expect(ehPublica("/panorama-interno")).toBe(false);
  });
});

/**
 * **A varredura que faltava, e ela custou os três documentos e o blog inteiro.**
 *
 * O Panorama ganhou teste depois de repetir o defeito das rotas de máquina, e o
 * teste dele confere uma lista escrita à mão — quatro rewrites que eu digitei.
 * Uma lista à mão nunca reprova a rota que alguém esqueceu de acrescentar nela:
 * é a mesma forma do `exportar_conta`, que ficou dezessete tabelas atrás porque
 * todas as verificações conferiam por lista.
 *
 * Esta pergunta ao **sistema de arquivos**. Toda página dentro de `app/(site)`
 * existe para ser lida por quem não tem conta — é o que o grupo significa — e
 * portanto tem de passar por `ehPublica`. A próxima página pública que alguém
 * criar reprova aqui, no dia em que for criada, e não meses depois quando
 * alguém reclamar que "o link não funciona".
 */
describe("toda página do site é alcançável sem sessão", () => {
  it("cada rota de app/(site) passa por ehPublica", () => {
    const raiz = join(process.cwd(), "app", "(site)");

    const rotas: string[] = [];
    const varrer = (dir: string, prefixo: string) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (e.isDirectory()) {
          // `[slug]` vira um valor qualquer: o que se testa é o prefixo.
          const parte = e.name.startsWith("[") ? "um-endereco-qualquer" : e.name;
          varrer(join(dir, e.name), `${prefixo}/${parte}`);
        } else if (e.name === "page.tsx") {
          rotas.push(prefixo === "" ? "/" : prefixo);
        }
      }
    };
    varrer(raiz, "");

    // Se este número cair, alguém apagou uma página pública sem querer.
    expect(rotas.length).toBeGreaterThanOrEqual(6);

    const fechadas = rotas.filter((r) => !ehPublica(r));
    expect(fechadas, "estas páginas do site cairiam em /entrar").toEqual([]);
  });
});

describe("o que continua fechado", () => {
  it.each([
    "/agenda",
    "/encaixes",
    "/encaixes/abc",
    "/pacientes",
    "/pacientes/abc",
    "/pacientes/abc/exportar",
    "/comecar",
    "/perfil/exportar",
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

describe("a página do paciente (P7) é pública", () => {
  /**
   * Este teste existe porque o mesmo defeito aconteceu **três vezes** neste
   * projeto: as rotas de máquina, as URLs limpas do Panorama e os três
   * documentos legais mais o blog. Toda vez o sintoma foi o mesmo — um 307 para
   * `/entrar`, que nem a Vercel nem uma pessoa leem como erro —, e toda vez a
   * causa foi uma rota nova que ninguém pôs na lista.
   *
   * Aqui o custo seria: o paciente recebe o link no WhatsApp, toca, e cai numa
   * tela de login de um sistema em que ele não tem conta e nunca vai ter. Ele
   * não reclama; ele só não confirma o horário.
   */
  it("o token abre sem sessão", () => {
    expect(ehPublica("/p/agora/e5826e7f06cc4992a338fe44eec58d04")).toBe(true);
  });

  it("...e o documento dentro dela também", () => {
    expect(
      ehPublica("/p/agora/e5826e7f06cc4992a338fe44eec58d04/documento/ba47ac94-0000-4000-8000-000000000000"),
    ).toBe(true);
  });

  it("as três páginas de link mágico entram pelo mesmo prefixo", () => {
    // Se um dia alguém trocar o prefixo por uma lista de rotas, este teste é o
    // que reprova a quarta página esquecida.
    for (const rota of ["/p/contrato/abc", "/p/remarcar/abc", "/p/agora/abc"]) {
      expect(ehPublica(rota), rota).toBe(true);
    }
  });

  it("mas a área logada continua fechada", () => {
    // A prova de que a varredura acima não passa a vazio.
    expect(ehPublica("/pacientes/abc")).toBe(false);
    expect(ehPublica("/agenda")).toBe(false);
  });
});
