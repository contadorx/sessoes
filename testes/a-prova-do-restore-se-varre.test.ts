import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * A prova do restore não confere por lista escrita à mão.
 *
 * `supabase/verificar-restauracao.sql` carrega o **único critério de pronto do
 * projeto que não se verifica lendo** — o `RESTAURAR.md` abre dizendo isso, e a
 * razão está escrita lá: *"prontuário perdido é fim do produto"*.
 *
 * Até 03/09 ele conferia por enumeração, e as listas tinham envelhecido
 * exatamente como a lei 7 do `CLAUDE.md` prevê. Medido contra o catálogo do
 * banco naquele dia:
 *
 *     tabelas ....  44 de  56    funções ...  147 de 285
 *     gatilhos ..   38 de  79    views .....   12 de  29
 *
 * Entre as tabelas que ninguém conferia estavam `janelas_atendimento` (a
 * capacidade declarada) e `objetivos` (prontuário). Entre as views,
 * `v_nao_se_aplica_textos` — texto livre escrito por psicóloga, irmã da
 * `v_residual_textos` cujo risco o próprio arquivo descrevia em nove linhas.
 *
 * Este teste existe porque o conserto não é a frase, é a varredura — e porque
 * a lista escrita à mão volta com cara de melhoria. Ele não tem banco: lê o
 * arquivo e reprova enumeração não declarada.
 *
 * **O que continua permitido, e por quê.** Nem tudo o que o arquivo precisa
 * saber está no catálogo. "Esta tabela deve ter RLS e nenhuma política" é
 * *decisão*, não fato — o catálogo sabe que ela não tem política, não sabe se
 * isso é o desenho. Essas listas ficam, com duas condições: aparecem abaixo,
 * nomeadas, e conferem **nos dois sentidos** (o item que sai reprova, e o item
 * novo que ninguém declarou também).
 */

const RAIZ = join(import.meta.dirname, "..");
const PROVA = readFileSync(join(RAIZ, "supabase/verificar-restauracao.sql"), "utf8");

/**
 * As enumerações que o arquivo tem direito de manter — cada uma é uma decisão
 * que o catálogo não consegue expressar.
 *
 * `doisSentidos` diz se o item **novo e não declarado** também precisa
 * reprovar. Ele precisa quando existir em silêncio já é a falha; não precisa
 * quando o item novo é inerte.
 */
const DECISOES: { chave: string; doisSentidos: boolean; porque: string }[] = [
  {
    chave: "calendarios_segredo",
    doisSentidos: true,
    porque:
      "as cinco tabelas que existem para NÃO ter política (0040c, 0045, 0052, 0060): " +
      "tabela nova sem política é uma decisão tomada calada, e tabela declarada " +
      "que ganhou política é um vazamento com cara de manutenção",
  },
  {
    chave: "lembrete_de_sessao",
    doisSentidos: true,
    porque:
      "os quatro templates essenciais: essencial é a mensagem que passa por cima " +
      "do teto do plano, então um essencial novo que ninguém declarou é gasto e " +
      "alcance decididos em silêncio — foi assim que o quarto, da 0057, ficou " +
      "quatro builds sem entrar na conferência",
  },
  {
    chave: "mensagens_por_conta_hora",
    doisSentidos: false,
    porque:
      "os dois tetos técnicos da 0060: aqui o segundo sentido seria teatro. " +
      "`teto_tecnico()` lê os dois códigos pelo nome, então uma linha nova em " +
      "`limites_tecnicos` não é lida por ninguém e não freia nada",
  },
];

function enumeracoes(sql: string): string[] {
  return [...sql.matchAll(/unnest\(array\[([\s\S]*?)\]\)/g)].map((m) => m[1]);
}

describe("a prova do restore se varre, não se enumera", () => {
  it("toda enumeração que sobrou é uma decisão declarada", () => {
    const naoDeclaradas = enumeracoes(PROVA).filter(
      (bloco) => !DECISOES.some(({ chave }) => bloco.includes(chave)),
    );
    expect(naoDeclaradas).toEqual([]);
  });

  it("a decisão cujo item novo é falha reprova nos dois sentidos", () => {
    // Uma verificação que só olha o que sumiu deixa passar o que apareceu — e
    // o que aparece calado é o modo de falha deste arquivo inteiro.
    for (const { chave, doisSentidos, porque } of DECISOES) {
      if (!doisSentidos) continue;
      const ocorrencias = PROVA.split(chave).length - 1;
      expect(ocorrencias, `${chave}: ${porque}`).toBeGreaterThanOrEqual(2);
    }
  });

  it("as varreduras de catálogo continuam lá", () => {
    // Cada uma destas é uma classe inteira que a versão anterior conferia por
    // lista. Se uma sumir, alguém trocou varredura por enumeração de novo.
    for (const varredura of [
      "not c.relrowsecurity", //            RLS ligada em toda tabela
      "c.relkind = 'v'", //                 nenhuma view aberta
      "p.prosecdef", //                     search_path em todo definer
      "con.contype = 'f'", //               FK indexada
      "query_to_xml", //                    contagem de todas as tabelas
    ]) {
      expect(PROVA, `sumiu a varredura: ${varredura}`).toContain(varredura);
    }
  });

  it("a impressão digital cobre as classes que somem sem deixar rastro", () => {
    // Uma tabela que não voltou não deixa rastro na base restaurada: ela só
    // não está lá. A parte 2 é a única coisa capaz de perceber isso, e só
    // percebe as classes que ela lista.
    for (const classe of [
      "'tabelas'",
      "'colunas'",
      "'views'",
      "'funcoes'",
      "'gatilhos'",
      "'politicas'",
      "'indices'",
      "'restricoes'",
      "'anon_executa'",
      "'authenticated_executa'",
      "'extensoes'",
    ]) {
      expect(PROVA, `a impressão digital não cobre ${classe}`).toContain(classe);
    }
  });

  it("o RESTAURAR.md manda tirar a digital antes do ensaio", () => {
    // A parte 2 não serve para nada se ninguém rodar na produção ANTES. É a
    // única expectativa do arquivo, e ela se gera — não se escreve.
    const roteiro = readFileSync(join(RAIZ, "supabase/RESTAURAR.md"), "utf8");
    expect(roteiro).toMatch(/impressão digital/i);
    expect(roteiro).toMatch(/PRODUÇÃO/);
  });
});
