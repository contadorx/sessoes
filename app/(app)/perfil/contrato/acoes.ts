"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { faltamObrigatorios, marcadoresDesconhecidos } from "@/lib/contrato";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * Publica a próxima versão do texto.
 *
 * A validação daqui é cortesia — quem recusa de verdade é a `publicar_contrato`
 * da 0031, e ela recusa mesmo que este arquivo suma. A regra pela qual se cobra
 * tem de estar no papel que a pessoa aceitou (doc 07, portão da fase 2).
 */
export async function publicarContrato(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const titulo = String(form.get("titulo") ?? "").trim();
  const corpo = String(form.get("corpo") ?? "").trim();

  const sessao = await sessaoAtual();
  if (sessao.papel !== "dona") {
    return { estado: "erro", erros: ["Só a dona da conta publica o contrato."] };
  }

  const erros: string[] = [];
  if (titulo.length < 1) erros.push("Dê um título ao documento.");
  if (corpo.length < 200) erros.push("O texto está curto demais para valer como combinado.");

  for (const m of faltamObrigatorios(corpo)) {
    erros.push(
      m === "{{politica}}"
        ? "Falta {{politica}} no texto. A regra de desmarcação precisa estar escrita para quem aceita — é ela que a cobrança automática aplica."
        : "Falta {{valor}} no texto. O combinado de dinheiro precisa estar escrito para quem aceita.",
    );
  }

  const errados = marcadoresDesconhecidos(corpo);
  if (errados.length > 0) {
    erros.push(
      `Não conheço ${errados.join(", ")} — vai sair no texto do jeito que está. ` +
        "Confira a lista de marcadores ao lado.",
    );
  }

  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();
  await db(
    "contrato.publicar",
    supabase.rpc("publicar_contrato", { p_titulo: titulo, p_corpo: corpo }),
  );

  revalidatePath("/perfil/contrato");
  revalidatePath("/pacientes");
  return {
    estado: "ok",
    mensagem:
      "Publicado. Vale para os próximos aceites — quem já aceitou continua com o texto que leu.",
  };
}

/** Prepara (ou renova) o link de aceite do combinado vigente. */
export async function prepararAceite(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const enquadre = String(form.get("enquadre") ?? "");
  const paciente = String(form.get("paciente") ?? "");

  const supabase = await supabaseSessao();

  try {
    await db("aceite.preparar", supabase.rpc("preparar_aceite", { p_enquadre: enquadre }));
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  return { estado: "ok", mensagem: "Link pronto." };
}

/**
 * Ela registra que a pessoa assinou na sala.
 *
 * O gatilho é que rotula como presencial, e é ele que carimba a hora — daqui
 * não sai data nenhuma. Um campo de data aqui seria um convite a antedatar.
 */
export async function registrarPresencial(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const enquadre = String(form.get("enquadre") ?? "");
  const paciente = String(form.get("paciente") ?? "");
  const quem = String(form.get("quem") ?? "").trim();
  const parentesco = String(form.get("parentesco") ?? "").trim();

  if (quem.length < 2) {
    return { estado: "erro", erros: ["Escreva o nome de quem assinou."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "aceite.presencial",
      supabase.rpc("registrar_aceite_presencial", {
        p_enquadre: enquadre,
        p_quem: quem,
        p_parentesco: parentesco || null,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  return { estado: "ok", mensagem: "Registrado." };
}

export async function revogarAceite(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("aceite") ?? "");
  const paciente = String(form.get("paciente") ?? "");
  const motivo = String(form.get("motivo") ?? "").trim();

  const supabase = await supabaseSessao();

  try {
    await db(
      "aceite.revogar",
      supabase.rpc("revogar_aceite", { p_id: id, p_motivo: motivo || null }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  return {
    estado: "ok",
    mensagem: "Revogado. O registro fica — o que foi cobrado sob ele continua explicável.",
  };
}

/**
 * A mensagem do Postgres já é escrita em português e para gente (0031). Levar
 * isso à tela é melhor do que traduzir de novo aqui e ter duas versões da mesma
 * frase envelhecendo em lugares diferentes.
 */
function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 200
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
