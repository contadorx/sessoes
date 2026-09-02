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
  | "suspensa"
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
    case "suspensa":
      return "suspensa";
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

// ============================================ a operação (OP5)

/**
 * O que se pode fazer com uma assinatura, dado o estado dela.
 *
 * Existe porque a tela mostrava oito números e nenhum botão, e a primeira
 * versão dos botões oferecia tudo em tudo: "cancelar" numa assinatura já
 * cancelada, "emitir fatura" numa que não existe. Oferecer e recusar depois é
 * pior que não oferecer — a pessoa clica, lê um erro que ela não causou, e
 * passa a desconfiar do botão do lado.
 *
 * A regra é a do banco (migração 0050), repetida aqui para a tela não precisar
 * adivinhar. Se as duas discordarem, o banco ganha e o sintoma é um erro
 * legível, não uma escrita errada.
 */
export type AcaoDeAssinatura = "abrir" | "mudar_plano" | "cancelar" | "emitir_fatura";

export function acoesDaAssinatura(estado: EstadoAssinatura): AcaoDeAssinatura[] {
  if (estado === "sem_assinatura") return ["abrir"];
  if (estado === "cancelada") return ["abrir"];
  // trial, ativa, em_atraso e **suspensa** são todas vivas: mudam de plano,
  // cancelam e faturam. `assinatura_viva_da_conta` (0052d) é quem impede a
  // segunda — e `suspensa` entrou nessa lista porque uma conta suspensa tem
  // dívida pendurada e volta ao ar quando alguém paga.
  return ["mudar_plano", "cancelar", "emitir_fatura"];
}

export const ROTULO_ACAO_ASSINATURA: Record<AcaoDeAssinatura, string> = {
  abrir: "Abrir assinatura",
  mudar_plano: "Mudar de plano",
  cancelar: "Cancelar",
  emitir_fatura: "Emitir fatura do mês",
};

export type EstadoFatura = "pendente" | "paga" | "vencida" | "cancelada" | "estornada";

export function rotuloFatura(e: EstadoFatura): string {
  switch (e) {
    case "pendente": return "aguardando";
    case "paga": return "paga";
    case "vencida": return "vencida";
    case "cancelada": return "cancelada";
    case "estornada": return "estornada";
  }
}

/**
 * O que se faz com uma fatura. Paga não se cancela — estorna; e o que já
 * saiu do fluxo (cancelada, estornada) não volta.
 */
export type AcaoDeFatura = "baixar" | "estornar" | "cancelar";

export function acoesDaFatura(e: EstadoFatura): AcaoDeFatura[] {
  if (e === "pendente" || e === "vencida") return ["baixar", "cancelar"];
  if (e === "paga") return ["estornar"];
  return [];
}

/**
 * O motivo é obrigatório em cancelamento e estorno, e o mínimo é cinco
 * caracteres — o mesmo do banco.
 *
 * Não é burocracia: o churn é o número que decide o roadmap, e um churn sem
 * causa não muda decisão nenhuma. "Cancelou" não ensina; "cancelou porque
 * parou de atender" e "cancelou porque achou caro" mandam construir coisas
 * opostas.
 */
export function motivoValido(motivo: string): boolean {
  return motivo.trim().length >= 5;
}

export function fraseDoMotivoCurto(): string {
  return "Escreva o motivo — cancelamento sem causa vira um número que não ensina nada.";
}

/**
 * A soma dos custos fixos de um mês, em centavos.
 *
 * Some inteiros e devolve inteiro: custo fixo já é centavo, e passar por
 * `float` aqui seria a mesma classe de erro que a B1 proibiu no dinheiro da
 * psicóloga. Vale para o meu dinheiro também.
 */
export function somaDosCustos(linhas: { centavos: number }[]): number {
  return linhas.reduce((s, l) => s + l.centavos, 0);
}

/**
 * O preço vigente de um canal numa data — a mesma cascata do banco.
 *
 * Pega a vigência mais recente que não é posterior ao dia. Devolve `null`
 * quando não há preço declarado antes daquela data, e isso **não é zero**:
 * zero seria dizer que a mensagem foi de graça, e o painel passaria a mostrar
 * margem cheia num mês em que eu simplesmente esqueci de cadastrar o preço.
 */
