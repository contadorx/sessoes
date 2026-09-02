import { formatar, percentual } from "@/lib/dinheiro";

/**
 * A política assistida (P4) — o lado puro.
 *
 * Espelha a 0058 com os **mesmos valores esperados** da suíte
 * `0058_politica_assistida.sql`: 50% de R$ 200 = R$ 100; 40% de R$ 300 =
 * R$ 120; ajuste para 50 vale, para 250 (acima da sessão) não vale, para 0
 * também não.
 *
 * AS TRÊS REGRAS QUE ATRAVESSAM O ARQUIVO
 *
 * **1 · Nada aqui decide.** Não existe função que devolva "o que fazer", que
 * marque alguém como reincidente ou que ordene as propostas por gravidade. O
 * histórico é contagem; a leitura é dela. É a fronteira 3 do doc 11 num lugar
 * onde ela escapa com facilidade — bastaria um campo `sugestao` para o software
 * passar a opinar sobre a relação clínica de alguém a partir de faltas.
 *
 * **2 · Perdoar não tem valor.** Cobrar menos é *cobrar*. Se perdão parcial
 * contasse como perdão, a contagem de perdões — que é a informação que este
 * bloco existe para devolver — deixaria de significar coisa alguma.
 *
 * **3 · O ajuste não passa do valor da hora.** Multa maior que o serviço não é
 * política de faltas, é penalidade, e nenhum combinado assinado previu isso. O
 * banco recusa; aqui a frase diz por quê antes de ela tentar.
 */

export type MotivoDaProposta = "cancelada_tarde" | "falta";
export type Decisao = "cobrar" | "perdoar";

/** O que a decisão faz com o aviso — as três respostas possíveis da 0058. */
export type DestinoDoAviso = "agendado" | "silencio_do_paciente" | "barrado_no_teto" | null;

const MOTIVO: Record<MotivoDaProposta, string> = {
  cancelada_tarde: "desmarcou em cima da hora",
  falta: "não veio",
};

export function rotuloMotivo(m: string): string {
  return MOTIVO[m as MotivoDaProposta] ?? m;
}

// ====================================================== o valor e o ajuste

/**
 * O que a política congelada mandaria cobrar. Mesma conta de
 * `multa_da_politica` no banco — e é `percentual` do `lib/dinheiro`, que
 * arredonda meio-centavo **para longe do zero**, e não para o par mais próximo.
 * Duas implementações da mesma conta têm de dar o mesmo número, ou a tela
 * mostra uma coisa e a cobrança guarda outra.
 */
export function multaSugerida(valorSessaoCentavos: number, pct: number): number {
  return percentual(valorSessaoCentavos, pct);
}

export function ajusteValido(centavos: number, valorSessaoCentavos: number | null): boolean {
  if (!Number.isFinite(centavos) || !Number.isInteger(centavos)) return false;
  if (centavos <= 0) return false;
  if (valorSessaoCentavos !== null && centavos > valorSessaoCentavos) return false;
  return true;
}

export function problemaNoAjuste(
  centavos: number,
  valorSessaoCentavos: number | null,
): string | null {
  if (ajusteValido(centavos, valorSessaoCentavos)) return null;
  if (!Number.isFinite(centavos) || !Number.isInteger(centavos)) {
    return "Escreva um valor.";
  }
  if (centavos <= 0) {
    return "Cobrança de zero não é cobrança — quem não quer cobrar perdoa, e o perdão fica contado.";
  }
  return `O ajuste não passa do valor da sessão (${formatar(valorSessaoCentavos ?? 0)}).`;
}

// ====================================================== o histórico

export type HistoricoBruto = {
  realizadas: number;
  faltas: number;
  tardias: number;
  cobradas: number;
  pagas: number;
  perdoadas: number;
  valor_perdoado: number | string;
  ultima_decisao: { decisao: string | null; quando: string | null; valor: string | null } | null;
};

export type Historico = HistoricoBruto & {
  /** Faltas mais desmarques em cima da hora. */
  ausencias: number;
  valorPerdoadoCentavos: number;
};

export function lerHistorico(b: HistoricoBruto): Historico {
  return {
    ...b,
    ausencias: b.faltas + b.tardias,
    valorPerdoadoCentavos: Math.round(Number(b.valor_perdoado ?? 0) * 100),
  };
}

