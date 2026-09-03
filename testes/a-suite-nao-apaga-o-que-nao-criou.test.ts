import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Uma suíte não apaga o que ela não criou.
 *
 * As 60 suítes de `supabase/tests/` rodam como `postgres`. **Sem RLS no
 * caminho**: é o que permite a elas trocar de papel e provar que a `anon` não
 * lê, e é o que as torna capazes de escrever em qualquer linha do banco.
 *
 * Elas foram escritas para um banco vazio, onde "toda cobrança" e "as minhas
 * cobranças" são a mesma coisa. Rodadas contra um banco que tem outras contas
 * dentro, deixam de ser a mesma coisa — e três linhas passaram a ser
 * destruição de dado real:
 *
 *     0030 · update public.cobrancas set criado_em = now() - interval '9 days';
 *     0030 · update public.mensagens set estado='cancelada' where estado='pendente';
 *     0045 · delete from public.custos_fixos where mes = '2026-07-01';
 *
 * As duas primeiras reescreviam a data de **toda** cobrança do sistema e
 * cancelavam **toda** mensagem pendente. A terceira apagava custo fixo que a
 * suíte nunca criou — e havia três linhas de verdade naquele mês no dia em que
 * isto foi conferido. O `CLAUDE.md` §11 é explícito sobre a conta que tem
 * gente de verdade dentro, e este teste é a forma executável daquela frase.
 *
 * ## O que conta como "amarrado"
 *
 * Um `where` que cite `conta_id`, `paciente_id`, um id que a suíte guardou, um
 * nome/e-mail de fixture, um marcador (`provedor='teste'`, `canal='teste-suite'`,
 * `slug like 'suite-0051-%'`) ou uma chave de idempotência. É o que amarra a
 * escrita às linhas que aquele arquivo criou.
 *
 * **Data não amarra.** `where mes = '2026-07-01'` parece um filtro e não é: ele
 * casa com a linha de quem quer que seja naquele mês. Foi por aí que a 0045
 * passou — e havia três custos fixos de verdade em julho de 2026. Quando uma
 * suíte de fato cria a linha daquele mês, isso se declara embaixo, com o
 * motivo.
 *
 * ## O que fica de fora, e por quê
 *
 * Escrita feita **como `anon` ou `authenticated`** dentro de um bloco que
 * espera ser barrada: ali a RLS está no caminho, zero linha é o resultado
 * esperado, e a ausência de `where` é o próprio teste. A 0044 tem duas assim.
 * O teste as reconhece pelo `set local role` imediatamente anterior.
 */

const PASTA = join(import.meta.dirname, "..", "supabase", "tests");

const ESCRITA = /^[ \t]*(update|delete from)\s+(public\.[a-z_]+)\b([^;]*);/gim;

/** Um `where` amarrado às linhas que a própria suíte plantou. */
const AMARRA =
  /\b(conta_id|paciente_id|profissional_id|sessao_id|cobranca_id|anamnese_id|oferta_id|vaga_id|pacote_id|enquadre_id|documento_id|post_id|objetivo_id|registro_id|auth_user_id|\bid\b|chave_idem|evento_id|provedor|provedor_msg_id|canal|slug|caminho|url|nome|titulo|email|token|codigo|rubrica)\b/i;

function semComentarios(texto: string): string {
  return texto.replace(/(^|[^:])--[^\n]*/g, (l, antes) => antes);
}

/** O papel vigente no ponto do arquivo: o último `set local role` / `reset role`. */
function papelEm(fonte: string, pos: number): "postgres" | "anon" | "authenticated" {
  const antes = fonte.slice(0, pos);
  const ultimo = [...antes.matchAll(/set\s+local\s+role\s+(anon|authenticated)|reset\s+role/gi)].pop();
  if (!ultimo || ultimo[0].toLowerCase().startsWith("reset")) return "postgres";
  return ultimo[1].toLowerCase() as "anon" | "authenticated";
}

/**
 * As exceções, declaradas com o motivo — e não uma lista de "ignore isto".
 *
 * Uma varredura sem lugar para o caso legítimo vira uma varredura que alguém
 * desliga. O que a mantém honesta é o motivo escrito ao lado: se ele deixar de
 * valer, a linha sai daqui.
 */
const DECLARADAS: { arquivo: string; trecho: string; porque: string }[] = [
  {
    arquivo: "0047_limite_de_pacientes.sql",
    trecho: "update public.planos set limite_pacientes_ativos = null",
    porque:
      "não destrói: RESTAURA o valor de produção. Desde a 0048 nenhum plano " +
      "limita pacientes, e `null` em todos é exatamente o estado certo. A " +
      "suíte liga o limite para si mesma e é obrigação dela desligar de volta — " +
      "a própria 0047 confere isso na parte 3.",
  },
  {
    arquivo: "0050_operar_o_negocio.sql",
    trecho: "delete from public.custos_fixos",
    porque:
      "esta suíte CRIA a linha que apaga: `lancar_custo_fixo(date '2031-03-01', …)`, " +
      "duas vezes na verificação 24. O filtro é por mês, que sozinho não amarra — " +
      "o que amarra é a data-sentinela de 2031, que nenhuma operação real usa.",
  },
  {
    arquivo: "0050_operar_o_negocio.sql",
    trecho: "delete from public.precos_canal",
    porque: "mesma razão: a suíte insere os preços de 2031-03-01 e 2020-01-01 que apaga.",
  },
  {
    arquivo: "0045_negocio.sql",
    trecho: "delete from public.precos_canal",
    porque:
      "a suíte insere o preço de 2026-08-01 na verificação 21 — o 'preço absurdo, " +
      "vigente a partir de agosto' — e apaga o próprio rastro na linha seguinte.",
  },
];

const SUITES = readdirSync(PASTA)
  .filter((f) => f.endsWith(".sql"))
  .sort();

describe("uma suíte não apaga o que ela não criou", () => {
  it("toda escrita feita como postgres amarra nas linhas da própria suíte", () => {
    const soltas: string[] = [];

    for (const arquivo of SUITES) {
      const bruto = readFileSync(join(PASTA, arquivo), "utf8");
      const fonte = semComentarios(bruto);

      for (const m of fonte.matchAll(ESCRITA)) {
        // Com a RLS no caminho, zero linha é o resultado esperado — e é o teste.
        if (papelEm(fonte, m.index!) !== "postgres") continue;

        const corpo = m[3].toLowerCase();
        const onde = corpo.includes(" where ") ? corpo.split(" where ", 2)[1] : "";

        if (onde && AMARRA.test(onde)) continue;

        const declarada = DECLARADAS.find(
          (d) => d.arquivo === arquivo && m[0].includes(d.trecho),
        );
        if (declarada) continue;

        const linha = fonte.slice(0, m.index!).split("\n").length;
        soltas.push(
          `${arquivo}:${linha}  ${m[0].replace(/\s+/g, " ").trim().slice(0, 110)}`,
        );
      }
    }

    expect(
      soltas,
      "Escrita como `postgres` sem `where` que amarre nas linhas da própria suíte.\n" +
        "Num banco vazio é inofensiva; num banco com outras contas dentro ela\n" +
        "reescreve ou apaga dado que a suíte não criou.\n\n" +
        soltas.join("\n"),
    ).toEqual([]);
  });
});
