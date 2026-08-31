import { NextResponse, type NextRequest } from "next/server";
import { despacharPendentes } from "@/lib/mensageria/worker";

/**
 * A porta do worker.
 *
 * Quem bate aqui é o cron da Vercel, de minuto em minuto. Como a rota é pública
 * na internet, ela tem de provar que quem chamou é o cron — e não alguém que
 * descobriu o caminho e resolveu drenar a fila de mensagens de todo mundo.
 *
 * A Vercel manda `Authorization: Bearer $CRON_SECRET` nas rotas de cron. É esse
 * segredo que a rota exige. **Sem segredo configurado, a rota recusa tudo** —
 * o contrário (abrir quando falta configuração) é como uma porta trancada vira
 * uma porta aberta num deploy distraído.
 *
 * A comparação é em tempo constante. Comparar segredo com `===` vaza o
 * comprimento do prefixo correto pelo tempo de resposta; é um ataque chato de
 * executar e trivial de evitar.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function autorizado(req: NextRequest): boolean {
  const segredo = process.env.CRON_SECRET;
  if (!segredo) {
    console.error("[mensageria] CRON_SECRET ausente — a rota está fechada");
    return false;
  }

  const cabecalho = req.headers.get("authorization") ?? "";
  return iguaisEmTempoConstante(cabecalho, `Bearer ${segredo}`);
}

function iguaisEmTempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferenca = 0;
  for (let i = 0; i < a.length; i += 1) {
    diferenca |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diferenca === 0;
}

export async function GET(req: NextRequest) {
  if (!autorizado(req)) {
    // 404, não 401: quem não tem o segredo não precisa saber que existe uma
    // rota aqui.
    return new NextResponse(null, { status: 404 });
  }

  try {
    const relatorio = await despacharPendentes(20);
    return NextResponse.json({ ok: true, ...relatorio });
  } catch (e) {
    const motivo = e instanceof Error ? e.message : String(e);
    console.error("[mensageria] a varredura falhou", { motivo });
    // 500 de propósito: o cron da Vercel registra a falha, e uma varredura que
    // erra em silêncio é uma fila que para sem ninguém notar.
    return NextResponse.json({ ok: false, erro: motivo }, { status: 500 });
  }
}
