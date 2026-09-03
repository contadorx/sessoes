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

// ============================================ a seção do combinado foi tocada?

/**
 * Os padrões da seção "O combinado" — **num lugar só.**
 *
 * `CamposEnquadre` nasce com estes valores e `lerEnquadre` decide por eles se a
 * seção foi tocada. Enquanto eram duas listas, o dia padrão do formulário podia
 * mudar para segunda e o servidor continuaria achando que terça é "intocado":
 * um combinado inteiro passaria por não-preenchido, que é o defeito que esta
 * função existe para fechar.
 */
export const PADRAO_ENQUADRE = {
  dia_semana: 2,
  duracao_min: 50,
  modelo_cobranca: "avulso",
  politica_horas: 24,
  politica_percentual: 50,
} as const;

export type CamposDoCombinado = {
  hora: string;
  valor: string;
  dia_semana: string;
  duracao_min: string;
  modelo_cobranca: string;
  mensalidade_valor: string;
  social: boolean;
  falta_cobra_a_parte: boolean;
  politica_horas: string;
  politica_percentual: string;
  confirmacao_horas_antes: string;
};

/**
 * Ela mexeu em alguma coisa do combinado?
 *
 * O que isto conserta: `lerEnquadre` devolvia "sem combinado" quando hora **e**
 * valor estavam vazios, e devolvia isso **antes** de olhar dia, duração,
 * modelo de cobrança, política de falta e confirmação. Quem preenchia o dia,
 * escolhia mensalista e ajustava a política, mas pulava a hora, criava a
 * paciente e perdia o combinado inteiro — sem erro, sem aviso, sem nada na
 * tela. Ela descobriria na semana seguinte, quando nenhuma sessão nascesse.
 *
 * Campo em branco conta como intocado, e não como zero: `politica_percentual`
 * vazio não é "não cobro nada".
 */
export function combinadoTocado(c: CamposDoCombinado): boolean {
  const texto = (v: string) => v.trim() !== "";
  if (texto(c.hora) || texto(c.valor) || texto(c.mensalidade_valor)) return true;
  if (texto(c.confirmacao_horas_antes)) return true;
  if (c.social || c.falta_cobra_a_parte) return true;

  if (texto(c.modelo_cobranca) && c.modelo_cobranca !== PADRAO_ENQUADRE.modelo_cobranca) {
    return true;
  }

  const numeros: [string, number][] = [
    [c.dia_semana, PADRAO_ENQUADRE.dia_semana],
    [c.duracao_min, PADRAO_ENQUADRE.duracao_min],
    [c.politica_horas, PADRAO_ENQUADRE.politica_horas],
    [c.politica_percentual, PADRAO_ENQUADRE.politica_percentual],
  ];
  for (const [bruto, padrao] of numeros) {
    if (!texto(bruto)) continue;
    const n = Number(bruto);
    // Valor que não é número é mexida — e cai na validação, que diz onde.
    if (!Number.isFinite(n) || n !== padrao) return true;
  }

  return false;
}
