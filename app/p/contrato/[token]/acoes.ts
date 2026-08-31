"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";

export type ResultadoAceite =
  | { estado: "inicial" }
  | { estado: "erro"; mensagem: string }
  | { estado: "ok" };

const MOTIVOS: Record<string, string> = {
  inexistente: "Este link não existe. Confira se ele veio inteiro.",
  expirado: "Este link venceu. Peça outro para quem te enviou.",
  revogado: "Este combinado foi cancelado por quem te enviou.",
  sem_nome: "Escreva seu nome completo para confirmar.",
};

/**
 * O aceite de quem chegou pelo link.
 *
 * Roda como `anon`: quem clica não tem conta aqui e não vai criar uma para
 * assinar um papel. Toda a proteção está do lado do banco — a função é a única
 * porta, o token é a chave, e o que ela devolve é o mínimo (0031).
 *
 * `ip` e `agente` são qualidade de prova, não de segurança: valem por dizerem
 * de onde veio o clique, e não são confiáveis contra quem quer mentir. Ficam
 * porque um aceite sem procedência nenhuma é mais fraco do que um com ela.
 */
export async function aceitar(
  _anterior: ResultadoAceite,
  form: FormData,
): Promise<ResultadoAceite> {
  const token = String(form.get("token") ?? "");
  const nome = String(form.get("nome") ?? "").trim();
  const parentesco = String(form.get("parentesco") ?? "").trim();

  if (nome.length < 2) {
    return { estado: "erro", mensagem: MOTIVOS.sem_nome };
  }

  const cabecalhos = await headers();
  const encaminhado = cabecalhos.get("x-forwarded-for") ?? "";
  const ip = encaminhado.split(",")[0]?.trim() || null;

  const supabase = supabaseServer();

  const resposta = (await db(
    "contrato.aceitar",
    supabase.rpc("aceitar_contrato", {
      p_token: token,
      p_nome: nome,
      p_parentesco: parentesco || null,
      p_ip: ip,
      p_agente: cabecalhos.get("user-agent") ?? null,
    }),
  )) as unknown as { ok: boolean; motivo: string };

  if (!resposta?.ok) {
    return {
      estado: "erro",
      mensagem: MOTIVOS[resposta?.motivo] ?? "Não consegui confirmar. Tente de novo.",
    };
  }

  revalidatePath(`/p/contrato/${token}`);
  return { estado: "ok" };
}
