import { DIAS } from "@/lib/enquadre";

/**
 * A vaga fixa — o lado puro (D13).
 *
 * O vocabulário desta build existe para uma coisa: deixar claro, na tela, que
 * **são duas filas diferentes**. Uma pessoa espera uma hora extra esta semana; a
 * outra espera um horário para o próximo ano. Chamar as duas de "fila de
 * espera" seria o erro que o produto inteiro existe para não cometer.
 */

export type MotivoDaVaga = "alta" | "abandono" | "mudanca" | "outro";

export const MOTIVOS: { valor: MotivoDaVaga; rotulo: string }[] = [
  { valor: "alta", rotulo: "alta" },
  { valor: "abandono", rotulo: "abandono" },
  { valor: "mudanca", rotulo: "mudou de horário" },
  { valor: "outro", rotulo: "outro" },
];

export function rotuloMotivo(m: string): string {
  return MOTIVOS.find((x) => x.valor === m)?.rotulo ?? m;
}

/** "às terças, 15h" — o horário que se repete, e não um dia específico. */
export function horarioSemanal(dia: number, hora: string): string {
  const nome = DIAS[dia] ?? "?";
  const plural = nome.endsWith("s") ? nome : `${nome}s`;
  const [h, m] = (hora ?? "").split(":");
  const relogio = m && m !== "00" ? `${Number(h)}h${m}` : `${Number(h)}h`;
  return `às ${plural}, ${relogio}`;
}

export type EstadoDaVaga = "aberta" | "oferecida" | "preenchida" | "sem_takers" | "cancelada";

export type VagaLinha = {
  id: string;
  dia_semana: number;
  hora: string;
  duracao_min: number;
  motivo: string;
  valor_anterior: string | null;
  aberta_em: string;
  fechada_em: string | null;
  fechada_por: string | null;
  novo_paciente: string | null;
  /** Nome de quem está com a oferta viva, se houver. */
  oferecida_a: string | null;
  /** Nome de quem ficou com a vaga. */
  ficou_com: string | null;
};

export function estadoDaVaga(v: VagaLinha): EstadoDaVaga {
  if (v.fechada_por === "preenchida") return "preenchida";
  if (v.fechada_por === "sem_takers") return "sem_takers";
  if (v.fechada_por === "cancelada") return "cancelada";
  return v.oferecida_a ? "oferecida" : "aberta";
}

/**
 * A frase da vaga.
 *
 * A de `preenchida` é a mais importante da tela inteira: o aceite **não** cria
 * combinado, e o próximo passo é uma conversa. Se essa frase for ambígua, ela
 * acha que está tudo pronto e a pessoa fica com um horário sem valor, sem
 * política e sem contrato.
 */
export function rotuloDaVaga(v: VagaLinha): string {
  const e = estadoDaVaga(v);

  if (e === "preenchida") {
    return `${v.ficou_com ?? "Alguém"} aceitou. Falta combinar valor, política e contrato — o horário só existe depois disso.`;
  }
  if (e === "oferecida") {
    return `Oferecida a ${v.oferecida_a}. Sem resposta, segue para a próxima da fila.`;
  }
  if (e === "sem_takers") {
    return "A fila de entrada acabou sem ninguém disponível. Você pode reabrir quando alguém novo entrar.";
  }
  if (e === "cancelada") {
    return "Vaga cancelada por você.";
  }
  return "Aberta e ainda não oferecida.";
}

/** O que fazer agora, em uma frase. Vazio quando não há nada a fazer. */
export function proximoPasso(v: VagaLinha): string {
  const e = estadoDaVaga(v);
  if (e === "aberta") return "Oferecer para a fila de entrada";
  if (e === "preenchida") return "Abrir o combinado";
  return "";
}

/**
 * A elegibilidade, como ela aparece na tela.
 *
 * Vem do banco com todo mundo e o motivo — inclusive quem **não** foi chamado.
 * É o que faz a fila ser confiável: ela vê por que a pessoa que tinha em mente
 * ficou de fora, em vez de desconfiar do sistema.
 */
export type Elegivel = {
  paciente_id: string;
  nome: string;
  elegivel: boolean;
  motivo: string;
  ordem: number;
};

/** Quantas pessoas a cascata ainda pode alcançar. */
export function quantosNaFrente(lista: Elegivel[]): number {
  return lista.filter((e) => e.elegivel).length;
}
