import { NextResponse, type NextRequest } from "next/server";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import { cutucarDespacho } from "@/lib/mensageria/worker";

/**
 * A porta por onde a resposta entra.
 *
 * Quem bate aqui é o provedor, não uma pessoa. Isso muda três coisas em relação
 * a qualquer outra rota do app:
 *
 * **1. Responder 200 é uma decisão, não um reflexo.** O provedor reentrega
 * enquanto não receber 200 — e reentrega com razão. Então: 200 assim que o
 * evento estiver **gravado no banco**, mesmo que a interpretação dele tenha dado
 * em nada; 500 só quando o banco não recebeu, que é o único caso em que tentar
 * de novo ajuda. Devolver 500 por causa de um texto estranho faria o provedor
 * repetir esse texto para sempre.
 *
 * **2. A idempotência não mora aqui.** Mora no índice único da 0021. Esta rota
 * pode ser chamada cinco vezes com o mesmo evento sem consequência — e vai ser.
 *
 * **3. O corpo é dado de terceiro.** Nada do que chega é usado para decidir
 * quem é quem: a rota passa provedor, id, telefone e texto adiante, e é o banco
 * que resolve o vínculo. Não existe um `oferta_id` vindo de fora.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 30;

function autorizado(req: NextRequest): boolean {
  const segredo = process.env.WHATSAPP_WEBHOOK_TOKEN;
  if (!segredo) {
    console.error("[whatsapp] WHATSAPP_WEBHOOK_TOKEN ausente — a rota está fechada");
    return false;
  }

  // O Gupshup não assina o callback: o que dá para controlar é a URL que ele
  // chama. Então o segredo vem na query (`?t=...`), e o cabeçalho fica aceito
  // para quem puder mandá-lo.
  const daQuery = req.nextUrl.searchParams.get("t") ?? "";
  const doCabecalho = req.headers.get("x-sessoes-token") ?? "";

  return igual(daQuery, segredo) || igual(doCabecalho, segredo);
}

function igual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i += 1) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** 404 em vez de 401: quem não tem o segredo não precisa saber que há algo aqui. */
const NAO_EXISTE = new NextResponse(null, { status: 404 });

export async function GET(req: NextRequest) {
  // Alguns provedores validam a URL com um GET antes de começar a mandar.
  return autorizado(req) ? NextResponse.json({ ok: true }) : NAO_EXISTE.clone();
}

type Entrada = {
  tipo: "mensagem" | "entrega" | "ignorar";
  id?: string;
  de?: string;
  texto?: string;
  estado?: "entregue" | "falhou";
};

/**
 * Traduz o corpo do Gupshup para o pouco que nos interessa.
 *
 * Fica isolado de propósito: quando o provedor mudar — e o doc 11 assume que um
 * dia muda — é esta função que se reescreve, e mais nada. O resto do arquivo
 * não sabe o nome de ninguém.
 */
export function lerGupshup(corpo: unknown): Entrada {
  if (!corpo || typeof corpo !== "object") return { tipo: "ignorar" };
  const c = corpo as Record<string, unknown>;

  const p = (c.payload ?? {}) as Record<string, unknown>;

  if (c.type === "message") {
    const interno = (p.payload ?? {}) as Record<string, unknown>;

    // Texto livre, ou o texto do botão de resposta rápida.
    const texto =
      typeof interno.text === "string"
        ? interno.text
        : typeof interno.title === "string"
          ? interno.title
          : null;

    const id = typeof p.id === "string" ? p.id : null;
    const de = typeof p.source === "string" ? p.source : null;

    // Áudio, figurinha, foto: chegou, e não é resposta. Registrar como texto
    // vazio faria o banco marcar "indefinida", que é a verdade.
    if (!id || !de) return { tipo: "ignorar" };
    return { tipo: "mensagem", id, de, texto: texto ?? "" };
  }

  if (c.type === "message-event") {
    const id = typeof p.gsId === "string" ? p.gsId
      : typeof p.id === "string" ? p.id : null;
    const tipo = typeof p.type === "string" ? p.type : "";
    if (!id) return { tipo: "ignorar" };

    if (tipo === "delivered" || tipo === "read") {
      return { tipo: "entrega", id, estado: "entregue" };
    }
    if (tipo === "failed") return { tipo: "entrega", id, estado: "falhou" };
    return { tipo: "ignorar" };
  }

  return { tipo: "ignorar" };
}

export async function POST(req: NextRequest) {
  if (!autorizado(req)) return NAO_EXISTE.clone();

  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    // Corpo ilegível não melhora na segunda tentativa.
    return NextResponse.json({ ok: false, motivo: "corpo inválido" }, { status: 200 });
  }

  const entrada = lerGupshup(corpo);
  if (entrada.tipo === "ignorar") {
    return NextResponse.json({ ok: true, estado: "ignorado" });
  }

  try {
    const supabase = supabaseServico();

    if (entrada.tipo === "entrega") {
      await db("whatsapp.entrega", supabase.rpc("marcar_entregue", {
        p_provedor_msg_id: entrada.id,
        p_estado: entrada.estado,
      }));
      return NextResponse.json({ ok: true, estado: entrada.estado });
    }

    const r = await db<{ estado: string }>(
      "whatsapp.resposta",
      supabase.rpc("responder_do_whatsapp", {
        p_provedor: "gupshup",
        p_provedor_msg_id: entrada.id,
        p_de: entrada.de,
        p_texto: entrada.texto,
      }),
    );

    // Uma recusa fez a fila andar: a próxima oferta já está enfileirada e sai
    // agora, não no próximo tick do cron. É o que faz a cascata parecer viva.
    if (r?.estado === "recusada" || r?.estado === "aceita") {
      await cutucarDespacho();
    }

    return NextResponse.json({ ok: true, ...r });
  } catch (e) {
    // Aqui sim: o banco não recebeu, e tentar de novo é a coisa certa.
    const motivo = e instanceof Error ? e.message : String(e);
    console.error("[whatsapp] não consegui gravar o evento", { motivo });
    return NextResponse.json({ ok: false, erro: motivo }, { status: 500 });
  }
}
