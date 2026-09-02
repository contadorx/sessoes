import { formatar } from "@/lib/dinheiro";
import { lerCapacidade, type Capacidade, type CapacidadeBruta } from "@/lib/capacidade";
import {
  acaoDaCausa,
  type Causa,
  type LinhaDeCausa,
} from "@/lib/livro";

/**
 * A receita em risco, por causa (P5) — o lado puro.
 *
 * Espelha a 0059 com os **mesmos valores esperados** da suíte
 * `0059_receita_em_risco.sql`: 300 minutos vendáveis, 100 atendidos → 33,3%;
 * 50 minutos pagos → 16,7%; R$ 400 reconhecidos em 5 horas → R$ 80 por hora.
 *
 * AS QUATRO REGRAS QUE ATRAVESSAM O ARQUIVO
 *
 * **1 · Os quatro números andam juntos.** Não existe função aqui que devolva
 * ocupação sozinha, e `fraseDoCockpit` recusa montar uma frase que fale só de
 * ocupação. Ocupação subindo com receita por hora caindo é sintoma, e só se
 * enxerga com os dois lado a lado — é a fronteira 4 nova do doc 11.
 *
 * **2 · Sem semana declarada, os percentuais são nulos.** Zero por cento é uma
 * afirmação sobre o trabalho de alguém; nulo é a ausência de uma declaração. A
 * frase, nesse caso, fala do que falta declarar e **não contém "0%"**.
 *
 * **3 · Não existe meta, e nada elogia.** Nenhum alvo, nenhuma barra de
 * progresso rumo a 100%, e passar de 100% é fato — nunca parabéns. Um produto
 * para psicólogas que comemora ocupação alta é um produto empurrando alguém a
 * eliminar o próprio tempo de registro e de descanso.
 *
 * **4 · A hora nunca vendida não ganha ação.** Ela aparece como fato. Qualquer
 * botão ali seria induzir alguém a recorrer aos serviços, que o Código de Ética
 * veda — e é onde a versão anterior do roadmap descarrilava.
 */

// ====================================================== o cockpit

export type CockpitBruto = {
  de: string;
  ate: string;
  ocupacao_realizada: number | string | null;
  ocupacao_paga: number | string | null;
  receita_por_hora: number | string | null;
  receita_reconhecida: number | string;
  causas: {
    causa: Causa;
    n: number | null;
    valor: number | string | null;
    minutos?: number | null;
    acao: string | null;
  }[];
  minutos: {
    realizada: number;
    paga: number;
    reservada: number;
    vendavel: number;
    protegido: number;
  };
  capacidade: CapacidadeBruta;
  completude: { sessoes: number; completas: number; resolvidas: number; repostas: number };
  alem_do_declarado: boolean;
};

export type Cockpit = {
  de: string;
  ate: string;
  /** 0 a 100 e além; `null` quando não há semana declarada. */
  ocupacaoRealizada: number | null;
  ocupacaoPaga: number | null;
  /** Em centavos, por hora vendável. `null` sem semana declarada. */
  receitaPorHora: number | null;
  receitaCentavos: number;
  causas: LinhaDeCausa[];
  minutos: CockpitBruto["minutos"];
  capacidade: Capacidade;
  completude: CockpitBruto["completude"];
  alemDoDeclarado: boolean;
  /** Não há o que medir enquanto ninguém declarou a semana. */
  semJanela: boolean;
};

const num = (v: number | string | null | undefined): number =>
  v === null || v === undefined ? 0 : typeof v === "number" ? v : Number(v);

const ou = (v: number | string | null | undefined): number | null =>
  v === null || v === undefined ? null : typeof v === "number" ? v : Number(v);

export function lerCockpit(b: CockpitBruto): Cockpit {
  const capacidade = lerCapacidade(b.capacidade);
  return {
    de: b.de,
    ate: b.ate,
    ocupacaoRealizada: ou(b.ocupacao_realizada),
    ocupacaoPaga: ou(b.ocupacao_paga),
    receitaPorHora:
      b.receita_por_hora === null || b.receita_por_hora === undefined
        ? null
        : Math.round(num(b.receita_por_hora) * 100),
    receitaCentavos: Math.round(num(b.receita_reconhecida) * 100),
    causas: (b.causas ?? []).map((c) => ({
      causa: c.causa,
      n: c.n ?? null,
      valor: c.valor === null || c.valor === undefined ? null : num(c.valor),
      minutos: c.minutos ?? null,
      acao: c.acao ?? null,
    })),
    minutos: b.minutos,
    capacidade,
    completude: b.completude,
    alemDoDeclarado: b.alem_do_declarado === true,
    semJanela: capacidade.semJanela,
  };
}

// ====================================================== os quatro, juntos

export type NumeroDoCockpit = {
  chave: "realizada" | "paga" | "por_hora" | "perda";
  rotulo: string;
  valor: string;
  nota: string;
};

const pct = (n: number): string => `${n.toString().replace(".", ",")}%`;

