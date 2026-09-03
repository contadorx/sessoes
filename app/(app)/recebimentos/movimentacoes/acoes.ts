"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { lerValor } from "@/lib/formato";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { deCentavos } from "@/lib/dinheiro";
import { hoje } from "@/lib/tempo-servidor";
import { CATEGORIAS } from "@/lib/financeiro";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * "Recebi."
 *
 * Um clique, e é o clique que separa "atendi" de "recebi" — a distinção que
 * faltava para o recibo do avulso poder conferir alguma coisa (0037).
 */
export async function registrarRecebimento(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const sessao = String(form.get("sessao") ?? "");
  const quando = String(form.get("quando") ?? "").trim();

  if (quando && !/^\d{4}-\d{2}-\d{2}$/.test(quando)) {
    return { estado: "erro", erros: ["A data do recebimento está fora do formato."] };
  }
  if (quando && quando > hoje()) {
    return {
      estado: "erro",
      erros: ["Recebimento no futuro não existe: aqui só entra o dinheiro que já entrou."],
    };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "financeiro.recebi",
      supabase.rpc("registrar_recebimento", {
        p_sessao: sessao,
        p_quando: quando === "" ? null : quando,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/recebimentos/movimentacoes");
  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Registrado. A hora entrou no caixa do mês em que o dinheiro entrou." };
}

export async function desfazerRecebimento(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const sessao = String(form.get("sessao") ?? "");
  const supabase = await supabaseSessao();

  let r: string;
  try {
    r = (await db(
      "financeiro.desfazer",
      supabase.rpc("desfazer_recebimento", { p_sessao: sessao }),
    )) as unknown as string;
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/recebimentos/movimentacoes");
  revalidatePath("/agenda");
  return {
    estado: "ok",
    mensagem:
      r === "reaberta"
        ? "Desfeito. A cobrança voltou a ficar em aberto."
        : "Desfeito. Nada foi cobrado de ninguém — o registro só saiu do caixa.",
  };
}

// ------------------------------------------------------------------ despesas

export async function lancarDespesa(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const paga = String(form.get("paga_em") ?? "").trim();
  const categoria = String(form.get("categoria") ?? "").trim();
  const descricao = String(form.get("descricao") ?? "").trim();
  const valorCru = String(form.get("valor") ?? "").trim();

  const erros: string[] = [];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paga)) erros.push("Informe a data em que o dinheiro saiu.");
  else if (paga > hoje()) {
    erros.push(
      "Data no futuro: aqui entra só o que já saiu. Contas a pagar é outra coisa, e não é deste sistema.",
    );
  }
  if (!CATEGORIAS.some((c) => c.valor === categoria)) erros.push("Escolha uma categoria.");
  if (descricao.length < 2 || descricao.length > 120) {
    erros.push("A descrição tem de 2 a 120 caracteres.");
  }

  const centavos = lerValor(valorCru) ?? 0;
  if (centavos <= 0) erros.push("O valor precisa ser maior que zero.");

  if (erros.length > 0) return { estado: "erro", erros };

  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  try {
    await db(
      "despesas.lancar",
      supabase.from("despesas").insert({
        conta_id: sessao.contaId,
        paga_em: paga,
        categoria,
        descricao,
        valor: deCentavos(centavos),
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/recebimentos/movimentacoes");
  return { estado: "ok", mensagem: "Lançada." };
}

/**
 * Apagar aqui é permitido, e é o contrário do que vale para cobrança: uma
 * cobrança perdoada é informação sobre outra pessoa; uma despesa lançada errada
 * é só um engano dela sobre o próprio dinheiro.
 */
export async function apagarDespesa(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("despesa") ?? "");
  const supabase = await supabaseSessao();

  try {
    await db("despesas.apagar", supabase.from("despesas").delete().eq("id", id));
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/recebimentos/movimentacoes");
  return { estado: "ok", mensagem: "Apagada." };
}

function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 240
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
