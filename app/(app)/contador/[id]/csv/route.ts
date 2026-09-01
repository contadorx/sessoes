import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { comBom, nomeDoArquivo } from "@/lib/contador";

/**
 * O arquivo que o contador abre.
 *
 * Nada é recalculado aqui: o CSV foi congelado no fechamento e é ele que sai.
 * Se o mês mudou depois, existe uma versão nova — e é ela que tem outro id.
 *
 * Nenhum filtro por conta nesta consulta: quem filtra é a RLS. Se ela cair, a
 * linha não vem e o download dá 404, em vez de entregar o fechamento de outra
 * pessoa.
 */
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const supabase = await supabaseSessao();

  try {
    const linhas = (await db(
      "contador.csv",
      supabase
        .from("pastas_contador")
        .select("csv, versao, retrato")
        .eq("id", id)
        .limit(1),
    )) as unknown as { csv: string; versao: number; retrato: { competencia: string } }[];

    const p = (linhas ?? [])[0];
    if (!p) return NextResponse.json({ erro: "Pasta não encontrada." }, { status: 404 });

    const arquivo = nomeDoArquivo(p.retrato.competencia, p.versao);

    // O BOM vai só aqui: o que está guardado é UTF-8 limpo, e é o Excel em
    // português que precisa dos três bytes para não abrir "Supervisão" torto.
    return new NextResponse(comBom(p.csv), {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="${arquivo}"`,
        "cache-control": "no-store, private",
      },
    });
  } catch (e) {
    console.error("[contador] csv", e);
    return NextResponse.json({ erro: "Não consegui montar o arquivo agora." }, { status: 500 });
  }
}
