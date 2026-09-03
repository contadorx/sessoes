import { describe, it, expect } from "vitest";
import { faltando, feito, fraseDoQueFalta, PASSOS } from "./comecar";
import type { EstadoInicial } from "@/app/(app)/comecar/page";

const est = (over: Partial<EstadoInicial> = {}): EstadoInicial => ({
  pacientes: 0,
  enquadres: 0,
  sessoes: 0,
  na_fila: 0,
  com_canal: 0,
  politica_definida: false,
  vagas_abertas: 0,
  preenchidas: 0,
  janelas: 0,
  semana_min: 0,
  ...over,
});

describe("o que ainda falta configurar", () => {
  it("conta nova: os três", () => {
    expect(faltando(est())).toEqual(PASSOS);
  });

  /**
   * O defeito que fechou esta linha: a faixa da agenda exigia `vagas_abertas > 0`,
   * e vaga aberta só existe quando **uma paciente desmarca**. Uma conta com tudo
   * configurado e nenhum cancelamento carregava "Terminar de configurar" na
   * agenda para sempre.
   */
  it("tudo configurado e nenhum cancelamento: não falta nada", () => {
    const pronta = est({ janelas: 3, semana_min: 1200, pacientes: 8, enquadres: 8, na_fila: 2 });
    expect(faltando(pronta)).toEqual([]);
    expect(fraseDoQueFalta(pronta)).toBe("");
  });

  /**
   * A rota órfã. `/comecar` não está em `destinos()` nem em `SECOES`: a faixa da
   * agenda é a **única** porta para ela. Enquanto a condição ignorava `janelas`,
   * quem pulasse o passo 1 e fizesse os outros dois perdia a porta — e com ela o
   * passo que é o denominador de todo número do produto.
   */
  it("quem pulou só as horas continua tendo porta", () => {
    const e = est({ pacientes: 8, enquadres: 8, na_fila: 2 });
    expect(faltando(e)).toEqual(["horas"]);
    expect(fraseDoQueFalta(e)).toBe("faltam os seus horários — um passo, uma vez só");
  });

  /**
   * O passo que se marcava sozinho. `enquadres > 0` é o que a importação do
   * passo anterior produz; conferir valor e política não deixa rastro nenhum no
   * banco. Nenhum passo depende de `enquadres`, e é por isso.
   */
  it("nenhum passo se marca com o que outro passo já produziu", () => {
    const soImportou = est({ pacientes: 8, enquadres: 8, sessoes: 40 });
    expect(faltando(soImportou)).toEqual(["horas", "fila"]);
    expect(feito(soImportou, "pessoas")).toBe(true);
  });

  /**
   * `politica_definida` é falso para quem decidiu **não** cobrar cancelamento, e
   * essa decisão é legítima. Um passo pendurado nele nunca fecharia para ela.
   */
  it("quem não cobra cancelamento também termina de configurar", () => {
    const semMulta = est({ janelas: 2, pacientes: 5, enquadres: 5, na_fila: 1, politica_definida: false });
    expect(faltando(semMulta)).toEqual([]);
  });

  it("a frase diz o que falta, e o número sai da contagem", () => {
    expect(fraseDoQueFalta(est())).toBe(
      "faltam os seus horários, os pacientes e a fila — três passos, uma vez só",
    );
    expect(fraseDoQueFalta(est({ janelas: 1 }))).toBe(
      "faltam os pacientes e a fila — dois passos, uma vez só",
    );
  });

  /**
   * O guarda contra a divergência voltar: a faixa e a página contam a mesma
   * coisa porque contam **daqui**. Nenhum número de passos escrito à mão em
   * lugar nenhum.
   */
  it("o número de passos nunca é constante literal", () => {
    for (const e of [est(), est({ janelas: 1 }), est({ janelas: 1, pacientes: 3 })]) {
      const frase = fraseDoQueFalta(e);
      const contados = faltando(e).length;
      const palavra = { 1: "um passo", 2: "dois passos", 3: "três passos" }[contados];
      expect(frase).toContain(palavra);
    }
  });
});
