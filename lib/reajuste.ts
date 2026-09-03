import { formatar } from "@/lib/dinheiro";

/**
 * O reajuste, do lado dela.
 *
 * O mecanismo já existia desde a B4 — fecha o combinado, abre o próximo — e não
 * é ele que faz a psicóloga adiar o reajuste por dois anos. O que falta é
 * **quando** e **com que palavras**, e é só isso que mora aqui.
 *
 * Três coisas que este módulo não faz, e nenhuma volta:
 *
 * **1. Não sugere valor.** Nem percentual, nem inflação, nem "abaixo do valor de
 * referência", nem comparação com o mercado. O valor é dela, e um número
 * sugerido numa tela vira âncora — quem vê 8% escreve 8%.
 *
 * **2. Não lembra de reajustar.** Um aviso anual automático é o produto
 * decidindo calado que está na hora, e "o default que decide por ela" é
 * antipadrão nomeado desta casa.
 *
 * **3. Não julga a antecedência.** A tela diz quantos dias são; não diz se é
 * pouco. Quem sabe quanto tempo aquela relação precisa é quem atende — e há
 * paciente que prefere saber em cima e paciente que precisa de dois meses.
 */

/** Quantos dias entre hoje e a data em que o valor novo passa a valer. */
export function diasDeAviso(hoje: string, vigencia: string): number {
  const a = Date.parse(`${hoje}T12:00:00Z`);
  const b = Date.parse(`${vigencia}T12:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return 0;
  return Math.round((b - a) / 86_400_000);
}

/**
 * A data sugerida: o dia 1º do mês que vem.
 *
 * É convenção de calendário, não opinião sobre o preço dela — e a tela diz que
 * é sugestão. A mensalidade vira no dia 1º, então virar o valor junto é a única
 * data em que a conta do mês não precisa ser explicada a ninguém.
 */
export function primeiroDoMesQueVem(hoje: string): string {
  const d = new Date(`${hoje}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return hoje;
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + 1);
  return d.toISOString().slice(0, 10);
}

const DIA_MES = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "numeric",
  month: "long",
});

export function dataPorExtenso(iso: string): string {
  const d = new Date(`${iso}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return iso;
  return DIA_MES.format(d);
}

/**
 * A frase que ela lê antes de confirmar.
 *
 * Diz o que vai acontecer e o que **não** vai — e a segunda metade é a que
 * importa: o medo de reajustar é o de mexer no que já está combinado. A sessão
 * que já está marcada mantém o valor de hoje, e isso não é gentileza do produto:
 * é como o banco funciona, porque o valor viaja congelado na sessão.
 */
export function fraseDoReajuste(
  deCentavos: number,
  paraCentavos: number,
  hoje: string,
  vigencia: string,
): string {
  const dias = diasDeAviso(hoje, vigencia);
  const quando =
    dias <= 0
      ? "a partir de hoje"
      : dias === 1
        ? "a partir de amanhã"
        : `a partir de ${dataPorExtenso(vigencia)}, daqui a ${dias} dias`;

  return (
    `De ${formatar(deCentavos)} para ${formatar(paraCentavos)}, ${quando}. ` +
    `As sessões marcadas até lá mantêm ${formatar(deCentavos)}.`
  );
}

/**
 * O que a paciente vai receber, para ela ler antes de mandar.
 *
 * Não é um segundo texto: é o **mesmo** corpo do template `aviso_de_reajuste`,
 * montado por `lib/mensageria/templates.ts`. Duas redações do mesmo aviso — uma
 * na pré-visualização e outra na mensagem — seriam a segunda fonte de verdade
 * na única frase do produto que a paciente recebe sobre dinheiro.
 */
export const TEMPLATE_DO_AVISO = "aviso_de_reajuste" as const;

/** O mesmo, para a pausa. */
export const TEMPLATE_DA_PAUSA = "aviso_de_pausa" as const;

/**
 * A pausa, em uma frase.
 *
 * "Sai da agenda" e "sai da conta do mês" são duas consequências diferentes, e
 * ela precisa das duas antes de confirmar — a segunda é dinheiro, e até esta
 * build o produto cobrava o mês cheio de um mês em que o consultório não abriu.
 */
export function fraseDaPausa(de: string, ate: string, sessoes: number): string {
  const periodo =
    de === ate ? dataPorExtenso(de) : `${dataPorExtenso(de)} a ${dataPorExtenso(ate)}`;

  if (sessoes === 0) {
    return `De ${periodo}. Não há sessão marcada nesse período.`;
  }

  return (
    `De ${periodo}. ${sessoes === 1 ? "Uma sessão sai" : `${sessoes} sessões saem`} ` +
    `da agenda, e ${sessoes === 1 ? "ela" : "elas"} saem também da conta do mês de quem paga mensalidade.`
  );
}
