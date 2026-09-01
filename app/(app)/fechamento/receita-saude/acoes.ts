"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * "Emiti na Receita."
 *
 * O nome importa: não é "emitir". O sistema não emite e não tem como emitir —
 * não existe API pública. Isto **registra o que ela fez** no app da Receita, e
 * a diferença entre as duas coisas é a diferença entre um produto honesto e um
 * que faz alguém levar multa por confiar nele.
 */
export async function marcarEmitido(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const numero = String(form.get("numero") ?? "").trim();

  if (numero !== "" && (numero.length < 3 || numero.length > 60)) {
    return { estado: "erro", erros: ["O número do recibo tem de 3 a 60 caracteres."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "rfb.marcar",
      supabase.rpc("marcar_recibo_rfb", {
        p_recibo: recibo,
        p_numero: numero === "" ? null : numero,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: numero
      ? "Registrado, com o número. É ele que responde a pergunta daqui a três anos."
      : "Registrado. Se puder, volte e anote o número do recibo — ele vale numa conferência futura.",
  };
}

export async function desmarcar(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const supabase = await supabaseSessao();

  try {
    await db("rfb.desmarcar", supabase.rpc("desmarcar_recibo_rfb", { p_recibo: recibo }));
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return { estado: "ok", mensagem: "Voltou para a lista." };
}

/**
 * "Este não precisa de recibo da Receita Saúde."
 *
 * O caso real: repasse de clínica (PJ), que fica fora do Receita Saúde e vai
 * direto ao carnê-leão. Pede motivo porque quem dispensa uma obrigação fiscal
 * precisa poder explicar a si mesma, dois anos depois, por que dispensou.
 */
export async function dispensar(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const motivo = String(form.get("motivo") ?? "").trim();

  if (motivo.length < 5) {
    return {
      estado: "erro",
      erros: ["Escreva o motivo — é ele que responde à pergunta daqui a dois anos."],
    };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "rfb.dispensar",
      supabase.rpc("dispensar_recibo_rfb", { p_recibo: recibo, p_motivo: motivo }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return { estado: "ok", mensagem: "Dispensado, com o motivo registrado." };
}

/** Liga e desliga o modo. Desligar não apaga nada — só para de gerar pendência nova. */
export async function mudarModo(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const ligar = String(form.get("ligar") ?? "") === "1";

  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  try {
    await db(
      "rfb.modo",
      supabase.from("contas").update({ receita_saude: ligar }).eq("id", sessao.contaId),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: ligar
      ? "Modo ligado. Cada pagamento registrado passa a virar uma pendência de recibo."
      : "Modo desligado. O que já estava na lista continua lá — desligar não apaga histórico.",
  };
}

function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 300
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
