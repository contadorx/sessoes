"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { db, ErroDeBanco } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

const TIPOS = ["recibo", "declaracao_comparecimento", "informe_anual"] as const;

/**
 * Emite e leva direto para o documento.
 *
 * O `redirect` no fim é deliberado: o que ela quer é **ver o papel**, conferir
 * e imprimir. Voltar para a lista com um "emitido com sucesso" a obrigaria a
 * procurar o que acabou de criar.
 */
export async function emitirDocumento(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const paciente = String(form.get("paciente_id") ?? "");
  const tipo = String(form.get("tipo") ?? "");
  const de = String(form.get("de") ?? "");
  const ate = String(form.get("ate") ?? "");

  const erros: string[] = [];
  if (!paciente) erros.push("Escolha a pessoa.");
  if (!(TIPOS as readonly string[]).includes(tipo)) erros.push("Escolha o tipo de documento.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(de) || !/^\d{4}-\d{2}-\d{2}$/.test(ate)) {
    erros.push("Preencha o período.");
  } else if (ate < de) {
    erros.push("A data final vem antes da inicial.");
  } else if (ate > hoje()) {
    // Recibo de sessão que ainda não aconteceu é declaração falsa, mesmo que
    // sem intenção. O sistema não emite.
    erros.push("Não dá para emitir documento de um período que ainda não terminou.");
  }

  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();
  let novo: string;

  try {
    novo = await db<string>(
      "documento.emitir",
      supabase.rpc("emitir_documento", {
        p_paciente: paciente,
        p_tipo: tipo,
        p_de: de,
        p_ate: ate,
      }),
    );
  } catch (e) {
    console.error("[documento] falhou emitir", e);
    if (e instanceof ErroDeBanco && /sessão realizada/i.test(e.message)) {
      return {
        estado: "erro",
        erros: [
          "Nenhuma sessão marcada como realizada nesse período. " +
            "Só entra no documento o que de fato aconteceu — falta cobrada não conta.",
        ],
      };
    }
    return { estado: "erro", erros: ["Não consegui emitir agora. Tente de novo em instantes."] };
  }

  revalidatePath("/documentos");
  redirect(`/documentos/${novo}`);
}

export async function cancelarDocumento(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("documento_id") ?? "");
  const motivo = String(form.get("motivo") ?? "").trim();

  if (!id) return { estado: "erro", erros: ["Documento não identificado."] };
  if (motivo.length < 3) {
    return { estado: "erro", erros: ["Diga por que está cancelando — fica no lugar do documento."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "documento.cancelar",
      supabase.rpc("cancelar_documento", { p_documento: id, p_motivo: motivo }),
    );
  } catch (e) {
    console.error("[documento] falhou cancelar", e);
    return { estado: "erro", erros: ["Não consegui cancelar agora."] };
  }

  revalidatePath("/documentos");
  revalidatePath(`/documentos/${id}`);
  return {
    estado: "ok",
    mensagem: "Cancelado. O número fica queimado — sequência com buraco é auditável.",
  };
}
