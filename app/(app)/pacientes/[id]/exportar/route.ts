import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

/**
 * O registro do paciente, para o paciente (PR12, Res. CFP 001/2009).
 *
 * É rota, e não ação de formulário, porque o resultado é um **arquivo**: o
 * navegador baixa e a pessoa guarda. Nada disso passa pelo estado do React.
 *
 * A checagem da restrição judicial não está aqui — está no banco. Quem exporta
 * precisa mandar `?ciente=1`, e esse parâmetro só aparece na tela depois de ela
 * ler o aviso. Se a rota fosse a única guardiã, bastaria alguém digitar a URL.
 */
export async function GET(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const ciente = new URL(req.url).searchParams.get("ciente") === "1";

  const supabase = await supabaseSessao();

  try {
    const dados = await db<unknown>(
      "paciente.exportar",
      supabase.rpc("exportar_paciente", {
        p_paciente: id,
        p_ciente_da_restricao: ciente,
      }),
    );

    const nome =
      (dados as { paciente?: { nome?: string } })?.paciente?.nome ?? "paciente";

    return new NextResponse(JSON.stringify(dados, null, 2), {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "content-disposition": `attachment; filename="${arquivo(nome)}.json"`,
        // Documento sigiloso não fica em cache de proxy nem de navegador.
        "cache-control": "no-store, private",
      },
    });
  } catch (e) {
    const motivo = e instanceof Error ? e.message : String(e);
    const restrito = /restrição judicial/i.test(motivo);

    console.error("[exportar] paciente", { id, motivo });
    return NextResponse.json(
      {
        erro: restrito
          ? "Há restrição judicial nesta ficha. Confirme na tela antes de exportar."
          : "Não consegui exportar agora.",
      },
      { status: restrito ? 409 : 500 },
    );
  }
}

/** "Maria Fernanda Reis" → "maria-fernanda-reis". */
function arquivo(nome: string): string {
  return (
    nome
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "paciente"
  );
}
