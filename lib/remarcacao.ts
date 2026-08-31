import { FUSO } from "@/lib/tempo";

/**
 * A remarcação guiada — o lado puro (D11).
 *
 * O que este arquivo carrega é o **vocabulário**: por que cada hora foi
 * oferecida, e o que a pessoa do outro lado lê. A escolha das horas é do banco
 * (`opcoes_de_remarcacao`, na 0035), onde ela pode ser verificada contra a
 * agenda inteira e onde ninguém consegue contorná-la pelo PostgREST.
 */

export type MotivoDaOpcao = "buraco" | "grade" | "adjacente";

export type Opcao = {
  inicio: string;
  motivo: MotivoDaOpcao | string;
  livre: boolean;
};

/**
 * Por que esta hora está na lista.
 *
 * Aparece só na tela **dela**. A pessoa que recebe o link vê três horários e
 * mais nada — saber que "esta hora vagou porque alguém desmarcou" é informação
 * sobre outro paciente, e não sai daqui.
 */
export function porqueDaOpcao(m: string): string {
  return (
    {
      buraco: "tapa um buraco — alguém desmarcou esta hora",
      grade: "é uma hora sua que está vazia nessa semana",
      adjacente: "encosta no que você já tem nesse dia",
    }[m] ?? ""
  );
}

/** Quanto esta opção ajuda: buraco tapa, adjacente só não atrapalha. */
export function ganhoDaOpcao(m: string): "tapa" | "aproveita" | "neutro" {
  if (m === "buraco") return "tapa";
  if (m === "grade") return "aproveita";
  return "neutro";
}

export type EstadoDaRemarcacao =
  | "inexistente"
  | "aberta"
  | "escolhida"
  | "expirada"
  | "cancelada";

/**
 * O que a página pública diz em cada estado.
 *
 * Nenhuma frase manda a pessoa fazer nada com urgência, e nenhuma menciona
 * terapia, sessão ou consultório: a tela é lida por quem passa (D3).
 */
export function rotuloPublico(e: EstadoDaRemarcacao): string {
  return {
    inexistente: "Este link não existe. Confira se ele veio inteiro.",
    aberta: "Escolha o horário que ficar melhor para você.",
    escolhida: "Pronto, está trocado.",
    expirada: "Este link venceu. Peça outro para quem te enviou.",
    cancelada: "Esta troca foi cancelada por quem te enviou.",
  }[e];
}

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

/** "terça-feira, 3 de março às 15:00" — a mesma forma das mensagens. */
export function quando(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return DIA_E_HORA.format(d);
}

/**
 * O texto que ela manda do próprio WhatsApp.
 *
 * Mesma escolha da B19: quem envia é ela, de um toque, e o texto não nomeia
 * nada. Um "remarcação de terapia" chegando de número desconhecido aparece na
 * tela de bloqueio de um celular que outra pessoa pode estar segurando.
 */
export function convite(nome: string, link: string): string {
  const primeiro = nome.trim().split(/\s+/)[0] || "tudo bem";
  return (
    `Oi, ${primeiro}. Separei alguns horários para a gente trocar. ` +
    `É só escolher o que der melhor: ${link}`
  );
}

/** As palavras que jamais entram no convite nem na página do visitante. */
export const PROIBIDAS_NO_CONVITE = [
  "terapia",
  "psicoterapia",
  "psicólog",
  "psicanáli",
  "consultório",
  "clínica",
  "paciente",
  "sessão",
  "atendimento",
  "consulta",
] as const;

/**
 * O aviso de custo, vindo do banco (`custo_da_remarcacao`).
 *
 * Existe para que a consequência apareça **antes** de o link sair. Descobrir
 * pela cobrança que remarcar em cima da hora custava dinheiro é o pior lugar
 * possível — para ela e para quem recebe a conta.
 */
export type Custo = {
  tardia: boolean;
  modelo: string;
  valor: string | number;
  texto: string;
};

export function custoEmCentavos(c: Custo | null): number {
  if (!c) return 0;
  const n = typeof c.valor === "number" ? c.valor : Number(c.valor ?? 0);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}
