import { NextResponse, type NextRequest } from "next/server";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import { eventoDoProvedor } from "@/lib/mensageria/entrega";

/**
 * A confirmação de entrega entra por aqui.
 *
 * **Sem esta rota, nada do resto funciona** — e, pior, o resto conclui errado:
 * sem confirmação nenhuma toda mensagem vira "perdida" na janela, a varredura
 * reenvia a base inteira e o disjuntor desliga o canal que estava bom. É por
 * isso que a ordem de implantação manda ligar o webhook **antes** do cron, e
 * por isso `instrumentoConfiavel()` existe do outro lado.
 *
 * Três decisões, e as três são iguais às da rota do WhatsApp — porque quem bate
 * aqui é o provedor, não uma pessoa:
 *
 * **1 · Sem segredo, 503 e não grava.** O padrão é fechado. Uma rota de webhook
 * aberta é uma máquina de forjar confirmação de entrega: quem souber a URL diz
 * que a mensagem chegou, e o produto para de reenviar o que não chegou.
 *
 * **2 · 200 assim que estiver gravado, inclusive para o que ignoramos.** O
 * provedor reentrega enquanto não receber 200, e reentrega com razão. Devolver
 * erro para um evento que não interessa faria ele repetir esse evento para
 * sempre. 500 só quando o banco não recebeu, que é o único caso em que tentar
 * de novo ajuda.
 *
 * **3 · O corpo é dado de terceiro.** Nada do que chega decide quem é quem: a
 * rota passa o id do provedor e o nome do evento, e é o banco que resolve o
 * vínculo por `provedor_msg_id`. Não existe id de mensagem nosso vindo de fora.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 30;

function autorizado(req: NextRequest): boolean {
  const segredo = process.env.EMAIL_WEBHOOK_SEGREDO;
  if (!segredo) return false;

  const daQuery = req.nextUrl.searchParams.get("s");
  const doHeader = req.headers.get("x-webhook-segredo");
  return daQuery === segredo || doHeader === segredo;
}

/** O id da mensagem no provedor, procurado nos nomes que os dois usam. */
function idDoProvedor(corpo: Record<string, unknown>): string | null {
  const alvos = [
    corpo["message_id"],
    corpo["messageId"],
    corpo["provedor_msg_id"],
    (corpo["message"] as Record<string, unknown> | undefined)?.["id"],
    (corpo["message"] as Record<string, unknown> | undefined)?.["message_id"],
    corpo["id"],
  ];

  for (const alvo of alvos) {
    if (typeof alvo === "string" && alvo.trim() !== "") return alvo.trim();
    if (typeof alvo === "number") return String(alvo);
  }
  return null;
}

function nomeDoEvento(corpo: Record<string, unknown>): string | null {
  for (const chave of ["event", "evento", "type", "status", "EventType"]) {
    const v = corpo[chave];
    if (typeof v === "string" && v.trim() !== "") return v;
  }
  return null;
}

export async function POST(req: NextRequest) {
  if (!process.env.EMAIL_WEBHOOK_SEGREDO) {
    // 503 e não 401: a diferença importa para quem está implantando. 401 diz
    // "seu segredo está errado"; 503 diz "esta ponta ainda não existe".
    return NextResponse.json(
      { erro: "webhook de e-mail não configurado" },
      { status: 503 },
    );
  }

  if (!autorizado(req)) {
    return NextResponse.json({ erro: "não autorizado" }, { status: 401 });
  }

  let corpo: Record<string, unknown>;
  try {
    corpo = (await req.json()) as Record<string, unknown>;
  } catch {
    // Corpo ilegível não melhora com reentrega.
    return NextResponse.json({ resultado: "corpo_invalido" }, { status: 200 });
  }

  const evento = eventoDoProvedor(nomeDoEvento(corpo));
  const id = idDoProvedor(corpo);

  if (evento === "ignorado" || !id) {
    return NextResponse.json({ resultado: evento === "ignorado" ? "ignorado" : "sem_id" });
  }

  try {
    const supabase = supabaseServico();
    const resultado = await db<string>(
      "email.confirmar",
      supabase.rpc("confirmar_mensagem", { p_provedor_msg_id: id, p_evento: evento }),
    );

    return NextResponse.json({ resultado });
  } catch (e) {
    // O banco não recebeu: aqui sim vale reentregar.
    console.error("[email] falhou ao gravar a confirmação", e);
    return NextResponse.json({ erro: "não consegui gravar" }, { status: 500 });
  }
}
