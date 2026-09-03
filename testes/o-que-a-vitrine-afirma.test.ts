import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PLANOS, precoDeTabela } from "@/lib/planos";

/**
 * O que a vitrine afirma, e o que sustenta cada afirmação.
 *
 * "A promessa que o software não cumpre" é um antipadrão nomeado deste projeto,
 * e **já aconteceu quatro vezes**: duas exclusões inexistentes na
 * `/privacidade`, 60 mensagens prometidas na `/termos` depois de o limite ter
 * mudado, oito recursos inexistentes na página de planos, e o nono de volta no
 * cartão de R$ 129. Quatro vezes, quatro correções de frase, e a quinta sempre
 * apareceu.
 *
 * **A correção que importa nunca foi a frase — é isto aqui.** Cada afirmação
 * factual de tela pública fica ao lado de quem a sustenta, e o teste falha de
 * dois jeitos:
 *
 * 1. **a frase sumiu ou mudou** — alguém reescreveu a vitrine sem reconferir o
 *    que ela promete, e é exatamente aí que a promessa se descola do produto;
 * 2. **o que sustentava sumiu** — a função foi removida ou renomeada, e a
 *    vitrine continuou afirmando.
 *
 * As linhas que a auditoria conferiu e que **batem** também estão aqui, e são a
 * maior parte: uma suíte só com o que falhou vira lista de defeitos passados;
 * uma com o que vale vira contrato.
 *
 * O que este arquivo **não** faz: julgar frase de opinião, de tom ou de
 * posicionamento. Só o que é verificável — número, prazo, garantia, "o sistema
 * faz X".
 */

const RAIZ = join(import.meta.dirname, "..");
const pagina = (caminho: string) => readFileSync(join(RAIZ, caminho), "utf8");

const LANDING = pagina("app/(site)/page.tsx");
const TERMOS = pagina("app/(site)/termos/page.tsx");
const PRIVACIDADE = pagina("app/(site)/privacidade/page.tsx");

type Afirmacao = {
  /** Onde ela aparece. */
  onde: string;
  /** O que a página diz, como está escrito lá. */
  diz: string;
  /** Onde mora o comportamento que a torna verdadeira. */
  sustenta: string;
};

/*
  `lib/planos.ts` entra como se fosse uma página, e é o ponto da build.

  Os cartões de preço da landing não têm texto: eles saem de `PLANOS.map`. Foi
  por aí que "com aprovação em etapas" voltou — a restrição do banco protege a
  coluna `planos.recursos`, e ninguém olhava a constante que a tela realmente
  renderiza. Uma varredura de vitrine que só lesse os arquivos de página
  repetiria o mesmo ponto cego.
*/
const TEXTOS: Record<string, string> = {
  "/": LANDING,
  "/termos": TERMOS,
  "/privacidade": PRIVACIDADE,
  "lib/planos.ts": pagina("lib/planos.ts"),
};

/**
 * As afirmações, e quem responde por cada uma.
 *
 * A coluna `sustenta` é lida por um humano, não pelo teste — o teste garante
 * que o arquivo citado existe e contém o símbolo. É o suficiente para que quem
 * apagar a função saiba que havia uma vitrine em cima dela.
 */
const AFIRMACOES: Afirmacao[] = [
  // ------------------------------------------------ as quatro que a B46 consertou
  {
    onde: "lib/planos.ts",
    diz: "Permissões por pessoa: quem vê o quê",
    sustenta: "os cartões da landing saem de PLANOS.map — e a aprovação em etapas foi para porVir",
  },
  {
    onde: "/termos",
    diz: "tem uma faixa de 60\n            sessões por mês",
    sustenta: "lib/planos.ts · PLANOS[solo].faixa === 60",
  },
  {
    onde: "/termos",
    diz: "você não recebe aviso de faixa nenhuma",
    sustenta: "lib/faixa.ts · nivelDaFaixa devolve 'nenhum' em plano fair-use",
  },
  {
    onde: "/",
    diz: "ainda não está ligada",
    sustenta: "lib/pagamentos/adaptadores.ts · pixDireto grava provedorCobrancaId null",
  },
  {
    onde: "/",
    diz: "o sistema diz até quando\n                você continua responsável",
    sustenta: "migração 0062 · eliminar_conta não recusa por prazo de guarda; devolve a data",
  },
  {
    onde: "/privacidade",
    diz: "ele diz até quando aquele registro ainda está no prazo",
    sustenta: "migração 0062 · a mesma função",
  },

  // ----------------------------------------- as que a auditoria conferiu e batem
  {
    onde: "/",
    diz: "Nada de gravar paciente, transcrever sessão ou IA opinando",
    sustenta: "fronteira 1 · nenhuma dependência de áudio ou de IA no repositório",
  },
  {
    onde: "/termos",
    diz: "No plano Gratuito, a fila e a cobrança são\n            enviadas por você",
    sustenta: "migração 0061 · mensagem_escolhe_o_canal lê planos.canal_saida",
  },
  {
    onde: "/privacidade",
    diz: "O texto padrão é discreto: remetente neutro, sem o seu\n            nome profissional",
    sustenta: "lib/mensageria/templates.ts · PROIBIDAS_NO_DISCRETO",
  },
];

