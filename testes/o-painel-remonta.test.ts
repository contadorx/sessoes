import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * O S1 da B39, preso para não voltar.
 *
 * `<PainelSessao>` é renderizado num slot condicional, sempre na mesma posição
 * da árvore. Sem `key`, tocar em outra sessão troca as props e o React **não
 * desmonta** o componente. A partir daí os dois campos da evolução divergem:
 *
 *   Registro.tsx  <input type="hidden" name="sessao_id" value={sessaoId} />
 *                 → controlado por `value`, **atualiza**
 *   Registro.tsx  <textarea name="texto" defaultValue={texto ?? ""} />
 *                 → não-controlado por `defaultValue`, **não atualiza**
 *
 * O resultado, no fim do dia, com duas sessões já realizadas: escrever a
 * evolução da Helena sem salvar, tocar na sessão do João na mesma lista, tocar
 * em Guardar — e o texto da Helena vai para o prontuário do João. Guarda de
 * cinco anos, e `evolucao_nao_se_reescreve` impede desfazer.
 *
 * **Por que um teste que lê o arquivo, e não um que renderiza.** O defeito é de
 * *identidade de componente*, não de saída: renderizado uma vez, o painel está
 * correto — o erro só existe na transição entre duas sessões, e reproduzi-lo
 * exigiria montar React com DOM, que este projeto não tem e que não vale a
 * dependência para prender uma palavra. O que se pode garantir sem isso é que a
 * palavra continua lá, e é o que este arquivo faz.
 *
 * Se um dia o painel deixar de ser renderizado assim, este teste reprova e quem
 * mexeu vai ler o parágrafo acima — que é o ponto.
 */

const SEMANA = readFileSync(
  join(import.meta.dirname, "..", "components", "app", "Semana.tsx"),
  "utf8",
);

describe("o painel da sessão remonta ao trocar de sessão", () => {
  it("PainelSessao é renderizado com key", () => {
    const abertura = SEMANA.indexOf("<PainelSessao");
    expect(abertura, "o painel sumiu de Semana.tsx — reveja este teste").toBeGreaterThan(-1);

    const tag = SEMANA.slice(abertura, SEMANA.indexOf("/>", abertura));
    expect(
      /\bkey=\{/.test(tag),
      "<PainelSessao> sem `key`: trocar de sessão com evolução não salva grava o " +
        "texto de uma paciente no prontuário da outra",
    ).toBe(true);
  });

  it("a key é a identidade da sessão, e não o índice nem uma constante", () => {
    const abertura = SEMANA.indexOf("<PainelSessao");
    const tag = SEMANA.slice(abertura, SEMANA.indexOf("/>", abertura));
    const key = /\bkey=\{([^}]+)\}/.exec(tag)?.[1] ?? "";

    // Uma `key` fixa não remonta nada, e uma por índice remonta na hora errada.
    expect(key).toMatch(/\.id\b/);
    expect(key).not.toMatch(/^["'`]/);
  });

  /**
   * A textarea continua não-controlada, e é decisão: controlá-la resolveria a
   * troca de sessão e custaria re-render a cada tecla numa tela que já faz
   * quinze consultas. A `key` resolve o mesmo com custo zero — mas só enquanto
   * a `key` existir, que é o que o teste acima guarda.
   */
  it("a evolução continua não-controlada — a key é que resolve, não o controle", () => {
    const registro = readFileSync(
      join(import.meta.dirname, "..", "components", "app", "Registro.tsx"),
      "utf8",
    );
    const abertura = registro.indexOf('<textarea\n        ref={campo}');
    expect(abertura, "a textarea da evolução mudou de forma").toBeGreaterThan(-1);

    const tag = registro.slice(abertura, registro.indexOf("/>", abertura));
    expect(tag).toContain("defaultValue=");
    expect(tag).not.toContain("value={");
  });
});
