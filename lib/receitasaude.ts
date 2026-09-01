import { paraCentavos, formatar } from "@/lib/dinheiro";

/**
 * O modo Receita Saúde (F2a) — o lado puro.
 *
 * Duas coisas moram aqui: o **prazo** (espelho de `prazo_do_ano`, na 0038) e as
 * **frases** que a tela usa para dizer quanto tempo resta sem assustar mais do
 * que o necessário nem tranquilizar mais do que é verdade.
 *
 * A regra que atravessa o arquivo: **o sistema não emite e não estima multa.**
 * Não há função aqui que calcule um valor de multa; há uma que calcula o
 * **piso** — R$ 100 por recibo, o mínimo legal — e o nome dela diz isso.
 */

/** R$ 100 por mês-calendário ou fração, por recibo. O piso é um mês. */
export const PISO_POR_RECIBO = 10000;

export type EstadoRecibo = "pendente" | "emitido" | "dispensado" | "vencido" | "cancelado";

const ROTULO: Record<EstadoRecibo, string> = {
  pendente: "a emitir",
  emitido: "emitido",
  dispensado: "dispensado",
  vencido: "fora do prazo",
  cancelado: "cancelado",
};

export function rotuloEstado(e: string): string {
  return ROTULO[e as EstadoRecibo] ?? e;
}

// ------------------------------------------------------------------ o prazo

/**
 * O último dia de fevereiro do ano seguinte — espelho exato de
 * `public.prazo_do_ano`.
 *
 * `Date.UTC(ano + 1, 2, 0)` é o dia 0 de março, ou seja, o último de fevereiro.
 * Em ano bissexto isso dá 29 sozinho, sem nenhum `if`. Tudo em UTC: data civil
 * não tem fuso, e usar o relógio de quem abriu a tela faria o prazo mudar de
 * dia conforme o navegador.
 */
export function prazoDoAno(ano: number): string {
  if (!Number.isInteger(ano) || ano < 2000 || ano > 2100) {
    throw new Error(`Ano fora de faixa: ${ano}`);
  }
  const d = new Date(Date.UTC(ano + 1, 2, 0));
  const mes = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dia = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}-${mes}-${dia}`;
}

/** Dias civis entre dois "AAAA-MM-DD". Negativo quando o prazo já passou. */
export function diasEntre(de: string, ate: string): number {
  const a = Date.parse(`${de}T00:00:00Z`);
  const b = Date.parse(`${ate}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) throw new Error(`Data inválida: ${de} / ${ate}`);
  return Math.round((b - a) / 86_400_000);
}

export type Fase = "tranquilo" | "atencao" | "urgente" | "fechado";

/**
 * Quanto barulho a tela deve fazer.
 *
 * A escada é deliberadamente lenta: alarme que grita o ano inteiro vira
 * paisagem, e aí não grita no dia em que precisa. Só a partir de 60 dias do
 * prazo — ou seja, a partir do começo de janeiro — a coisa muda de cor.
 */
export function faseDoPrazo(dias: number, pendentes: number): Fase {
  if (dias < 0) return "fechado";
  if (pendentes === 0) return "tranquilo";
  if (dias <= 15) return "urgente";
  if (dias <= 60) return "atencao";
  return "tranquilo";
}

/**
 * A frase do prazo.
 *
 * Nunca diz "está tudo em dia" quando há pendência, e nunca diz "você vai ser
 * multada" — diz o que falta, até quando, e qual é o piso da exposição.
 */
export function fraseDoPrazo(dias: number, pendentes: number, prazo: string): string {
  const quando = diaBr(prazo);

  if (dias < 0) {
    return pendentes === 0
      ? `O prazo deste ano fechou em ${quando}. Nada ficou pendente.`
      : `O prazo fechou em ${quando}. A emissão retroativa já não é aceita — o caminho agora é com o seu contador.`;
  }

  if (pendentes === 0) {
    return `Nada a emitir. O prazo deste ano vai até ${quando}.`;
  }

  const r = `${pendentes} recibo${pendentes > 1 ? "s" : ""} a emitir`;
  if (dias === 0) return `${r}, e o prazo é hoje.`;
  if (dias === 1) return `${r}, e o prazo é amanhã, ${quando}.`;
  return `${r}. O retroativo fecha em ${quando} — faltam ${dias} dias.`;
}

/**
 * O piso da exposição, e só o piso.
 *
 * R$ 100 por mês-calendário **ou fração**, por recibo: o mínimo é um mês. O
 * valor real depende de quanto cada um atrasou, e estimar isso seria dar
 * parecer fiscal com cara de conta. A tela diz "pelo menos".
 */
