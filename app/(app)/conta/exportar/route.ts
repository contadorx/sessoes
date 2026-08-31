import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { diaEmSP } from "@/lib/tempo";

/**
 * Tudo o que é dela, num arquivo.
 *
 * Portabilidade dos dois lados (doc 07). Vale a pena dizer por que isto existe
 * tão cedo, antes de haver cliente: um sistema que guarda prontuário e dificulta
 * a saída não está retendo, está sequestrando. Se a psicóloga quiser ir embora
 * no terceiro mês, ela vai embora com tudo — e é justamente saber disso que
 * torna razoável ela colocar os pacientes aqui no primeiro.
 */
export async function GET() {
  const supabase = await supabaseSessao();

  try {
    const dados = await db<unknown>("conta.exportar", supabase.rpc("exportar_conta"));

    return new NextResponse(JSON.stringify(dados, null, 2), {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "content-disposition": `attachment; filename="sessoes-${diaEmSP()}.json"`,
        "cache-control": "no-store, private",
      },
    });
  } catch (e) {
    console.error("[exportar] conta", e);
    return NextResponse.json({ erro: "Não consegui exportar agora." }, { status: 500 });
  }
}
