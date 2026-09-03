import type { EstadoInicial } from "@/app/(app)/comecar/page";

/**
 * O que ainda falta configurar — uma resposta só, para as duas telas que
 * perguntam.
 *
 * Havia duas contas diferentes rodando sobre o mesmo estado. A agenda dizia
 * *"faltam os pacientes, a fila e o primeiro horário — **três passos**"*; a
 * página que ela abria em seguida se chamava *"**cinco** passos"*. Ninguém
 * mentiu de propósito: são dois arquivos, escritos em semanas diferentes, e a
 * segunda fonte de verdade nasce assim toda vez.
 *
 * E a condição da faixa era pior que divergente: ela exigia `vagas_abertas > 0`,
 * que só acontece quando **uma paciente desmarca de verdade**. Numa conta bem
 * configurada, sem cancelamento nenhum, a faixa "Terminar de configurar" ficava
 * na agenda para sempre — e alarme que toca sempre vira paisagem.
 *
 * ---
 *
 * **Por que três passos e não cinco.** Um passo é uma caixa que se marca, e uma
 * caixa que se marca precisa de um sinal que o sistema consiga observar sem
 * inventar. Dois dos cinco não tinham:
 *
 * - *"Confira o combinado de cada uma"* se dava por feito com `enquadres > 0` —
 *   que é exatamente o que o passo anterior já produz ao importar a lista. Ela
 *   nunca conferiu valor nem política, e a tela dizia que sim. (O outro sinal
 *   disponível, `politica_definida`, é pior: ele é falso para quem decidiu não
 *   cobrar cancelamento, e essa decisão é legítima — a caixa nunca fecharia.)
 * - *"Deixe a cascata correr"* não tem ação nenhuma nessa tela: ele descreve o
 *   que vai acontecer sozinho da próxima vez que alguém desmarcar. Um passo que
 *   ela não pode dar não é um passo — é a frase que fecha a página.
 *
 * O que os dois diziam não se perdeu: virou texto dentro dos passos que
 * sobraram. O que se perdeu foi a caixa que se marcava sem ela ter feito nada.
 */
export type Passo = "horas" | "pessoas" | "fila";

/** Os três, na ordem em que se fazem. */
export const PASSOS: Passo[] = ["horas", "pessoas", "fila"];

export function feito(estado: EstadoInicial, passo: Passo): boolean {
  switch (passo) {
    // O denominador: sem as horas que ela decide disponibilizar, nenhum número
    // do produto tem com o que ser comparado.
    case "horas":
      return estado.janelas > 0;
    case "pessoas":
      return estado.pacientes > 0;
    case "fila":
      return estado.na_fila > 0;
  }
}

export function faltando(estado: EstadoInicial): Passo[] {
  return PASSOS.filter((p) => !feito(estado, p));
}

/** Nome curto de cada passo, para a faixa da agenda dizer o que falta. */
const NOME: Record<Passo, string> = {
  horas: "os seus horários",
  pessoas: "os pacientes",
  fila: "a fila",
};

/**
 * A frase da faixa, montada a partir do que falta de verdade.
 *
 * Sem número escrito à mão: "três passos" era uma constante numa tela e outra
 * constante em outra, e as duas envelheceram em direções diferentes.
 */
export function fraseDoQueFalta(estado: EstadoInicial): string {
  const faltam = faltando(estado);
  if (faltam.length === 0) return "";

  const nomes = faltam.map((p) => NOME[p]);
  const lista =
    nomes.length === 1 ? nomes[0] : nomes.slice(0, -1).join(", ") + " e " + nomes.at(-1);

  const quantos = faltam.length === 1 ? "um passo" : `${faltam.length === 2 ? "dois" : "três"} passos`;
  return `faltam ${lista} — ${quantos}, uma vez só`;
}
