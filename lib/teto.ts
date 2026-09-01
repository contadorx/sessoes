/**
 * O teto de mensagens — do lado do app (OP2).
 *
 * A regra que este módulo existe para carregar, e que vale mais que a
 * aritmética: **o teto barra o que gera negócio novo, nunca o que o paciente
 * precisa saber.**
 *
 * Um teto de mensagens parece decisão comercial e não é — ele decide quem fica
 * sem aviso. Se barrasse a próxima mensagem qualquer, o que deixaria de sair
 * seria um lembrete de véspera, ou o aviso de que a sessão de amanhã foi
 * desmarcada, e alguém iria até o consultório encontrar a porta fechada por um
 * limite comercial que essa pessoa não escolheu e nem sabe que existe.
 *
 * Gêmeo de `teto_da_conta` no banco, com os mesmos valores esperados da suíte
 * 0046.
 */

export type Teto = {
  tem_teto: boolean;
  limite: number | null;
  usadas: number;
  restantes: number | null;
  estourou: boolean;
  pct: number;
};

export type Template = {
  codigo: string;
  descricao: string;
  essencial: boolean;
  motivo: string;
};

/** O que nunca é barrado, em qualquer plano. Gêmeo de `templates.essencial`. */
export const ESSENCIAIS = [
  "lembrete_de_sessao",
  "aviso_de_desmarque",
  "encaixe_confirmado",
] as const;

export function ehEssencial(template: string): boolean {
  return (ESSENCIAIS as readonly string[]).includes(template);
}

/**
 * Quando avisar, e quando calar.
 *
 * Abaixo de 70% o aviso é ruído: ela não precisa pensar no teto num mês
 * normal. De 70 a 99 é aviso; a partir de 100 é estado, não aviso.
 *
 * O limiar existe porque um plano cujo limite só aparece quando estoura não é
 * plano, é armadilha — e porque um aviso que aparece o mês inteiro é um aviso
 * que se aprende a não ler.
 */
export type Aviso = "nenhum" | "perto" | "estourou";

export function nivelDoAviso(t: Teto): Aviso {
  if (!t.tem_teto) return "nenhum";
  if (t.estourou) return "estourou";
  if (t.pct >= 70) return "perto";
  return "nenhum";
}

/** A frase do topo. Fala do plano, nunca do uso que ela faz dele. */
export function fraseDoTeto(t: Teto): string {
  if (!t.tem_teto) return "";
  if (t.estourou) {
    return `O plano Grátis chegou ao limite de ${t.limite} mensagens neste mês.`;
  }
  return `${t.usadas} de ${t.limite} mensagens usadas neste mês.`;
}

/**
 * O que exatamente parou de acontecer — e o que continua.
 *
 * É a parte que não pode faltar. "Você atingiu o limite" sozinho deixa ela
 * imaginando o pior, e o pior aqui seria justamente o que não acontece: o
 * paciente ficar sem lembrete.
 */
export function fraseDoQueParou(t: Teto): string {
  if (!t.estourou) return "";
  return (
    "A fila de encaixe está pausada e os avisos de cobrança não saem até o dia 1º. " +
    "Lembrete de véspera, aviso de desmarque e confirmação de encaixe continuam saindo normalmente — " +
    "essas o paciente precisa receber, e nenhum limite nosso alcança elas."
  );
}

/** O que ela pode fazer agora, sem que o sistema decida por ela. */
export function fraseDaSaida(t: Teto): string {
  if (!t.estourou) return "";
  return "Você continua podendo oferecer o horário e cobrar pelo seu WhatsApp — o que muda é que o sistema não faz isso sozinho até virar o mês.";
}

/**
 * Quantas faltam, em português, sem exagerar nem minimizar.
 */
export function fraseDoRestante(t: Teto): string {
  if (!t.tem_teto) return "Seu plano não tem limite de mensagens.";
  if (t.estourou) return "Nenhuma mensagem de fila ou cobrança sai até o dia 1º.";
  const r = t.restantes ?? 0;
  if (r === 1) return "Falta 1 mensagem de fila ou cobrança neste mês.";
  return `Faltam ${r} mensagens de fila ou cobrança neste mês.`;
}

/**
 * A pergunta que a tela precisa responder antes de a fila parar.
 *
 * `pausaria` diz se abrir uma vaga agora não ofereceria para ninguém. É o que
 * evita o pior sintoma possível: ela cancelar uma sessão, ver a fila não fazer
 * nada, e concluir que o produto quebrou.
 */
export function filaPausada(t: Teto): boolean {
  return t.tem_teto && t.estourou;
}

export function fraseDaFilaPausada(t: Teto): string {
  return filaPausada(t)
    ? "A fila não vai oferecer esta vaga: o limite de mensagens do mês foi atingido."
    : "";
}

/**
 * O estado de uma mensagem, em português.
 *
 * `barrada_no_teto` tem frase própria e explícita. Uma mensagem que não saiu
 * precisa dizer que não saiu — o modo de falha ruim aqui seria ela sumir da
 * tela e a psicóloga descobrir semanas depois que ninguém foi cobrado.
 */
export type EstadoMensagem =
  | "pendente"
  | "enviando"
  | "enviada"
  | "entregue"
  | "falhou"
  | "cancelada"
  | "barrada_no_teto";

export function rotuloEstadoMensagem(e: EstadoMensagem): string {
  switch (e) {
    case "pendente":
      return "na fila";
    case "enviando":
      return "saindo";
    case "enviada":
      return "enviada";
    case "entregue":
      return "entregue";
    case "falhou":
      return "falhou";
    case "cancelada":
      return "cancelada";
    case "barrada_no_teto":
      return "não saiu — limite do plano";
  }
}

/** Estados em que a mensagem não vai mais sair, aconteça o que acontecer. */
export function terminal(e: EstadoMensagem): boolean {
  return e === "entregue" || e === "cancelada" || e === "barrada_no_teto";
}
