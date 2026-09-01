"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * Liga e desliga a régua para uma pessoa.
 *
 * O freio tem de estar mais à mão do que o acelerador. Há situações que ela
 * conhece e o sistema não — alguém desempregado, alguém em crise, alguém com
 * quem o dinheiro virou tema da terapia. Nenhuma dessas cabe num campo de
 * cadastro, e é por isso que a decisão é dela e o botão fica aqui, ao lado do
 * nome, e não escondido numa tela de ajustes.
 */
export async function pausarRegua(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  const ativar = String(form.get("ativar") ?? "") === "1";

  if (!id) return { estado: "erro", erros: ["Pessoa não identificada."] };

  const supabase = await supabaseSessao();

  try {
    await db(
      "regua.pausar",
      supabase
        .from("pacientes")
        .update({ regua_ativa: ativar })
        .eq("id", id)
        .select("id"),
    );
  } catch (e) {
    console.error("[regua] falhou pausar", e);
    return { estado: "erro", erros: ["Não consegui agora. Tente de novo em instantes."] };
  }

  revalidatePath("/recebimentos");
  revalidatePath(`/pacientes/${id}`);

  return {
    estado: "ok",
    mensagem: ativar
      ? "Os lembretes voltam a sair para esta pessoa."
      : "Nenhum lembrete sai para esta pessoa. As cobranças continuam registradas.",
  };
}
