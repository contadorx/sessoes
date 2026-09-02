/**
 * A avaliação do produto — do lado do app (OP8).
 *
 * Cinco regras carregam este módulo, e nenhuma delas é sobre a nota:
 *
 *   1. **a nota é do produto, não da pessoa.** Nada que ela responda muda o que
 *      o sistema faz por ela — nem faixa, nem freio, nem preço, nem tela;
 *   2. **não se pede num momento de dor.** Os momentos são lista fechada no
 *      banco, e nenhum deles é dentro de um cancelamento, de uma cobrança ou de
 *      um erro. E não se pergunta a quem está com a assinatura em atraso;
 *   3. **nota baixa não some.** Nenhuma função lê a avaliação e escreve na
 *      relação comercial — há verificação varrendo o catálogo;
 *   4. **não se troca nota por nada.** Sem desconto por nota, sem
 *      funcionalidade destravada por nota;
 *   5. **o texto é dela**, e sai na exportação da conta.
 *
 * A sexta regra é de interface e mora aqui: **a pergunta se recusa.** Um convite
 * que não pode ser dispensado não é convite.
 *
 * Gêmeo de `avaliacao_pendente` e `nota_do_produto` no banco, com os mesmos
 * valores esperados da suíte 0060.
 */

/** Os três lugares em que se pode perguntar. Gêmeo do check de `momento`. */
export const MOMENTOS = ["perfil", "convite", "fim_do_mes"] as const;
export type Momento = (typeof MOMENTOS)[number];

export function momentoValido(m: string): m is Momento {
  return (MOMENTOS as readonly string[]).includes(m);
}

export type Pendencia = {
  pedir: boolean;
  motivo: string;
  ultima: string | null;
  dias_de_uso: number;
  sessoes_realizadas: number;
};

/** O que a tela mostra quando a leitura falha: não pergunta nada. */
export const NAO_PERGUNTAR: Pendencia = {
  pedir: false,
  motivo: "não deu para saber",
  ultima: null,
  dias_de_uso: 0,
  sessoes_realizadas: 0,
};

/**
 * Os quatro portões, e três deles são silêncios.
 *
 * A ordem importa: `atraso` é conferido antes de `avaliou há pouco` porque é o
 * motivo mais forte para calar. Pedir nota a quem está devendo é pedir a nota
 * errada pela razão errada — e ainda mistura a conversa da cobrança com a
 * conversa do produto.
 */
export function decidir(
  diasDeUso: number,
  sessoesRealizadas: number,
  emAtraso: boolean,
  diasDesdeAUltima: number | null,
): { pedir: boolean; motivo: string } {
  if (diasDeUso < 30) return { pedir: false, motivo: "conta nova" };
  if (sessoesRealizadas < 10) return { pedir: false, motivo: "pouco uso" };
  if (emAtraso) return { pedir: false, motivo: "assinatura em atraso" };
  if (diasDesdeAUltima !== null && diasDesdeAUltima < 90) {
    return { pedir: false, motivo: "avaliou há pouco" };
  }
  return { pedir: true, motivo: "pode perguntar" };
}

/** A escala. Fora dela o banco recusa, e a tela nem oferece. */
export function notaValida(n: number): boolean {
  return Number.isInteger(n) && n >= 0 && n <= 10;
}

/**
 * A pergunta.
 *
 * Não é "você recomendaria o Sessões para uma colega": essa mede disposição a
 * expor a própria reputação, que é outra coisa e depende de quanto ela gosta da
 * colega. A pergunta é sobre o trabalho, porque é o que o produto promete
 * mexer.
 */
export const PERGUNTA = "De 0 a 10, quanto o Sessões reduziu o trabalho que não é atender?";

export const PERGUNTA_ABERTA = "O que ainda dá mais trabalho do que devia?";

/**
 * As âncoras das pontas, e elas não são "ruim" e "ótimo".
 *
 * Rotular a ponta baixa de "ruim" convida a pessoa a ser gentil. Descrevendo o
 * fato — não mudou nada — a nota baixa deixa de ser uma acusação e passa a ser
 * uma informação, que é o que eu preciso que ela seja.
 */
export const ANCORA_BAIXA = "não mudou nada";
export const ANCORA_ALTA = "mudou muito";

/**
 * O que se diz depois, e é a mesma frase para nota 0 e para nota 10.
 *
 * Agradecer mais quem deu 10 é ensinar que a nota alta agrada — e a partir daí
 * o instrumento mede a vontade de agradar. Pedir explicação só de quem deu
 * nota baixa é a mesma coisa pelo outro lado.
 */
export function agradecimento(): string {
  return "Anotado. Isso vai para a lista do que construir a seguir.";
}

// ─────────────────────────────────────────────────────────────── a leitura

export type Agregado = {
  n: number;
  media: number | null;
  promotores: number;
  neutros: number;
  detratores: number;
  nps: number | null;
  distribuicao: Record<string, number>;
  por_plano: Record<string, { n: number; media: number | null }>;
};

/** A amostra mínima para o NPS existir. É a do portão 1→2 do doc 04. */
export const AMOSTRA_MINIMA = 5;

/**
 * O NPS, com a recusa embutida.
 *
 * Com três respostas ele anda 66 pontos por pessoa. Um número que se move assim
 * vira decisão errada com cara de medida — então abaixo da amostra mínima ele
 * é **nulo**, e não zero. Mesma distinção do P5: zero é uma afirmação, nulo é a
 * ausência de uma.
 */
export function nps(promotores: number, detratores: number, n: number): number | null {
  if (n < AMOSTRA_MINIMA) return null;
  return Math.round((100 * (promotores - detratores)) / n);
}

export function fraseDoNps(a: Agregado): string {
  if (a.n === 0) return "Ninguém avaliou ainda.";
  if (a.nps === null) {
    return `${a.n} ${a.n === 1 ? "resposta" : "respostas"} — poucas para um NPS que signifique alguma coisa.`;
  }
  return `NPS ${a.nps}, em ${a.n} respostas.`;
}

/**
 * A distribuição em texto, porque a média esconde dois produtos diferentes.
 *
 * Média 7,4 pode ser dez notas 7 ou cinco notas 10 e cinco notas 5. O segundo
 * caso é um produto que serve muito para metade das pessoas e não serve para a
 * outra — e essa é a informação que decide o que construir.
 */
export function fraseDaDistribuicao(a: Agregado): string {
  if (a.n === 0) return "";
  return `${a.detratores} até 6 · ${a.neutros} entre 7 e 8 · ${a.promotores} de 9 para cima.`;
}
