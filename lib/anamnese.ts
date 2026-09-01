/**
 * A anamnese e o aviso da terceira — do lado do app (PR3, PR5).
 *
 * Uma coisa importa mais que todas as outras neste arquivo, e ela é uma
 * ausência: **não existe função aqui que monte formulário para o paciente.**
 * A fronteira 6 do doc 11 diz que pergunta clínica não vai por formulário, e a
 * anamnese acontece na conversa. O que existe é um **roteiro** — títulos de
 * seção, editáveis — e não um questionário.
 *
 * O resto é o de sempre: os roteiros são gêmeos de `roteiro_padrao` no banco, e
 * as frases do aviso são aritmética virada em português, sem juízo sobre
 * ninguém.
 */

export type ModeloAnamnese = "adulto" | "infantil" | "casal";
export type EstadoAnamnese = "aberta" | "fechada";

export type Secao = { titulo: string; texto: string };

export type Adendo = { id: string; texto: string; criado_em: string };

export type Anamnese = {
  id: string;
  modelo: ModeloAnamnese;
  estado: EstadoAnamnese;
  conteudo: Secao[];
  medicacao_atual: string | null;
  fechada_em: string | null;
  criado_em: string;
  adendos: Adendo[];
};

export type Aviso = {
  mostrar: boolean;
  sessoes: number;
  limite: number;
  existe: boolean;
  estado: EstadoAnamnese | null;
  anamnese_id: string | null;
};

export const MODELOS: { valor: ModeloAnamnese; rotulo: string; quando: string }[] = [
  { valor: "adulto", rotulo: "Adulto", quando: "atendimento individual de adulto" },
  { valor: "infantil", rotulo: "Infantil", quando: "criança ou adolescente, com responsáveis" },
  { valor: "casal", rotulo: "Casal", quando: "os dois na sala" },
];

/**
 * Os três roteiros — gêmeos de `public.roteiro_padrao`.
 *
 * Ficam aqui para a tela poder **mostrar o roteiro antes de abrir**: escolher
 * o modelo às cegas e descobrir a estrutura depois é escolher errado uma vez a
 * cada três.
 *
 * São títulos, nunca perguntas. Um roteiro com "?" seria questionário, e
 * questionário com campo fixo é instrumento clínico — território de outra
 * profissão (fronteira 3 do doc 11). Há teste dos dois lados para isso.
 */
export function roteiroPadrao(modelo: ModeloAnamnese): string[] {
  if (modelo === "infantil") {
    return [
      "Quem procurou, e por quê",
      "Com quem mora, e como é a rotina",
      "Escola",
      "História do desenvolvimento",
      "Saúde e acompanhamentos",
      "O que a família já tentou",
      "Combinados com os responsáveis",
    ];
  }
  if (modelo === "casal") {
    return [
      "O que trouxe os dois aqui",
      "História da relação",
      "Como cada um descreve a queixa",
      "Filhos, casa e rotina",
      "Acompanhamentos anteriores",
      "O que cada um espera",
    ];
  }
  return [
    "Queixa e o que a trouxe agora",
    "História de vida",
    "Trabalho e rotina",
    "Vínculos e apoio",
    "Saúde e acompanhamentos",
    "Atendimentos anteriores",
    "Objetivos",
  ];
}

/** Quantas seções já têm texto. O que está vazio aparece vazio (Manual, nov/2025). */
export function secoesEscritas(a: Anamnese | null): number {
  if (!a) return 0;
  return a.conteudo.filter((s) => s.texto.trim() !== "").length;
}

export function fraseDoProgresso(a: Anamnese | null): string {
  if (!a) return "Ainda não há anamnese.";
  const escritas = secoesEscritas(a);
  const total = a.conteudo.length;

  if (a.estado === "fechada") {
    const n = a.adendos.length;
    const base = `Fechada com ${escritas} de ${total} seções escritas.`;
    if (n === 0) return base;
    return `${base} ${n === 1 ? "Um adendo depois disso." : `${n} adendos depois disso.`}`;
  }

  if (escritas === 0) return `Aberta, ${total} seções em branco.`;
  return `Aberta · ${escritas} de ${total} seções escritas.`;
}

/**
 * O aviso da terceira — e ele fala do registro dela.
 *
 * "A anamnese ainda está aberta", nunca "este caso está atrasado". A diferença
 * é a linha do doc 07 que a B27 já guarda com teste, e ela vale mais aqui: um
 * aviso é justamente o lugar onde o software fica tentado a opinar.
 */
export function fraseDoAviso(a: Aviso): string {
  if (!a.mostrar) return "";
  const quantas = `${a.sessoes} ${a.sessoes === 1 ? "sessão" : "sessões"}`;
  return a.existe
    ? `${quantas} realizadas e a anamnese ainda está aberta.`
    : `${quantas} realizadas e a anamnese ainda não foi começada.`;
}

/**
 * O rodapé que explica por que o aviso existe — e que o número é provisório.
 *
 * Dizer que o 3 é palpite não é humildade decorativa: é o que impede que ele
 * vire regra por hábito antes de alguém que atende opinar sobre ele.
 */
export function fraseDoLimite(a: Aviso): string {
  return `O aviso aparece a partir da ${a.limite}ª sessão realizada. O número é um ponto de partida — ele vai ser revisto com uma psicóloga.`;
}

export function rotuloEstado(e: EstadoAnamnese): string {
  return e === "fechada" ? "fechada" : "aberta";
}

export function rotuloModelo(m: ModeloAnamnese): string {
  return MODELOS.find((x) => x.valor === m)?.rotulo ?? m;
}

/**
 * O que muda ao fechar, dito antes de fechar.
 *
 * Fechar é irreversível — não existe reabrir, por desenho. Uma ação sem volta
 * que não avisa que não tem volta é uma armadilha.
 */
export const AVISO_DE_FECHAMENTO =
  "Depois de fechada, a anamnese não se reescreve nem reabre: o que chegar depois entra como adendo, com a data em que chegou.";

/** Uma anamnese em branco não fecha — o Manual pede que não se guarde vazio. */
export function podeFechar(a: Anamnese | null): boolean {
  return Boolean(a) && a!.estado === "aberta" && secoesEscritas(a) > 0;
}

/** "2026-03-05T18:00:00Z" → "05/03/2026". */
export function diaBr(iso: string): string {
  const [a, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}
