/**
 * O painel do negócio — do lado do app (OP1).
 *
 * Gêmeo em TypeScript da aritmética que mora em `valor_da_conta`,
 * `custo_da_conta` e `churn_do_mes`. Os valores esperados dos testes são os
 * mesmos das verificações 16 a 25 da suíte 0045, de propósito: quando as duas
 * implementações discordarem, uma das duas está errada e eu quero saber no
 * `vitest`, não numa tela.
 *
 * Uma ausência importa mais que o resto: **nada aqui lê, formata ou nomeia
 * dado clínico.** Nem paciente, nem registro, nem evolução, nem anamnese, nem
 * nota de sessão. A fronteira 9 do doc 11 diz que dado clínico não vai para
 * ferramenta de suporte, e este módulo é a ferramenta de suporte. Há teste que
 * varre os nomes exportados e reprova qualquer um que sugira o contrário.
 */

import { formatar } from "@/lib/dinheiro";

export type OrigemDoValor = "fatura" | "assinatura" | "tabela" | "trial";

export type EstadoAssinatura =
  | "trial"
  | "ativa"
  | "em_atraso"
  | "cancelada"
  | "sem_assinatura";

export type Ciclo = "mensal" | "anual";

export type Plano = {
  codigo: string;
  nome: string;
  preco_centavos: number;
  ciclo: Ciclo;
  chamada: string | null;
  recursos: string[];
};

export type ContaNoPainel = {
  conta_id: string;
  nome: string;
  plano: string;
  is_teste: boolean;
  criada_em: string;
  estado_assinatura: EstadoAssinatura;
  valor_centavos: number;
  origem_do_valor: OrigemDoValor;
  divergencia: string | null;
  proximo_vencimento: string | null;
  fatura_vencida: boolean;
  sessoes_no_mes: number;
  mensagens_no_mes: number;
  custo_centavos: number;
  ultima_atividade: string | null;
};

export type Painel = {
  mes: string;
  mrr_centavos: number;
  arr_centavos: number;
  mrr_potencial_centavos: number;
  assinantes: { ativas: number; trial: number; em_atraso: number; canceladas: number };
  ticket_centavos: number;
  custo_centavos: number;
  margem_centavos: number;
  margem_pct: number | null;
  churn: { base_inicial: number; cancelaram: number; pct: number | null };
  ltv_centavos: number | null;
};

/**
 * Anuidade vira mensalidade.
 *
 * MRR é mensal por definição, e somar uma anuidade de R$ 690 a uma
 * mensalidade de R$ 69 é o erro mais caro desta aritmética — porque ele é
 * plausível: o número fica dez vezes maior e continua parecendo dinheiro.
 */
export function porMes(centavos: number, ciclo: Ciclo): number {
  return ciclo === "anual" ? Math.round(centavos / 12) : centavos;
}

/**
 * "R$ 69,00" — com o espaço fino que `formatar` usa. Não asserte a string.
 *
 * `formatar` já recebe centavos e divide por cem; dividir antes daria
 * R$ 0,69, que é o tipo de erro que passa despercebido numa tela porque
 * continua parecendo dinheiro.
 */
export function reais(centavos: number): string {
  return formatar(centavos);
}

/**
 * De onde veio o número, em português.
 *
 * A tela escreve "R$ 69 · da última fatura paga" em vez de "R$ 69". A
 * procedência é o que permite desconfiar de um número, e um painel de negócio
 * em que não dá para desconfiar de um número é um painel que se acredita.
 */
export function fraseDaOrigem(o: OrigemDoValor): string {
  switch (o) {
    case "fatura":
      return "da última fatura paga";
    case "assinatura":
      return "do contrato — ainda sem fatura paga";
    case "tabela":
      return "do preço de tabela — não há assinatura";
    case "trial":
      return "em teste, não entra no MRR";
  }
}

export function rotuloEstado(e: EstadoAssinatura): string {
  switch (e) {
    case "ativa":
      return "ativa";
    case "trial":
      return "em teste";
    case "em_atraso":
      return "em atraso";
    case "cancelada":
      return "cancelada";
    case "sem_assinatura":
      return "sem assinatura";
  }
}

/**
 * A margem, e o caso em que ela não existe.
 *
 * Sem receita, margem percentual é divisão por zero — e "0%" seria uma
 * afirmação falsa sobre um mês em que não houve o que dividir. Devolve `null`,
 * e a tela escreve um travessão.
 */
