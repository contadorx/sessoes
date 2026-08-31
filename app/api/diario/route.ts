import { NextResponse, type NextRequest } from "next/server";
import { passadaDiaria } from "@/lib/mensageria/diario";

/**
 * A passada diária.
 *
 * Mesma tranca da rota do minuto: sem `CRON_SECRET` configurado, 404 — inclusive
 * quando a variável não existe. Duas rotas de máquina, uma regra só.
 *
 * Roda às 11h UTC, que são 8h em São Paulo. O horário não é indiferente: o
 * lembrete enfileirado aqui é para a sessão de amanhã, e enfileirar de manhã dá
 * ao outbox o dia inteiro para tentar de novo se o provedor estiver instável.
 * Uma passada à meia-noite deixaria a primeira tentativa cair dentro da janela
 * de silêncio, e o lembrete só sairia às 8h — sem folga nenhuma para erro.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 300;

function autorizado(req: NextRequest): boolean {
  const segredo = process.env.CRON_SECRET;
  if (!segredo) {
    console.error("[diario] CRON_SECRET ausente — a rota está fechada");
    return false;
  }
  return igual(req.headers.get("authorization") ?? "", `Bearer ${segredo}`);
}

function igual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i += 1) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export async function GET(req: NextRequest) {
  if (!autorizado(req)) return new NextResponse(null, { status: 404 });

  try {
    const r = await passadaDiaria();
    console.info("[diario] passada concluída", r);
    return NextResponse.json({ ok: true, ...r });
  } catch (e) {
    const motivo = e instanceof Error ? e.message : String(e);
    console.error("[diario] a passada falhou", { motivo });
    // 500 de propósito: o cron da Vercel registra a falha. Uma agenda que para
    // de se estender em silêncio só é descoberta oito semanas depois.
    return NextResponse.json({ ok: false, erro: motivo }, { status: 500 });
  }
}
