import { duracao, lerCapacidade, type Capacidade, type CapacidadeBruta } from "@/lib/capacidade";
import { formatar } from "@/lib/dinheiro";

/**
 * O livro-razão da sessão — o lado puro.
 *
 * Espelha a 0056 com os **mesmos valores esperados** da suíte
 * `0056_livro_razao.sql`. Se as duas contas divergirem, uma das duas falha.
 *
 * AS DUAS REGRAS QUE ATRAVESSAM O ARQUIVO
 *
 * **1 · Duas horas de capacidade podem valer uma receita só.** É o caso
 * `reposta`, e é o que nenhum sistema do mercado separa. Nenhuma função aqui
 * soma a hora reposta com a hora que a repôs, e há teste que reprova o dia em
 * que alguém somar.
 *
 * **2 · A sétima causa não tem botão.** `hora_nunca_vendida` aparece como fato
 * e não gera sugestão de contato com ninguém — o Código de Ética veda induzir
 * pessoa a recorrer a serviços, e uma lista de horas vazias com botão de
 * "oferecer" é isso com outro nome. `acaoDaCausa` devolve `null` para ela, e o
 * teste confere.
 */

// ============================================================ os eixos

export type EixoAgenda = "reservada" | "realizada" | "ausente" | "cancelada";
export type EixoCapacidade = "vendida" | "perdida" | "reposta";
export type EixoFinanceiro =
  | "nao_cobrada" | "cobrada" | "paga" | "perdoada" | "estornada" | "credito";
export type EixoFiscal = "nao_aplicavel" | "pendente" | "emitida" | "cancelada";

/**
 * O mesmo mapa de `public.eixo_agenda`.
 *
 * `prevista` e `confirmada` colapsam porque a diferença entre elas é
 * confirmação, e confirmação tem eixo próprio. `cedo` e `tarde` colapsam porque
 * a diferença entre elas é política, e política decide cobrança, não ocupação.
 */
export function eixoAgenda(estado: string): EixoAgenda {
  switch (estado) {
    case "realizada": return "realizada";
    case "falta": return "ausente";
    case "cancelada_cedo":
    case "cancelada_tarde": return "cancelada";
    default: return "reservada";
  }
}

const ROTULO_AGENDA: Record<EixoAgenda, string> = {
  reservada: "reservadas",
  realizada: "atendidas",
  ausente: "faltas",
  cancelada: "canceladas",
};

const ROTULO_FINANCEIRO: Record<EixoFinanceiro, string> = {
  nao_cobrada: "sem cobrança",
  cobrada: "cobrada, em aberto",
  paga: "paga",
  perdoada: "perdoada",
  estornada: "estornada",
  credito: "coberta por mensalidade ou pacote",
};

export function rotuloAgenda(e: EixoAgenda): string {
  return ROTULO_AGENDA[e] ?? e;
}

export function rotuloFinanceiro(e: string): string {
  return ROTULO_FINANCEIRO[e as EixoFinanceiro] ?? e;
}

/** O tempo protegido nunca é hora vaga, e a hora entregue nunca é perda. */
export function eHoraPerdida(cap: string | null): boolean {
  return cap === "perdida" || cap === "reposta";
}

// ============================================================ as sete causas

export type Causa =
  | "falta_sem_cobranca"
  | "falta_com_cobranca"
  | "cancelada_nao_revendida"
  | "reposta"
  | "atendida_nao_recebida"
  | "abaixo_do_valor"
  | "hora_nunca_vendida";

export type LinhaDeCausa = {
  causa: Causa;
  n: number | null;
  valor: number | null;
  minutos?: number | null;
  acao: string | null;
};

const TEXTO: Record<Causa, { titulo: string; explica: string }> = {
  falta_sem_cobranca: {
    titulo: "Falta sem cobrança",
    explica: "A hora não aconteceu e nada foi cobrado por ela.",
  },
  falta_com_cobranca: {
    titulo: "Falta com cobrança",
    explica:
      "A hora se perdeu e o dinheiro entrou. Não é perda de receita — é a política funcionando.",
  },
  cancelada_nao_revendida: {
    titulo: "Cancelada e não reocupada",
    explica: "Houve janela e ninguém entrou no lugar.",
  },
  reposta: {
    titulo: "Reposta",
    explica:
      "A hora se perdeu e a pessoa consumiu outra hora com o mesmo dinheiro: duas horas de capacidade, uma receita.",
  },
  atendida_nao_recebida: {
    titulo: "Atendida e não recebida",
    explica: "A hora aconteceu e a cobrança continua em aberto.",
  },
  abaixo_do_valor: {
    titulo: "Recebida abaixo do combinado",
    explica: "A diferença entre o valor do combinado e o que entrou.",
  },
  hora_nunca_vendida: {
    titulo: "Hora nunca vendida",
    explica:
      "Capacidade que você declarou e que não virou sessão. Aparece como fato, e o sistema não sugere nada a fazer com ela.",
  },
};

export function tituloDaCausa(c: Causa): string {
  return TEXTO[c]?.titulo ?? c;
}

export function explicaCausa(c: Causa): string {
  return TEXTO[c]?.explica ?? "";
}

/**
 * A ação de cada causa — e o `null` da última é a decisão do build.
 *
 * Devolver qualquer coisa para `hora_nunca_vendida` seria transformar ausência
 * de demanda em lista de contatos, que é onde a versão anterior deste roadmap
 * descarrilava.
 */
