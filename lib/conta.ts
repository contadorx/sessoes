import "server-only";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

export type Sessao = {
  authUserId: string;
  usuarioId: string;
  contaId: string;
  papel: "dona" | "profissional" | "secretaria";
  nome: string | null;
  email: string;
  contaNome: string;
  contaTipo: "solo" | "clinica";
  plano: string;
  profissionalId: string | null;
};

/**
 * Quem está logada, com a conta já resolvida. Manda para /entrar se não houver
 * sessão — a mesma decisão do middleware, repetida aqui de propósito: o
 * middleware é conveniência, a página não confia nele.
 *
 * Note que nada aqui filtra por conta_id: a RLS já devolve só o que é dela.
 * Se um dia a RLS cair, esta função para de funcionar em vez de vazar.
 */
export async function sessaoAtual(): Promise<Sessao> {
  const supabase = await supabaseSessao();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/entrar");

  const linhas = await db(
    "sessao.usuario",
    supabase
      .from("usuarios")
      .select(
        "id, conta_id, papel, nome, email, contas ( nome, tipo, plano ), profissionais ( id )",
      )
      .eq("auth_user_id", user.id)
      .limit(1),
  );

  const u = linhas?.[0];
  if (!u) {
    // Existe auth.user mas não existe usuário: o gatilho de signup falhou.
    // Não inventar uma conta aqui — é bug de cadastro e tem que aparecer.
    throw new Error(`Usuário autenticado sem conta (auth_user_id: ${user.id})`);
  }

  const conta = Array.isArray(u.contas) ? u.contas[0] : u.contas;
  const profissional = Array.isArray(u.profissionais) ? u.profissionais[0] : u.profissionais;

  return {
    authUserId: user.id,
    usuarioId: u.id as string,
    contaId: u.conta_id as string,
    papel: u.papel as Sessao["papel"],
    nome: (u.nome as string | null) ?? null,
    email: u.email as string,
    contaNome: (conta?.nome as string) ?? "",
    contaTipo: (conta?.tipo as Sessao["contaTipo"]) ?? "solo",
    plano: (conta?.plano as string) ?? "gratis",
    profissionalId: (profissional?.id as string | undefined) ?? null,
  };
}
