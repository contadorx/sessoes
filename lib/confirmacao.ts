/**
 * A confirmação ativa — o lado puro.
 *
 * Espelha a 0057 com os **mesmos valores esperados** da suíte
 * `0057_confirmacao_ativa.sql`.
 *
 * AS DUAS REGRAS QUE ATRAVESSAM O ARQUIVO
 *
 * **1 · Nada aqui libera horário.** Não existe função que cancele, que proponha
 * cancelar por silêncio, ou que devolva uma ação para o estado `silenciosa`. A
 * recusa explícita tem ação — porque é o que ela já faz —, e ela é *um toque
 * dela*, com o custo à vista. O silêncio não tem nenhuma.
 *
 * **2 · O padrão é não pedir.** `null` é "não pede", e é o que toda conta tem
 * hoje. Ligar é decisão de quem atende; 24 é o que a prática de campo mostrou,
 * e é sugestão, não imposição.
 */

export type EixoConfirmacao =
  | "nao_pedida"
  | "pendente"
  | "confirmada"
  | "recusada"
  | "silenciosa";

/** A mesma faixa do `check` de `enquadres.confirmacao_horas_antes`. */
export const MIN_HORAS = 2;
export const MAX_HORAS = 168;

/**
 * O que a prática de campo mostrou (02/09): um dia antes, por WhatsApp.
 *
 * É sugestão do formulário, e não padrão do sistema — o padrão do sistema é
 * `null`, e continua sendo.
 */
export const HORAS_SUGERIDAS = 24;

export const OPCOES_DE_HORAS: { valor: number; rotulo: string }[] = [
  { valor: 3, rotulo: "3 horas antes" },
  { valor: 12, rotulo: "12 horas antes" },
  { valor: 24, rotulo: "um dia antes" },
  { valor: 48, rotulo: "dois dias antes" },
];

export function horasValidas(h: number | null): boolean {
  if (h === null) return true;
  return Number.isInteger(h) && h >= MIN_HORAS && h <= MAX_HORAS;
}

export function problemaNasHoras(h: number | null): string | null {
  if (horasValidas(h)) return null;
  if (h !== null && h < MIN_HORAS) {
    return `Menos de ${MIN_HORAS} horas não dá tempo de reagir a uma resposta.`;
  }
  return `Mais de uma semana ninguém lembra do que confirmou (o máximo é ${MAX_HORAS} horas).`;
}

// ============================================================ os rótulos

const ROTULO: Record<EixoConfirmacao, string> = {
  nao_pedida: "sem confirmação",
  pendente: "aguardando resposta",
  confirmada: "confirmou",
  recusada: "avisou que não vem",
  silenciosa: "não respondeu",
};

const EXPLICA: Record<EixoConfirmacao, string> = {
  nao_pedida: "Esta sessão não pede confirmação.",
  pendente: "A pergunta saiu e a resposta ainda não chegou.",
  confirmada: "A pessoa respondeu que vem.",
  recusada:
    "A pessoa avisou que não vem. O horário continua reservado — liberar é decisão sua, e o valor da política aparece antes.",
  silenciosa:
    "A pergunta saiu e ninguém respondeu até perto da hora. Não quer dizer que a pessoa não vem: quem não respondeu pode estar sem bateria.",
};

export function rotuloConfirmacao(e: string): string {
  return ROTULO[e as EixoConfirmacao] ?? e;
}

export function explicaConfirmacao(e: string): string {
  return EXPLICA[e as EixoConfirmacao] ?? "";
}

/**
 * O estado tem ação?
 *
 * **Só a recusa**, e a ação é *dela*: cancelar, com o custo da política à
 * vista. O silêncio devolve `null` — é a invariante 2 da 0057, e é o teste que
 * decide este arquivo.
 */
export function acaoDaConfirmacao(e: string): { rotulo: string; tipo: "cancelar" } | null {
  return e === "recusada" ? { rotulo: "Liberar o horário", tipo: "cancelar" } : null;
}

/** Merece aparecer na faixa do dia? O que não foi perguntado, não. */
export function apareceNoDia(e: string): boolean {
  return e === "pendente" || e === "confirmada" || e === "recusada" || e === "silenciosa";
}

// ============================================================ os dois números

export type RespostaBruta = {
  de: string;
  ate: string;
  pedidas: number;
  confirmadas: number;
  recusadas: number;
  silenciosas: number;
  pendentes: number;
  antecedencia_media_h: number | string | null;
};

export type Resposta = {
  de: string;
  ate: string;
  pedidas: number;
  confirmadas: number;
  recusadas: number;
  silenciosas: number;
  pendentes: number;
  /** Quantas responderam, de qualquer jeito. */
  responderam: number;
  /** 0 a 100, ou null quando ninguém foi perguntado. */
  taxa: number | null;
  antecedenciaH: number | null;
};

export function lerResposta(b: RespostaBruta): Resposta {
  const responderam = b.confirmadas + b.recusadas;
  const a = b.antecedencia_media_h;
  return {
    de: b.de,
    ate: b.ate,
    pedidas: b.pedidas,
    confirmadas: b.confirmadas,
    recusadas: b.recusadas,
    silenciosas: b.silenciosas,
    pendentes: b.pendentes,
    responderam,
    taxa: b.pedidas === 0 ? null : Math.round((responderam / b.pedidas) * 100),
    antecedenciaH: a === null || a === undefined ? null : Number(a),
  };
}

/**
 * A frase que decide se o bloco se paga.
 *
 * O critério de pronto do P3 diz que **se a taxa for baixa, o bloco não se paga,
 * e isso aparece no primeiro mês**. Uma feature que não traz consigo o
 * instrumento que a mediria é uma feature que ninguém desliga depois — então a
 * frase diz o número e diz o que fazer com ele, inclusive quando ele é ruim.
 */
export function fraseDaResposta(r: Resposta): string {
  if (r.pedidas === 0) {
    return "Nenhuma confirmação pedida no período. Ela é opcional, e liga no combinado de cada paciente.";
  }

  const partes = [
    `${r.responderam} de ${r.pedidas} responderam (${r.taxa}%).`,
  ];

  if (r.antecedenciaH !== null) {
    partes.push(
      `Em média, a resposta chegou ${r.antecedenciaH.toString().replace(".", ",")} horas antes da sessão.`,
    );
  }

  if (r.taxa !== null && r.taxa < 40) {
    partes.push(
      "Com taxa baixa assim, a confirmação está custando mensagem e incômodo sem devolver informação — vale desligar.",
    );
  }

  return partes.join(" ");
}

/** A frase do ajuste, no combinado do paciente. */
export function fraseDoAjuste(h: number | null): string {
  if (h === null) {
    return "Não pede confirmação. É o padrão, e é o que faz o sistema não falar com ninguém sem você mandar.";
  }
  const rotulo = OPCOES_DE_HORAS.find((o) => o.valor === h)?.rotulo ?? `${h} horas antes`;
  return `Pergunta ${rotulo}. Quem responder muda a agenda sozinho; quem não responder aparece na sua tela, e nada acontece com o horário.`;
}
