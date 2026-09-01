"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/** Dispara a cascata da fila de entrada para uma vaga aberta. */
export async function oferecerVaga(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const vaga = String(form.get("vaga") ?? "");
  const supabase = await supabaseSessao();

  let oferta: string | null;
  try {
    oferta = (await db(
      "vagafixa.avancar",
      supabase.rpc("avancar_fila_fixa", { p_vaga: vaga }),
    )) as unknown as string | null;
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/encaixes/fixos");

  if (!oferta) {
    return {
      estado: "ok",
      mensagem:
        "Ninguém da fila de entrada está disponível para este horário. A vaga fica registrada — reabra quando alguém novo entrar.",
    };
  }

  return {
    estado: "ok",
    mensagem: "Oferecida. A pessoa tem 24 horas para responder; sem resposta, a fila anda sozinha.",
  };
}

/** Abre uma vaga à mão: abandono, ou um horário que nunca teve dono. */
export async function abrirVaga(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const dia = Number(form.get("dia_semana") ?? 2);
  const hora = String(form.get("hora") ?? "").trim();
  const duracao = Number(form.get("duracao_min") ?? 50);
  const motivo = String(form.get("motivo") ?? "outro");

  const erros: string[] = [];
  if (!Number.isInteger(dia) || dia < 0 || dia > 6) erros.push("Escolha o dia da semana.");
  if (!/^\d{2}:\d{2}$/.test(hora)) erros.push("Informe o horário.");
  if (!Number.isInteger(duracao) || duracao < 15 || duracao > 240) {
    erros.push("A duração vai de 15 a 240 minutos.");
  }
  if (erros.length > 0) return { estado: "erro", erros };

  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta ainda não tem profissional."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "vagafixa.abrir",
      supabase.rpc("abrir_vaga_fixa", {
        p_profissional: sessao.profissionalId,
        p_dia: dia,
        p_hora: hora,
        p_duracao: duracao,
        p_motivo: motivo,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/encaixes/fixos");
  return { estado: "ok", mensagem: "Vaga aberta. Ofereça quando quiser." };
}

export async function fecharVaga(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const vaga = String(form.get("vaga") ?? "");
  const supabase = await supabaseSessao();

  try {
    await db(
      "vagafixa.fechar",
      supabase.rpc("fechar_vaga_fixa", { p_vaga: vaga, p_motivo: "cancelada" }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/encaixes/fixos");
  return { estado: "ok", mensagem: "Vaga fechada. A oferta que estava viva foi cancelada." };
}

/** Entra ou sai da fila de entrada — a de quem espera um horário fixo. */
export async function mudarFilaDeEntrada(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const paciente = String(form.get("paciente") ?? "");
  const entrar = String(form.get("entrar") ?? "") === "1";

  const supabase = await supabaseSessao();

  try {
    if (entrar) {
      await db(
        "filaentrada.entrar",
        supabase
          .from("fila_entrada")
          .upsert({ paciente_id: paciente, ativo: true }, { onConflict: "paciente_id" }),
      );
    } else {
      await db(
        "filaentrada.sair",
        supabase.from("fila_entrada").delete().eq("paciente_id", paciente),
      );
    }
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  revalidatePath("/encaixes/fixos");
  return {
    estado: "ok",
    mensagem: entrar
      ? "Na fila de entrada. Quando um horário fixo vagar, o sistema oferece na ordem de chegada."
      : "Fora da fila de entrada.",
  };
}

/**
 * A mensagem do Postgres já é escrita em português e para gente (0036). Levar
 * isso à tela é melhor do que traduzir de novo aqui e ter duas versões da mesma
 * frase envelhecendo em lugares diferentes.
 */
function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 240
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
