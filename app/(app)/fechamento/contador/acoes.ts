"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { primeiroDia } from "@/lib/contador";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/** Quem recebe, e em que dia. Nada sai daqui sem os dois. */
export async function salvarContador(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const email = String(form.get("contador_email") ?? "").trim();
  const nome = String(form.get("contador_nome") ?? "").trim();
  const dia = Number(form.get("pasta_dia") ?? 5);
  const ativa = String(form.get("pasta_ativa") ?? "") === "1";

  const erros: string[] = [];
  if (email !== "" && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    erros.push("O e-mail do contador não parece um e-mail.");
  }
  if (nome !== "" && (nome.length < 2 || nome.length > 120)) {
    erros.push("O nome do contador tem de 2 a 120 caracteres.");
  }
  if (!Number.isInteger(dia) || dia < 1 || dia > 28) {
    erros.push("O dia vai de 1 a 28 — fevereiro existe.");
  }
  if (ativa && email === "") {
    erros.push("Para enviar automaticamente eu preciso do e-mail de quem recebe.");
  }
  if (erros.length > 0) return { estado: "erro", erros };

  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  try {
    await db(
      "contador.salvar",
      supabase
        .from("contas")
        .update({
          contador_email: email === "" ? null : email,
          contador_nome: nome === "" ? null : nome,
          pasta_dia: dia,
          pasta_ativa: ativa,
        })
        .eq("id", sessao.contaId),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/contador");
  return {
    estado: "ok",
    mensagem: ativa
      ? `Combinado. Todo dia ${dia} eu fecho o mês anterior e preparo a pasta.`
      : "Salvo. O envio automático está desligado — você fecha o mês quando quiser.",
  };
}

/**
 * Fechar o mês à mão.
 *
 * Não é atalho para o automático: é o caso em que o contador pediu, hoje, o mês
 * passado. Fechar de novo sem nada ter mudado devolve a mesma pasta, então
 * clicar duas vezes não polui o histórico.
 */
export async function fecharMes(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const competencia = String(form.get("competencia") ?? "").trim();

  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(competencia)) {
    return { estado: "erro", erros: ["Escolha um mês."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "contador.fechar",
      supabase.rpc("fechar_mes_do_contador", { p_competencia: primeiroDia(competencia) }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/contador");
  return { estado: "ok", mensagem: "Mês fechado. O arquivo está aqui embaixo." };
}

function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 300
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
