import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * A ordem da tela que ela abre todo dia.
 *
 * Antes desta build, em 375 px, vinham **oito blocos e dez números** de
 * dinheiro e de ocupação antes do primeiro nome de paciente. Ela abre o app
 * entre uma sessão e outra para ver quem vem às 15h, e rolava dois polegares de
 * painéis primeiro. O produto compete com o caderno, e perdia essa comparação
 * por rolagem.
 *
 * A regra é uma só: **o que exige decisão hoje vem antes da grade; o que
 * descreve o mês vem depois.**
 *
 * Antes da grade ficam três, e cada um está lá por uma razão que não é
 * estética:
 *
 *   · a faixa de prazos — o que vence hoje;
 *   · "A decidir" — enquanto ela não decidir, **nada é cobrado**; a pergunta
 *     escondida é uma cobrança que nunca sai;
 *   · "Na sua mão" — a oferta que ela não mandou **segura a vaga**, então uma
 *     caixa fora de vista é uma fila parada sem sintoma.
 *
 * **Este teste não mede pixels.** Ele prende a ordem no código, que é a decisão
 * — a medida em 375 px é de olho, no aparelho. O que ele impede é a ordem se
 * desfazer sem ninguém perceber, que é como ela se fez.
 */

const PAGINA = readFileSync(
  join(import.meta.dirname, "..", "app", "(app)", "agenda", "page.tsx"),
  "utf8",
);

/*
  A âncora é uma expressão, e não um trecho literal — a primeira versão deste
  teste procurava `"<Semana "`, com o espaço, e reprovou no dia em que a tag
  ganhou uma prop e virou multilinha. O teste estava certo em avisar e errado no
  que perguntava: o que importa é **onde o componente é renderizado**, não como
  as props foram quebradas em linhas.
*/
const onde = (marca: RegExp): number => {
  const i = PAGINA.search(marca);
  expect(i, `${marca} sumiu da agenda — reveja este teste antes de mudá-lo`).toBeGreaterThan(-1);
  return i;
};

describe("a agenda mostra a agenda antes de mostrar números", () => {
  const grade = () => onde(/<Semana[\s>]/);

  it.each([
    ["a faixa de prazos", /<FaixaDePendencias[\s>]/],
    ["a caixa A decidir", /<CaixaDeDecisoes[\s>]/],
    ["a caixa Na sua mão", /<CaixaNaSuaMao[\s>]/],
  ] as const)("%s vem antes da grade — exige decisão hoje", (_nome, marca) => {
    expect(onde(marca)).toBeLessThan(grade());
  });

  it.each([
    ["a faixa de quatro números", /\{\/\* a faixa de números \*\/\}/],
    ["o cockpit do mês", /<Cockpit[\s>]/],
    ["o Retorno", /<Retorno[\s>]/],
  ] as const)("%s vem depois da grade — descreve o mês, não o dia", (_nome, marca) => {
    expect(onde(marca)).toBeGreaterThan(grade());
  });

  /**
   * A armadilha do arquivo da build, escrita como teste: "descer" não é
   * "esconder". O cockpit continua na primeira tela — o P5 tem razão escrita
   * sobre isso, e uma métrica que mora onde ninguém abre não muda decisão
   * nenhuma.
   */
  it("nada virou aba, acordeão ou 'ver mais'", () => {
    for (const proibido of ["<details", 'role="tab"', "Ver mais", "ver mais"]) {
      expect(PAGINA, `a agenda ganhou "${proibido}" — aba é onde métrica morre`).not.toContain(
        proibido,
      );
    }
  });

  /**
   * Oito cartões de número empilhados um por linha são meia tela cada em
   * 375 px. Duas colunas já na base.
   */
  it("os dois blocos de números abrem em duas colunas no celular", () => {
    const cockpit = readFileSync(
      join(import.meta.dirname, "..", "components", "app", "Cockpit.tsx"),
      "utf8",
    );
    for (const [nome, texto] of [
      ["a faixa da agenda", PAGINA],
      ["o cockpit", cockpit],
    ] as const) {
      const dl = /<dl className="[^"]*grid[^"]*"/.exec(texto)?.[0] ?? "";
      expect(dl, `${nome}: o <dl> de números sumiu`).not.toBe("");
      expect(dl, `${nome}: uma coluna no celular`).toContain("grid-cols-2");
      expect(dl, `${nome}: as duas colunas só começam no sm:`).not.toContain("sm:grid-cols-2");
    }
  });
});
