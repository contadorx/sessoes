import { formatar } from "@/lib/dinheiro";
import { DIAS } from "@/lib/enquadre";

/**
 * Os três modelos de cobrança (D15) — o lado puro.
 *
 * O que este arquivo existe para fazer é **mostrar antes**: quanto vai sair no
 * mês de cinco terças, com o modelo que ela acabou de escolher, antes de a
 * primeira cobrança nascer. A conta que vale é a do banco
 * (`valor_da_mensalidade`, na 0033); esta é a que aparece embaixo do campo
 * enquanto ela decide.
 *
 * As duas contas têm os mesmos casos, com os mesmos números, nas duas suítes —
 * março/2026 (cinco terças) e abril/2026 (quatro). Se divergirem, uma das duas
 * falha e a outra diz onde.
 */

export type Modelo = "avulso" | "mensal" | "pacote";

export const MODELOS: { valor: Modelo; rotulo: string; explica: string }[] = [
  {
    valor: "avulso",
    rotulo: "por sessão",
    explica: "Cada encontro é uma cobrança. É o mais comum, e o mais simples de conferir.",
  },
  {
    valor: "mensal",
    rotulo: "mensalidade",
    explica:
      "Uma cobrança por mês, gerada sozinha. A falta já está paga dentro do mês — não vira cobrança nova.",
  },
  {
    valor: "pacote",
    rotulo: "pacote",
    explica:
      "Um número de sessões pago adiantado. Cada encontro consome um crédito; a falta também, porque a hora foi reservada.",
  },
];

export function rotuloModelo(m: string): string {
  return MODELOS.find((x) => x.valor === m)?.rotulo ?? m;
}

/**
 * Quantas vezes um dia da semana cai num mês. Espelho de
 * `ocorrencias_do_dia_no_mes`.
 *
 * `mes` é 1–12, como uma pessoa escreve, e não 0–11 como o `Date` do
 * JavaScript. A conversão fica aqui, num lugar só: a única defesa contra o erro
 * de mês do JS é ele nunca aparecer em mais de uma função.
 */
export function ocorrenciasNoMes(diaSemana: number, ano: number, mes: number): number {
  // Dia 0 do mês seguinte = último dia deste mês. UTC em tudo: data civil não
  // tem fuso, e usar o local faria a resposta mudar conforme o relógio de quem
  // abriu a tela.
  const ultimo = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  let n = 0;
  for (let d = 1; d <= ultimo; d++) {
    if (new Date(Date.UTC(ano, mes - 1, d)).getUTCDay() === diaSemana) n++;
  }
  return n;
}

export type Combinado = {
  modelo: Modelo;
  diaSemana: number;
  /** Valor da sessão, em centavos. */
  valorCentavos: number;
  /** Valor fixo do mês, em centavos. `null` = por sessão do mês. */
  mensalidadeCentavos: number | null;
};

export type PrevisaoDoMes = {
  ocorrencias: number;
  centavos: number;
  frase: string;
};

/**
 * O que sai num mês, com este combinado.
 *
 * Só faz sentido no `mensal`; nos outros devolve a frase que explica por quê.
 */
export function previsaoDoMes(
  c: Combinado,
  ano: number,
  mes: number,
): PrevisaoDoMes {
  const ocorrencias = ocorrenciasNoMes(c.diaSemana, ano, mes);
  const dia = DIAS[c.diaSemana] ?? "?";
  const plural = `${dia}s`;

  if (c.modelo !== "mensal") {
    return { ocorrencias, centavos: 0, frase: "" };
  }

  if (c.mensalidadeCentavos === null) {
    const total = c.valorCentavos * ocorrencias;
    return {
      ocorrencias,
      centavos: total,
      frase:
        `Um mês com ${ocorrencias} ${plural} sai por ${formatar(total)} ` +
        `(${ocorrencias} × ${formatar(c.valorCentavos)}).`,
    };
  }

  return {
    ocorrencias,
    centavos: c.mensalidadeCentavos,
    frase:
      `Um mês com ${ocorrencias} ${plural} sai por ${formatar(c.mensalidadeCentavos)} — ` +
      `o mesmo de um mês com ${ocorrencias === 5 ? 4 : 5}.`,
  };
}

/**
 * A frase que responde à pergunta do mês de cinco terças.
 *
 * É a decisão inteira da D15 numa linha, e ela precisa aparecer **ao lado do
 * campo**, não num texto de ajuda: quem escolhe errado aqui só descobre no mês
 * em que a conta vem diferente do combinado, e aí a conversa é com o paciente.
 */
export function explicacaoDoMesDeCinco(mensalidadeCentavos: number | null): string {
  return mensalidadeCentavos === null
    ? "Por sessão do mês: o mês de cinco sai maior, o de quatro sai menor."
    : "Valor fixo: o mês de cinco sai pelo mesmo preço do de quatro.";
}

/** Um mês próximo com cinco ocorrências daquele dia — para a tela dar um exemplo real. */
export function proximoMesDeCinco(
  diaSemana: number,
  desde: Date = new Date(),
): { ano: number; mes: number } | null {
  for (let i = 0; i < 24; i++) {
    const d = new Date(Date.UTC(desde.getUTCFullYear(), desde.getUTCMonth() + i, 1));
    const ano = d.getUTCFullYear();
    const mes = d.getUTCMonth() + 1;
    if (ocorrenciasNoMes(diaSemana, ano, mes) === 5) return { ano, mes };
  }
  return null;
}

// ------------------------------------------------------------------ pacote

export type PacoteLinha = {
  id: string;
  quantidade: number;
  valor: string;
  validade: string;
  vendido_em: string;
  cancelado_em: string | null;
  consumidos: number;
};

export type EstadoDoPacote = "vivo" | "esgotado" | "vencido" | "cancelado";

export function estadoDoPacote(p: PacoteLinha, hoje: string): EstadoDoPacote {
  if (p.cancelado_em) return "cancelado";
  if (p.quantidade - p.consumidos <= 0) return "esgotado";
  if (p.validade < hoje) return "vencido";
  return "vivo";
}

/**
 * A frase do painel do pacote.
 *
 * O caso que importa é o **esgotado e o vencido**: a partir dali as sessões
 * voltam a ser cobradas avulsas, e descobrir isso pela cobrança é o pior lugar
 * possível. A tela diz antes, com todas as letras.
 */
export function rotuloDoPacote(p: PacoteLinha, hoje: string): string {
  const saldo = p.quantidade - p.consumidos;
  const e = estadoDoPacote(p, hoje);

  if (e === "cancelado") return "Pacote cancelado. Os créditos já usados continuam registrados.";
  if (e === "esgotado")
    return "Créditos esgotados. As próximas sessões voltam a ser cobradas por sessão.";
  if (e === "vencido")
    return `Venceu com ${saldo} crédito${saldo > 1 ? "s" : ""} sem usar. As próximas sessões voltam a ser cobradas por sessão.`;

  return `${saldo} de ${p.quantidade} crédito${p.quantidade > 1 ? "s" : ""} — vale até ${diaBr(p.validade)}.`;
}

/** "2026-12-31" → "31/12/2026". Sem `new Date`: data civil não tem fuso. */
export function diaBr(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso.trim());
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}