export function precoVigente(
  precos: { vigencia_inicio: string; centavos_milesimos: number }[],
  dia: string,
): number | null {
  const validos = precos
    .filter((p) => p.vigencia_inicio <= dia)
    .sort((a, b) => (a.vigencia_inicio < b.vigencia_inicio ? 1 : -1));
  return validos.length > 0 ? validos[0].centavos_milesimos : null;
}

// =====================================================================
// A régua da assinatura, e o churn com causa (OP6)
// =====================================================================

/**
 * A causa do cancelamento — a minha classificação, ao lado da frase dela.
 *
 * A lista espelha o `check` da coluna `assinaturas.causa_cancelamento`. Duas
 * colunas existem porque juntar as duas perde uma das duas: a lista sozinha
 * perde a frase que diz **o que construir**, e a frase sozinha não se conta.
 *
 * `mudanca_de_plano` está aqui e **não é churn**. É a correção do defeito que a
 * 0052 encontrou: `mudar_plano` cancela a assinatura antiga para preservar a
 * história, e o churn contava essa linha — toda promoção virava perda.
 */
export type CausaDeCancelamento =
  | "preco"
  | "parou_de_atender"
  | "foi_para_outro"
  | "faltou_recurso"
  | "nao_usou"
  | "problema_no_produto"
  | "inadimplencia"
  | "mudanca_de_plano"
  | "outra";

/**
 * A ordem é a da conversa, não a alfabética: as duas primeiras são as que mais
 * aparecem, e `outra` fecha a lista porque escolhê-la é desistir de classificar.
 */
export const CAUSAS: { valor: CausaDeCancelamento; rotulo: string; explica: string }[] = [
  { valor: "preco", rotulo: "achou caro",
    explica: "O valor não fechou para ela — pode ser preço, pode ser o que ela usa do produto." },
  { valor: "parou_de_atender", rotulo: "parou de atender",
    explica: "Saiu da profissão, mudou de vida, licença. Não é sobre o produto." },
  { valor: "foi_para_outro", rotulo: "foi para outro sistema",
    explica: "Trocou por um concorrente. Escreva qual, na frase." },
  { valor: "faltou_recurso", rotulo: "faltou algo que ela precisava",
    explica: "Existe uma coisa que o produto não faz e ela precisava. Isto vira roadmap." },
  { valor: "nao_usou", rotulo: "não entrou no hábito",
    explica: "Assinou e não usou. É problema de onboarding, não de funcionalidade." },
  { valor: "problema_no_produto", rotulo: "algo quebrado ou lento",
    explica: "Defeito, lentidão, uma frustração concreta. É o mais urgente da lista." },
  { valor: "inadimplencia", rotulo: "não pagou, e a régua chegou ao fim",
    explica: "Perda de verdade, e separada das outras: perder gente é diferente de perder pagamento." },
  { valor: "mudanca_de_plano", rotulo: "trocou de plano",
    explica: "Não é churn. A assinatura antiga é cancelada para preservar a faixa anterior no histórico." },
  { valor: "outra", rotulo: "outra",
    explica: "Quando nenhuma das anteriores serve. Se você escolher esta com frequência, falta uma opção na lista." },
];

/** As que contam como perda. Espelha `causas_de_churn()` no banco. */
export function eChurn(c: CausaDeCancelamento): boolean {
  return c !== "mudanca_de_plano";
}

export function rotuloCausa(c: CausaDeCancelamento): string {
  return CAUSAS.find((x) => x.valor === c)?.rotulo ?? c;
}

/**
 * As causas que a tela oferece ao cancelar à mão.
 *
 * `mudanca_de_plano` fica **fora**: quem grava essa causa é a função
 * `mudar_plano`, sozinha. Oferecê-la num formulário de cancelamento seria
 * convidar a marcar uma saída como troca — e o churn passaria a ser o número
 * que eu quisesse que ele fosse.
 */
export function causasParaEscolher(): typeof CAUSAS {
  return CAUSAS.filter((c) => c.valor !== "mudanca_de_plano");
}

