"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";

export type ResultadoEscolha =
  | { estado: "inicial" }
  | { estado: "erro"; mensagem: string }
  | { estado: "ok"; inicio: string };

const MOTIVOS: Record<string, string> = {
  inexistente: "Este link não existe. Confira se ele veio inteiro.",
  expirada: "Este link venceu. Peça outro para quem te enviou.",
  cancelada: "Esta troca foi cancelada por quem te enviou.",
  nao_oferecida: "Esse horário não está na lista.",
  passou: "Esse horário já passou.",
  sessao_mudou: "Algo mudou por aqui. Fale com quem te enviou o link.",
  // O caso que existe porque não há reserva. A frase evita a leitura de que
  // deu erro: não deu — o horário simplesmente foi de outra pessoa primeiro.
  ocupada: "Esse horário acabou de ser preenchido. Escolha um dos outros.",
};

/**
 * A escolha de quem chegou pelo link.
 *
 * Roda como `anon`: quem clica não tem conta aqui e não vai criar uma para
 * trocar de horário. Toda a proteção é do banco — a função é a única porta, o
 * token é a chave, e a hora tem de ser uma das que o sistema ofereceu (0035).
 */
export async function escolher(
  _anterior: ResultadoEscolha,
  form: FormData,
): Promise<ResultadoEscolha> {
  const token = String(form.get("token") ?? "");
  const inicio = String(form.get("inicio") ?? "");

  const supabase = supabaseServer();

  const r = (await db(
    "remarcacao.escolher",
    supabase.rpc("escolher_remarcacao", { p_token: token, p_inicio: inicio }),
  )) as unknown as { ok?: boolean; motivo?: string };

  if (!r?.ok) {
    return {
      estado: "erro",
      mensagem: MOTIVOS[r?.motivo ?? ""] ?? "Não consegui trocar. Tente de novo.",
    };
  }

  revalidatePath(`/p/remarcar/${token}`);
  return { estado: "ok", inicio };
}
