import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

export type TipoDoc = "recibo" | "declaracao_comparecimento" | "informe_anual";

export type ItemDoRetrato = {
  inicio: string;
  dia: string;
  /** Ausente de propósito na declaração de comparecimento. */
  valor?: string;
};

export type Retrato = {
  profissional: { nome: string | null; crp: string | null; documento: string | null };
  conta: { nome: string | null; cidade: string | null };
  paciente: { nome: string; cpf: string | null };
  itens: ItemDoRetrato[];
};

export type DocumentoLinha = {
  id: string;
  numero: number;
  tipo: TipoDoc;
  periodo_de: string;
  periodo_ate: string;
  valor_total: string;
  quantidade: number;
  retrato: Retrato;
  emitido_em: string;
  cancelado_em: string | null;
  motivo_cancelamento: string | null;
  pacientes: { id: string; nome: string } | null;
};

const CAMPOS =
  "id, numero, tipo, periodo_de, periodo_ate, valor_total, quantidade, retrato, " +
  "emitido_em, cancelado_em, motivo_cancelamento";

export async function listarDocumentos(): Promise<DocumentoLinha[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "documentos.listar",
    supabase
      .from("documentos")
      .select(`${CAMPOS}, pacientes ( id, nome )`)
      .order("numero", { ascending: false })
      .limit(200),
  );

  return (linhas ?? []) as unknown as DocumentoLinha[];
}

export async function obterDocumento(id: string): Promise<DocumentoLinha | null> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "documentos.obter",
    supabase
      .from("documentos")
      .select(`${CAMPOS}, pacientes ( id, nome )`)
      .eq("id", id)
      .limit(1),
  );

  return ((linhas ?? []) as unknown as DocumentoLinha[])[0] ?? null;
}

export type PacienteParaDoc = { id: string; nome: string };

/** Quem tem sessão realizada — só desses dá para emitir alguma coisa. */
export async function pacientesComAtendimento(): Promise<PacienteParaDoc[]> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "documentos.pacientes",
    supabase
      .from("pacientes")
      .select("id, nome, sessoes!inner ( id )")
      .eq("sessoes.estado", "realizada")
      .order("nome"),
  )) as unknown as { id: string; nome: string }[] | null;

  // O embed traz uma linha por sessão; aqui interessa a pessoa, uma vez só.
  const vistos = new Set<string>();
  const unicos: PacienteParaDoc[] = [];
  for (const p of linhas ?? []) {
    if (vistos.has(p.id)) continue;
    vistos.add(p.id);
    unicos.push({ id: p.id, nome: p.nome });
  }
  return unicos;
}
