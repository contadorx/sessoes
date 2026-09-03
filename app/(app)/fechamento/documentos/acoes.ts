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

  revalidatePath("/fechamento/documentos");
  redirect(`/fechamento/documentos/${novo}`);
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

  revalidatePath("/fechamento/documentos");
  revalidatePath(`/fechamento/documentos/${id}`);
  return {
    estado: "ok",
    mensagem: "Cancelado. O número fica queimado — sequência com buraco é auditável.",
  };
}

/**
 * Avisa a pessoa de que o documento está na página dela (B54, §5.2).
 *
 * **A mensagem não carrega o documento.** Ela carrega o aviso; o papel mora na
 * página, atrás do link que a pessoa já tem. É isso que resolve a tensão da
 * classe `documento` da fronteira 8: não há valor, procedimento nem período
 * dentro do texto, então ele pode sair pelo WhatsApp sem tocar em nada.
 *
 * **E não acontece sozinho na emissão.** `emitir_documento` continua não
 * avisando ninguém: "o default que decide por ela" é antipadrão nomeado do §9,
 * e há emissão que é só contabilidade dela, feita em lote no fechamento do mês.
 * Aqui é um botão, e o botão é o consentimento.
 */
export async function avisarDocumento(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("documento_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Documento não identificado."] };

  const supabase = await supabaseSessao();
  let msg: string | null;

  try {
    msg = await db<string | null>(
      "documento.avisar",
      supabase.rpc("avisar_documento_disponivel", { p_documento: id }),
    );
  } catch (e) {
    console.error("[documento] falhou avisar", e);
    if (e instanceof ErroDeBanco && /link vivo/i.test(e.message)) {
      return {
        estado: "erro",
        erros: [
          "Esta pessoa ainda não tem página aberta. Gere o link dela na ficha " +
            "antes de avisar — sem ele, o aviso apontaria para uma página que não abre.",
        ],
      };
    }
    if (e instanceof ErroDeBanco && /sem (telefone|e-mail)/i.test(e.message)) {
      return {
        estado: "erro",
        erros: ["Falta o contato desta pessoa no cadastro. Sem ele não há para onde mandar."],
      };
    }
    if (e instanceof ErroDeBanco && /cancelado/i.test(e.message)) {
      return { estado: "erro", erros: ["Este documento foi cancelado: não há o que avisar."] };
    }
    return { estado: "erro", erros: ["Não consegui avisar agora. Tente de novo em instantes."] };
  }

  revalidatePath(`/fechamento/documentos/${id}`);

  // `enfileirar_mensagem` devolve nulo em dois casos, e os dois merecem a
  // verdade em vez de um "pronto" genérico: a pessoa pediu para não ser
  // avisada, ou o aviso deste documento já estava na fila (`chave_idem`).
  if (!msg) {
    return {
      estado: "ok",
      mensagem:
        "Nada novo foi enfileirado: ou esta pessoa pediu para não ser avisada, " +
        "ou o aviso deste documento já estava na fila.",
    };
  }

  return {
    estado: "ok",
    mensagem: "Aviso na fila. Ele diz que há um documento na página dela — e não leva o documento.",
  };
}
