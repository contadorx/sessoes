import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import type { Canal, Estado } from "@/lib/paciente";

export type EnquadreLinha = {
  id: string;
  dia_semana: number;
  hora: string;
  duracao_min: number;
  valor: string;
  social: boolean;
  modelo_cobranca: string;
  politica_horas: number;
  politica_percentual: number;
  vigencia_inicio: string;
  vigencia_fim: string | null;
  motivo_fim: string | null;
};

export type PacienteLinha = {
  id: string;
  nome: string;
  telefone: string | null;
  email: string | null;
  cpf: string | null;
  estado: Estado;
  msg_canal: Canal;
  msg_modo: "discreto" | "completo";
  observacao: string | null;
  criado_em: string;
  enquadres: EnquadreLinha[];
};

const CAMPOS_ENQUADRE =
  "id, dia_semana, hora, duracao_min, valor, social, modelo_cobranca, politica_horas, politica_percentual, vigencia_inicio, vigencia_fim, motivo_fim";

const CAMPOS_PACIENTE =
  "id, nome, telefone, email, cpf, estado, msg_canal, msg_modo, observacao, criado_em";

/**
 * Nenhuma destas consultas filtra por conta_id — quem filtra é a RLS. Se ela
 * cair, a lista vem vazia em vez de vir com dado alheio.
 */
export async function listarPacientes(): Promise<PacienteLinha[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "pacientes.listar",
    supabase
      .from("pacientes")
      .select(`${CAMPOS_PACIENTE}, enquadres (${CAMPOS_ENQUADRE})`)
      .is("enquadres.vigencia_fim", null)
      .neq("estado", "arquivado")
      .order("nome"),
  );

  return (linhas ?? []) as unknown as PacienteLinha[];
}

export async function obterPaciente(id: string): Promise<PacienteLinha | null> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "pacientes.obter",
    supabase
      .from("pacientes")
      .select(`${CAMPOS_PACIENTE}, enquadres (${CAMPOS_ENQUADRE})`)
      .eq("id", id)
      .limit(1),
  );

  const p = (linhas ?? [])[0] as unknown as PacienteLinha | undefined;
  if (!p) return null;

  // O aberto primeiro, o histórico depois — do mais recente para o mais antigo.
  p.enquadres = [...(p.enquadres ?? [])].sort((a, b) => {
    if (!a.vigencia_fim) return -1;
    if (!b.vigencia_fim) return 1;
    return b.vigencia_inicio.localeCompare(a.vigencia_inicio);
  });

  return p;
}

export function enquadreAberto(p: PacienteLinha): EnquadreLinha | null {
  return p.enquadres?.find((e) => e.vigencia_fim === null) ?? null;
}
