import { DIAS } from "@/lib/enquadre";

/**
 * As janelas da fila, escritas do jeito que ela fala.
 *
 * No banco a coluna é `jsonb` e aceita várias janelas por paciente. A tela da
 * B8 oferece **uma** — "terça ou quarta, depois das 14h" cobre quase todo mundo
 * —, e o formato guarda espaço para as demais sem migração.
 */

export type Janela = {
  dias?: number[];
  de?: string;
  ate?: string;
};

/** "13:00" → "13h" · "13:30" → "13h30" */
export function hora(h: string): string {
  const [hh, mm] = h.split(":");
  return mm && mm !== "00" ? `${Number(hh)}h${mm}` : `${Number(hh)}h`;
}

function listaDeDias(dias: number[]): string {
  const nomes = [...dias].sort((a, b) => a - b).map((d) => DIAS[d]).filter(Boolean);
  if (nomes.length === 0) return "";
  if (nomes.length === 1) return nomes[0];

  // Sequência corrida vira "de segunda a sexta".
  const ordenados = [...dias].sort((a, b) => a - b);
  const corrida = ordenados.every((d, i) => i === 0 || d === ordenados[i - 1] + 1);
  if (corrida && nomes.length > 2) return `de ${nomes[0]} a ${nomes[nomes.length - 1]}`;

  return `${nomes.slice(0, -1).join(", ")} ou ${nomes[nomes.length - 1]}`;
}

function umaJanela(j: Janela): string {
  const dias = j.dias && j.dias.length > 0 ? listaDeDias(j.dias) : "";

  let horario = "";
  if (j.de && j.ate) horario = `das ${hora(j.de)} às ${hora(j.ate)}`;
  else if (j.de) horario = `depois das ${hora(j.de)}`;
  else if (j.ate) horario = `até as ${hora(j.ate)}`;

  if (dias && horario) return `${dias}, ${horario}`;
  if (dias) return dias;
  if (horario) return horario;
  return "qualquer horário";
}

/** A janela inteira em uma frase. Sem janela = aceita qualquer hora. */
export function rotuloJanela(janelas: Janela[] | null | undefined): string {
  if (!janelas || janelas.length === 0) return "qualquer horário";
  return janelas.map(umaJanela).join(" ou ");
}

/**
 * Monta a janela a partir do formulário. Campos vazios somem em vez de virarem
 * restrição — quem não escolheu dia aceita qualquer dia.
 */
export function montarJanela(entrada: {
  dias?: number[];
  de?: string;
  ate?: string;
}): Janela[] {
  const j: Janela = {};

  if (entrada.dias && entrada.dias.length > 0 && entrada.dias.length < 7) {
    j.dias = [...entrada.dias].sort((a, b) => a - b);
  }
  if (entrada.de && /^\d{2}:\d{2}$/.test(entrada.de)) j.de = entrada.de;
  if (entrada.ate && /^\d{2}:\d{2}$/.test(entrada.ate)) j.ate = entrada.ate;

  return Object.keys(j).length === 0 ? [] : [j];
}

/** "11 dias sem sessão" — o número que ordena a fila. */
export function tempoDeEspera(ultimaSessao: string | null, agora = new Date()): string {
  if (!ultimaSessao) return "ainda sem sessão";

  const dias = Math.floor(
    (agora.getTime() - new Date(ultimaSessao).getTime()) / 86_400_000,
  );

  if (dias <= 0) return "sessão hoje";
  if (dias === 1) return "1 dia sem sessão";
  return `${dias} dias sem sessão`;
}
