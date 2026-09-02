/**
 * A faixa de sessões do plano — do lado do app (OP8).
 *
 * A regra que este módulo carrega, e que vale mais que a aritmética:
 *
 *     **A faixa é a unidade de preço. Ela não é uma cerca.**
 *
 * Nenhuma função daqui, e nenhum gatilho no banco, impede alguém de marcar a
 * nona sessão numa faixa de oito. Isso é decisão, e a razão está escrita na
 * migração 0060: quem encontraria a porta fechada não é a psicóloga que
 * escolheu o plano, é a paciente que já tem hora marcada.
 *
 * O que o produto faz quando a faixa estoura é **dizer**, uma vez, sem alarme,
 * e sugerir subir de plano no ciclo seguinte. Não há excedente por mensagem,
 * não há cobrança automática, não há função bloqueada.
 *
 * Gêmeo de `faixa_da_conta` no banco, com os mesmos valores esperados da suíte
 * 0060.
 */

export type Faixa = {
  tem_faixa: boolean;
  /** Por profissional que atende. */
  limite: number | null;
  profissionais: number;
  /** `limite` × profissionais ativos. É o número que a tela mostra. */
  limite_total: number | null;
  usadas: number;
  restantes: number | null;
  acima: boolean;
  pct: number;
  /**
   * `true` = o número é fair-use meu, e não faixa vendida. A página de preços
   * diz "sem faixa"; o número só serve para eu enxergar a clínica disfarçada de
   * autônoma, e nunca aparece para ela como limite.
   */
  e_fair_use: boolean;
};

/** Faixa vazia — o que a tela mostra quando a leitura falha. */
export const SEM_FAIXA: Faixa = {
  tem_faixa: false,
  limite: null,
  profissionais: 1,
  limite_total: null,
  usadas: 0,
  restantes: null,
  acima: false,
  pct: 0,
  e_fair_use: false,
};

/**
 * A aritmética, isolada — os mesmos valores esperados da suíte 0060.
 *
 * `pct` passa de 100 e não estanca, pela mesma razão do P5: passar do declarado
 * é fato, e estancar esconderia a informação de quem precisa dela.
 */
export function calcular(
  limite: number | null,
  profissionais: number,
  usadas: number,
  eFairUse = false,
): Faixa {
  const prof = Math.max(profissionais, 1);
  if (limite === null) {
    return {
      tem_faixa: false,
      limite: null,
      profissionais: prof,
      limite_total: null,
      usadas,
      restantes: null,
      acima: false,
      pct: 0,
      e_fair_use: eFairUse,
    };
  }
  const total = limite * prof;
  return {
    tem_faixa: true,
    limite,
    profissionais: prof,
    limite_total: total,
    usadas,
    restantes: Math.max(total - usadas, 0),
    acima: usadas > total,
    pct: Math.min(999, Math.floor((100 * usadas) / Math.max(total, 1))),
    e_fair_use: eFairUse,
  };
}

/**
 * Quando falar da faixa, e quando calar.
 *
 * Mesma régua do teto que saiu: abaixo de 70% é ruído — ela não precisa pensar
 * na faixa num mês normal. Um aviso que aparece o mês inteiro é um aviso que se
 * aprende a não ler.
 *
 * E o fair-use **nunca** vira aviso: ele é número meu, não faixa dela. Avisar
 * alguém de que está perto de um limite que a página de preços diz não existir
 * seria a página mentindo em uma das duas pontas.
 */
export type NivelDaFaixa = "nenhum" | "perto" | "acima";

export function nivelDaFaixa(f: Faixa): NivelDaFaixa {
  if (!f.tem_faixa || f.e_fair_use) return "nenhum";
  if (f.acima) return "acima";
  if (f.pct >= 70) return "perto";
  return "nenhum";
}

/** A frase de estado. Fala do plano, nunca do uso que ela faz dele. */
export function fraseDaFaixa(f: Faixa): string {
  if (!f.tem_faixa || f.e_fair_use) return "";
  const s = f.usadas === 1 ? "sessão" : "sessões";
  if (f.acima) {
    return `${f.usadas} ${s} este mês, e o seu plano prevê ${f.limite_total}.`;
  }
  return `${f.usadas} de ${f.limite_total} ${s} este mês.`;
}

/**
 * O que **não** acontece — e é a frase que não pode faltar.
 *
 * "Você passou do limite" sozinho deixa ela imaginando o pior, e o pior aqui é
 * exatamente o que não acontece: a agenda parar, a paciente não ser avisada,
 * uma cobrança extra aparecer.
 */
export function fraseDoQueNaoMuda(f: Faixa): string {
  if (nivelDaFaixa(f) !== "acima") return "";
  return (
    "Nada para de funcionar por causa disso: a agenda continua, a fila continua oferecendo, " +
    "e as mensagens das suas pacientes continuam saindo. Não há cobrança por sessão extra."
  );
}

/** O convite, e ele é um convite — não um aviso de cobrança. */
export function fraseDoConvite(f: Faixa): string {
  if (nivelDaFaixa(f) !== "acima") return "";
  return "Se o mês que vem for parecido, vale olhar o plano seguinte — a mudança só valeria a partir do próximo ciclo.";
}

/** Quantas faltam, sem exagerar nem minimizar. */
export function fraseDoRestante(f: Faixa): string {
  if (!f.tem_faixa) return "Seu plano não tem faixa de sessões.";
  if (f.e_fair_use) return "Seu plano não tem faixa de sessões.";
  if (f.acima) return "";
  const r = f.restantes ?? 0;
  if (r === 0) return "Você está no limite da faixa deste mês.";
  if (r === 1) return "Falta 1 sessão para o fim da faixa deste mês.";
  return `Faltam ${r} sessões para o fim da faixa deste mês.`;
}

/**
 * O que conta e o que não conta, dito para quem for conferir a conta.
 *
 * A tela precisa disto porque a psicóloga vai contar na cabeça e chegar a um
 * número diferente do nosso. Um número que ela não consegue reproduzir é um
 * número em que ela não confia.
 */
export function fraseDoQueConta(): string {
  return "Conta toda sessão que ocupou um horário no mês, inclusive falta e desmarcação em cima da hora. Sessão desmarcada dentro do prazo não conta.";
}