export function pisoDaMulta(pendentes: number, vencidos: number = 0): number {
  const n = pendentes + vencidos;
  if (!Number.isInteger(n) || n < 0) throw new Error(`Contagem inválida: ${n}`);
  return n * PISO_POR_RECIBO;
}

export function frasePisoDaMulta(pendentes: number, vencidos: number = 0): string {
  const piso = pisoDaMulta(pendentes, vencidos);
  if (piso === 0) return "";
  return (
    `A multa prevista é de R$ 100 por mês-calendário ou fração, por recibo — ` +
    `ou seja, no mínimo ${formatar(piso)} se nada for emitido.`
  );
}

// ------------------------------------------------------------------ o painel

export type PainelBruto = {
  ano: number;
  ligado: boolean;
  prazo: string;
  dias_ate_o_prazo: number;
  pendentes: { n: number; valor: string };
  emitidos: { n: number; valor: string };
  dispensados: { n: number; valor: string };
  vencidos: { n: number; valor: string };
  divergentes: number;
  sem_cpf: number;
  piso_multa: number;
  faltas_de_fora: { n: number; valor: string };
  por_mes: { mes: string; pendentes: number; emitidos: number; vencidos: number; valor: string }[];
};

export type Painel = {
  ano: number;
  ligado: boolean;
  prazo: string;
  dias: number;
  fase: Fase;
  pendentes: { n: number; centavos: number };
  emitidos: { n: number; centavos: number };
  dispensados: { n: number; centavos: number };
  vencidos: { n: number; centavos: number };
  divergentes: number;
  semCpf: number;
  pisoMulta: number;
  faltasDeFora: { n: number; centavos: number };
  porMes: { mes: string; pendentes: number; emitidos: number; vencidos: number; centavos: number }[];
};

export function lerPainel(b: PainelBruto): Painel {
  const pendentes = { n: b.pendentes.n, centavos: paraCentavos(b.pendentes.valor) };
  const vencidos = { n: b.vencidos.n, centavos: paraCentavos(b.vencidos.valor) };

  return {
    ano: b.ano,
    ligado: b.ligado,
    prazo: b.prazo,
    dias: b.dias_ate_o_prazo,
    fase: faseDoPrazo(b.dias_ate_o_prazo, pendentes.n + vencidos.n),
    pendentes,
    emitidos: { n: b.emitidos.n, centavos: paraCentavos(b.emitidos.valor) },
    dispensados: { n: b.dispensados.n, centavos: paraCentavos(b.dispensados.valor) },
    vencidos,
    divergentes: b.divergentes,
    semCpf: b.sem_cpf,
    // Recalculado aqui de propósito: se o espelho divergir do banco, é o teste
    // que descobre, não a psicóloga na frente da tela.
    pisoMulta: pisoDaMulta(pendentes.n, vencidos.n),
    faltasDeFora: { n: b.faltas_de_fora.n, centavos: paraCentavos(b.faltas_de_fora.valor) },
    porMes: (b.por_mes ?? []).map((m) => ({
      mes: m.mes,
      pendentes: m.pendentes,
      emitidos: m.emitidos,
      vencidos: m.vencidos,
      centavos: paraCentavos(m.valor),
    })),
  };
}

/** A frase das faltas que ficaram de fora. Aparece só quando existem. */
export function fraseDasFaltas(p: Painel): string {
  if (p.faltasDeFora.n === 0) return "";
  return (
    `${formatar(p.faltasDeFora.centavos)} em ${p.faltasDeFora.n} falta` +
    `${p.faltasDeFora.n > 1 ? "s" : ""} cobrada${p.faltasDeFora.n > 1 ? "s" : ""} ` +
    "não entram aqui: multa de cancelamento não é atendimento prestado. " +
    "Como declarar isso é conversa com o seu contador."
  );
}

/** O aviso do CPF que falta — o motivo nº 1 de a digitação parar no meio. */
export function fraseSemCpf(p: Painel): string {
  if (p.semCpf === 0) return "";
  return (
    `${p.semCpf} ${p.semCpf > 1 ? "pessoas estão" : "pessoa está"} sem CPF no cadastro. ` +
    "O app da Receita exige o CPF de quem pagou, e sem ele o recibo não sai."
  );
}

/** "2026-02-28" → "28/02/2026". Sem `new Date`: data civil não tem fuso. */
export function diaBr(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso.trim());
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}