export function acaoDaCausa(c: Causa): { rotulo: string; href: string } | null {
  switch (c) {
    case "falta_sem_cobranca":
      return { rotulo: "ver em aberto", href: "/recebimentos" };
    case "cancelada_nao_revendida":
      return { rotulo: "ver a fila", href: "/encaixes" };
    case "reposta":
      return { rotulo: "rever a política", href: "/perfil" };
    case "atendida_nao_recebida":
      return { rotulo: "ver quem está devendo", href: "/recebimentos" };
    case "abaixo_do_valor":
      return { rotulo: "ver os combinados", href: "/pacientes" };
    default:
      // `falta_com_cobranca` não tem ação porque não é problema, e
      // `hora_nunca_vendida` não tem ação porque a ação seria antiética.
      return null;
  }
}

// ============================================================ o livro

export type LivroBruto = {
  de: string;
  ate: string;
  capacidade: CapacidadeBruta;
  horas: Partial<Record<EixoAgenda, number>>;
  minutos_usados: number;
  receita_reconhecida: number | string;
  causas: {
    causa: Causa;
    n: number | null;
    valor: number | string | null;
    minutos?: number | null;
    acao: string | null;
  }[];
  completude: { sessoes: number; completas: number; resolvidas: number; repostas: number };
};

export type Livro = {
  de: string;
  ate: string;
  capacidade: Capacidade;
  horas: Record<EixoAgenda, number>;
  minutosUsados: number;
  receita: number;
  causas: LinhaDeCausa[];
  completude: { sessoes: number; completas: number; resolvidas: number; repostas: number };
};

const num = (v: number | string | null | undefined): number =>
  v === null || v === undefined ? 0 : typeof v === "number" ? v : Number(v);

export function lerLivro(b: LivroBruto): Livro {
  return {
    de: b.de,
    ate: b.ate,
    capacidade: lerCapacidade(b.capacidade),
    horas: {
      reservada: b.horas?.reservada ?? 0,
      realizada: b.horas?.realizada ?? 0,
      ausente: b.horas?.ausente ?? 0,
      cancelada: b.horas?.cancelada ?? 0,
    },
    minutosUsados: b.minutos_usados ?? 0,
    receita: num(b.receita_reconhecida),
    causas: (b.causas ?? []).map((c) => ({
      causa: c.causa,
      n: c.n ?? null,
      valor: c.valor === null || c.valor === undefined ? null : num(c.valor),
      minutos: c.minutos ?? null,
      acao: c.acao ?? null,
    })),
    completude: b.completude,
  };
}

/** Só as causas que têm alguma coisa a dizer, na ordem em que doem. */
export function causasComPeso(l: Livro): LinhaDeCausa[] {
  return l.causas.filter(
    (c) => (c.n ?? 0) > 0 || (c.valor ?? 0) > 0 || (c.minutos ?? 0) > 0,
  );
}

/**
 * A frase da receita reconhecida.
 *
 * Ela diz **o que o número não é** quando há reposta no período, porque é
 * exatamente aí que a intuição erra: duas horas saíram da agenda e só uma
 * receita entrou.
 */
export function fraseDaReceita(l: Livro): string {
  const reposta = l.causas.find((c) => c.causa === "reposta");
  const base = `${formatar(Math.round(l.receita * 100))} de receita reconhecida em ${l.horas.realizada} hora${l.horas.realizada === 1 ? "" : "s"} atendida${l.horas.realizada === 1 ? "" : "s"}.`;

  if ((reposta?.n ?? 0) > 0) {
    const n = reposta!.n!;
    return (
      `${base} ${n} hora${n > 1 ? "s" : ""} sa${n > 1 ? "íram" : "iu"} da agenda e ` +
      `volt${n > 1 ? "aram" : "ou"} em outro horário com o mesmo dinheiro — ` +
      `${n > 1 ? "elas contam" : "ela conta"} como capacidade usada duas vezes, e como receita uma vez só.`
    );
  }

  return base;
}

/**
 * A frase da completude — o critério de pronto do P2 virando texto.
 *
 * Ela existe na tela porque um livro-razão com metade das linhas em branco não
 * mede nada, e quem olha o painel precisa saber se pode confiar no que vê.
 */
export function fraseDaCompletude(l: Livro): string {
  const { sessoes, completas } = l.completude;
  if (sessoes === 0) return "Nenhuma sessão no período.";
  const pct = Math.round((completas / sessoes) * 100);
  if (completas === sessoes) {
    return `As ${sessoes} sessões do período estão classificadas, e nenhuma precisou de digitação.`;
  }
  return `${completas} de ${sessoes} sessões classificadas (${pct}%). O resto o sistema ainda não conseguiu resolver sozinho.`;
}

/** O tempo que virou sessão, para a tela dizer o que sobrou sem adjetivar. */
export function fraseDoUso(l: Livro): string {
  if (l.capacidade.semJanela) {
    return "Sem horários declarados, não há com o que comparar as horas atendidas.";
  }
  const sobra = Math.max(0, l.capacidade.vendavel - l.minutosUsados);
  return (
    `${duracao(l.minutosUsados)} das ${duracao(l.capacidade.vendavel)} disponíveis ` +
    `foram para a agenda. ${duracao(sobra)} não viraram sessão.`
  );
}