/**
 * Os quatro números, na ordem, e **sempre os quatro**.
 *
 * A função devolve a lista inteira ou nada — não há como pedir um. É a mesma
 * decisão que a 0059 tomou no banco, do lado de cá: quem quiser mostrar só
 * ocupação vai ter de escrever a exceção à mão, e aí a decisão fica visível em
 * revisão em vez de acontecer por conveniência.
 */
export function quatroNumeros(c: Cockpit): NumeroDoCockpit[] {
  const perda = perdaTotalCentavos(c);

  return [
    {
      chave: "realizada",
      rotulo: "ocupação realizada",
      valor: c.ocupacaoRealizada === null ? "—" : pct(c.ocupacaoRealizada),
      nota: "das horas que você declarou para atender",
    },
    {
      chave: "paga",
      rotulo: "ocupação paga",
      valor: c.ocupacaoPaga === null ? "—" : pct(c.ocupacaoPaga),
      nota: "hora prestada com o dinheiro dentro",
    },
    {
      chave: "por_hora",
      rotulo: "receita por hora disponível",
      valor: c.receitaPorHora === null ? "—" : formatar(c.receitaPorHora),
      nota: "o que cada hora declarada rendeu",
    },
    {
      chave: "perda",
      rotulo: "não virou receita",
      valor: formatar(perda),
      nota: "somado das causas com valor",
    },
  ];
}

/** A soma das causas que têm valor. A hora nunca vendida não tem, e é por isso. */
export function perdaTotalCentavos(c: Cockpit): number {
  return c.causas
    .filter((x) => x.causa !== "falta_com_cobranca" && (x.valor ?? 0) > 0)
    .reduce((t, x) => t + Math.round((x.valor ?? 0) * 100), 0);
}

/** Só as causas que têm alguma coisa a dizer. */
export function perdasComPeso(c: Cockpit): LinhaDeCausa[] {
  return c.causas.filter(
    (x) => (x.n ?? 0) > 0 || (x.valor ?? 0) > 0 || (x.minutos ?? 0) > 0,
  );
}

/** A ação da causa, ou `null`. Delegado ao livro — uma fonte só. */
export function acaoDaPerda(c: Causa) {
  return acaoDaCausa(c);
}

// ====================================================== as frases

/**
 * A frase do cockpit.
 *
 * Ela **nunca fala de ocupação sem falar de receita por hora**: são as duas que,
 * juntas, distinguem trabalhar mais de ganhar mais. E não parabeniza nada.
 */
export function fraseDoCockpit(c: Cockpit): string {
  if (c.semJanela || c.ocupacaoRealizada === null) {
    return "Você ainda não declarou quantas horas por semana quer atender — e sem isso não há como dizer quanto da sua capacidade virou receita.";
  }

  const partes = [
    `${pct(c.ocupacaoRealizada)} das horas declaradas foram atendidas, e ${
      c.ocupacaoPaga === null ? "—" : pct(c.ocupacaoPaga)
    } já entraram.`,
  ];

  if (c.receitaPorHora !== null) {
    partes.push(`Cada hora declarada rendeu ${formatar(c.receitaPorHora)}.`);
  }

  return partes.join(" ");
}

/**
 * A frase do tempo protegido, e ela vai junto do cockpit sempre.
 *
 * Sem ela, ocupação se lê como espaço vazio a preencher — e tempo de prontuário
 * e de descanso são capacidade declarada, não ociosidade.
 */
export function fraseDoProtegido(c: Cockpit): string {
  if (c.minutos.protegido <= 0) return "";
  const h = (c.minutos.protegido / 60).toFixed(1).replace(".", ",");
  return `${h}h da sua semana estão reservadas para registro e descanso. Elas não entram nesta conta, e é assim que tem de ser.`;
}

/**
 * Passar de 100%: fato, não elogio.
 *
 * A frase diz o que aconteceu e devolve a leitura para ela — pode ser que a
 * semana declarada tenha ficado velha, e pode ser que ela esteja atendendo além
 * do que decidiu. As duas são dela para responder.
 */
export function fraseDoAlemDoDeclarado(c: Cockpit): string {
  if (!c.alemDoDeclarado) return "";
  return "Você atendeu mais horas do que declarou para o período. Ou a semana declarada ficou velha, ou o mês passou do que você tinha decidido.";
}

// ====================================================== o alerta que ninguém usou

export type AlertaARever = {
  causa: Causa;
  n: number | null;
  valor: number | string | null;
  nunca_usado: boolean;
};

export type AlertasBrutos = { de: string; ate: string; alertas: AlertaARever[] };

/**
 * A frase do critério de pronto do P5: *"todo alerta que ninguém clicar por três
 * meses é candidato a sumir"*.
 *
 * Ela é dirigida a **mim**, não a ela — é medida do produto. Por isso não diz
 * "você não usou": diz que o alerta não serviu.
 */
export function fraseDosAlertas(a: AlertasBrutos): string {
  const n = a.alertas?.length ?? 0;
  if (n === 0) {
    return "Todos os alertas que apareceram nos últimos três meses levaram a alguma coisa.";
  }
  return `${n} ${n === 1 ? "alerta apareceu" : "alertas apareceram"} nos últimos três meses sem levar a nada. ${
    n === 1 ? "Ele é candidato" : "Eles são candidatos"
  } a sumir da tela.`;
}
