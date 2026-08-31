import { percentual } from "@/lib/dinheiro";

/**
 * As regras puras do enquadre — o combinado entre a psicóloga e o paciente.
 * Sem banco, sem rede: só o que dá para testar de olhos fechados.
 */

/** 0 = domingo, para casar com o `extract(dow)` do Postgres. */
export const DIAS = [
  "domingo",
  "segunda",
  "terça",
  "quarta",
  "quinta",
  "sexta",
  "sábado",
] as const;

export type DiaSemana = 0 | 1 | 2 | 3 | 4 | 5 | 6;

export type Politica = {
  horas: number;
  percentual: number;
};

/** "terça, 15h" — e "15h30" quando não for hora cheia. */
export function rotuloHorario(dia: number, hora: string): string {
  const [h, m] = hora.split(":");
  const relogio = m && m !== "00" ? `${Number(h)}h${m}` : `${Number(h)}h`;
  return `${DIAS[dia] ?? "?"}, ${relogio}`;
}

/** A política em português, do jeito que aparece no contrato e na tela. */
export function rotuloPolitica({ horas, percentual: pct }: Politica): string {
  if (pct === 0) return "falta não é cobrada";
  if (horas === 0) return `falta cobra ${pct}% em qualquer aviso`;

  const janela = horas === 24 ? "24 horas" : horas === 48 ? "48 horas" : `${horas} horas`;
  const quanto = pct === 100 ? "a sessão inteira" : `${pct}%`;
  return `desmarcar com menos de ${janela} cobra ${quanto}`;
}

export type Cancelamento = "cancelada_cedo" | "cancelada_tarde";

/**
 * O coração da D2: o cancelamento se classifica sozinho.
 *
 * A conta é em horas corridas entre o aviso e o início da sessão. Avisar
 * depois que a sessão começou é sempre tardio — e uma política de 0 hora
 * significa "cobro sempre", não "nunca cobro".
 */
export function classificarCancelamento(
  inicioDaSessao: Date,
  avisadoEm: Date,
  politica: Politica,
): Cancelamento {
  const horasDeAntecedencia =
    (inicioDaSessao.getTime() - avisadoEm.getTime()) / 3_600_000;

  return horasDeAntecedencia >= politica.horas ? "cancelada_cedo" : "cancelada_tarde";
}

/**
 * Quanto cobrar de uma falta, em centavos. Cancelamento dentro do prazo não
 * gera cobrança nenhuma — é isso que faz a fila valer a pena para o paciente
 * também: avisar cedo é melhor para os dois lados.
 */
export function multaDeFalta(
  valorCentavos: number,
  classificacao: Cancelamento,
  politica: Politica,
): number {
  if (classificacao === "cancelada_cedo") return 0;
  return percentual(valorCentavos, politica.percentual);
}

/** Uma frase que a psicóloga lê e reconhece o próprio combinado. */
export function resumoDoEnquadre(e: {
  dia_semana: number;
  hora: string;
  duracao_min: number;
  valor: string;
  politica_horas: number;
  politica_percentual: number;
}): string {
  const dinheiro = Number(e.valor).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });

  return [
    rotuloHorario(e.dia_semana, e.hora),
    `${e.duracao_min} min`,
    dinheiro,
    rotuloPolitica({ horas: e.politica_horas, percentual: e.politica_percentual }),
  ].join(" · ");
}