/**
 * A frase do histórico.
 *
 * **Fatos, na ordem em que aconteceram, sem conclusão.** "É a quinta falta"
 * seria conclusão; "cinco ausências em vinte encontros" é contagem. A diferença
 * parece pequena e não é: a primeira empurra para uma decisão, a segunda
 * devolve o material para ela decidir.
 *
 * Quando não há história nenhuma, a frase diz isso em vez de mostrar zeros —
 * uma coluna de zeros lida como acusação de nada.
 */
export function fraseDoHistorico(h: Historico): string {
  if (h.realizadas === 0 && h.ausencias === 0) {
    return "Sem histórico ainda com esta pessoa.";
  }

  const partes: string[] = [];

  if (h.ausencias === 0) {
    partes.push(`${h.realizadas} encontro${h.realizadas === 1 ? "" : "s"}, nenhuma ausência até aqui.`);
  } else {
    partes.push(
      `${h.ausencias} ausência${h.ausencias === 1 ? "" : "s"} em ${h.realizadas + h.ausencias} horas reservadas.`,
    );
  }

  if (h.perdoadas > 0) {
    partes.push(
      `Você já abriu mão de ${formatar(h.valorPerdoadoCentavos)} em ${h.perdoadas} ${
        h.perdoadas === 1 ? "vez" : "vezes"
      }.`,
    );
  }
  if (h.cobradas > 0) {
    partes.push(`Cobrou ${h.cobradas} ${h.cobradas === 1 ? "vez" : "vezes"}, ${h.pagas} paga${h.pagas === 1 ? "" : "s"}.`);
  }

  return partes.join(" ");
}

// ====================================================== a espera

/**
 * Há quanto tempo a pergunta está parada.
 *
 * Sem urgência inventada e sem prazo: proposta não caduca, e é escolha da
 * 0058. A frase informa a idade, e nada mais — quem decide quando decidir é
 * quem vai conversar com a pessoa.
 */
export function fraseDaEspera(dias: number): string {
  if (dias <= 0) return "de hoje";
  if (dias === 1) return "de ontem";
  return `parada há ${dias} dias`;
}

// ====================================================== o aviso

/**
 * O que vai acontecer com a mensagem, dito **no momento da decisão**.
 *
 * Descobrir depois que o paciente nunca soube da cobrança é o pior lugar para
 * descobrir — e o teto do plano barra na hora do envio (0046), não na fila.
 */
export function fraseDoAviso(destino: DestinoDoAviso, quandoISO: string | null): string {
  switch (destino) {
    case "agendado": {
      if (!quandoISO) return "O aviso vai sair no texto neutro; você não precisa escrever nada.";
      const h = new Date(quandoISO).toLocaleTimeString("pt-BR", {
        hour: "2-digit",
        minute: "2-digit",
        timeZone: "America/Sao_Paulo",
      });
      return `O aviso sai às ${h}, no texto neutro — dá tempo de desfazer.`;
    }
    case "silencio_do_paciente":
      return "Esta pessoa pediu para não receber mensagens. A cobrança fica registrada, e o aviso é com você.";
    case "barrado_no_teto":
      return "O teto de mensagens do seu plano foi atingido neste mês: a cobrança fica registrada, mas o aviso não vai sair.";
    default:
      return "";
  }
}

// ====================================================== os rótulos da decisão

export const DECISOES: { valor: Decisao; rotulo: string; explica: string }[] = [
  {
    valor: "cobrar",
    rotulo: "Cobrar",
    explica:
      "Cria a cobrança pelo valor do combinado e agenda o aviso. Você pode ajustar o valor para menos antes de confirmar.",
  },
  {
    valor: "perdoar",
    rotulo: "Não cobrar",
    explica:
      "Fica registrado que você abriu mão, com o valor e o motivo. Ninguém recebe mensagem nenhuma.",
  },
];

/**
 * A frase que explica por que existe uma caixa de decisões, e ela precisa
 * dizer a parte incômoda: **sem decisão, nada acontece.**
 */
export function fraseDaCaixa(pendentes: number): string {
  if (pendentes === 0) {
    return "Nenhuma decisão esperando. Quando alguém desmarcar em cima da hora, a pergunta aparece aqui — e nada sai antes de você responder.";
  }
  return `${pendentes} ${pendentes === 1 ? "decisão espera" : "decisões esperam"} por você. Enquanto não decidir, nada é cobrado e ninguém recebe mensagem.`;
}
