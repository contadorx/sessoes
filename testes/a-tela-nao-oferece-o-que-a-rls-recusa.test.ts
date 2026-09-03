import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * Nenhuma tela oferece escrita que a RLS vai recusar.
 *
 * `lib/permissao.ts` já dizia a frase: *"o menu aqui existe para a tela não
 * oferecer o que a pessoa não pode fazer — oferecer e depois recusar é pior do
 * que não oferecer"*. O painel da sessão tinha ficado de fora dela.
 *
 * O que acontecia: uma **secretária** — que por padrão não tem acesso clínico
 * nem financeiro — abria a agenda, marcava "Aconteceu", e recebia ali mesmo uma
 * caixa de evolução **já aberta**, com *"Guarda de cinco anos: o que entra aqui
 * não se apaga"* embaixo, e o bloco "Recebi". As duas escritas são recusadas
 * pelas policies da 0049 (`le_clinico()` e `ve_financeiro()`). Era pior que
 * oferecer: era convidar quem não pode ler prontuário a escrever num.
 *
 * As abas do paciente já faziam certo — `SemAcessoClinico` no prontuário e na
 * anamnese. O painel da agenda é o mesmo componente para todo mundo, e ninguém
 * tinha lembrado dele.
 *
 * **Por que a checagem é por componente e não por tela.** A tela nova herda o
 * componente; a lista de telas, não. Aqui o conjunto é descoberto varrendo
 * quem **renderiza** cada escrita — se amanhã a evolução aparecer numa quarta
 * tela, ela entra nesta varredura sozinha.
 *
 * Uma nota sobre o que **não** está aqui: o bloco da cobrança (`<Cobranca>`)
 * não precisa de porta, e conferi antes de concluir isso — a policy de
 * **SELECT** de `cobrancas` também exige `ve_financeiro()`, então para quem não
 * tem acesso a linha nem chega ao componente e ele não renderiza. Fechar de
 * novo ali seria uma trava que ninguém pode exercitar.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) arquivos(caminho, res);
    else if (/\.tsx$/.test(e.name) && !/\.test\.tsx$/.test(e.name)) res.push(caminho);
  }
  return res;
}

/**
 * Comentário fora antes de varrer — e esta linha custou uma depuração.
 *
 * A primeira versão deste teste passava com o defeito reintroduzido, e a razão
 * era o comentário que eu mesmo tinha escrito no `PainelSessao` explicando o
 * conserto: ele cita `SemAcessoClinico`, e a varredura leu a citação como se
 * fosse a porta. Um teste que se satisfaz com o texto que descreve a proteção,
 * em vez da proteção, é pior que teste nenhum — ele dá o sinal verde no
 * exato caso em que deveria gritar.
 *
 * É a segunda vez nesta fila: a varredura de campos da B48 acusou o próprio
 * parágrafo que explicava o defeito. O padrão agora é este, sempre.
 */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (l, antes) => antes + " ".repeat(l.length - antes.length));
}

const FONTES = [join(RAIZ, "app"), join(RAIZ, "components")]
  .flatMap((d) => arquivos(d))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    texto: semComentarios(readFileSync(caminho, "utf8")),
  }));

/**
 * Cada escrita que a RLS condiciona, e a porta que a tela tem que passar antes
 * de oferecê-la.
 *
 * `SemAcessoClinico` conta como porta: a tela que o renderiza está justamente
 * decidindo por acesso, e diz isso na cara em vez de sumir calada.
 */
const PORTAS = [
  {
    o_que: "a caixa de evolução",
    render: /<Evolucao[\s>]/,
    porta: /podeClinico\s*\(|SemAcessoClinico/,
    policy: "evolucoes: insert/select/update exigem le_clinico() (0049)",
  },
  {
    o_que: 'o bloco "Recebi"',
    render: /<Recebi[\s>]/,
    porta: /podeFinanceiro\s*\(/,
    policy: "cobrancas: insert exige ve_financeiro() (0049)",
  },
];

describe("a tela não oferece o que a RLS vai recusar", () => {
  it("a varredura está varrendo", () => {
    expect(FONTES.length).toBeGreaterThan(40);
  });

  /**
   * A porta pode estar no arquivo **ou em quem o importa**, e essa segunda
   * metade não é indulgência: `Registro.tsx` renderiza a evolução e não checa
   * nada, e está certo — ele só é usado por `prontuario/page.tsx`, que abre com
   * `podeClinico` e mostra `SemAcessoClinico` quando a resposta é não. Cobrar a
   * porta ali dentro seria checar duas vezes a mesma coisa, e a segunda ficaria
   * desatualizada primeiro.
   *
   * O que a regra **não** aceita é o componente sem porta com um consumidor sem
   * porta. Foi exatamente a forma do defeito: `PainelSessao` renderizava a
   * evolução, e `Semana` e a agenda também não checavam nada.
   */
  const consumidores = (arquivo: string) => {
    const modulo = arquivo.replace(/\.tsx$/, "");
    const nome = modulo.split("/").pop()!;
    return FONTES.filter(
      (f) =>
        f.caminho !== arquivo &&
        new RegExp(`from "(@/${modulo}|\\.{1,2}/[^"]*${nome})"`).test(f.texto),
    );
  };

  it.each(PORTAS.map((p) => [p.o_que, p] as const))(
    "%s só é renderizada atrás da permissão",
    (_o_que, regra) => {
      const semPorta = FONTES.filter((f) => {
        if (!regra.render.test(f.texto)) return false;
        if (regra.porta.test(f.texto)) return false;

        // Delegou para cima: só vale se **todos** os consumidores têm a porta,
        // e se existe algum consumidor — componente que ninguém usa não delega
        // nada a ninguém.
        const quemUsa = consumidores(f.caminho);
        return quemUsa.length === 0 || !quemUsa.every((c) => regra.porta.test(c.texto));
      }).map((f) => f.caminho);

      expect(
        semPorta,
        `${regra.o_que} é oferecida sem checar a permissão, e quem a usa também não. ` +
          `${regra.policy}. Oferecer e depois recusar é pior do que não oferecer.`,
      ).toEqual([]);
    },
  );

  /**
   * O contrapeso, e ele é decisão do arquivo da build: **"Aconteceu" continua à
   * vista para todo mundo.** Marcar uma sessão como realizada é fato
   * administrativo, a policy de `sessoes` não exige acesso nenhum, e é o que a
   * secretária existe para fazer. Esconder devolveria o trabalho para a
   * psicóloga, que é o oposto do produto inteiro.
   */
  it('"Aconteceu" não ficou atrás de permissão nenhuma', () => {
    const painel = FONTES.find((f) => f.caminho.endsWith("PainelSessao.tsx"))!;
    const i = painel.texto.indexOf('rotulo="Aconteceu"');
    expect(i, "o botão Aconteceu sumiu do painel").toBeGreaterThan(-1);

    const linha = painel.texto.slice(painel.texto.lastIndexOf("\n", i - 200), i);
    expect(linha).not.toMatch(/podeClinico|podeFinanceiro/);
  });
});
