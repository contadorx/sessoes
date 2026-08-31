import { diaEmSP } from "@/lib/tempo";

/**
 * Aritmética de semana em dias civis de São Paulo, sobre strings AAAA-MM-DD.
 *
 * Trabalhar com string e meio-dia UTC evita o clássico: somar 24h a um Date e
 * cair no dia anterior por causa de fuso.
 */

const DIA_MS = 86_400_000;

function comoData(dia: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) {
    throw new Error(`Dia inválido (esperado AAAA-MM-DD): ${dia}`);
  }
  return new Date(`${dia}T12:00:00Z`);
}

export function somarDias(dia: string, n: number): string {
  const d = comoData(dia);
  return new Date(d.getTime() + n * DIA_MS).toISOString().slice(0, 10);
}

/** 0 = domingo, como o `extract(dow)` do Postgres. */
export function diaDaSemana(dia: string): number {
  return comoData(dia).getUTCDay();
}

/** A segunda-feira da semana que contém `dia`. A semana do produto é seg→dom. */
export function segundaDa(dia: string): string {
  const dow = diaDaSemana(dia);
  const recuo = dow === 0 ? 6 : dow - 1;
  return somarDias(dia, -recuo);
}

export type Semana = {
  inicio: string;
  fim: string;
  dias: string[];
};

export function semanaDe(dia: string): Semana {
  const inicio = segundaDa(dia);
  const dias = Array.from({ length: 7 }, (_, i) => somarDias(inicio, i));
  return { inicio, fim: dias[6], dias };
}

/** "1 – 7 de setembro" · "29 de setembro – 5 de outubro" · "30 de dez – 5 de jan" */
export function rotuloSemana(s: Semana): string {
  const mes = (d: string) =>
    new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC", month: "long" }).format(comoData(d));
  const ano = (d: string) => d.slice(0, 4);
  const num = (d: string) => String(Number(d.slice(8, 10)));

  const mesmoMes = s.inicio.slice(0, 7) === s.fim.slice(0, 7);
  const mesmoAno = ano(s.inicio) === ano(s.fim);

  if (mesmoMes) return `${num(s.inicio)} – ${num(s.fim)} de ${mes(s.inicio)}`;
  if (mesmoAno) return `${num(s.inicio)} de ${mes(s.inicio)} – ${num(s.fim)} de ${mes(s.fim)}`;
  return `${num(s.inicio)} de ${mes(s.inicio)} de ${ano(s.inicio)} – ${num(s.fim)} de ${mes(s.fim)} de ${ano(s.fim)}`;
}

export type ComHorario = { inicio: string; fim: string };

/**
 * A faixa de horas que a grade precisa mostrar, com uma folga de meia hora dos
 * dois lados. Sem sessão nenhuma, mostra o miolo do dia de trabalho.
 */
export function faixaDeHoras(
  sessoes: ComHorario[],
  padrao: [number, number] = [8, 20],
): [number, number] {
  if (sessoes.length === 0) return padrao;

  let de = 24;
  let ate = 0;

  for (const s of sessoes) {
    de = Math.min(de, minutosNoDia(s.inicio) / 60);
    ate = Math.max(ate, minutosNoDia(s.fim) / 60);
  }

  return [Math.max(0, Math.floor(de - 0.5)), Math.min(24, Math.ceil(ate + 0.5))];
}

/** Minutos desde a meia-noite de São Paulo. */
export function minutosNoDia(instante: string): number {
  const d = new Date(instante);
  const [h, m] = new Intl.DateTimeFormat("en-GB", {
    timeZone: "America/Sao_Paulo",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
    .format(d)
    .split(":")
    .map(Number);

  return (h === 24 ? 0 : h) * 60 + m;
}

/** Onde o bloco da sessão começa e que altura tem, em unidades de hora. */
export function posicaoNaGrade(
  s: ComHorario,
  deHora: number,
): { topo: number; altura: number } {
  const inicio = minutosNoDia(s.inicio) / 60;
  const fim = minutosNoDia(s.fim) / 60;
  // Sessão que atravessa a meia-noite é caso de borda: trata como até o fim do dia.
  const fimReal = fim > inicio ? fim : 24;

  return { topo: inicio - deHora, altura: Math.max(0.25, fimReal - inicio) };
}

/** Agrupa por dia civil de São Paulo. */
export function porDiaDaSemana<T extends { inicio: string }>(
  itens: T[],
  dias: string[],
): Record<string, T[]> {
  const mapa: Record<string, T[]> = Object.fromEntries(dias.map((d) => [d, [] as T[]]));

  for (const item of itens) {
    const dia = diaEmSP(new Date(item.inicio));
    if (mapa[dia]) mapa[dia].push(item);
  }

  return mapa;
}
