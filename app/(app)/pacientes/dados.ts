import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import type { Canal, Estado } from "@/lib/paciente";
import type { AceiteLinha } from "@/lib/contrato";
import type { PacoteLinha } from "@/lib/cobranca";

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
  mensalidade_valor: string | null;
  falta_cobra_a_parte: boolean;
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
  restricao_judicial: boolean;
  contato_esquecido_em: string | null;
  arquivado_em: string | null;
  encerramento: string | null;
  enquadres: EnquadreLinha[];
};

const CAMPOS_ENQUADRE =
  "id, dia_semana, hora, duracao_min, valor, social, modelo_cobranca, politica_horas, " +
  "politica_percentual, vigencia_inicio, vigencia_fim, motivo_fim, mensalidade_valor, " +
  "falta_cobra_a_parte";

const CAMPOS_PACIENTE =
  "id, nome, telefone, email, cpf, estado, msg_canal, msg_modo, observacao, criado_em, " +
  "restricao_judicial, contato_esquecido_em, arquivado_em, encerramento";

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

  // A leitura de uma ficha é um evento registrável (PR13, doc 07). Fica aqui,
  // e não na página, porque esta é a **única** porta por onde uma ficha inteira
  // sai do banco — trilha ligada na tela esquece a segunda tela.
  //
  // Falhar aqui não pode impedir o atendimento: se a trilha não gravar, a ficha
  // abre mesmo assim e o erro vai para o log. A alternativa — recusar a leitura
  // — protegeria o registro à custa da pessoa que está esperando na sala.
  try {
    await db("trilha.leu_ficha", supabase.rpc("registrar_acesso", {
      p_paciente: id,
      p_acao: "leu_ficha",
    }));
  } catch (e) {
    console.error("[trilha] não registrou a leitura da ficha", { id, e });
  }

  return p;
}

export function enquadreAberto(p: PacienteLinha): EnquadreLinha | null {
  return p.enquadres?.find((e) => e.vigencia_fim === null) ?? null;
}

/**
 * O lastro do combinado vigente (B19).
 *
 * Duas perguntas numa ida só: a conta já tem um texto publicado, e este
 * combinado já tem um aceite vivo. A segunda é filtrada pelo `enquadre_id` e
 * não pelo paciente — um aceite pertence ao combinado que estava valendo, e um
 * reajuste (que fecha um enquadre e abre outro) **perde o lastro de propósito**.
 * Perguntar por paciente responderia "sim, tem contrato" para um valor que
 * ninguém viu.
 */
export async function lastroDoPaciente(
  _pacienteId: string,
  enquadreId: string | null,
): Promise<{ temContrato: boolean; aceite: AceiteLinha | null }> {
  const supabase = await supabaseSessao();

  const contratos = (await db(
    "lastro.contrato",
    supabase.from("contratos").select("id").not("publicado_em", "is", null).limit(1),
  )) as unknown as { id: string }[];

  if (!enquadreId) {
    return { temContrato: (contratos ?? []).length > 0, aceite: null };
  }

  const aceites = (await db(
    "lastro.aceite",
    supabase
      .from("aceites")
      .select(
        "id, token, aceito_em, aceito_por, parentesco, origem, criado_em, expira_em, revogado_em, retrato",
      )
      .eq("enquadre_id", enquadreId)
      .is("revogado_em", null)
      .limit(1),
  )) as unknown as AceiteLinha[];

  return {
    temContrato: (contratos ?? []).length > 0,
    aceite: (aceites ?? [])[0] ?? null,
  };
}

/**
 * Os pacotes do paciente, com o saldo já derivado.
 *
 * O saldo vem de contar os consumos, e não de uma coluna: é a decisão da 0033.
 * Aqui isso custa um `count` embutido no `select` — e paga com um número que
 * não tem como estar errado sem que exista um consumo errado, com data e sessão.
 */
export async function pacotesDoPaciente(pacienteId: string): Promise<PacoteLinha[]> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "pacotes.listar",
    supabase
      .from("pacotes")
      .select(
        "id, quantidade, valor, validade, vendido_em, cancelado_em, pacote_consumos(count)",
      )
      .eq("paciente_id", pacienteId)
      .order("vendido_em", { ascending: false }),
  )) as unknown as (Omit<PacoteLinha, "consumidos"> & {
    pacote_consumos: { count: number }[];
  })[];

  return (linhas ?? []).map((p) => ({
    id: p.id,
    quantidade: p.quantidade,
    valor: p.valor,
    validade: p.validade,
    vendido_em: p.vendido_em,
    cancelado_em: p.cancelado_em,
    consumidos: p.pacote_consumos?.[0]?.count ?? 0,
  }));
}

/** Está na fila de entrada — a de quem espera um horário fixo (B22)? */
export async function filaDeEntradaDoPaciente(
  pacienteId: string,
): Promise<{ naFila: boolean; desde: string | null }> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "filaentrada.do_paciente",
    supabase
      .from("fila_entrada")
      .select("ativo, entrou_em")
      .eq("paciente_id", pacienteId)
      .limit(1),
  )) as unknown as { ativo: boolean; entrou_em: string }[];

  const f = (linhas ?? [])[0];
  return { naFila: Boolean(f?.ativo), desde: f?.entrou_em ?? null };
}
