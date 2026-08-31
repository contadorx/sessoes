import { NextResponse, type NextRequest } from "next/server";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";

/**
 * O webhook do provedor de pagamento.
 *
 * O doc 10 é explícito sobre o que este endereço enfrenta no Asaas: entrega
 * **"at least once"**, sem assinatura HMAC (a validação é um token em header), e
 * a fila dele **pausa depois de 15 falhas**, com os eventos apagados em 14 dias.
 *
 * Isso define três comportamentos, e nenhum é opinião:
 *
 * **1. Responder 200 quase sempre.** Cada não-200 conta para as 15 falhas que
 * pausam a fila. Um evento de tipo desconhecido, um pagamento de cobrança que
 * não é nossa, um corpo estranho — tudo isso é 200, porque devolver erro por
 * causa deles derrubaria a entrega dos eventos que importam. 500 fica reservado
 * para o único caso em que retentar ajuda: o banco não recebeu.
 *
 * **2. Este endereço não é a fonte da verdade.** A varredura diária confere
 * estado por conta própria. Se a fila pausar num fim de semana, o pagamento é
 * encontrado na segunda — sem ninguém perceber que houve problema.
 *
 * **3. A dedupe é do banco**, por `(provedor, evento_id)`. Uma reentrega não
 * marca a mesma cobrança como paga duas vezes.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 30;

function autorizado(req: NextRequest): boolean {
  const segredo = process.env.PAGAMENTOS_WEBHOOK_TOKEN;
  if (!segredo) {
    console.error("[pagamentos] PAGAMENTOS_WEBHOOK_TOKEN ausente — a rota está fechada");
    return false;
  }

  // O Asaas manda o token no header `asaas-access-token`, configurado por nós
  // no painel dele. Aceitamos também na query, para o caso de outro provedor.
  const doHeader = req.headers.get("asaas-access-token") ?? "";
  const daQuery = req.nextUrl.searchParams.get("t") ?? "";
  return igual(doHeader, segredo) || igual(daQuery, segredo);
}

function igual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i += 1) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

type Evento = {
  id: string;
  tipo: string;
  cobrancaId: string;
};

/**
 * Lê o corpo do Asaas. Isolado de propósito: quando o provedor mudar, é este
 * pedaço que se reescreve, e nada mais.
 */
export function lerAsaas(corpo: unknown): Evento | null {
  if (!corpo || typeof corpo !== "object") return null;
  const c = corpo as Record<string, unknown>;

  const id = typeof c.id === "string" ? c.id : null;
  const tipo = typeof c.event === "string" ? c.event : null;
  const pagamento = (c.payment ?? {}) as Record<string, unknown>;
  const cobrancaId = typeof pagamento.id === "string" ? pagamento.id : null;

  if (!id || !tipo || !cobrancaId) return null;
  return { id, tipo, cobrancaId };
}

export async function POST(req: NextRequest) {
  if (!autorizado(req)) return new NextResponse(null, { status: 404 });

  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return NextResponse.json({ ok: false, motivo: "corpo inválido" }, { status: 200 });
  }

  const evento = lerAsaas(corpo);
  if (!evento) {
    // 200: um corpo que não reconhecemos não melhora sendo reentregue quinze
    // vezes — e cada reentrega falha aproxima a pausa da fila inteira.
    console.warn("[pagamentos] evento sem os campos esperados");
    return NextResponse.json({ ok: true, estado: "ignorado" });
  }

  try {
    const supabase = supabaseServico();
    const r = await db<{ estado: string }>(
      "pagamentos.conciliar",
      supabase.rpc("conciliar_pagamento", {
        p_provedor: "asaas",
        p_evento_id: evento.id,
        p_tipo: evento.tipo,
        p_cobranca_provedor_id: evento.cobrancaId,
        p_corpo: corpo as Record<string, unknown>,
      }),
    );

    return NextResponse.json({ ok: true, ...r });
  } catch (e) {
    const motivo = e instanceof Error ? e.message : String(e);
    console.error("[pagamentos] não consegui gravar o evento", { motivo });
    // O único 500 legítimo: o banco não recebeu, e retentar resolve.
    return NextResponse.json({ ok: false, erro: motivo }, { status: 500 });
  }
}
