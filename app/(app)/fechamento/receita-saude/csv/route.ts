import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { nomeDoArquivo, type Arquivo } from "@/lib/receitasaude";

/**
 * O arquivo que ela leva para o e-CAC.
 *
 * O caminho lá é: e-CAC → Carnê-Leão → Escrituração → Importar Escrituração,
 * e **antes** de importar existe um passo de "Analisar Arquivo". A tela manda
 * usar esse passo, e isso não é cerimônia: é a única conferência que vale,
 * porque é a da Receita.
 *
 * Quem monta o texto é o banco (`csv_receita_saude`), não este arquivo. Duas
 * implementações do mesmo layout viram duas verdades no dia em que uma for
 * corrigida e a outra não — e o preço de divergir aqui é multa de quem confiou.
 * O que a rota faz é o que só ela pode fazer: nomear o arquivo, mandar sem BOM
 * (a importação da Receita lê por posição de campo, e três bytes invisíveis no
 * começo deslocam a primeira coluna) e não deixar nada em cache.
 *
 * Sem filtro por conta na chamada: quem filtra é a RLS somada ao
 * `conta_atual()` de dentro da função. Se a sessão cair, o erro é 500 — nunca
 * o arquivo de outra pessoa.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const pedido = url.searchParams.get("ano") ?? "";
  const atual = Number(hoje().slice(0, 4));
  const ano = /^\d{4}$/.test(pedido) ? Number(pedido) : atual;

  if (ano < 2000 || ano > 2100) {
    return NextResponse.json({ erro: "Ano fora de faixa." }, { status: 400 });
  }

  const supabase = await supabaseSessao();

  try {
    const r = (await db(
      "rfb.csv",
      supabase.rpc("csv_receita_saude", { p_ano: ano }),
    )) as unknown as Arquivo;

    if (!r || r.linhas === 0) {
      return NextResponse.json(
        { erro: "Não há nenhuma linha para gerar neste ano." },
        { status: 404 },
      );
    }

    return new NextResponse(r.texto, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="${nomeDoArquivo(ano)}"`,
        "cache-control": "no-store, private",
      },
    });
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    // As recusas da função são informação para ela, não erro de servidor: PJ
    // não tem Receita Saúde, e CPF faltando tem um lugar certo para preencher.
    if (/NFS-e|CPF/i.test(m)) {
      return NextResponse.json({ erro: m.replace(/^.*?:\s*/, "") }, { status: 409 });
    }
    console.error("[rfb] csv", e);
    return NextResponse.json({ erro: "Não consegui montar o arquivo agora." }, { status: 500 });
  }
}
