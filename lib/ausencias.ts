/**
 * A falta como dado clínico — do lado do app (PR8).
 *
 * A regra que governa este arquivo inteiro é uma frase do doc 07, na lista das
 * linhas que não se atravessam: *"IA que interpreta, sugere diagnóstico/conduta
 * ou avalia risco"*. Ela vale para IA e vale para `if`.
 *
 * Então aqui só existe **aritmética virada em português**. "Três das últimas
 * cinco horas não aconteceram" é fato — a psicóloga lê e conclui. "Padrão de
 * resistência", "risco de abandono", um badge vermelho: isso é leitura clínica,
 * e a leitura é dela. Não existe função aqui que devolva rótulo, e há teste que
 * falha se aparecer uma.
 *
 * A tentação é grande e vai voltar: é fácil escrever `if (seguidas >= 3)
 * return "atenção"`. A diferença entre este produto e um que a psicóloga
 * desliga na terceira semana está exatamente nessa linha não escrita.
 */

export type Desfecho = "realizada" | "falta" | "cancelada_cedo" | "cancelada_tarde";
export type EstadoSessao = Desfecho | "prevista" | "confirmada";

export type PainelAusencias = {
  sessoes: number;
  realizadas: number;
  faltas: number;
  cancelou_cedo: number;
  cancelou_tarde: number;
  ausencias: number;
  seguidas: number;
  ultimos: Desfecho[];
  primeira: string | null;
  ultima: string | null;
  ultima_realizada: string | null;
  dias_desde_a_ultima_realizada: number | null;
  com_nota: number;
};

export type LinhaDoTempo = {
  sessao_id: string;
  inicio: string;
  dia: string;
  estado: EstadoSessao;
  origem: "recorrencia" | "encaixe" | "avulsa" | "remarcada" | "importada";
  valor: string;
  nota: string | null;
  nota_em: string | null;
  cobranca_estado: "aberta" | "paga" | "perdoada" | null;
  cobranca_tipo: string | null;
  cobranca_valor: string | null;
};

export const DESFECHOS: Desfecho[] = [
  "realizada",
  "falta",
  "cancelada_cedo",
  "cancelada_tarde",
];

/** A hora aconteceu? Só o desfecho responde; previsto não é passado. */
export function aconteceu(estado: EstadoSessao): boolean {
  return estado === "realizada";
}

export function eAusencia(estado: EstadoSessao): boolean {
  return estado === "falta" || estado === "cancelada_cedo" || estado === "cancelada_tarde";
}

/** Onde cabe uma nota — gêmea da regra do gatilho `nota_so_na_ausencia`. */
export function podeAnotar(estado: EstadoSessao): boolean {
  return eAusencia(estado);
}

export function rotuloDesfecho(estado: EstadoSessao): string {
  if (estado === "realizada") return "aconteceu";
  if (estado === "falta") return "não veio";
  if (estado === "cancelada_cedo") return "desmarcou a tempo";
  if (estado === "cancelada_tarde") return "desmarcou em cima da hora";
  if (estado === "confirmada") return "confirmada";
  return "prevista";
}

/**
 * O sinal da faixa.
 *
 * Um caractere, e de propósito **não** é cor de semáforo: verde/vermelho num
 * histórico de paciente é juízo desenhado. Cheio é presença, vazio é ausência,
 * e a diferença entre os tipos de ausência fica no rótulo, ao lado.
 */
export function sinalDoDesfecho(estado: Desfecho): "●" | "○" {
  return estado === "realizada" ? "●" : "○";
}

export function rotuloOrigem(origem: LinhaDoTempo["origem"]): string | null {
  if (origem === "encaixe") return "entrou numa vaga que abriu";
  if (origem === "remarcada") return "remarcada";
  if (origem === "importada") return "veio do sistema anterior";
  return null;
}

export function rotuloCobranca(l: LinhaDoTempo): string | null {
  if (!l.cobranca_estado) return null;
  if (l.cobranca_estado === "paga") return "recebido";
  if (l.cobranca_estado === "perdoada") return "perdoado";
  return "em aberto";
}

// ==================================================== a aritmética em português

/**
 * As últimas horas, em uma frase.
 *
 * Fato, sempre: quantas das últimas N não aconteceram. Sem "muitas", sem
 * "poucas", sem adjetivo nenhum.
 */
