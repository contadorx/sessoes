/**
 * A lei nº 3 (doc 05): fuso é decisão, não acidente.
 *
 * Tudo que é "dia" no Sessões — sessão, vencimento, fechamento, competência —
 * se calcula em **America/Sao_Paulo**, nunca no fuso do servidor (que na Vercel
 * é UTC) nem no do navegador. No banco a função equivalente é `public.hoje_sp()`.
 *
 * Nada aqui assume o deslocamento fixo de -03:00: o Brasil já teve horário de
 * verão e pode voltar a ter. O deslocamento é perguntado ao Intl a cada
 * instante avaliado.
 */

export const FUSO = "America/Sao_Paulo";

/** O dia civil em São Paulo do instante dado, como "AAAA-MM-DD". */
export function diaEmSP(instante: Date = new Date()): string {
  const p = partes(instante);
  return `${p.year}-${p.month}-${p.day}`;
}

/** Hora civil em São Paulo, como "HH:MM". */
export function horaEmSP(instante: Date = new Date()): string {
  const p = partes(instante);
  return `${p.hour}:${p.minute}`;
}

/** O instante exato da meia-noite em São Paulo do dia "AAAA-MM-DD". */
export function inicioDoDiaSP(dia: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) {
    throw new Error(`Dia inválido (esperado AAAA-MM-DD): ${dia}`);
  }

  const base = new Date(`${dia}T00:00:00Z`);
  if (Number.isNaN(base.getTime())) throw new Error(`Dia inválido: ${dia}`);

  // Converge em duas passadas: a primeira estimativa pode cair do outro lado
  // de uma virada de deslocamento; a segunda corrige.
  const primeira = new Date(base.getTime() - deslocamentoSP(base) * 60_000);
  const segunda = new Date(base.getTime() - deslocamentoSP(primeira) * 60_000);
  return segunda;
}

/** O instante do primeiro milissegundo do dia seguinte — use como limite superior exclusivo. */
export function fimDoDiaSP(dia: string): Date {
  const inicio = inicioDoDiaSP(dia);
  const amanha = diaEmSP(new Date(inicio.getTime() + 36 * 3_600_000));
  return inicioDoDiaSP(amanha);
}

/** Deslocamento de São Paulo em minutos naquele instante (-180 fora do horário de verão). */
export function deslocamentoSP(instante: Date): number {
  const nome = new Intl.DateTimeFormat("en-US", {
    timeZone: FUSO,
    timeZoneName: "longOffset",
  })
    .formatToParts(instante)
    .find((p) => p.type === "timeZoneName")?.value;

  const casa = /GMT([+-])(\d{2}):(\d{2})/.exec(nome ?? "");
  if (!casa) throw new Error(`Não foi possível ler o deslocamento de ${FUSO}`);

  const sinal = casa[1] === "-" ? -1 : 1;
  return sinal * (Number(casa[2]) * 60 + Number(casa[3]));
}

const FORMATADOR = new Intl.DateTimeFormat("en-CA", {
  timeZone: FUSO,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});

function partes(instante: Date): Record<string, string> {
  if (Number.isNaN(instante.getTime())) throw new Error("Instante inválido");

  const mapa: Record<string, string> = {};
  for (const p of FORMATADOR.formatToParts(instante)) {
    if (p.type !== "literal") mapa[p.type] = p.value;
  }
  // Meia-noite sai como "24" em algumas implementações do hour12:false.
  if (mapa.hour === "24") mapa.hour = "00";
  return mapa;
}
