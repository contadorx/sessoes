import { diaBr } from "@/lib/registro";

/**
 * O plano terapêutico leve — a parte que é regra e não banco.
 *
 * **Leve significa leve.** O bloco 2 do registro já tem um campo de objetivos
 * em texto livre, e ele fica: serve para o que se escreve uma vez. O que
 * faltava é o objetivo que **tem prazo para ser revisto**, e que some de vista
 * sem ele.
 *
 * A regra que este arquivo carrega, e que é a build inteira:
 *
 *     **vencido é fato, não alerta.**
 *
 * A data que passou aparece onde ela olha, e não vira notificação, contagem
 * regressiva nem cor de urgência. "Marcado para revisar em 12/03" é uma frase
 * sobre um combinado dela consigo mesma. "Esta paciente está atrasada" seria
 * uma frase sobre a paciente — e frequência clínica não é decisão de software
 * (fronteira 3, a mesma que matou o D8).
 *
 * Por isso não há aqui nenhuma função que sugira data, nem que conte quantos
 * estão vencidos para virar número numa faixa. Há uma que **descreve** o
 * estado, e é só.
 */

export type Objetivo = {
  id: string;
  texto: string;
  revisar_em: string | null;
  concluido_em: string | null;
  criado_em: string;
};

export type EstadoDoObjetivo = "concluido" | "a_revisar" | "sem_data" | "aberto";

/**
 * Em que pé está — e note que `a_revisar` não se chama `atrasado`.
 *
 * A palavra importa: "a revisar" descreve o que fazer; "atrasado" atribui uma
 * falta, e a falta seria de quem?
 */
export function estadoDoObjetivo(o: Objetivo, hoje: string): EstadoDoObjetivo {
  if (o.concluido_em) return "concluido";
  if (!o.revisar_em) return "sem_data";
  return o.revisar_em <= hoje ? "a_revisar" : "aberto";
}

/**
 * A frase de cada estado.
 *
 * Nenhuma delas fala da paciente, e nenhuma usa "atrasado", "pendente" ou
 * "esquecido". A data marcada é dela; o que passou dela também.
 */
export function fraseDoObjetivo(o: Objetivo, hoje: string): string {
  switch (estadoDoObjetivo(o, hoje)) {
    case "concluido":
      return `concluído em ${diaBr((o.concluido_em ?? "").slice(0, 10))}`;
    case "a_revisar":
      return `você marcou para revisar em ${diaBr(o.revisar_em!)}`;
    case "aberto":
      return `revisar em ${diaBr(o.revisar_em!)}`;
    case "sem_data":
      return "sem data de revisão";
  }
}

/**
 * O resumo, para o topo do bloco. Fato e contagem, sem adjetivo.
 *
 * Devolve string vazia quando não há objetivo nenhum: um "0 objetivos" seria o
 * produto cobrando dela um plano que ela não é obrigada a escrever.
 */
export function fraseDoPlano(objetivos: Objetivo[], hoje: string): string {
  const abertos = objetivos.filter((o) => !o.concluido_em);
  if (objetivos.length === 0) return "";

  const aRevisar = abertos.filter((o) => estadoDoObjetivo(o, hoje) === "a_revisar").length;

  const partes: string[] = [];
  partes.push(abertos.length === 1 ? "1 objetivo aberto" : `${abertos.length} objetivos abertos`);
  if (aRevisar === 1) partes.push("1 com a data de revisão alcançada");
  else if (aRevisar > 1) partes.push(`${aRevisar} com a data de revisão alcançada`);

  return partes.join(" · ") + ".";
}

/**
 * Só o que ainda está aberto, na ordem em que o banco devolveu.
 *
 * A tela mostra os concluídos atrás de um toque: eles são parte do registro —
 * concluir não apaga —, mas a pergunta de todo dia é "o que falta".
 */
export function separar(objetivos: Objetivo[]): {
  abertos: Objetivo[];
  concluidos: Objetivo[];
} {
  return {
    abertos: objetivos.filter((o) => !o.concluido_em),
    concluidos: objetivos.filter((o) => o.concluido_em),
  };
}