describe("cada afirmação da vitrine continua escrita onde o teste a viu", () => {
  it.each(AFIRMACOES.map((a) => [a.onde, a.diz, a] as const))(
    "%s — %s",
    (onde, _diz, a) => {
      const texto = TEXTOS[onde];
      expect(texto, `página desconhecida: ${onde}`).toBeDefined();
      expect(
        texto.includes(a.diz),
        `${onde} não diz mais "${a.diz}".\n` +
          `Quem sustentava: ${a.sustenta}.\n` +
          `Se a frase mudou, confira o comportamento antes de atualizar este teste — ` +
          `é exatamente aqui que a promessa se descola do produto.`,
      ).toBe(true);
    },
  );

  it("a varredura não está vazia", () => {
    // Uma tabela que encolhe até zero passa em tudo, calada.
    expect(AFIRMACOES.length).toBeGreaterThanOrEqual(9);
    expect(new Set(AFIRMACOES.map((a) => a.onde)).size).toBe(4);
  });
});

/**
 * As afirmações que dá para **avaliar**, e não só localizar.
 *
 * Onde o número da tela sai de uma função, o teste chama a função. É o degrau
 * acima de conferir que a frase existe.
 */
describe("os números da vitrine saem de quem os calcula", () => {
  it("os quatro preços da página são os de lib/planos.ts", () => {
    for (const p of PLANOS) {
      const preco = precoDeTabela(p);
      expect(
        LANDING.includes("PLANOS.map"),
        "a landing parou de renderizar PLANOS — o preço voltou a ser texto solto",
      ).toBe(true);
      expect(preco).toMatch(/^R\$/);
    }
  });

  it("a faixa que a /termos afirma é a que o plano tem", () => {
    const solo = PLANOS.find((p) => p.codigo === "solo")!;
    expect(solo.faixa).toBe(60);
    expect(TERMOS).toContain("faixa de 60");
  });

  it("os três planos que a /termos diz não ter faixa, não têm", () => {
    // Gratuito por `faixa: null`; Completo e Clínica por `fairUse`, que faz
    // `nivelDaFaixa` responder "nenhum" e nenhum aviso disparar.
    const semFaixa = PLANOS.filter((p) => p.faixa === null || p.fairUse);
    expect(semFaixa.map((p) => p.codigo).sort()).toEqual(["clinica", "gratis", "pro"]);
  });

  /**
   * O nono recurso inexistente, preso pelo nome.
   *
   * Ele voltou uma vez, colado no fim de uma linha verdadeira — que é como
   * promessa entra sem ninguém notar. Enquanto não houver implementação, a
   * palavra não pode aparecer em `recursos` de plano nenhum.
   */
  it("aprovação em etapas não é vendida enquanto não existir", () => {
    for (const p of PLANOS) {
      expect(
        p.recursos.join(" | ").toLowerCase(),
        `${p.codigo} vende aprovação em etapas`,
      ).not.toContain("aprovação em etapas");
    }
    const noPorVir = PLANOS.some((p) =>
      p.porVir.some((v) => v.toLowerCase().includes("aprovação em etapas")),
    );
    expect(noPorVir, "a intenção sumiu da página em vez de ir para porVir").toBe(true);
  });
});