// ============================================ a régua

export type EstadoDoAviso = "pendente" | "enviado" | "cancelado";

export type AvisoPendente = {
  id: string;
  conta_id: string;
  conta: string;
  competencia: string;
  vencimento: string;
  dias: number;
  degrau: number;
  assunto: string;
  corpo: string;
};

/**
 * O que ainda vai acontecer com uma fatura em atraso, em dias.
 *
 * Espelha `regua_da_assinatura()` e `dias_para_suspender()`. Existe para a tela
 * dizer *"em cinco dias esta conta pausa"* em vez de mostrar só o número de
 * dias de atraso — o que a pessoa que olha o painel quer saber é o que vem, não
 * o que passou.
 */
export const DEGRAUS_DA_REGUA = [3, 10, 20] as const;
export const DIAS_PARA_SUSPENDER = 25;

export function proximoPassoDaRegua(diasDeAtraso: number): string {
  if (diasDeAtraso >= DIAS_PARA_SUSPENDER) {
    return "já pausou — a conta está no Grátis até alguém pagar";
  }
  const faltam = DIAS_PARA_SUSPENDER - diasDeAtraso;
  const proximo = DEGRAUS_DA_REGUA.find((d) => d > diasDeAtraso);
  if (proximo) {
    const ate = proximo - diasDeAtraso;
    return `próximo aviso em ${ate} ${ate === 1 ? "dia" : "dias"} · pausa em ${faltam}`;
  }
  return `pausa em ${faltam} ${faltam === 1 ? "dia" : "dias"}`;
}

/**
 * A frase que a tela mostra sobre o que a suspensão faz — e o que ela não faz.
 *
 * Ela existe na tela, e não só na migração, porque é a decisão que eu vou
 * querer atropelar num dia ruim, e a tela é onde o dia ruim acontece.
 */
export function oQueASuspensaoNaoTira(): string {
  return "Suspender devolve a conta ao plano Grátis: a fila para de oferecer vaga sozinha e a régua de cobrança pausa. Agenda, prontuário, anamnese e exportação continuam inteiros — a guarda de cinco anos é obrigação dela, não alavanca minha.";
}

// ============================================ a retenção

export type PorCausa = {
  causa: CausaDeCancelamento;
  quantas: number;
  mrr_perdido_centavos: number;
};

export type SaidaDaLista = {
  conta_id: string;
  conta: string;
  plano: string;
  valor_centavos: number;
  causa: CausaDeCancelamento;
  motivo: string | null;
  inicio: string;
  cancelada_em: string;
  dias_de_vida: number;
};

export type Retencao = {
  desde: string;
  quantas: number;
  mrr_perdido_centavos: number;
  dias_de_vida_mediana: number | null;
  por_causa: PorCausa[];
  lista: SaidaDaLista[];
};

/**
 * A frase do topo da retenção — e ela recusa a porcentagem.
 *
 * Com uma dúzia de contas, "33% saíram por preço" são duas pessoas. Um número
 * que parece saber mais do que sabe é pior que nenhum, e é o mesmo motivo pelo
 * qual `ltv` devolve nulo com churn zero em vez de devolver infinito.
 */
export function fraseDaRetencao(r: Retencao): string {
  if (r.quantas === 0) {
    return "Ninguém saiu no período. Não é resultado ainda — é uma base pequena, e a leitura só começa a valer com mais gente.";
  }
  const dias =
    r.dias_de_vida_mediana === null
      ? ""
      : ` A mediana de permanência foi de ${r.dias_de_vida_mediana} dias.`;
  return `${r.quantas} ${r.quantas === 1 ? "conta saiu" : "contas saíram"} no período.${dias}`;
}

/** A causa mais frequente, e null no empate — empate não indica direção. */
export function causaQueMaisPesa(r: Retencao): CausaDeCancelamento | null {
  if (r.por_causa.length === 0) return null;
  const ordenado = [...r.por_causa].sort((a, b) => b.quantas - a.quantas);
  if (ordenado.length > 1 && ordenado[0].quantas === ordenado[1].quantas) return null;
  return ordenado[0].causa;
}