export function fraseDasUltimas(p: PainelAusencias): string {
  const n = p.ultimos.length;
  if (n === 0) return "Ainda não houve nenhuma hora marcada com desfecho.";

  const fora = p.ultimos.filter((e) => e !== "realizada").length;
  if (fora === 0) {
    return n === 1
      ? "A última hora aconteceu."
      : `As últimas ${n} horas aconteceram.`;
  }
  if (fora === n) {
    return n === 1
      ? "A última hora não aconteceu."
      : `As últimas ${n} horas não aconteceram.`;
  }
  return `${fora} das últimas ${n} horas não aconteceram.`;
}

/** A cadeia corrente — e nada além do número dela. */
export function fraseDaSequencia(p: PainelAusencias): string {
  if (p.seguidas === 0) return "";
  if (p.seguidas === 1) return "A última não aconteceu.";
  return `As últimas ${p.seguidas} seguidas não aconteceram.`;
}

/** Há quantos dias foi a última hora que aconteceu de fato. */
export function fraseDesdeAUltima(p: PainelAusencias): string {
  const d = p.dias_desde_a_ultima_realizada;
  if (d === null || d === undefined) return "Nenhuma sessão realizada até agora.";
  if (d === 0) return "A última sessão aconteceu hoje.";
  if (d === 1) return "A última sessão aconteceu ontem.";
  if (d < 30) return `A última sessão aconteceu há ${d} dias.`;

  const meses = Math.floor(d / 30);
  return `A última sessão aconteceu há ${d} dias — cerca de ${meses} ${meses === 1 ? "mês" : "meses"}.`;
}

/** O resumo de sempre: quantas horas, quantas aconteceram, quantas não. */
export function fraseDoTotal(p: PainelAusencias): string {
  if (p.sessoes === 0) return "Nenhuma hora com desfecho ainda.";
  const partes = [`${p.sessoes} ${p.sessoes === 1 ? "hora" : "horas"}`];
  partes.push(`${p.realizadas} ${p.realizadas === 1 ? "aconteceu" : "aconteceram"}`);
  if (p.ausencias > 0) {
    partes.push(`${p.ausencias} não ${p.ausencias === 1 ? "aconteceu" : "aconteceram"}`);
  }
  return `${partes.join(" · ")}.`;
}

/**
 * A composição das ausências.
 *
 * Separar "não veio" de "desmarcou a tempo" é a única distinção que este
 * arquivo faz — e ela não é juízo, é o que a política do enquadre já
 * distingue desde a B6. Quem desmarca com antecedência avisou; quem não veio,
 * não. São eventos diferentes, e somá-los num número só esconde a informação
 * mais útil da tela.
 */
export function fraseDaComposicao(p: PainelAusencias): string {
  if (p.ausencias === 0) return "";
  const partes: string[] = [];
  if (p.faltas > 0) partes.push(`${p.faltas} sem aviso`);
  if (p.cancelou_cedo > 0) partes.push(`${p.cancelou_cedo} ${p.cancelou_cedo === 1 ? "desmarcada" : "desmarcadas"} a tempo`);
  if (p.cancelou_tarde > 0) partes.push(`${p.cancelou_tarde} em cima da hora`);
  return `${partes.join(" · ")}.`;
}

/** "2026-03-05" → "05/03". O ano só aparece quando não é o corrente. */
export function diaCurto(dia: string, hoje: string): string {
  const [a, m, d] = dia.split("-");
  return a === hoje.slice(0, 4) ? `${d}/${m}` : `${d}/${m}/${a}`;
}

/** Agrupa a linha do tempo por mês, para a tela não virar uma lista infinita. */
export function porMes(linhas: LinhaDoTempo[]): { mes: string; linhas: LinhaDoTempo[] }[] {
  const mapa = new Map<string, LinhaDoTempo[]>();
  for (const l of linhas) {
    const mes = l.dia.slice(0, 7);
    const atual = mapa.get(mes);
    if (atual) atual.push(l);
    else mapa.set(mes, [l]);
  }
  return [...mapa.entries()].map(([mes, ls]) => ({ mes, linhas: ls }));
}

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

/** "2026-03" → "março de 2026". */
export function nomeDoMes(competencia: string): string {
  const [ano, mes] = competencia.split("-");
  return `${MESES[Number(mes) - 1]} de ${ano}`;
}
