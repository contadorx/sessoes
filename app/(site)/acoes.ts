"use server";

import { db, ErroDeBanco } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";

export type EstadoInscricao =
  | { estado: "inicial" }
  | { estado: "ok"; mensagem: string }
  | { estado: "erro"; mensagem: string };

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const PERFIS = ["autonoma", "clinica", "estudante", "outro"] as const;
type Perfil = (typeof PERFIS)[number];

export async function entrarNaLista(
  _anterior: EstadoInscricao,
  form: FormData,
): Promise<EstadoInscricao> {
  // Armadilha para robô: campo escondido que só um bot preenche.
  if (String(form.get("site") ?? "").trim() !== "") {
    return { estado: "ok", mensagem: "Pronto. Te aviso quando abrir." };
  }

  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const nome = String(form.get("nome") ?? "").trim();
  const perfilBruto = String(form.get("perfil") ?? "").trim();

  if (!EMAIL.test(email) || email.length > 254) {
    return { estado: "erro", mensagem: "Esse e-mail não parece válido." };
  }

  const perfil: Perfil | "nao_informado" = (PERFIS as readonly string[]).includes(
    perfilBruto,
  )
    ? (perfilBruto as Perfil)
    : "nao_informado";

  try {
    await db(
      "interessados.insert",
      supabaseServer()
        .from("interessados")
        .insert({
          email,
          nome: nome.slice(0, 120) || null,
          perfil,
          origem: "landing",
        }),
    );
  } catch (erro) {
    // 23505 = e-mail já cadastrado. Para quem se inscreve, é sucesso —
    // e não confirmamos a ninguém que um endereço já está na base.
    if (erro instanceof ErroDeBanco && erro.codigo === "23505") {
      return { estado: "ok", mensagem: "Você já está na lista. Te aviso quando abrir." };
    }

    console.error("[lista] falhou a inscrição", erro);
    return {
      estado: "erro",
      mensagem: "Deu erro aqui do lado. Tenta de novo em instantes?",
    };
  }

  return { estado: "ok", mensagem: "Pronto. Te aviso quando abrir." };
}