export function margemPct(mrr: number, custo: number): number | null {
  if (mrr <= 0) return null;
  return Math.round(1000 * ((mrr - custo) / mrr)) / 10;
}

/**
 * LTV, e o infinito que não se mostra.
 *
 * Com churn zero o LTV é infinito, e nos primeiros meses o churn vai ser zero
 * por não haver dado nenhum. "LTV: ∞" numa tela dá confiança em vez de dar
 * informação — é um número que parece resultado e é ausência de dado. Nulo, e
 * a tela diz por quê.
 */
export function ltv(ticketCentavos: number, churnPct: number | null): number | null {
  if (churnPct === null || churnPct <= 0) return null;
  if (ticketCentavos <= 0) return null;
  return Math.round(ticketCentavos / (churnPct / 100));
}

export function fraseDoLtv(v: number | null): string {
  return v === null
    ? "sem churn medido ainda — o LTV não é infinito, é desconhecido"
    : `${reais(v)} por conta, no churn atual`;
}

/**
 * O custo de uma mensagem, em centavos, a partir do preço em milésimos.
 *
 * `precos_canal` guarda milésimos de centavo porque um e-mail custa 0,2
 * centavo: arredondar para centavo daria zero, e mil e-mails custariam nada.
 */
export function custoDeMensagens(quantidade: number, milesimos: number): number {
  return Math.floor((quantidade * milesimos) / 1000);
}

/**
 * O churn do mês, com o denominador certo.
 *
 * `cancelaram ÷ base_no_início_do_mês`. Os dois aplicativos lidos usam a base
 * do mês corrente, o que superestima em base pequena: com doze contas, uma
 * saída vira 8% ou 30% dependendo de qual dos dois se escolhe — e o alvo do
 * doc 10 é 5%.
 */
export function churnPct(baseInicial: number, cancelaram: number): number | null {
  if (baseInicial <= 0) return null;
  return Math.round(1000 * (cancelaram / baseInicial)) / 10;
}

/**
 * A conta que decide o preço, e ela é uma subtração.
 *
 * O doc 10 estima R$ 10 a R$ 12 por conta por mês entre mensageria e infra,
 * contra uma mensalidade de R$ 69. Esta função é o que transforma essa
 * estimativa em medição — e o que vai dizer, daqui a três meses, se o Solo
 * fecha.
 */
export function margemDaConta(valorCentavos: number, custoCentavos: number) {
  return {
    receita: valorCentavos,
    custo: custoCentavos,
    sobra: valorCentavos - custoCentavos,
    pct: margemPct(valorCentavos, custoCentavos),
  };
}

/**
 * A conta está saudável?
 *
 * Regras, não juízo — e nenhuma delas olha o que ela escreveu. "Não usa há 30
 * dias" é um fato sobre sessões marcadas; "em atraso" é um fato sobre fatura.
 * O painel relata; quem conclui sou eu.
 */
export type Sinal = { grave: boolean; texto: string };

export function sinaisDaConta(c: ContaNoPainel, hoje = new Date()): Sinal[] {
  const s: Sinal[] = [];

  if (c.fatura_vencida) s.push({ grave: true, texto: "fatura vencida" });
  if (c.estado_assinatura === "em_atraso") s.push({ grave: true, texto: "assinatura em atraso" });

  if (c.ultima_atividade) {
    const dias = Math.floor(
      (hoje.getTime() - new Date(c.ultima_atividade).getTime()) / 86_400_000,
    );
    if (dias >= 30) s.push({ grave: true, texto: `sem sessão há ${dias} dias` });
    else if (dias >= 14) s.push({ grave: false, texto: `sem sessão há ${dias} dias` });
  } else {
    s.push({ grave: false, texto: "nunca marcou uma sessão" });
  }

  if (c.divergencia) s.push({ grave: false, texto: c.divergencia });

  // Custo maior que receita numa conta paga. Numa conta grátis isso é o
  // esperado e não é sinal — é o modelo.
  if (c.valor_centavos > 0 && c.custo_centavos > c.valor_centavos) {
    s.push({ grave: true, texto: "custa mais do que paga" });
  }

  return s;
}

/** "2026-09-01" → "setembro de 2026". */
export function mesPorExtenso(iso: string): string {
  const meses = [
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  ];
  const [ano, mes] = iso.slice(0, 10).split("-");
  return `${meses[Number(mes) - 1]} de ${ano}`;
}
